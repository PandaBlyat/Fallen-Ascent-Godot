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

## How long (ms) an item that failed delivery is skipped before a fresh haul is
## posted. Read by Worker when it drops an undeliverable carry.
const HAUL_RETRY_COOLDOWN_MS: int = 4000

var _job_board: JobBoard
var _chunk_manager: ChunkManager
var _items_root: Node2D
var zones: Array[StockpileZone] = []
var _rematch_queued: bool = false
var _pending_haul_jobs: int = 0
## True while a delayed rematch timer is pending, so cooldown'd items get one
## retry pass without scheduling a timer per skipped item.
var _delayed_match_pending: bool = false
## Chunk-coord -> Array[Item]. Indexes loose items so _match_loose_items
## doesn't have to walk the full _items_root every cycle.
var _items_by_chunk: Dictionary = {}
## Item -> Vector2i bucket. Lets unregister find the right bucket without
## scanning.
var _item_to_bucket: Dictionary = {}


func _ready() -> void:
	_job_board = get_node(job_board_path) as JobBoard
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_items_root = get_node(items_root_path) as Node2D
	EventBus.tile_changed.connect(_on_tile_changed)
	if _items_root != null:
		_items_root.child_exiting_tree.connect(_on_item_exiting_root)
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


func capture_save() -> Dictionary:
	var out: Array = []
	for z in zones:
		out.append(z.capture_save())
	return {"zones": out}


## Recreate zones and their stored stacks. Bypasses the walkable / overlap
## filtering in create_zone because the saved cells were already valid (terrain
## diffs are replayed before this runs).
func restore_save(data: Dictionary) -> void:
	var make_item := func(cell: Vector2i, kind: int, count: int) -> Item:
		var item := Item.new()
		item.setup(cell, kind, count)
		return item
	for zdata in data.get("zones", []) as Array:
		var zone := StockpileZone.new()
		add_child(zone)
		zone.restore_save(zdata, make_item)
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


func register_storage_bin(cell: Vector2i) -> void:
	var zone: StockpileZone = zone_at(cell)
	if zone == null:
		return
	zone.set_capacity_multiplier(cell, 3)
	stockpile_changed.emit()
	_schedule_match_loose_items()


func unregister_storage_bin(cell: Vector2i) -> void:
	var zone: StockpileZone = zone_at(cell)
	if zone == null:
		return
	zone.set_capacity_multiplier(cell, 1)
	stockpile_changed.emit()


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
			_register_loose_item(item)
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


## Returns any cell that belongs to a stockpile zone, or `Pathfinder.UNREACHABLE`
## when no zones exist. Used by the worker save flow as a fallback drop-off
## point when no repair bench or outlet is reachable.
func any_zone_cell() -> Vector2i:
	for z in zones:
		if z != null and not z.cells.is_empty():
			return z.cells[0]
	return Pathfinder.UNREACHABLE


## Iterate loose items and post a HaulJob for each that has an open slot.
func _match_loose_items() -> void:
	_rematch_queued = false
	if _items_root == null:
		return
	# Iterate from the index keys; copy so the inner loop can mutate the index
	# (a successful match calls _try_post_haul_for → reserve(), which doesn't
	# touch _items_by_chunk, but worker pickup later will).
	var now: int = Time.get_ticks_msec()
	var has_cooldown_items: bool = false
	for chunk in _items_by_chunk.keys():
		var bucket: Array = _items_by_chunk[chunk] as Array
		for item in bucket.duplicate():
			if _pending_haul_count() >= max_pending_haul_jobs:
				return
			if item == null or not is_instance_valid(item) or item.reserved_by != null:
				continue
			if item.haul_blocked_until_msec > now:
				has_cooldown_items = true
				continue
			_try_post_haul_for(item)
	# Guarantee a retry pass once the cooldown lapses, in case nothing else
	# triggers a rematch in the meantime.
	if has_cooldown_items:
		_schedule_delayed_match()


func on_item_spawned(item: Item) -> void:
	_register_loose_item(item)
	_try_post_haul_for(item)


## Index `item` under its current grid bucket. Idempotent; if the item is
## already registered its bucket gets refreshed.
func _register_loose_item(item: Item) -> void:
	if item == null or not is_instance_valid(item):
		return
	if _item_to_bucket.has(item):
		_unregister_loose_item(item)
	var bucket: Vector2i = Chunk.grid_to_chunk(item.get_grid())
	if not _items_by_chunk.has(bucket):
		_items_by_chunk[bucket] = []
	(_items_by_chunk[bucket] as Array).append(item)
	_item_to_bucket[item] = bucket


func _unregister_loose_item(item: Item) -> void:
	if not _item_to_bucket.has(item):
		return
	var bucket: Vector2i = _item_to_bucket[item] as Vector2i
	_item_to_bucket.erase(item)
	if not _items_by_chunk.has(bucket):
		return
	var arr: Array = _items_by_chunk[bucket] as Array
	arr.erase(item)
	if arr.is_empty():
		_items_by_chunk.erase(bucket)


## child_exiting_tree fires when an item is reparented (worker pickup) or
## freed. Either way we want it out of the loose-item index.
func _on_item_exiting_root(node: Node) -> void:
	if node is Item:
		_unregister_loose_item(node as Item)


func _try_post_haul_for(item: Item) -> void:
	if item == null or not is_instance_valid(item) or item.reserved_by != null:
		return
	if item.haul_blocked_until_msec > Time.get_ticks_msec():
		# Recently failed delivery; let the cooldown lapse before retrying so we
		# don't loop a worker on an unreachable / full destination.
		_schedule_delayed_match()
		return
	if _pending_haul_count() >= max_pending_haul_jobs:
		_schedule_match_loose_items()
		return
	var haul_amount: int = mini(item.count, Worker.MAX_CARRY_STACK)
	# Prefer the *nearest* viable stockpile cell instead of the first one in
	# `zones` order. Chebyshev distance matches the metric used elsewhere
	# (pathfinder cost, group orders), so workers don't trek across the
	# colony to drop something off when a closer stockpile has room.
	var item_grid: Vector2i = item.get_grid()
	var best_zone: StockpileZone = null
	var best_cell: Vector2i = Vector2i.ZERO
	var best_dist: int = 0x7fffffff
	for zone in zones:
		var cell_v: Variant = zone.first_free_cell_for(item.kind, haul_amount)
		if cell_v == null:
			continue
		var cell: Vector2i = cell_v
		var d: int = maxi(absi(cell.x - item_grid.x), absi(cell.y - item_grid.y))
		if d < best_dist:
			best_zone = zone
			best_cell = cell
			best_dist = d
	if best_zone == null:
		return
	best_zone.reserve(best_cell, item.kind)
	item.reserved_by = self
	_job_board.add_haul_job(item, best_zone, best_cell)
	_pending_haul_jobs += 1


func _pending_haul_count() -> int:
	return _pending_haul_jobs


func _schedule_match_loose_items() -> void:
	if _rematch_queued:
		return
	_rematch_queued = true
	call_deferred("_match_loose_items")


## Re-run the loose-item match once the haul cooldown window elapses. Uses a
## wall-clock SceneTreeTimer so the retry cadence matches the wall-clock
## `haul_blocked_until_msec` stamps regardless of game speed / pause.
func _schedule_delayed_match() -> void:
	if _delayed_match_pending:
		return
	_delayed_match_pending = true
	var timer: SceneTreeTimer = get_tree().create_timer(
		float(HAUL_RETRY_COOLDOWN_MS) / 1000.0 + 0.2, true, false, true)
	timer.timeout.connect(func() -> void:
		_delayed_match_pending = false
		_match_loose_items()
	)


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
				zone._refresh_cell_state(cell)
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
			_register_loose_item(item)
		if zone.cells.is_empty():
			zones.erase(zone)
			zone_removed.emit(zone)
			zone.queue_free()
	if any_change:
		stockpile_changed.emit()
		_match_loose_items()
