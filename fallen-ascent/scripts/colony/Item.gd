class_name Item
extends Node2D
##
## A loose or stored object on the floor. Drawn as a small filled square.
## Lifecycle:
##   1. Spawned on a grid cell by ColonySite._spawn_item after a mine.
##   2. Reserved by a HaulJob (reserved_by = worker).
##   3. Picked up: reparented to the worker, kept hidden during carry.
##   4. Dropped: reparented to the StockpileZone, visible again, occupant
##      slot recorded on the zone.
##

enum Kind { SCRAP }

const SCRAP_COLOR := Color(0.85, 0.75, 0.25)
const SIZE_PX: float = 8.0

var kind: int = Kind.SCRAP
var grid: Vector2i = Vector2i.ZERO
var reserved_by: Node = null


func setup(g: Vector2i, k: int = Kind.SCRAP) -> void:
	grid = g
	kind = k
	position = Chunk.grid_to_pixel_center(g)
	queue_redraw()


func set_grid(g: Vector2i) -> void:
	grid = g
	position = Chunk.grid_to_pixel_center(g)


func get_grid() -> Vector2i:
	return grid


func _draw() -> void:
	var c: Color = SCRAP_COLOR
	var r := Rect2(-Vector2(SIZE_PX, SIZE_PX) * 0.5, Vector2(SIZE_PX, SIZE_PX))
	draw_rect(r, c)
