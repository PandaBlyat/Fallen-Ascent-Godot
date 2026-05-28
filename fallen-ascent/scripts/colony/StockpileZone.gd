class_name StockpileZone
extends Node2D
##
## A painted rectangle of floor cells designated as storage. Tracks per-cell
## occupancy: each cell holds at most one Item stack. Reservations remember
## the inbound kind so two workers don't both pick the same merge slot.
##

const FILL_COLOR := Color(0.25, 0.65, 0.35, 0.25)
const BORDER_COLOR := Color(0.4, 0.85, 0.5, 0.5)
const MAX_STACK_PER_CELL: int = 4
const STORAGE_BIN_STACK_PER_CELL: int = 12

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


func setup(zone_cells: Array[Vector2i]) -> void:
	cells = zone_cells
	for c in cells:
		_cell_set[c] = true
		_empty_cells[c] = true
	_perimeter_dirty = true
	queue_redraw()


func contains_cell(grid: Vector2i) -> bool:
	return _cell_set.has(grid)


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
		var it: Item = null
		if v is Item:
			it = v as Item
		elif v is Dictionary:
			it = (v as Dictionary).get(R_EXISTING) as Item
		if it != null and is_instance_valid(it) and it.count > 0:
			items.append([cell, int(it.kind), int(it.count)])
	return {"cells": cell_list, "capacity": cap, "items": items}


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
		add_child(item)
		place(item, cell)


## Picks a cell that can accept `amount` of `kind`:
##   1. A same-kind stack/reservation with enough room.
##   2. An empty cell.
## Returns null if no slot is suitable.
func first_free_cell_for(kind: int, amount: int = 1) -> Variant:
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
	if v is Item:
		var item := v as Item
		if item.kind != kind:
			return 0
		return maxi(0, _stack_limit_at(cell) - item.count)
	if v is Dictionary:
		var d := v as Dictionary
		var existing: Item = d.get(R_EXISTING) as Item
		if existing != null and is_instance_valid(existing):
			if existing.kind != kind:
				return 0
			return maxi(0, _stack_limit_at(cell) - existing.count)
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
		if v is Item:
			n += 1
		elif v is Dictionary:
			var d := v as Dictionary
			var existing: Item = d.get(R_EXISTING) as Item
			if existing != null and is_instance_valid(existing):
				n += 1
	return n


func resource_counts() -> Dictionary:
	var counts: Dictionary = {}
	for v in occupant.values():
		var item: Item = null
		if v is Item:
			item = v as Item
		elif v is Dictionary:
			item = (v as Dictionary).get(R_EXISTING) as Item
		if item != null and is_instance_valid(item) and item.count > 0:
			counts[item.kind] = int(counts.get(item.kind, 0)) + item.count
	return counts


func stored_count_for_kind(kind: int) -> int:
	var n: int = 0
	for v in occupant.values():
		var item: Item = null
		if v is Item:
			item = v as Item
		elif v is Dictionary:
			item = (v as Dictionary).get(R_EXISTING) as Item
		if item != null and is_instance_valid(item) and item.kind == kind:
			n += item.count
	return n


func reserve(cell: Vector2i, kind: int) -> void:
	var v: Variant = occupant.get(cell)
	var existing: Item = null
	if v is Item:
		existing = v as Item
	occupant[cell] = {R_KIND: kind, R_EXISTING: existing}
	_refresh_cell_state(cell)


func unreserve(cell: Vector2i) -> void:
	var v: Variant = occupant.get(cell)
	if not (v is Dictionary):
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
	if v is Dictionary:
		return (v as Dictionary).get(R_KIND, -1)
	if v is Item:
		return (v as Item).kind
	return -1


## Place a stack into `cell`. If a matching-kind stack already lives there,
## merge counts (capped at MAX_STACK_PER_CELL). Overflow remains on the
## incoming Item so the caller can drop or rematch it. The returned Item is
## the live occupant.
func place(item: Item, cell: Vector2i) -> Item:
	# Pull the previous existing (from reservation) so we can decide to merge.
	var prev: Variant = occupant.get(cell)
	var existing: Item = null
	if prev is Dictionary:
		var d := prev as Dictionary
		existing = d.get(R_EXISTING) as Item
	elif prev is Item:
		existing = prev as Item

	if existing != null and is_instance_valid(existing) and existing.kind == item.kind:
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
		if v is Item:
			n += (v as Item).count
		elif v is Dictionary and (v as Dictionary).has(R_EXISTING):
			var ex: Item = (v as Dictionary)[R_EXISTING] as Item
			if ex != null and is_instance_valid(ex):
				n += ex.count
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
	if v is Item:
		return v as Item
	if v is Dictionary:
		var d := v as Dictionary
		return d.get(R_EXISTING) as Item
	return null


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
	if v is Item:
		var item := v as Item
		if item.count < _stack_limit_at(cell):
			partial_kind = item.kind
	elif v is Dictionary:
		var d := v as Dictionary
		var existing: Item = d.get(R_EXISTING) as Item
		if existing != null and is_instance_valid(existing):
			if existing.count < _stack_limit_at(cell):
				partial_kind = existing.kind
		else:
			partial_kind = int(d.get(R_KIND, -1))
	if partial_kind >= 0:
		if not _partials_by_kind.has(partial_kind):
			_partials_by_kind[partial_kind] = {}
		(_partials_by_kind[partial_kind] as Dictionary)[cell] = true


func _draw() -> void:
	if _perimeter_dirty:
		_rebuild_perimeter_edges()
	if not _perimeter_edges.is_empty():
		draw_multiline(_perimeter_edges, BORDER_COLOR, 1.0)


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
