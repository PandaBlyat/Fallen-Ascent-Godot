class_name StockpileManager
extends Node2D
##
## Owns the set of StockpileZones for the colony. The zones live as children
## of this node so they share its draw order (above chunks, below workers).
## When a zone is created or a new item is dropped, this manager pairs free
## cells with unreserved items and posts HaulJobs.
##
## Re-validates zones when terrain under them changes (via EventBus.tile_changed):
## non-walkable cells are detached and their items dropped as loose items.
##

signal zone_added(zone: StockpileZone)
signal zone_removed(zone: StockpileZone)
signal stockpile_changed()

@export var job_board_path: NodePath
@export var chunk_manager_path: NodePath
@export var items_root_path: NodePath
@export var max_pending_haul_jobs: int = 96

var _job_board: JobBoard
var _chunk_manager: ChunkManager
var _items_root: Node2D
var zones: Array[StockpileZone] = []
var _rematch_queued: bool = false
var _pending_haul_jobs: int = 0


func _ready() -> void:
	_job_board = get_node(job_board_path) as JobBoard
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_items_root = get_node(items_root_path) as Node2D
	EventBus.tile_changed.connect(_on_tile_changed)
	if _job_board != null:
		_job_board.job_completed.connect(_on_job_changed)
		_job_board.job_cancelled.connect(_on_job_changed)


func create_zone(rect_cells: Array[Vector2i]) -> void:
	var walkable: Array[Vector2i] = []
	for c in rect_cells:
		if _chunk_manager.is_walkable(c) and not _cell_in_any_zone(c):
			walkable.append(c)
	if walkable.is_empty():
		return
	var zone := StockpileZone.new()
	add_child(zone)
	zone.setup(walkable)
	zones.append(zone)
	zone_added.emit(zone)
	stockpile_changed.emit()
	_schedule_match_loose_items()


## Returns the zone covering `grid` or null.
func zone_at(grid: Vector2i) -> StockpileZone:
	for z in zones:
		if z.contains_cell(grid):
			return z
	return null


func remove_zone(zone: StockpileZone) -> void:
	if zone == null or not is_instance_valid(zone):
		return
	# Clear reservations on items that were inbound to this zone before we
	# cancel the hauls — workers will see job_cancelled and drop carry.
	for j in _job_board.pending:
		if j is HaulJob and (j as HaulJob).dropoff_zone == zone:
			var it: Item = (j as HaulJob).item as Item
			if it != null and is_instance_valid(it):
				it.reserved_by = null
	_job_board.cancel_hauls_to_zone(zone)
	# Drop placed items as loose items at their cell, in case a worker is
	# carrying inbound material we drop the carry on _on_job_cancelled.
	for cell in zone.cells.duplicate():
		var item: Item = zone.detach_cell(cell)
		if item != null and is_instance_valid(item):
			zone.remove_child(item)
			_items_root.add_child(item)
			item.set_grid(cell)
			item.reserved_by = null
	zones.erase(zone)
	zone_removed.emit(zone)
	zone.queue_free()
	stockpile_changed.emit()
	_schedule_match_loose_items()


func _cell_in_any_zone(grid: Vector2i) -> bool:
	for z in zones:
		if z.contains_cell(grid):
			return true
	return false


## Iterate loose items and post a HaulJob for each that has an open slot.
func _match_loose_items() -> void:
	_rematch_queued = false
	if _items_root == null:
		return
	for child in _items_root.get_children():
		if _pending_haul_count() >= max_pending_haul_jobs:
			return
		var item := child as Item
		if item == null or item.reserved_by != null:
			continue
		_try_post_haul_for(item)


func on_item_spawned(item: Item) -> void:
	_try_post_haul_for(item)


func _try_post_haul_for(item: Item) -> void:
	if item == null or not is_instance_valid(item) or item.reserved_by != null:
		return
	if _pending_haul_count() >= max_pending_haul_jobs:
		_schedule_match_loose_items()
		return
	var haul_amount: int = mini(item.count, Worker.MAX_CARRY_STACK)
	for zone in zones:
		var cell_v: Variant = zone.first_free_cell_for(item.kind, haul_amount)
		if cell_v == null:
			continue
		var cell: Vector2i = cell_v
		zone.reserve(cell, item.kind)
		item.reserved_by = self
		_job_board.add_haul_job(item, zone, cell)
		_pending_haul_jobs += 1
		return


func _pending_haul_count() -> int:
	return _pending_haul_jobs


func _schedule_match_loose_items() -> void:
	if _rematch_queued:
		return
	_rematch_queued = true
	call_deferred("_match_loose_items")


func _on_job_changed(job: Job) -> void:
	if job is HaulJob:
		_pending_haul_jobs = maxi(0, _pending_haul_jobs - 1)
		_schedule_match_loose_items()


func total_stored() -> int:
	var n: int = 0
	for z in zones:
		n += z.stored_count()
	return n


func available_count(kind: int) -> int:
	var n: int = 0
	for zone in zones:
		for value in zone.occupant.values():
			var item: Item = null
			if value is Item:
				item = value as Item
			elif value is Dictionary:
				item = (value as Dictionary).get(StockpileZone.R_EXISTING) as Item
			if item != null and is_instance_valid(item) and item.reserved_by == null and item.kind == kind and item.count > 0:
				n += item.count
	return n


func consume_one(kind: int) -> bool:
	for zone in zones:
		for cell in zone.cells:
			var value: Variant = zone.occupant.get(cell)
			var item: Item = null
			if value is Item:
				item = value as Item
			elif value is Dictionary:
				item = (value as Dictionary).get(StockpileZone.R_EXISTING) as Item
			if item == null or not is_instance_valid(item) or item.reserved_by != null or item.kind != kind or item.count <= 0:
				continue
			item.count -= 1
			if item.count <= 0:
				zone.take(cell)
				if item.get_parent() == zone:
					zone.remove_child(item)
				item.queue_free()
			else:
				item.queue_redraw()
			stockpile_changed.emit()
			return true
	return false


## When terrain under a zone cell becomes non-walkable, drop the cell. If
## the cell had a placed item, leave it as loose at the same grid (it sits
## on the new tile; if the new tile is solid the item gets stranded — that's
## consistent with the current "carry until reachable" behavior).
func _on_tile_changed(grid: Vector2i, _new_tile: int) -> void:
	if _chunk_manager.is_walkable(grid):
		return
	var any_change: bool = false
	for zone in zones.duplicate():
		if not zone.contains_cell(grid):
			continue
		any_change = true
		# Clear reservation on any inbound item before cancelling, so it can
		# be re-matched to a different cell.
		for j in _job_board.pending:
			if j is HaulJob and (j as HaulJob).dropoff_zone == zone \
					and (j as HaulJob).dropoff == grid:
				var it: Item = (j as HaulJob).item as Item
				if it != null and is_instance_valid(it):
					it.reserved_by = null
		_job_board.cancel_haul_to(zone, grid)
		var item: Item = zone.detach_cell(grid)
		if item != null and is_instance_valid(item):
			zone.remove_child(item)
			_items_root.add_child(item)
			item.set_grid(grid)
			item.reserved_by = null
		if zone.cells.is_empty():
			zones.erase(zone)
			zone_removed.emit(zone)
			zone.queue_free()
	if any_change:
		stockpile_changed.emit()
		_match_loose_items()
