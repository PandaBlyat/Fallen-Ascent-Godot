class_name StockpileZone
extends Node2D
##
## A painted rectangle of floor cells designated as storage. Tracks per-cell
## occupancy: each cell holds at most one Item stack. Reservations remember
## the inbound kind so two workers don't both pick the same merge slot.
##

const FILL_COLOR := Color(0.25, 0.65, 0.35, 0.25)
const BORDER_COLOR := Color(0.4, 0.85, 0.5, 0.5)

# Reservation dict keys.
const R_KIND: String = "kind"
const R_EXISTING: String = "existing"

var cells: Array[Vector2i] = []
var _cell_set: Dictionary = {}                   ## Vector2i -> true
## Vector2i -> Item (placed) | Dictionary (reservation).
## A reservation may hold an existing Item that gets restored on unreserve
## (so a same-kind merge can be paused/cancelled cleanly).
var occupant: Dictionary = {}


func setup(zone_cells: Array[Vector2i]) -> void:
	cells = zone_cells
	for c in cells:
		_cell_set[c] = true
	queue_redraw()


func contains_cell(grid: Vector2i) -> bool:
	return _cell_set.has(grid)


## Picks a cell that can accept a stack of `kind`:
##   1. A free cell.
##   2. A cell holding a non-reserved same-kind stack with room < MAX_STACK.
## Returns null if no slot is suitable.
func first_free_cell_for(kind: int) -> Variant:
	# Prefer empty cells (no fragmentation): keeps stacks visible per cell.
	for c in cells:
		if not occupant.has(c):
			return c
	for c in cells:
		var v: Variant = occupant.get(c)
		if v is Item and (v as Item).kind == kind and (v as Item).count < Item.MAX_STACK:
			return c
	return null


func reserve(cell: Vector2i, kind: int) -> void:
	var v: Variant = occupant.get(cell)
	var existing: Item = null
	if v is Item:
		existing = v as Item
	occupant[cell] = {R_KIND: kind, R_EXISTING: existing}


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


func reserved_kind_at(cell: Vector2i) -> int:
	var v: Variant = occupant.get(cell)
	if v is Dictionary:
		return (v as Dictionary).get(R_KIND, -1)
	if v is Item:
		return (v as Item).kind
	return -1


## Place a stack into `cell`. If a matching-kind stack already lives there,
## merge counts (capped at MAX_STACK) and free the incoming Item. The
## returned Item is the live occupant.
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
		if item.get_parent() != null:
			item.get_parent().remove_child(item)
		item.queue_free()
		occupant[cell] = existing
		return existing

	occupant[cell] = item
	return item


func take(cell: Vector2i) -> void:
	occupant.erase(cell)


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
	queue_redraw()
	if v is Item:
		return v as Item
	if v is Dictionary:
		var d := v as Dictionary
		return d.get(R_EXISTING) as Item
	return null


func _draw() -> void:
	for c in cells:
		var local := Vector2(
			c.x * Chunk.TILE_PIXELS,
			c.y * Chunk.TILE_PIXELS,
		)
		var r := Rect2(local, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(r, FILL_COLOR)
		draw_rect(r, BORDER_COLOR, false, 1.0)
