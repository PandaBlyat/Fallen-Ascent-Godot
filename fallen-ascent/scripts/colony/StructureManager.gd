class_name StructureManager
extends Node2D
##
## Lightweight static-object layer for buildables that are not terrain tiles.
## Structures are plain dictionaries for now: id, anchor, cells, produce timer.
##

const LIGHT_SIGHT_RADIUS: int = 8
const SENSOR_SIGHT_RADIUS: int = 15
const EXTRACTOR_COLOR := Color(0.25, 0.75, 0.9, 0.95)
const DOOR_COLOR := Color(0.9, 0.55, 0.25, 0.95)
const LIGHT_COLOR := Color(1.0, 0.9, 0.35, 0.95)
const SENSOR_COLOR := Color(0.45, 0.95, 0.65, 0.95)
const CHARGE_PAD_COLOR := Color(0.9, 0.45, 1.0, 0.95)
const FABRICATOR_COLOR := Color(0.95, 0.72, 0.38, 0.95)
const DOCK_COLOR := Color(0.45, 0.62, 0.98, 0.95)
const REPAIR_BENCH_COLOR := Color(0.95, 0.52, 0.38, 0.95)
const PARTS_LOOM_COLOR := Color(0.58, 0.95, 0.82, 0.95)
const MAINTENANCE_DOCK_COLOR := Color(0.98, 0.82, 0.42, 0.95)
const CALIBRATION_SHRINE_COLOR := Color(0.72, 0.58, 1.0, 0.95)
const MEDITATION_PAD_COLOR := Color(0.62, 0.78, 1.0, 0.95)
const SENTIENCE_CRADLE_COLOR := Color(0.95, 0.88, 0.55, 0.95)

@export var chunk_manager_path: NodePath
@export var items_root_path: NodePath
@export var stockpile_manager_path: NodePath
@export var workers_root_path: NodePath
@export var job_board_path: NodePath
@export var pathfinder_path: NodePath
@export var fog_of_war_path: NodePath
@export var room_manager_path: NodePath
@export var colony_site_path: NodePath

var _chunk_manager: ChunkManager
var _items_root: Node2D
var _stockpile_manager: StockpileManager
var _workers_root: Node2D
var _job_board: JobBoard
var _pathfinder: Pathfinder
var _fog: FogOfWar
var _room_manager: Node
var _colony_site: Node
var _cell_to_structure: Dictionary = {}          ## Vector2i -> Dictionary
var _structures: Array[Dictionary] = []
var _accum: float = 0.0


func _ready() -> void:
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_items_root = get_node(items_root_path) as Node2D
	_stockpile_manager = get_node(stockpile_manager_path) as StockpileManager
	_workers_root = get_node_or_null(workers_root_path) as Node2D
	_job_board = get_node_or_null(job_board_path) as JobBoard
	_pathfinder = get_node_or_null(pathfinder_path) as Pathfinder
	_fog = get_node_or_null(fog_of_war_path) as FogOfWar
	_room_manager = get_node_or_null(room_manager_path)
	_colony_site = get_node_or_null(colony_site_path)
	if _chunk_manager != null:
		_chunk_manager.set_structure_manager(self)


func can_place_blueprint(id: int, anchor: Vector2i, rotation: int = 0) -> bool:
	var has_outlet: bool = false
	for cell in BuildBlueprint.footprint(id, anchor, rotation):
		if not _chunk_manager.is_grid_in_map(cell):
			return false
		if _cell_to_structure.has(cell):
			return false
		var tile: int = _chunk_manager.get_tile_at(cell)
		if tile == TerrainGenerator.TILE_OUTLET:
			has_outlet = true
		if id == BuildBlueprint.Id.WALL:
			if tile != TerrainGenerator.TILE_FLOOR:
				return false
		else:
			if not _chunk_manager.is_walkable(cell):
				return false
		if _stockpile_manager != null and _stockpile_manager.zone_at(cell) != null:
			return false
	if BuildBlueprint.requires_outlet(id) and not has_outlet:
		return false
	return true


func build_structure(id: int, anchor: Vector2i, rotation: int = 0) -> void:
	var cells: Array[Vector2i] = BuildBlueprint.footprint(id, anchor, rotation)
	var structure: Dictionary = {
		"id": id,
		"anchor": anchor,
		"rotation": posmod(rotation, 4),
		"cells": cells,
		"timer": 0.0,
		"blocked": "",
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


func structure_status_at(grid: Vector2i) -> Dictionary:
	var structure: Dictionary = structure_at(grid)
	if structure.is_empty():
		return {}
	return _status_for(structure)


func structure_status_by_anchor(anchor: Vector2i) -> Dictionary:
	for structure in _structures:
		if (structure["anchor"] as Vector2i) == anchor:
			return _status_for(structure)
	return {}


func consume_repair_materials() -> bool:
	if _consume_recipe({Item.Kind.SCRAP: 1}):
		return true
	return _consume_recipe({Item.Kind.MECHANISM: 1})


func nearest_structure_anchor(ids: Array, from: Vector2i, pathfinder: Pathfinder = null, fog: FogOfWar = null) -> Vector2i:
	var best: Vector2i = Pathfinder.UNREACHABLE
	var best_d: int = 0x7fffffff
	for structure in _structures:
		var id: int = int(structure["id"])
		if not ids.has(id):
			continue
		var anchor: Vector2i = structure["anchor"] as Vector2i
		if fog != null and not fog.is_explored(anchor):
			continue
		var target: Vector2i = interaction_cell_for(anchor)
		if target == Pathfinder.UNREACHABLE:
			continue
		var d: int = maxi(absi(anchor.x - from.x), absi(anchor.y - from.y))
		if d >= best_d:
			continue
		if pathfinder != null and not pathfinder.has_path(from, target):
			continue
		best = anchor
		best_d = d
	return best


func interaction_cell_for(anchor: Vector2i) -> Vector2i:
	var structure: Dictionary = structure_at(anchor)
	if structure.is_empty():
		return Pathfinder.UNREACHABLE
	var cells: Array = structure["cells"] as Array
	for raw_cell in cells:
		var cell: Vector2i = raw_cell as Vector2i
		if _chunk_manager.is_walkable(cell):
			return cell
	var neighbor: Vector2i = _walkable_neighbor_of_cells(cells)
	return neighbor


func blocks_cell(grid: Vector2i) -> bool:
	var structure: Dictionary = structure_at(grid)
	if structure.is_empty():
		return false
	var id: int = int(structure["id"])
	return id == BuildBlueprint.Id.EXTRACTOR \
		or id == BuildBlueprint.Id.FABRICATOR \
		or id == BuildBlueprint.Id.REPAIR_BENCH \
		or id == BuildBlueprint.Id.PARTS_LOOM \
		or id == BuildBlueprint.Id.MAINTENANCE_DOCK \
		or id == BuildBlueprint.Id.SENTIENCE_CRADLE


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
		var interval: float = BuildBlueprint.production_interval(id)
		if interval <= 0.0:
			continue
		structure["timer"] = float(structure["timer"]) + tick
		if float(structure["timer"]) < interval:
			continue
		if id == BuildBlueprint.Id.SENTIENCE_CRADLE:
			if not _try_complete_cradle(structure, interval):
				continue
			continue
		if not _consume_recipe(BuildBlueprint.production_inputs(id)):
			structure["timer"] = interval
			structure["blocked"] = "missing input: " + BuildBlueprint.ingredients_text_from(BuildBlueprint.production_inputs(id))
			continue
		var output_kind: int = _roll_output(id)
		if output_kind >= 0:
			if not _spawn_item_from(structure, output_kind):
				structure["timer"] = interval
				structure["blocked"] = "output blocked"
				continue
		structure["timer"] = 0.0
		structure["blocked"] = ""


func _try_complete_cradle(structure: Dictionary, interval: float) -> bool:
	# Verify there is somewhere to land a bot before consuming inputs — saves the
	# refined parts from being spent on a cycle that can't deliver.
	var anchor: Vector2i = structure["anchor"] as Vector2i
	var spawn_target: Vector2i = _cradle_spawn_cell(structure)
	if spawn_target == Pathfinder.UNREACHABLE:
		structure["timer"] = interval
		structure["blocked"] = "no spawn cell adjacent"
		return false
	if not _consume_recipe(BuildBlueprint.production_inputs(BuildBlueprint.Id.SENTIENCE_CRADLE)):
		structure["timer"] = interval
		structure["blocked"] = "missing input: " + BuildBlueprint.ingredients_text_from(BuildBlueprint.production_inputs(BuildBlueprint.Id.SENTIENCE_CRADLE))
		return false
	var worker: Worker = WorkerSpawner.spawn_one_at(
		anchor, _chunk_manager, _job_board, _pathfinder,
		_stockpile_manager, _items_root, _workers_root,
		_colony_site, _fog, self, _room_manager,
	)
	if worker == null:
		structure["timer"] = interval
		structure["blocked"] = "spawn failed"
		return false
	EventBus.worker_spawned_from_cradle.emit(worker)
	structure["timer"] = 0.0
	structure["blocked"] = ""
	return true


func _cradle_spawn_cell(structure: Dictionary) -> Vector2i:
	# Reuse the output-cell helper as a first try, then any walkable adjacent cell.
	var fallback: Vector2i = _first_output_cell(structure)
	if fallback != Pathfinder.UNREACHABLE:
		return fallback
	return _walkable_neighbor_of_cells(structure["cells"] as Array)


func _spawn_item_from(structure: Dictionary, kind: int) -> bool:
	if _items_root == null:
		return false
	var output: Vector2i = _first_output_cell(structure)
	if output == Pathfinder.UNREACHABLE:
		return false
	var item := Item.new()
	_items_root.add_child(item)
	item.setup(output, kind, 1)
	if _stockpile_manager != null:
		_stockpile_manager.on_item_spawned(item)
	return true


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


func _walkable_neighbor_of_cells(cells: Array) -> Vector2i:
	const OFFSETS: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	for raw_cell in cells:
		var cell: Vector2i = raw_cell as Vector2i
		for off in OFFSETS:
			var candidate: Vector2i = cell + off
			if _chunk_manager.is_walkable(candidate):
				return candidate
	return Pathfinder.UNREACHABLE


func _roll_output(id: int) -> int:
	match id:
		BuildBlueprint.Id.EXTRACTOR:
			return Item.Kind.MECHANISM if randf() < 0.65 else Item.Kind.PLATING
		BuildBlueprint.Id.FABRICATOR:
			return Item.Kind.CHARGE_CELL if randf() < 0.25 else Item.Kind.DATACORE
		BuildBlueprint.Id.PARTS_LOOM:
			return Item.Kind.CHARGE_CELL if randf() < 0.18 else Item.Kind.MECHANISM
		_:
			return -1


func _consume_recipe(recipe: Dictionary) -> bool:
	for kind in recipe.keys():
		var needed: int = int(recipe[kind])
		if _available_item_count(int(kind)) < needed:
			return false
	for kind in recipe.keys():
		for _i in range(int(recipe[kind])):
			_consume_one_item(int(kind))
	return true


func _available_item_count(kind: int) -> int:
	var count: int = 0
	if _items_root != null:
		for child in _items_root.get_children():
			var item := child as Item
			if item != null and item.reserved_by == null and item.kind == kind and item.count > 0:
				count += item.count
	if _stockpile_manager != null and _stockpile_manager.has_method("available_count"):
		var stored_count: int = _stockpile_manager.call("available_count", kind) as int
		count += stored_count
	return count


func _consume_one_item(kind: int) -> bool:
	if _items_root != null:
		for child in _items_root.get_children():
			var item := child as Item
			if item == null or item.reserved_by != null or item.kind != kind or item.count <= 0:
				continue
			item.count -= 1
			if item.count <= 0:
				item.queue_free()
			else:
				item.queue_redraw()
			return true
	if _stockpile_manager != null and _stockpile_manager.has_method("consume_one"):
		var consumed: bool = _stockpile_manager.call("consume_one", kind) as bool
		return consumed
	return false


func _status_for(structure: Dictionary) -> Dictionary:
	var id: int = int(structure["id"])
	var interval: float = BuildBlueprint.production_interval(id)
	var timer: float = float(structure["timer"])
	var output: Vector2i = _first_output_cell(structure)
	var blocked: String = structure.get("blocked", "") as String
	if interval > 0.0 and output == Pathfinder.UNREACHABLE:
		blocked = "output blocked"
	return {
		"id": id,
		"anchor": structure["anchor"] as Vector2i,
		"name": BuildBlueprint.display_name(id),
		"description": BuildBlueprint.description(id),
		"timer": timer,
		"interval": interval,
		"progress": clampf(timer / interval, 0.0, 1.0) if interval > 0.0 else 0.0,
		"production": BuildBlueprint.production_text(id),
		"inputs": BuildBlueprint.ingredients_text_from(BuildBlueprint.production_inputs(id)),
		"blocked": blocked,
	}


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
		BuildBlueprint.Id.DOCK:
			return DOCK_COLOR
		BuildBlueprint.Id.REPAIR_BENCH:
			return REPAIR_BENCH_COLOR
		BuildBlueprint.Id.PARTS_LOOM:
			return PARTS_LOOM_COLOR
		BuildBlueprint.Id.MAINTENANCE_DOCK:
			return MAINTENANCE_DOCK_COLOR
		BuildBlueprint.Id.CALIBRATION_SHRINE:
			return CALIBRATION_SHRINE_COLOR
		BuildBlueprint.Id.MEDITATION_PAD:
			return MEDITATION_PAD_COLOR
		BuildBlueprint.Id.SENTIENCE_CRADLE:
			return SENTIENCE_CRADLE_COLOR
		_:
			return Color.WHITE
