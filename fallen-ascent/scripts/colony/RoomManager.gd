class_name RoomManager
extends Node2D
##
## Tracks player-designated rooms (Rimworld-style). Supported kinds:
##   - DOCK_ROOM         — personal rest space, one bot per room
##   - MEDITATION_CHAMBER — must contain a Meditation Pad; offers a wisdom bonus
##   - MECHANIC_ROOM     — must contain a Mechanic Dock; gates limb-heal services
##                         (heal effect itself is deferred — see to-do-list.md)
##
## A room is valid if it has the minimum cell count AND contains the required
## structure for its kind. Enclosure detection (Rimworld-style walls-only
## boundary) is intentionally deferred — see to-do-list.md.
##

signal rooms_changed

enum Kind { DOCK_ROOM, MEDITATION_CHAMBER, MECHANIC_ROOM }

const ROOM_FILL := Color(0.45, 0.62, 0.98, 0.05)
const ROOM_BORDER := Color(0.45, 0.62, 0.98, 0.30)
const ROOM_INVALID_BORDER := Color(0.95, 0.45, 0.45, 0.40)
const MEDITATION_BORDER := Color(0.62, 0.78, 1.0, 0.32)
const MECHANIC_BORDER := Color(0.98, 0.82, 0.42, 0.32)
const MIN_ROOM_CELLS: int = 2
const MECHANIC_HEAL_TICK_SECONDS: float = 1.0
const MECHANIC_LIMB_REPAIR_PER_SEC: float = 5.0

@export var structure_manager_path: NodePath
@export var chunk_manager_path: NodePath
@export var workers_root_path: NodePath

var _structure_manager: StructureManager
var _chunk_manager: ChunkManager
var _workers_root: Node2D
var _rooms: Array[Dictionary] = []
var _cell_to_room: Dictionary = {}                   ## Vector2i -> Dictionary
var _next_id: int = 1
var _mechanic_heal_accum: float = 0.0


func _ready() -> void:
	_structure_manager = get_node_or_null(structure_manager_path) as StructureManager
	_chunk_manager = get_node_or_null(chunk_manager_path) as ChunkManager
	_workers_root = get_node_or_null(workers_root_path) as Node2D
	EventBus.structure_built.connect(_on_structure_built)


func _process(delta: float) -> void:
	_mechanic_heal_accum += delta
	if _mechanic_heal_accum < MECHANIC_HEAL_TICK_SECONDS:
		return
	var elapsed: float = _mechanic_heal_accum
	_mechanic_heal_accum = 0.0
	_process_mechanic_heal(elapsed)


func create_dock_room(cells: Array[Vector2i]) -> Dictionary:
	return _create_room(Kind.DOCK_ROOM, cells)


func create_meditation_chamber(cells: Array[Vector2i]) -> Dictionary:
	return _create_room(Kind.MEDITATION_CHAMBER, cells)


func create_mechanic_room(cells: Array[Vector2i]) -> Dictionary:
	return _create_room(Kind.MECHANIC_ROOM, cells)


func _create_room(kind: int, cells: Array[Vector2i]) -> Dictionary:
	var unique_cells: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell in cells:
		if seen.has(cell):
			continue
		if _cell_to_room.has(cell):
			continue
		if not _can_designate_room_cell(cell, kind):
			continue
		seen[cell] = true
		unique_cells.append(cell)
	if unique_cells.size() < MIN_ROOM_CELLS:
		return {}
	var room: Dictionary = {
		"id": _next_id,
		"kind": kind,
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


func room_status_at(grid: Vector2i) -> String:
	var room: Dictionary = room_at(grid)
	if room.is_empty():
		return ""
	var name: String = _room_kind_name(int(room["kind"]))
	var valid: bool = is_room_valid(room)
	var assigned: Node = room.get("assigned_to") as Node
	if not valid:
		return name + ": invalid (" + invalid_reason(room) + ")"
	if assigned != null and is_instance_valid(assigned) and assigned.has_method("display_name"):
		return name + ": assigned to " + (assigned.call("display_name") as String)
	return name + ": unassigned"


func rooms() -> Array[Dictionary]:
	return _rooms


func valid_rooms_for_kind(kind: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room in _rooms:
		if int(room["kind"]) == kind and is_room_valid(room):
			out.append(room)
	return out


func workers_in_room(room: Dictionary) -> Array[Worker]:
	var out: Array[Worker] = []
	if room.is_empty() or _workers_root == null:
		return out
	var cells: Dictionary = {}
	for raw_cell in (room["cells"] as Array):
		cells[raw_cell as Vector2i] = true
	for child in _workers_root.get_children():
		var worker := child as Worker
		if worker == null or not is_instance_valid(worker):
			continue
		if cells.has(worker.current_grid()):
			out.append(worker)
	return out


func is_room_valid(room: Dictionary) -> bool:
	if room.is_empty():
		return false
	if (room["cells"] as Array).size() < MIN_ROOM_CELLS:
		return false
	var kind: int = int(room["kind"])
	match kind:
		Kind.DOCK_ROOM:
			return _room_has_structure(room, [BuildBlueprint.Id.DOCK, BuildBlueprint.Id.MAINTENANCE_DOCK])
		Kind.MEDITATION_CHAMBER:
			return _room_has_structure(room, [BuildBlueprint.Id.MEDITATION_PAD])
		Kind.MECHANIC_ROOM:
			return _room_has_structure(room, [BuildBlueprint.Id.MAINTENANCE_DOCK])
	return true


func invalid_reason(room: Dictionary) -> String:
	if room.is_empty():
		return "missing room"
	if (room["cells"] as Array).size() < MIN_ROOM_CELLS:
		return "too small"
	match int(room["kind"]):
		Kind.DOCK_ROOM:
			if not _room_has_structure(room, [BuildBlueprint.Id.DOCK, BuildBlueprint.Id.MAINTENANCE_DOCK]):
				return "needs dock"
		Kind.MEDITATION_CHAMBER:
			if not _room_has_structure(room, [BuildBlueprint.Id.MEDITATION_PAD]):
				return "needs meditation pad"
		Kind.MECHANIC_ROOM:
			if not _room_has_structure(room, [BuildBlueprint.Id.MAINTENANCE_DOCK]):
				return "needs mechanic dock"
	return "unknown"


func _can_designate_room_cell(cell: Vector2i, kind: int) -> bool:
	if _chunk_manager != null:
		if not _chunk_manager.is_grid_in_map(cell):
			return false
		if _chunk_manager.is_walkable(cell):
			return true
	if _structure_manager == null:
		return false
	var structure: Dictionary = _structure_manager.structure_at(cell)
	if structure.is_empty():
		return false
	var id: int = int(structure["id"])
	match kind:
		Kind.DOCK_ROOM:
			return id == BuildBlueprint.Id.DOCK or id == BuildBlueprint.Id.MAINTENANCE_DOCK
		Kind.MEDITATION_CHAMBER:
			return id == BuildBlueprint.Id.MEDITATION_PAD
		Kind.MECHANIC_ROOM:
			return id == BuildBlueprint.Id.MAINTENANCE_DOCK
	return false


func _room_has_structure(room: Dictionary, ids: Array) -> bool:
	if _structure_manager == null:
		return false
	for raw_cell in (room["cells"] as Array):
		var cell: Vector2i = raw_cell as Vector2i
		var s: Dictionary = _structure_manager.structure_at(cell)
		if s.is_empty():
			continue
		if ids.has(int(s["id"])):
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
	if room.is_empty():
		return false
	if int(room["kind"]) != Kind.DOCK_ROOM:
		return false
	return is_room_valid(room)


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


func _process_mechanic_heal(elapsed: float) -> void:
	for room in valid_rooms_for_kind(Kind.MECHANIC_ROOM):
		for worker in workers_in_room(room):
			if worker.has_method("repair_limbs_external"):
				worker.call("repair_limbs_external", MECHANIC_LIMB_REPAIR_PER_SEC * elapsed)


func _draw() -> void:
	for room in _rooms:
		var valid: bool = is_room_valid(room)
		var border: Color = _border_for_kind(int(room["kind"])) if valid else ROOM_INVALID_BORDER
		for raw_cell in (room["cells"] as Array):
			var cell: Vector2i = raw_cell as Vector2i
			var origin := Vector2(cell.x * Chunk.TILE_PIXELS, cell.y * Chunk.TILE_PIXELS)
			var rect := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
			draw_rect(rect, ROOM_FILL)
			draw_rect(rect, border, false, 0.8)


static func _border_for_kind(kind: int) -> Color:
	match kind:
		Kind.MEDITATION_CHAMBER:
			return MEDITATION_BORDER
		Kind.MECHANIC_ROOM:
			return MECHANIC_BORDER
		_:
			return ROOM_BORDER


static func _room_kind_name(kind: int) -> String:
	match kind:
		Kind.MEDITATION_CHAMBER:
			return "Meditation Chamber"
		Kind.MECHANIC_ROOM:
			return "Mechanic Room"
		_:
			return "Dock Room"
