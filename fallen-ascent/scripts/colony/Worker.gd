class_name Worker
extends Node2D
##
## One unit. Pulls jobs from the JobBoard, paths via the Pathfinder, executes
## them. State machine in one switch; movement scales with Engine.time_scale
## because `delta` already does.
##
## Direct orders from the player (selection + right-click) come in via the
## `command_*` methods. They abort any current job and inject a new one.
##

enum State {
	IDLE,
	MOVING_TO_WORK,
	WORKING,
	MOVING_TO_PICKUP,
	CARRYING,
	MOVING_TO_DROP,
	MOVING_TO_BUILD_SITE,
	BUILDING,
	MOVING_FREEFORM,
}

const MOVE_SPEED_PX_PER_SEC: float = 48.0
const ARRIVE_EPSILON_PX: float = 1.0
const IDLE_RETRY_SECONDS: float = 0.5
const BODY_RADIUS: float = 5.0
const BODY_COLOR := Color(0.85, 0.85, 0.95)
const SELECTION_COLOR := Color(1.0, 0.95, 0.4, 0.9)
const ITEM_SCRIPT: Script = preload("res://scripts/colony/Item.gd")

var _state: int = State.IDLE
var _job: Job = null
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _idle_cooldown: float = 0.0
var _carried: Item = null
var _selected: bool = false

var _job_board: JobBoard
var _pathfinder: Pathfinder
var _chunk_manager: ChunkManager
var _stockpile_manager: StockpileManager
var _items_root: Node2D
var _colony_site: Node


func setup(
	job_board: JobBoard,
	pathfinder: Pathfinder,
	chunk_manager: ChunkManager,
	stockpile_manager: StockpileManager,
	items_root: Node2D,
	colony_site: Node,
) -> void:
	_job_board = job_board
	_pathfinder = pathfinder
	_chunk_manager = chunk_manager
	_stockpile_manager = stockpile_manager
	_items_root = items_root
	_colony_site = colony_site


func _ready() -> void:
	if _job_board != null:
		_job_board.job_added.connect(_on_job_added)
		_job_board.job_cancelled.connect(_on_job_cancelled)
	EventBus.tile_changed.connect(_on_tile_changed)


func current_grid() -> Vector2i:
	return Vector2i(
		int(floor(position.x / Chunk.TILE_PIXELS)),
		int(floor(position.y / Chunk.TILE_PIXELS)),
	)


func set_selected(v: bool) -> void:
	if _selected == v:
		return
	_selected = v
	queue_redraw()


func is_selected() -> bool:
	return _selected


func _on_job_added(_added_job: Job) -> void:
	if _state == State.IDLE:
		_idle_cooldown = 0.0


func _on_job_cancelled(job: Job) -> void:
	if _job == job:
		_abandon_job()


func _on_tile_changed(grid: Vector2i, _new_tile: int) -> void:
	if _path.is_empty():
		return
	# If the changed tile lies on the remaining path, re-plan.
	for i in range(_path_index, _path.size()):
		var p: Vector2 = _path[i]
		var g := Vector2i(
			int(floor(p.x / Chunk.TILE_PIXELS)),
			int(floor(p.y / Chunk.TILE_PIXELS)),
		)
		if g == grid:
			_replan()
			return


func _process(delta: float) -> void:
	match _state:
		State.IDLE:
			_idle_cooldown -= delta
			if _idle_cooldown <= 0.0:
				_idle_cooldown = IDLE_RETRY_SECONDS
				_try_claim_job()
		State.MOVING_TO_WORK:
			if _advance_path(delta):
				_state = State.WORKING
		State.WORKING:
			var mine := _job as MineJob
			if mine == null:
				_abandon_job()
				return
			mine.progress += delta
			if mine.progress >= MineJob.DURATION:
				_complete_mine(mine)
		State.MOVING_TO_PICKUP:
			if _advance_path(delta):
				_pickup_item()
		State.CARRYING, State.MOVING_TO_DROP:
			if _advance_path(delta):
				_drop_item()
		State.MOVING_TO_BUILD_SITE:
			if _advance_path(delta):
				_state = State.BUILDING
		State.BUILDING:
			var build := _job as BuildJob
			if build == null:
				_abandon_job()
				return
			build.progress += delta
			if build.progress >= BuildJob.BUILD_DURATION:
				_complete_build(build)
		State.MOVING_FREEFORM:
			if _advance_path(delta):
				_state = State.IDLE
				_idle_cooldown = 0.0


func _try_claim_job() -> void:
	if _job_board == null or _pathfinder == null:
		return
	var job: Job = _job_board.claim_next_for(self, current_grid())
	if job == null:
		return
	_job = job
	if job is MineJob:
		_begin_mine(job as MineJob)
	elif job is HaulJob:
		_begin_haul(job as HaulJob)
	elif job is BuildJob:
		_begin_build(job as BuildJob)


func _begin_mine(job: MineJob) -> void:
	var stand: Vector2i = _pathfinder.walkable_neighbor_of(job.target)
	if stand == Pathfinder.UNREACHABLE:
		_release_and_idle()
		return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), stand)
	if path.is_empty() and current_grid() != stand:
		_release_and_idle()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_WORK


func _begin_haul(job: HaulJob) -> void:
	if job.item == null or not is_instance_valid(job.item):
		_release_and_idle()
		return
	var item_grid: Vector2i = (job.item as Item).get_grid()
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), item_grid)
	if path.is_empty() and current_grid() != item_grid:
		_release_and_idle()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_PICKUP


func _begin_build(job: BuildJob) -> void:
	# Build needs a material item. Find the nearest unreserved Item of the
	# right kind from items_root or any stockpile zone, claim it as the
	# source. If nothing's available, release the job and try later.
	var source: Item = _find_material_for_build(job)
	if source == null:
		_release_and_idle()
		return
	job.source_item = source
	source.reserved_by = self
	# Phase 1: walk to the source item.
	var sg: Vector2i = source.get_grid()
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), sg)
	if path.is_empty() and current_grid() != sg:
		source.reserved_by = null
		_release_and_idle()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_PICKUP


func _find_material_for_build(job: BuildJob) -> Item:
	# Prefer loose items first (cheaper to grab).
	var best: Item = null
	var best_d: int = 0x7fffffff
	var origin: Vector2i = current_grid()
	if _items_root != null:
		for child in _items_root.get_children():
			var it := child as Item
			if it == null or it.reserved_by != null or it.kind != job.material_kind:
				continue
			var d: int = maxi(absi(it.get_grid().x - origin.x), absi(it.get_grid().y - origin.y))
			if d < best_d:
				best = it
				best_d = d
	if best != null:
		return best
	# Fall back to stockpiled items.
	if _stockpile_manager != null:
		for zone in _stockpile_manager.zones:
			for cell in zone.cells:
				var occ: Variant = zone.occupant.get(cell)
				if occ is Item:
					var it2 := occ as Item
					if it2.reserved_by == null and it2.kind == job.material_kind:
						var d2: int = maxi(absi(cell.x - origin.x), absi(cell.y - origin.y))
						if d2 < best_d:
							best = it2
							best_d = d2
	return best


func _pickup_item() -> void:
	if _job is HaulJob:
		_pickup_for_haul()
	elif _job is BuildJob:
		_pickup_for_build()
	else:
		_abandon_job()


func _pickup_for_haul() -> void:
	var haul := _job as HaulJob
	if haul == null or haul.item == null or not is_instance_valid(haul.item):
		_abandon_job()
		return
	var item := haul.item as Item
	_take_into_hand(item)
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), haul.dropoff)
	if path.is_empty() and current_grid() != haul.dropoff:
		_drop_in_place()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_DROP


func _pickup_for_build() -> void:
	var build := _job as BuildJob
	if build == null or build.source_item == null or not is_instance_valid(build.source_item):
		_abandon_job()
		return
	var item := build.source_item as Item
	# If the source was in a stockpile cell, free that occupant slot.
	var src_parent: Node = item.get_parent()
	if src_parent is StockpileZone:
		(src_parent as StockpileZone).take(item.get_grid())
	# Carry only one unit; if the stack has more, leave the remainder loose.
	# The StockpileManager will re-haul it if a slot is available.
	if item.count > 1:
		var remainder: Item = ITEM_SCRIPT.new() as Item
		_items_root.add_child(remainder)
		remainder.setup(item.get_grid(), item.kind, item.count - 1)
		_stockpile_manager.on_item_spawned(remainder)
		item.count = 1
	_take_into_hand(item)
	# Phase 2: walk adjacent to the build target.
	var stand: Vector2i = _pathfinder.walkable_neighbor_of(build.target)
	if stand == Pathfinder.UNREACHABLE:
		_drop_in_place()
		return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), stand)
	if path.is_empty() and current_grid() != stand:
		_drop_in_place()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_BUILD_SITE


func _take_into_hand(item: Item) -> void:
	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	add_child(item)
	item.position = Vector2.ZERO
	item.visible = false
	_carried = item


func _drop_item() -> void:
	var haul := _job as HaulJob
	if haul == null or _carried == null:
		_abandon_job()
		return
	var zone := haul.dropoff_zone as StockpileZone
	if zone == null or not is_instance_valid(zone) or not zone.contains_cell(haul.dropoff):
		_drop_in_place()
		return
	remove_child(_carried)
	zone.add_child(_carried)
	_carried.visible = true
	_carried.set_grid(haul.dropoff)
	zone.unreserve(haul.dropoff)
	var placed: Item = zone.place(_carried, haul.dropoff)
	placed.reserved_by = null
	_carried = null
	_finish_job()
	if _stockpile_manager != null:
		_stockpile_manager.stockpile_changed.emit()


func _drop_in_place() -> void:
	var haul := _job as HaulJob
	if haul != null and haul.dropoff_zone is StockpileZone:
		(haul.dropoff_zone as StockpileZone).unreserve(haul.dropoff)
	if _carried != null:
		var here := current_grid()
		remove_child(_carried)
		_items_root.add_child(_carried)
		_carried.visible = true
		_carried.set_grid(here)
		_carried.reserved_by = null
		_carried = null
	_finish_job()


func _complete_mine(mine: MineJob) -> void:
	_chunk_manager.set_tile_at(mine.target, TerrainGenerator.TILE_FLOOR)
	if _colony_site != null and _colony_site.has_method("spawn_item_at"):
		_colony_site.call("spawn_item_at", mine.target)
	_finish_job()


func _complete_build(build: BuildJob) -> void:
	# Consume the carried material and convert the target tile to wall.
	if _carried != null:
		remove_child(_carried)
		_carried.queue_free()
		_carried = null
	_chunk_manager.set_tile_at(build.target, TerrainGenerator.TILE_WALL)
	_finish_job()


func _finish_job() -> void:
	if _job != null and _job_board != null:
		_job_board.complete(_job)
	_job = null
	_path = PackedVector2Array()
	_path_index = 0
	_state = State.IDLE
	_idle_cooldown = 0.0


func _release_and_idle() -> void:
	if _job != null and _job_board != null:
		_job_board.release(_job)
	_job = null
	_path = PackedVector2Array()
	_path_index = 0
	_state = State.IDLE
	_idle_cooldown = IDLE_RETRY_SECONDS


func _abandon_job() -> void:
	# Used when the job was cancelled or invalid mid-flight. Drop anything
	# carried in place so we don't lose the item.
	if _carried != null:
		var here := current_grid()
		remove_child(_carried)
		_items_root.add_child(_carried)
		_carried.visible = true
		_carried.set_grid(here)
		_carried.reserved_by = null
		_carried = null
	_job = null
	_path = PackedVector2Array()
	_path_index = 0
	_state = State.IDLE
	_idle_cooldown = IDLE_RETRY_SECONDS


func _replan() -> void:
	if _job == null:
		if _state == State.MOVING_FREEFORM and _path.size() > 0:
			# Try to re-path to the final waypoint.
			var dest_pixel: Vector2 = _path[_path.size() - 1]
			var dest: Vector2i = Vector2i(
				int(floor(dest_pixel.x / Chunk.TILE_PIXELS)),
				int(floor(dest_pixel.y / Chunk.TILE_PIXELS)),
			)
			var p: PackedVector2Array = _pathfinder.find_path(current_grid(), dest)
			if p.is_empty():
				_state = State.IDLE
				_path = PackedVector2Array()
				_path_index = 0
				return
			_path = p
			_path_index = 0
		return
	var target_grid: Vector2i
	match _state:
		State.MOVING_TO_WORK:
			var stand: Vector2i = _pathfinder.walkable_neighbor_of((_job as MineJob).target)
			if stand == Pathfinder.UNREACHABLE:
				_release_and_idle()
				return
			target_grid = stand
		State.MOVING_TO_PICKUP:
			if _job is HaulJob:
				target_grid = (_job as HaulJob).item.call("get_grid") as Vector2i
			elif _job is BuildJob:
				target_grid = ((_job as BuildJob).source_item as Item).get_grid()
			else:
				return
		State.CARRYING, State.MOVING_TO_DROP:
			target_grid = (_job as HaulJob).dropoff
		State.MOVING_TO_BUILD_SITE:
			var b_stand: Vector2i = _pathfinder.walkable_neighbor_of((_job as BuildJob).target)
			if b_stand == Pathfinder.UNREACHABLE:
				if _carried != null:
					_drop_in_place()
				else:
					_release_and_idle()
				return
			target_grid = b_stand
		_:
			return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), target_grid)
	if path.is_empty() and current_grid() != target_grid:
		# Lost reachability. Carrying? Drop it. Otherwise release.
		if _carried != null:
			_drop_in_place()
		else:
			_release_and_idle()
		return
	_path = path
	_path_index = 0


# ----- Direct orders from the player ---------------------------------------

func command_move(target: Vector2i) -> void:
	# Abort whatever we were doing, then walk to target.
	_abandon_job()
	if not _chunk_manager.is_walkable(target):
		return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), target)
	if path.is_empty() and current_grid() != target:
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_FREEFORM


func command_mine(target: Vector2i) -> void:
	# Add a mine designation (if needed) and immediately take it for ourselves.
	# If something else already had this job claimed, cancelling drops their
	# claim cleanly via the job_cancelled signal.
	if _chunk_manager.get_tile_at(target) != TerrainGenerator.TILE_WALL:
		return
	_abandon_job()
	if _job_board.has_mine_at(target):
		_job_board.cancel_mine_at(target)
	var job: MineJob = _job_board.add_mine_job(target)
	job.claimed_by = self
	_job = job
	_begin_mine(job)


func command_build(target: Vector2i) -> void:
	if _chunk_manager.get_tile_at(target) != TerrainGenerator.TILE_FLOOR:
		return
	_abandon_job()
	if _job_board.has_build_at(target):
		_job_board.cancel_build_at(target)
	var job: BuildJob = _job_board.add_build_job(target, Item.Kind.SCRAP)
	job.claimed_by = self
	_job = job
	_begin_build(job)


func _advance_path(delta: float) -> bool:
	if _path.is_empty():
		return true
	if _path_index >= _path.size():
		return true
	var step: float = MOVE_SPEED_PX_PER_SEC * delta
	while step > 0.0 and _path_index < _path.size():
		var target: Vector2 = _path[_path_index]
		var to_target: Vector2 = target - position
		var dist: float = to_target.length()
		if dist <= step + ARRIVE_EPSILON_PX:
			position = target
			step -= dist
			_path_index += 1
		else:
			position += to_target / dist * step
			step = 0.0
	return _path_index >= _path.size()


func _draw() -> void:
	if _selected:
		draw_circle(Vector2.ZERO, BODY_RADIUS + 3.0, Color(0, 0, 0, 0))
		draw_arc(Vector2.ZERO, BODY_RADIUS + 3.0, 0.0, TAU, 24, SELECTION_COLOR, 1.5)
	draw_circle(Vector2.ZERO, BODY_RADIUS, BODY_COLOR)
	if _carried != null:
		draw_circle(Vector2(0, -BODY_RADIUS - 2), 2.0, Item.kind_color(_carried.kind))
