class_name StockpileZone
extends Node2D
##
## A painted rectangle of floor cells designated as storage. Tracks per-cell
## occupancy: each cell holds at most one Item. Reserving a cell for an
## inbound HaulJob and placing the Item are two separate steps.
##

const FILL_COLOR := Color(0.25, 0.65, 0.35, 0.25)
const BORDER_COLOR := Color(0.4, 0.85, 0.5, 0.5)

var cells: Array[Vector2i] = []
var _cell_set: Dictionary = {}                   ## Vector2i -> true
var occupant: Dictionary = {}                    ## Vector2i -> Item (or "reserved")

const RESERVED_MARKER: String = "__reserved__"


func setup(zone_cells: Array[Vector2i]) -> void:
	cells = zone_cells
	for c in cells:
		_cell_set[c] = true
	queue_redraw()


func contains_cell(grid: Vector2i) -> bool:
	return _cell_set.has(grid)


func first_free_cell() -> Variant:
	for c in cells:
		if not occupant.has(c):
			return c
	return null


func reserve(cell: Vector2i) -> void:
	occupant[cell] = RESERVED_MARKER


func unreserve(cell: Vector2i) -> void:
	if occupant.get(cell) == RESERVED_MARKER:
		occupant.erase(cell)


func place(item: Item, cell: Vector2i) -> void:
	occupant[cell] = item


func take(cell: Vector2i) -> void:
	occupant.erase(cell)


func stored_count() -> int:
	var n: int = 0
	for v in occupant.values():
		if v is Item:
			n += 1
	return n


func _draw() -> void:
	for c in cells:
		var local := Vector2(
			c.x * Chunk.TILE_PIXELS,
			c.y * Chunk.TILE_PIXELS,
		)
		var r := Rect2(local, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(r, FILL_COLOR)
		draw_rect(r, BORDER_COLOR, false, 1.0)
