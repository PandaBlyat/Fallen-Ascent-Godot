class_name RoomManager
extends Node2D
##
## Tracks player-designated rooms (Rimworld-style). v1 supports a single room
## kind: DOCK_ROOM. A dock room is a 1x2+ floor area that contains at least one
## DOCK structure; rooms can be assigned to a single worker who satisfies their
## "needs dock room" need by having an assigned, valid room.
##

signal rooms_changed

enum Kind { DOCK_ROOM }

const ROOM_FILL := Color(0.45, 0.62, 0.98, 0.10)
const ROOM_BORDER := Color(0.45, 0.62, 0.98, 0.55)
const ROOM_INVALID_BORDER := Color(0.95, 0.45, 0.45, 0.65)
const MIN_ROOM_CELLS: int = 2

@export var structure_manager_path: NodePath
@export var chunk_manager_path: NodePath

var _structure_manager: StructureManager
var _chunk_manager: ChunkManager
var _rooms: Array[Dictionary] = []
var _cell_to_room: Dictionary = {}                   ## Vector2i -> Dictionary
var _next_id: int = 1


func _ready() -> void:
	_structure_manager = get_node_or_null(structure_manager_path) as StructureManager
	_chunk_manager = get_node_or_null(chunk_manager_path) as ChunkManager
	EventBus.structure_built.connect(_on_structure_built)


func create_dock_room(cells: Array[Vector2i]) -> Dictionary:
	# Filter to walkable cells not already in a room.
	var unique_cells: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell in cells:
		if seen.has(cell):
			continue
		if _cell_to_room.has(cell):
			continue
		if _chunk_manager != null and not _chunk_manager.is_grid_in_map(cell):
			continue
		seen[cell] = true
		unique_cells.append(cell)
	if unique_cells.size() < MIN_ROOM_CELLS:
		return {}
	var room: Dictionary = {
		"id": _next_id,
		"kind": Kind.DOCK_ROOM,
		"cells": unique_cells,
		"assigned_to": null,
	}
	_next_id += 1
	_rooms.append(room)
	for cell in unique_cells:
		_cell_to_room[cell] = room
	rooms_changed.emit()
	queue_redraw()
	return room


func remove_room_at(grid: Vector2i) -> void:
	var room: Dictionary = _cell_to_room.get(grid, {})
	if room.is_empty():
		return
	for cell in (room["cells"] as Array):
		_cell_to_room.erase(cell)
	_rooms.erase(room)
	rooms_changed.emit()
	queue_redraw()


func remove_all_rooms() -> void:
	if _rooms.is_empty():
		return
	_rooms.clear()
	_cell_to_room.clear()
	rooms_changed.emit()
	queue_redraw()


func room_at(grid: Vector2i) -> Dictionary:
	return _cell_to_room.get(grid, {})


func rooms() -> Array[Dictionary]:
	return _rooms


func is_room_valid(room: Dictionary) -> bool:
	if room.is_empty():
		return false
	if (room["cells"] as Array).size() < MIN_ROOM_CELLS:
		return false
	if int(room["kind"]) == Kind.DOCK_ROOM:
		return _room_has_dock(room)
	return true


func _room_has_dock(room: Dictionary) -> bool:
	if _structure_manager == null:
		return false
	for raw_cell in (room["cells"] as Array):
		var cell: Vector2i = raw_cell as Vector2i
		var s: Dictionary = _structure_manager.structure_at(cell)
		if s.is_empty():
			continue
		var sid: int = int(s["id"])
		if sid == BuildBlueprint.Id.DOCK or sid == BuildBlueprint.Id.MAINTENANCE_DOCK:
			return true
	return false


func ensure_dock_room_for(worker: Node) -> Dictionary:
	# If worker already has a valid assigned room, return it.
	var existing: Dictionary = _assigned_room_for(worker)
	if not existing.is_empty() and is_room_valid(existing):
		return existing
	# Try to claim an unassigned valid dock room.
	for room in _rooms:
		if int(room["kind"]) != Kind.DOCK_ROOM:
			continue
		if room.get("assigned_to") != null and room["assigned_to"] != worker:
			continue
		if not is_room_valid(room):
			continue
		room["assigned_to"] = worker
		rooms_changed.emit()
		return room
	return {}


func has_dock_room(worker: Node) -> bool:
	var room: Dictionary = _assigned_room_for(worker)
	return not room.is_empty() and is_room_valid(room)


func dock_anchor_for(worker: Node) -> Vector2i:
	var room: Dictionary = _assigned_room_for(worker)
	if room.is_empty() or _structure_manager == null:
		return Pathfinder.UNREACHABLE
	for raw_cell in (room["cells"] as Array):
		var cell: Vector2i = raw_cell as Vector2i
		var s: Dictionary = _structure_manager.structure_at(cell)
		if s.is_empty():
			continue
		var sid: int = int(s["id"])
		if sid == BuildBlueprint.Id.DOCK or sid == BuildBlueprint.Id.MAINTENANCE_DOCK:
			return s["anchor"] as Vector2i
	return Pathfinder.UNREACHABLE


func release_worker(worker: Node) -> void:
	for room in _rooms:
		if room.get("assigned_to") == worker:
			room["assigned_to"] = null
	rooms_changed.emit()


func _assigned_room_for(worker: Node) -> Dictionary:
	for room in _rooms:
		if room.get("assigned_to") == worker:
			return room
	return {}


func _on_structure_built(_manager: Node) -> void:
	# When new structures are placed, room validity may change.
	rooms_changed.emit()
	queue_redraw()


func _draw() -> void:
	for room in _rooms:
		var valid: bool = is_room_valid(room)
		var border: Color = ROOM_BORDER if valid else ROOM_INVALID_BORDER
		for raw_cell in (room["cells"] as Array):
			var cell: Vector2i = raw_cell as Vector2i
			var origin := Vector2(cell.x * Chunk.TILE_PIXELS, cell.y * Chunk.TILE_PIXELS)
			var rect := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
			draw_rect(rect, ROOM_FILL)
			draw_rect(rect, border, false, 1.0)
