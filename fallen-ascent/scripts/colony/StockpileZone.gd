class_name StockpileZone
extends Node2D
##
## A painted rectangle of floor cells designated as storage. Tracks per-cell
## occupancy: each cell holds at most one Item stack. Reservations remember
## the inbound kind so two workers don't both pick the same merge slot.
##

const FILL_COLOR := Color(0.25, 0.65, 0.35, 0.25)
const BORDER_COLOR := Color(0.4, 0.85, 0.5, 0.5)
const MAX_STACK_PER_CELL: int = 16

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


func setup(zone_cells: Array[Vector2i]) -> void:
	cells = zone_cells
	for c in cells:
		_cell_set[c] = true
		_empty_cells[c] = true
	queue_redraw()


func contains_cell(grid: Vector2i) -> bool:
	return _cell_set.has(grid)


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
		return MAX_STACK_PER_CELL
	if v is Item:
		var item := v as Item
		if item.kind != kind:
			return 0
		return maxi(0, MAX_STACK_PER_CELL - item.count)
	if v is Dictionary:
		var d := v as Dictionary
		var existing: Item = d.get(R_EXISTING) as Item
		if existing != null and is_instance_valid(existing):
			if existing.kind != kind:
				return 0
			return maxi(0, MAX_STACK_PER_CELL - existing.count)
		if int(d.get(R_KIND, -1)) == kind:
			return MAX_STACK_PER_CELL
	return 0


func capacity() -> int:
	return cells.size() * MAX_STACK_PER_CELL


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
		var overflow: int = existing.add_to_stack(item.count)
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
	_empty_cells.erase(cell)
	for kind_bucket in _partials_by_kind.values():
		(kind_bucket as Dictionary).erase(cell)
	queue_redraw()
	if v is Item:
		return v as Item
	if v is Dictionary:
		var d := v as Dictionary
		return d.get(R_EXISTING) as Item
	return null


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
		if item.count < MAX_STACK_PER_CELL:
			partial_kind = item.kind
	elif v is Dictionary:
		var d := v as Dictionary
		var existing: Item = d.get(R_EXISTING) as Item
		if existing != null and is_instance_valid(existing):
			if existing.count < MAX_STACK_PER_CELL:
				partial_kind = existing.kind
		else:
			partial_kind = int(d.get(R_KIND, -1))
	if partial_kind >= 0:
		if not _partials_by_kind.has(partial_kind):
			_partials_by_kind[partial_kind] = {}
		(_partials_by_kind[partial_kind] as Dictionary)[cell] = true


func _draw() -> void:
	for c in cells:
		var local := Vector2(
			c.x * Chunk.TILE_PIXELS,
			c.y * Chunk.TILE_PIXELS,
		)
		var r := Rect2(local, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(r, FILL_COLOR)
		draw_rect(r, BORDER_COLOR, false, 1.0)
