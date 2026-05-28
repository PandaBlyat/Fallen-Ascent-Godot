class_name ForbiddenZoneManager
extends Node2D
##
## Tracks cells the player has painted as forbidden. Workers with wander/
## roam behaviour will not pick forbidden cells as idle targets. Draws a
## semi-transparent red overlay over each forbidden cell.
##

const FILL_COLOR := Color(0.85, 0.12, 0.12, 0.28)
const BORDER_COLOR := Color(1.0, 0.22, 0.18, 0.55)

## All forbidden cells. Vector2i -> true.
var _cells: Dictionary = {}


func mark(cell: Vector2i) -> void:
	if _cells.has(cell):
		return
	_cells[cell] = true
	queue_redraw()


func unmark(cell: Vector2i) -> void:
	if not _cells.has(cell):
		return
	_cells.erase(cell)
	queue_redraw()


func is_forbidden(cell: Vector2i) -> bool:
	return _cells.has(cell)


func capture_save() -> Dictionary:
	var list: Array = []
	for cell in _cells:
		list.append(cell)
	return {"cells": list}


func restore_save(data: Dictionary) -> void:
	_cells.clear()
	for raw in data.get("cells", []) as Array:
		_cells[raw as Vector2i] = true
	queue_redraw()


func _draw() -> void:
	for raw_cell in _cells:
		var cell: Vector2i = raw_cell as Vector2i
		var origin := Vector2(cell.x * Chunk.TILE_PIXELS, cell.y * Chunk.TILE_PIXELS)
		var rect := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(rect, FILL_COLOR)
		draw_rect(rect, BORDER_COLOR, false, 0.8)
