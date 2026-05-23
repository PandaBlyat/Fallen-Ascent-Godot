class_name Worker
extends Node2D
##
## One unit. Pulls jobs from the JobBoard, paths via the Pathfinder, executes
## them. State machine in one switch; movement scales with Engine.time_scale
## because `delta` already does.
##

enum State { IDLE, MOVING_TO_WORK, WORKING, MOVING_TO_PICKUP, CARRYING, MOVING_TO_DROP }

const MOVE_SPEED_PX_PER_SEC: float = 48.0
const ARRIVE_EPSILON_PX: float = 1.0
const IDLE_RETRY_SECONDS: float = 0.5
const BODY_RADIUS: float = 5.0
const BODY_COLOR := Color(0.85, 0.85, 0.95)

var _state: int = State.IDLE
var _job: Job = null
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _idle_cooldown: float = 0.0
var _carried: Item = null

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


func _on_job_added(_job: Job) -> void:
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
	# The item sits on a (now-floor) tile that is walkable, so target it directly.
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), item_grid)
	if path.is_empty() and current_grid() != item_grid:
		_release_and_idle()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_PICKUP


func _pickup_item() -> void:
	var haul := _job as HaulJob
	if haul == null or haul.item == null or not is_instance_valid(haul.item):
		_abandon_job()
		return
	var item := haul.item as Item
	# Reparent under the worker, hide while carried.
	item.get_parent().remove_child(item)
	add_child(item)
	item.position = Vector2.ZERO
	item.visible = false
	_carried = item
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), haul.dropoff)
	if path.is_empty() and current_grid() != haul.dropoff:
		# Can't reach the dropoff. Drop the item where we stand and bail.
		_drop_in_place()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_DROP


func _drop_item() -> void:
	var haul := _job as HaulJob
	if haul == null or _carried == null:
		_abandon_job()
		return
	var zone := haul.dropoff_zone as StockpileZone
	if zone == null or not is_instance_valid(zone):
		_drop_in_place()
		return
	remove_child(_carried)
	zone.add_child(_carried)
	_carried.visible = true
	_carried.set_grid(haul.dropoff)
	# Convert the zone's reserved slot into a real occupant.
	zone.unreserve(haul.dropoff)
	zone.place(_carried, haul.dropoff)
	_carried.reserved_by = null
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
			target_grid = (_job as HaulJob).item.call("get_grid") as Vector2i
		State.CARRYING, State.MOVING_TO_DROP:
			target_grid = (_job as HaulJob).dropoff
		_:
			return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), target_grid)
	if path.is_empty() and current_grid() != target_grid:
		# Lost reachability. Carrying? Drop it. Mining? Release.
		if _carried != null:
			_drop_in_place()
		else:
			_release_and_idle()
		return
	_path = path
	_path_index = 0


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
	draw_circle(Vector2.ZERO, BODY_RADIUS, BODY_COLOR)
	if _carried != null:
		# Tiny indicator that we're carrying something.
		draw_circle(Vector2(0, -BODY_RADIUS - 2), 2.0, Item.SCRAP_COLOR)
