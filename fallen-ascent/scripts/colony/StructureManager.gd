class_name StructureManager
extends Node2D
##
## Lightweight static-object layer for buildables that are not terrain tiles.
## Structures are plain dictionaries for now: id, anchor, cells, produce timer.
##

const EXTRACTOR_INTERVAL: float = 8.0
const FABRICATOR_INTERVAL: float = 12.0
const LIGHT_SIGHT_RADIUS: int = 8
const SENSOR_SIGHT_RADIUS: int = 15
const EXTRACTOR_COLOR := Color(0.25, 0.75, 0.9, 0.95)
const DOOR_COLOR := Color(0.9, 0.55, 0.25, 0.95)
const LIGHT_COLOR := Color(1.0, 0.9, 0.35, 0.95)
const SENSOR_COLOR := Color(0.45, 0.95, 0.65, 0.95)
const CHARGE_PAD_COLOR := Color(0.9, 0.45, 1.0, 0.95)
const FABRICATOR_COLOR := Color(0.95, 0.72, 0.38, 0.95)

@export var chunk_manager_path: NodePath
@export var items_root_path: NodePath
@export var stockpile_manager_path: NodePath

var _chunk_manager: ChunkManager
var _items_root: Node2D
var _stockpile_manager: StockpileManager
var _cell_to_structure: Dictionary = {}          ## Vector2i -> Dictionary
var _structures: Array[Dictionary] = []
var _accum: float = 0.0


func _ready() -> void:
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_items_root = get_node(items_root_path) as Node2D
	_stockpile_manager = get_node(stockpile_manager_path) as StockpileManager
	if _chunk_manager != null:
		_chunk_manager.set_structure_manager(self)


func can_place_blueprint(id: int, anchor: Vector2i) -> bool:
	for cell in BuildBlueprint.footprint(id, anchor):
		if not _chunk_manager.is_grid_in_map(cell):
			return false
		if _cell_to_structure.has(cell):
			return false
		var tile: int = _chunk_manager.get_tile_at(cell)
		if id == BuildBlueprint.Id.WALL:
			if tile != TerrainGenerator.TILE_FLOOR:
				return false
		else:
			if not _chunk_manager.is_walkable(cell):
				return false
		if _stockpile_manager != null and _stockpile_manager.zone_at(cell) != null:
			return false
	return true


func build_structure(id: int, anchor: Vector2i) -> void:
	var cells: Array[Vector2i] = BuildBlueprint.footprint(id, anchor)
	var structure: Dictionary = {
		"id": id,
		"anchor": anchor,
		"cells": cells,
		"timer": 0.0,
	}
	_structures.append(structure)
	for cell in cells:
		_cell_to_structure[cell] = structure
		if id == BuildBlueprint.Id.CHARGE_PAD:
			_chunk_manager.set_tile_at(cell, TerrainGenerator.TILE_OUTLET)
		EventBus.tile_changed.emit(cell, _chunk_manager.get_tile_at(cell))
	EventBus.structure_built.emit(self)
	queue_redraw()


func structure_at(grid: Vector2i) -> Dictionary:
	return _cell_to_structure.get(grid, {})


func structure_name_at(grid: Vector2i) -> String:
	var structure: Dictionary = structure_at(grid)
	if structure.is_empty():
		return ""
	return BuildBlueprint.display_name(int(structure["id"]))


func blocks_cell(grid: Vector2i) -> bool:
	var structure: Dictionary = structure_at(grid)
	if structure.is_empty():
		return false
	var id: int = int(structure["id"])
	return id == BuildBlueprint.Id.EXTRACTOR or id == BuildBlueprint.Id.FABRICATOR


func reveal_sources() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for structure in _structures:
		var id: int = int(structure["id"])
		if id == BuildBlueprint.Id.LIGHT:
			out.append({
				"grid": structure["anchor"] as Vector2i,
				"radius": LIGHT_SIGHT_RADIUS,
			})
		elif id == BuildBlueprint.Id.SENSOR:
			out.append({
				"grid": structure["anchor"] as Vector2i,
				"radius": SENSOR_SIGHT_RADIUS,
			})
	return out


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 1.0:
		return
	var tick: float = _accum
	_accum = 0.0
	for structure in _structures:
		var id: int = int(structure["id"])
		if id != BuildBlueprint.Id.EXTRACTOR and id != BuildBlueprint.Id.FABRICATOR:
			continue
		structure["timer"] = float(structure["timer"]) + tick
		var interval: float = FABRICATOR_INTERVAL if id == BuildBlueprint.Id.FABRICATOR else EXTRACTOR_INTERVAL
		if float(structure["timer"]) < interval:
			continue
		structure["timer"] = 0.0
		if id == BuildBlueprint.Id.FABRICATOR:
			_spawn_item_from(structure, Item.Kind.POWER_CELL if randf() < 0.25 else Item.Kind.CIRCUIT)
		else:
			_spawn_item_from(structure, Item.Kind.COMPONENT if randf() < 0.65 else Item.Kind.SUBSTRATE)


func _spawn_item_from(structure: Dictionary, kind: int) -> void:
	if _items_root == null:
		return
	var output: Vector2i = _first_output_cell(structure)
	if output == Pathfinder.UNREACHABLE:
		return
	var item := Item.new()
	_items_root.add_child(item)
	item.setup(output, kind, 1)
	if _stockpile_manager != null:
		_stockpile_manager.on_item_spawned(item)


func _first_output_cell(structure: Dictionary) -> Vector2i:
	var cells: Array = structure["cells"] as Array
	const OFFSETS: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	for raw_cell in cells:
		var cell: Vector2i = raw_cell as Vector2i
		for off in OFFSETS:
			var candidate: Vector2i = cell + off
			if _cell_to_structure.has(candidate):
				continue
			if _chunk_manager.is_walkable(candidate):
				return candidate
	return Pathfinder.UNREACHABLE


func _draw() -> void:
	for structure in _structures:
		var id: int = int(structure["id"])
		var color: Color = _color_for(id)
		var cells: Array = structure["cells"] as Array
		for raw_cell in cells:
			var cell: Vector2i = raw_cell as Vector2i
			var origin := Vector2(cell.x * Chunk.TILE_PIXELS, cell.y * Chunk.TILE_PIXELS)
			var r := Rect2(origin + Vector2(2, 2), Vector2(Chunk.TILE_PIXELS - 4, Chunk.TILE_PIXELS - 4))
			draw_rect(r, color)
			draw_rect(r, Color.BLACK, false, 1.0)


static func _color_for(id: int) -> Color:
	match id:
		BuildBlueprint.Id.DOOR:
			return DOOR_COLOR
		BuildBlueprint.Id.LIGHT:
			return LIGHT_COLOR
		BuildBlueprint.Id.EXTRACTOR:
			return EXTRACTOR_COLOR
		BuildBlueprint.Id.SENSOR:
			return SENSOR_COLOR
		BuildBlueprint.Id.CHARGE_PAD:
			return CHARGE_PAD_COLOR
		BuildBlueprint.Id.FABRICATOR:
			return FABRICATOR_COLOR
		_:
			return Color.WHITE
