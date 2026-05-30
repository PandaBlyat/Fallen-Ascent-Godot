class_name StockpileZone
extends Node2D
##
## A painted rectangle of floor cells designated as storage. Tracks per-cell
## occupancy: each cell holds at most one Item stack. Reservations remember
## the inbound kind so two workers don't both pick the same merge slot.
##

const FILL_COLOR := Color(0.25, 0.65, 0.35, 0.25)
const BORDER_COLOR := Color(0.4, 0.85, 0.5, 0.5)
const CUSTOM_FILL_COLOR := Color(0.25, 0.40, 0.72, 0.25)
const CUSTOM_BORDER_COLOR := Color(0.40, 0.60, 0.92, 0.55)
const HOVER_FILL_COLOR := Color(0.35, 0.85, 0.50, 0.18)
const HOVER_CUSTOM_FILL_COLOR := Color(0.35, 0.55, 0.92, 0.18)
const MAX_STACK_PER_CELL: int = 4
const STORAGE_BIN_STACK_PER_CELL: int = 12
const ENCLOSURE_SEARCH_LIMIT: int = 1024

# Reservation dict keys.
const R_KIND: String = "kind"
const R_EXISTING: String = "existing"

var cells: Array[Vector2i] = []
var _cell_set: Dictionary = {}                   ## Vector2i -> true
## Vector2i -> Item (placed) | Dictionary (reservation).
## A reservation may hold an existing Item that gets restored on unreserve
## (so a same-kind merge can be paused/cancelled cleanly).
var occupant: Dictionary = {}
## Cells with no occupant. Lets first_free_cell_for return an empty cell
## in O(1) instead of scanning the full cells array.
var _empty_cells: Dictionary = {}                ## Vector2i -> true
## Cells that can still accept a given kind (partial stack or reserved
## slot). Lets first_free_cell_for find a merge slot in O(1) common case.
var _partials_by_kind: Dictionary = {}           ## kind:int -> Dictionary[Vector2i, true]
var _capacity_multipliers: Dictionary = {}       ## Vector2i -> int
var _perimeter_edges := PackedVector2Array()
var _perimeter_dirty: bool = true
## Cached enclosure state. Invalidated when terrain/structures change.
var _enclosed: bool = false
var _enclosure_dirty: bool = true
## When non-empty, only these item kinds are accepted for new hauls.
## Existing stored items are not affected.
var allowed_kinds: Array = []
## Degradation tracking for detailed UI display.
var _degrade_total_items_lost: int = 0
var _degrade_total_condition_damage: float = 0.0
var _degrade_avg_condition: float = 100.0
var _hovered: bool = false


func setup(zone_cells: Array[Vector2i]) -> void:
	cells = zone_cells
	for c in cells:
		_cell_set[c] = true
		_empty_cells[c] = true
	_perimeter_dirty = true
	queue_redraw()


func contains_cell(grid: Vector2i) -> bool:
	return _cell_set.has(grid)


## Safely extract an Item from an occupant value. Handles freed instances
## (queue_freed items still in the dict) by returning null.
static func _occupant_item(v: Variant) -> Item:
	if v == null:
		return null
	if typeof(v) == TYPE_OBJECT:
		if not is_instance_valid(v as Object):
			return null
		if v is Item:
			return v as Item
		return null
	if v is Dictionary:
		var d := v as Dictionary
		var existing: Variant = d.get(R_EXISTING)
		if existing != null and typeof(existing) == TYPE_OBJECT and is_instance_valid(existing as Object):
			return existing as Item
	return null


## True when the occupant value is a reservation dict (not a placed Item).
static func _occupant_is_reservation(v: Variant) -> bool:
	if v == null:
		return false
	if typeof(v) == TYPE_OBJECT:
		if not is_instance_valid(v as Object):
			return false
		return false
	return v is Dictionary


func set_hovered(hovered: bool) -> void:
	if _hovered == hovered:
		return
	_hovered = hovered
	queue_redraw()


## True when any item filter is active.
func is_customized() -> bool:
	return not allowed_kinds.is_empty()


func accepts_kind(kind: int) -> bool:
	if allowed_kinds.is_empty():
		return true
	return allowed_kinds.has(kind)


func toggle_kind_allowed(kind: int) -> void:
	if allowed_kinds.has(kind):
		allowed_kinds.erase(kind)
	else:
		allowed_kinds.append(kind)
	_perimeter_dirty = true
	queue_redraw()


func set_all_kinds_allowed() -> void:
	allowed_kinds.clear()
	_perimeter_dirty = true
	queue_redraw()


func clear_all_kinds_allowed() -> void:
	allowed_kinds.clear()
	for k in range(Item.Kind.size()):
		allowed_kinds.append(k)
	_perimeter_dirty = true
	queue_redraw()


func degrade_stats() -> Dictionary:
	return {
		"items_lost": _degrade_total_items_lost,
		"condition_damage": _degrade_total_condition_damage,
		"avg_condition": _degrade_avg_condition,
	}


func reset_degrade_stats() -> void:
	_degrade_total_items_lost = 0
	_degrade_total_condition_damage = 0.0
	_degrade_avg_condition = 100.0


func _update_avg_condition() -> void:
	var total: float = 0.0
	var n: int = 0
	for v in occupant.values():
		var item: Item = _occupant_item(v)
		if item != null and item.count > 0:
			total += item.condition
			n += 1
	_degrade_avg_condition = total / float(maxi(n, 1))


## Remove cells from this zone. Returns array of [cell, Item|null] for each
## detached cell so the caller (StockpileManager) can handle haul cancellation
## and item re-homing.
func remove_cells(cells_to_remove: Array[Vector2i]) -> Array:
	var result: Array = []
	for cell in cells_to_remove:
		if not contains_cell(cell):
			continue
		var item: Item = detach_cell(cell)
		result.append([cell, item])
	return result


## Save layer: cells, per-cell capacity bumps, and the placed stacks. Inbound
## reservations are transient and intentionally dropped.
func capture_save() -> Dictionary:
	var cell_list: Array = []
	for c in cells:
		cell_list.append(c)
	var cap: Array = []
	for cell in _capacity_multipliers:
		cap.append([cell, int(_capacity_multipliers[cell])])
	var items: Array = []
	for cell in occupant:
		var v: Variant = occupant[cell]
		var it: Item = _occupant_item(v)
		if it != null and it.count > 0:
			items.append([cell, int(it.kind), int(it.count), float(it.condition)])
	var filter: Array = []
	for k in allowed_kinds:
		filter.append(int(k))
	return {
		"cells": cell_list,
		"capacity": cap,
		"items": items,
		"filter": filter,
		"degrade_lost": _degrade_total_items_lost,
		"degrade_damage": _degrade_total_condition_damage,
	}


## Rebuild a zone from saved data. `make_item` is a Callable returning a fresh
## Item the zone takes ownership of (the manager supplies it so the zone has no
## dependency on the item scene path).
func restore_save(data: Dictionary, make_item: Callable) -> void:
	var zone_cells: Array[Vector2i] = []
	for c in (data.get("cells", []) as Array):
		zone_cells.append(c as Vector2i)
	setup(zone_cells)
	for entry in data.get("capacity", []) as Array:
		set_capacity_multiplier(entry[0] as Vector2i, int(entry[1]))
	for entry in data.get("items", []) as Array:
		var cell: Vector2i = entry[0] as Vector2i
		var item: Item = make_item.call(cell, int(entry[1]), int(entry[2])) as Item
		if item == null:
			continue
		if entry.size() > 3:
			item.condition = float(entry[3])
		add_child(item)
		place(item, cell)
	var filter_data: Array = data.get("filter", []) as Array
	if not filter_data.is_empty():
		allowed_kinds.clear()
		for k in filter_data:
			allowed_kinds.append(int(k))
	_degrade_total_items_lost = int(data.get("degrade_lost", 0))
	_degrade_total_condition_damage = float(data.get("degrade_damage", 0.0))
	_update_avg_condition()


## Picks a cell that can accept `amount` of `kind`:
##   1. A same-kind stack/reservation with enough room.
##   2. An empty cell.
## Returns null if no slot is suitable.
func first_free_cell_for(kind: int, amount: int = 1) -> Variant:
	if not accepts_kind(kind):
		return null
	var partials: Dictionary = _partials_by_kind.get(kind, {}) as Dictionary
	for c in partials.keys():
		if room_at(c, kind) >= amount:
			return c
	if not _empty_cells.is_empty():
		return _empty_cells.keys()[0]
	return null


func room_at(cell: Vector2i, kind: int) -> int:
	var v: Variant = occupant.get(cell)
	if v == null:
		return _stack_limit_at(cell)
	var item: Item = _occupant_item(v)
	if item != null:
		if item.kind != kind:
			return 0
		return maxi(0, _stack_limit_at(cell) - item.count)
	if _occupant_is_reservation(v):
		var d := v as Dictionary
		if int(d.get(R_KIND, -1)) == kind:
			return _stack_limit_at(cell)
	return 0


func capacity() -> int:
	var total: int = 0
	for cell in cells:
		total += cell_capacity(cell)
	return total


func stack_capacity() -> int:
	return cells.size()


func stack_count() -> int:
	var n: int = 0
	for v in occupant.values():
		if _occupant_item(v) != null:
			n += 1
	return n


func resource_counts() -> Dictionary:
	var counts: Dictionary = {}
	for v in occupant.values():
		var item: Item = _occupant_item(v)
		if item != null and item.count > 0:
			counts[item.kind] = int(counts.get(item.kind, 0)) + item.count
	return counts


func stored_count_for_kind(kind: int) -> int:
	var n: int = 0
	for v in occupant.values():
		var item: Item = _occupant_item(v)
		if item != null and item.kind == kind:
			n += item.count
	return n


func reserve(cell: Vector2i, kind: int) -> void:
	var v: Variant = occupant.get(cell)
	var existing: Item = _occupant_item(v)
	occupant[cell] = {R_KIND: kind, R_EXISTING: existing}
	_refresh_cell_state(cell)


func unreserve(cell: Vector2i) -> void:
	var v: Variant = occupant.get(cell)
	if not _occupant_is_reservation(v):
		return
	var d := v as Dictionary
	var existing: Item = d.get(R_EXISTING) as Item
	if existing != null and is_instance_valid(existing):
		occupant[cell] = existing
	else:
		occupant.erase(cell)
	_refresh_cell_state(cell)


func reserved_kind_at(cell: Vector2i) -> int:
	var v: Variant = occupant.get(cell)
	if _occupant_is_reservation(v):
		return (v as Dictionary).get(R_KIND, -1)
	var item: Item = _occupant_item(v)
	if item != null:
		return item.kind
	return -1


## Place a stack into `cell`. If a matching-kind stack already lives there,
## merge counts (capped at MAX_STACK_PER_CELL). Overflow remains on the
## incoming Item so the caller can drop or rematch it. The returned Item is
## the live occupant.
func place(item: Item, cell: Vector2i) -> Item:
	# Pull the previous existing (from reservation) so we can decide to merge.
	var prev: Variant = occupant.get(cell)
	var existing: Item = _occupant_item(prev)

	if existing != null and existing.kind == item.kind:
		var overflow: int = existing.add_to_stack(item.count, _stack_limit_at(cell))
		item.count = overflow
		if overflow <= 0 and item.get_parent() != null:
			item.get_parent().remove_child(item)
			item.queue_free()
		else:
			item.queue_redraw()
		occupant[cell] = existing
		_refresh_cell_state(cell)
		return existing

	occupant[cell] = item
	_refresh_cell_state(cell)
	return item


func take(cell: Vector2i) -> void:
	occupant.erase(cell)
	_refresh_cell_state(cell)


func stored_count() -> int:
	var n: int = 0
	for v in occupant.values():
		var item: Item = _occupant_item(v)
		if item != null:
			n += item.count
	return n


## Removes a cell from the zone (used by re-validation when terrain changes
## under the zone). Returns the placed Item (if any) so the caller can
## drop it as a loose item.
func detach_cell(cell: Vector2i) -> Item:
	var v: Variant = occupant.get(cell)
	occupant.erase(cell)
	_cell_set.erase(cell)
	cells.erase(cell)
	_capacity_multipliers.erase(cell)
	_empty_cells.erase(cell)
	_perimeter_dirty = true
	for kind_bucket in _partials_by_kind.values():
		(kind_bucket as Dictionary).erase(cell)
	queue_redraw()
	return _occupant_item(v)


func set_capacity_multiplier(cell: Vector2i, multiplier: int) -> void:
	if not contains_cell(cell):
		return
	if multiplier <= 1:
		_capacity_multipliers.erase(cell)
	else:
		_capacity_multipliers[cell] = multiplier
	_refresh_cell_state(cell)
	queue_redraw()


func _stack_limit_at(cell: Vector2i) -> int:
	return cell_capacity(cell)


func cell_capacity(cell: Vector2i) -> int:
	if int(_capacity_multipliers.get(cell, 1)) > 1:
		return STORAGE_BIN_STACK_PER_CELL
	return MAX_STACK_PER_CELL


## Mark the cached enclosure state as stale. Called when terrain or structures
## change near the zone.
func invalidate_enclosure() -> void:
	_enclosure_dirty = true


## True when every cell just outside the zone perimeter is a solid wall tile
## or a player-built wall/door structure. A zone with no perimeter neighbors
## (fully interior) counts as enclosed.
func is_enclosed(chunk_manager: ChunkManager, structure_manager: StructureManager) -> bool:
	if not _enclosure_dirty:
		return _enclosed
	_enclosed = _compute_enclosed(chunk_manager, structure_manager)
	_enclosure_dirty = false
	return _enclosed


func _compute_enclosed(chunk_manager: ChunkManager, structure_manager: StructureManager) -> bool:
	if cells.is_empty():
		return false
	const NEIGHBORS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var visited: Dictionary = {}
	for c in cells:
		visited[c] = true
	var queue: Array[Vector2i] = cells.duplicate()
	var has_door: bool = false
	var checked: int = 0
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		checked += 1
		if checked > ENCLOSURE_SEARCH_LIMIT:
			return false
		for off in NEIGHBORS:
			var n: Vector2i = current + off
			if visited.has(n):
				continue
			visited[n] = true
			if not chunk_manager.is_walkable(n):
				continue
			var s: Dictionary = structure_manager.structure_at(n)
			if not s.is_empty():
				var sid: int = int(s.get("id", -1))
				if sid == BuildBlueprint.Id.WALL:
					continue
				if sid == BuildBlueprint.Id.DOOR:
					has_door = true
					continue
			queue.append(n)
	if not has_door:
		return false
	return true




## Degrade all stored items in this zone. Returns an array of cells whose
## stack was fully consumed (so the caller can clean up).
func degrade_exposed_items(amount: float) -> Array[Vector2i]:
	var consumed: Array[Vector2i] = []
	for cell in cells:
		var v: Variant = occupant.get(cell)
		var item: Item = _occupant_item(v)
		if item == null:
			continue
		var prev_condition: float = item.condition
		var prev_count: int = item.count
		if item.degrade(amount):
			consumed.append(cell)
			take(cell)
			if item.get_parent() == self:
				remove_child(item)
			item.queue_free()
			_degrade_total_items_lost += prev_count
			_degrade_total_condition_damage += prev_condition
		else:
			var damage: float = prev_condition - item.condition
			if damage < 0.0:
				damage = prev_condition + (100.0 - item.condition)
			_degrade_total_condition_damage += damage
			var items_lost: int = prev_count - item.count
			if items_lost > 0:
				_degrade_total_items_lost += items_lost
	_update_avg_condition()
	return consumed


## Clear all index entries for `cell`, then re-classify based on the current
## `occupant` state. Called from every mutator so the indexes stay in sync.
func _refresh_cell_state(cell: Vector2i) -> void:
	_empty_cells.erase(cell)
	for kind_bucket in _partials_by_kind.values():
		(kind_bucket as Dictionary).erase(cell)
	if not occupant.has(cell):
		_empty_cells[cell] = true
		return
	var v: Variant = occupant[cell]
	var partial_kind: int = -1
	var item: Item = _occupant_item(v)
	if item != null:
		if item.count < _stack_limit_at(cell):
			partial_kind = item.kind
	elif _occupant_is_reservation(v):
		partial_kind = int((v as Dictionary).get(R_KIND, -1))
	if partial_kind >= 0:
		if not _partials_by_kind.has(partial_kind):
			_partials_by_kind[partial_kind] = {}
		(_partials_by_kind[partial_kind] as Dictionary)[cell] = true


func _draw() -> void:
	if _perimeter_dirty:
		_rebuild_perimeter_edges()
	if _hovered:
		var hover_fill: Color = HOVER_CUSTOM_FILL_COLOR if is_customized() else HOVER_FILL_COLOR
		for c in cells:
			var origin := Vector2(c.x * Chunk.TILE_PIXELS, c.y * Chunk.TILE_PIXELS)
			var rect := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
			draw_rect(rect, hover_fill)
	if not _perimeter_edges.is_empty():
		var border: Color = CUSTOM_BORDER_COLOR if is_customized() else BORDER_COLOR
		draw_multiline(_perimeter_edges, border, 1.0)


func _rebuild_perimeter_edges() -> void:
	_perimeter_edges.clear()
	for c in cells:
		var x: float = c.x * Chunk.TILE_PIXELS
		var y: float = c.y * Chunk.TILE_PIXELS
		var s: float = Chunk.TILE_PIXELS
		if not _cell_set.has(c + Vector2i(0, -1)):
			_perimeter_edges.append(Vector2(x, y))
			_perimeter_edges.append(Vector2(x + s, y))
		if not _cell_set.has(c + Vector2i(1, 0)):
			_perimeter_edges.append(Vector2(x + s, y))
			_perimeter_edges.append(Vector2(x + s, y + s))
		if not _cell_set.has(c + Vector2i(0, 1)):
			_perimeter_edges.append(Vector2(x + s, y + s))
			_perimeter_edges.append(Vector2(x, y + s))
		if not _cell_set.has(c + Vector2i(-1, 0)):
			_perimeter_edges.append(Vector2(x, y + s))
			_perimeter_edges.append(Vector2(x, y))
	_perimeter_dirty = false
