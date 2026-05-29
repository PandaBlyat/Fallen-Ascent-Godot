class_name StructureManager
extends Node2D
##
## Lightweight static-object layer for buildables that are not terrain tiles.
## Structures are plain dictionaries for now: id, anchor, cells, produce timer.
##

const LIGHT_VISUAL_RADIUS: int = 13
const SMALL_LIGHT_VISUAL_RADIUS: int = 10
const LARGE_LIGHT_VISUAL_RADIUS: int = 22
const SENSOR_SIGHT_RADIUS: int = 15
const RUDIMENTARY_SENSOR_SIGHT_RADIUS: int = 7
const SENSOR_VISUAL_RADIUS: int = 17
const RUDIMENTARY_SENSOR_VISUAL_RADIUS: int = 9
const LIGHT_VISUAL_INTENSITY: float = 1.35
const SMALL_LIGHT_VISUAL_INTENSITY: float = 1.25
const LARGE_LIGHT_VISUAL_INTENSITY: float = 1.90
const SENSOR_VISUAL_INTENSITY: float = 0.72
const RUDIMENTARY_SENSOR_VISUAL_INTENSITY: float = 0.48
const LIGHT_WORK_BUFF_RADIUS: int = 6
const SMALL_LIGHT_WORK_BUFF_RADIUS: int = 4
const LARGE_LIGHT_WORK_BUFF_RADIUS: int = 8
const LIGHT_WORK_BUFF_MAX: float = 1.25
const SMALL_LIGHT_WORK_BUFF_MAX: float = 1.15
const LARGE_LIGHT_WORK_BUFF_MAX: float = 1.35
const LineOfSight: Script = preload("res://scripts/util/LineOfSight.gd")
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
const FABRICATION_SPOT_COLOR := Color(0.90, 0.68, 0.42, 0.95)
const WORKSHOP_ATLAS: Texture2D = preload("res://resources/objects/workshops_atlas.png")
const OBJECT_ATLAS: Texture2D = preload("res://resources/objects/craftable_objects_atlas.png")
const DOOR_ATLAS: Texture2D = preload("res://resources/objects/doors_atlas.png")
const OBJECT_SOURCE_CELL_SIZE := Vector2(32, 32)
const DOOR_SOURCE_CELL_SIZE := Vector2(32, 32)
const WORKSHOP_SOURCE_CELL_SIZE := Vector2(64, 64)
const DOOR_OPEN_DELAY_SECONDS: float = 0.12
const DOOR_HOLD_OPEN_SECONDS: float = 0.9
const WORLD_LIGHT_MAX_PER_CHUNK: int = 2
const WORLD_LIGHT_MIN_SPACING: int = 9
const WORLD_LIGHT_MIN_ROOM_SIZE: int = 14
const WORLD_LIGHT_LARGE_ROOM_SIZE: int = 70
const WORLD_LIGHT_TILES: Array[int] = [
	TerrainGenerator.TILE_FLOOR,
	TerrainGenerator.TILE_DEBRIS,
	TerrainGenerator.TILE_CONDUIT,
	TerrainGenerator.TILE_RUST,
	TerrainGenerator.TILE_OUTLET,
]
const WORLD_LIGHT_NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

## Condition system: every player-placed structure carries a 0..100 condition.
## "Machines" (worker-operated workshops, benches, docks, lights, sensors, charge
## pads) slowly wear down; anything can be smashed by a berserk worker via
## `damage_structure_at`. Below REPAIR_THRESHOLD a high-priority repair job is
## auto-queued; at 0 a machine stops functioning until repaired.
const STRUCTURE_CONDITION_MAX: float = 100.0
const STRUCTURE_REPAIR_THRESHOLD: float = 55.0
const STRUCTURE_AMBIENT_WEAR_PER_SEC: float = 0.05    ## machines only, per real second
const STRUCTURE_WEAR_PER_OPERATION: float = 1.2
const STRUCTURE_REPAIR_AMOUNT: float = 100.0          ## a finished repair restores to full

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
var _brightest_color_cache: Dictionary = {}      ## int -> Color
var _door_open_at_msec: Dictionary = {}          ## Vector2i -> msec when passable-open
var _door_close_at_msec: Dictionary = {}         ## Vector2i -> msec when visual closes
var _site_seed: int = 0
var _generated_light_chunks: Dictionary = {}      ## Vector2i -> true
var _removed_generated_lights: Dictionary = {}    ## Vector2i -> true
## Cells with an active delete-overlay flash. Vector2i -> expires_at_msec.
## Painted in `_draw` as a translucent red square so the player sees what
## was just removed; cleared automatically once the timestamp lapses.
const DELETE_OVERLAY_SECONDS: float = 0.7
const DELETE_OVERLAY_FILL := Color(0.95, 0.20, 0.20, 0.55)
const DELETE_OVERLAY_BORDER := Color(1.0, 0.32, 0.28, 0.95)
var _delete_overlays: Dictionary = {}             ## Vector2i -> expires_at_msec


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
	EventBus.chunk_loaded.connect(_on_chunk_loaded)
	# World-generated lights (and any other structure whose draw is gated on
	# `is_explored`) only had their atlas texture appear when something else
	# in this node forced a redraw. Listen for fog updates so newly explored
	# tiles repaint their structures immediately.
	EventBus.visibility_changed.connect(_on_visibility_changed)


func setup(site_seed: int) -> void:
	_site_seed = site_seed
	if _chunk_manager != null:
		for coord in _chunk_manager.loaded_chunk_coords():
			_generate_world_lights_for_chunk(coord)


func can_place_blueprint(id: int, anchor: Vector2i, rotation: int = 0) -> bool:
	var has_outlet: bool = false
	for cell in BuildBlueprint.footprint(id, anchor, rotation):
		if not _chunk_manager.is_grid_in_map(cell):
			return false
		if _cell_to_structure.has(cell):
			return false
		var tile: int = _chunk_manager.get_tile_at(cell)
		# Hazardous fluids — nothing builds on water or acid, regardless of
		# whether the tile is technically walkable (shallow/puddle are).
		if TileVisuals.is_water_or_acid_family(tile):
			return false
		if tile == TerrainGenerator.TILE_OUTLET:
			has_outlet = true
		if id == BuildBlueprint.Id.WALL:
			if tile == TerrainGenerator.TILE_DEBRIS:
				if not (TechManager != null and TechManager.is_unlocked(TechDatabase.DEBRIS_CLEARANCE)):
					return false
			elif tile != TerrainGenerator.TILE_FLOOR:
				return false
		elif id == BuildBlueprint.Id.FLOOR:
			if not _chunk_manager.is_walkable(cell):
				return false
		elif id == BuildBlueprint.Id.STORAGE_BIN:
			if _stockpile_manager == null or _stockpile_manager.zone_at(cell) == null:
				return false
			if not _chunk_manager.is_walkable(cell):
				return false
		elif id == BuildBlueprint.Id.OUTLET_EXTENSION:
			if tile != TerrainGenerator.TILE_OUTLET:
				return false
		else:
			if not _chunk_manager.is_walkable(cell):
				return false
		if id != BuildBlueprint.Id.STORAGE_BIN \
				and _stockpile_manager != null \
				and _stockpile_manager.zone_at(cell) != null:
			return false
	if BuildBlueprint.requires_outlet(id) and not has_outlet:
		return false
	var outlet_range: int = BuildBlueprint.outlet_range(id)
	if outlet_range > 0:
		var nearest: Vector2i = _chunk_manager.nearest_outlet(anchor)
		if nearest == Pathfinder.UNREACHABLE:
			return false
		if maxi(absi(nearest.x - anchor.x), absi(nearest.y - anchor.y)) > outlet_range:
			return false
	return true


func build_structure(id: int, anchor: Vector2i, rotation: int = 0) -> void:
	_add_structure(id, anchor, rotation, false)
	EventBus.player_structure_placed.emit()


func _add_structure(id: int, anchor: Vector2i, rotation: int = 0, generated: bool = false) -> void:
	var cells: Array[Vector2i] = BuildBlueprint.footprint(id, anchor, rotation)
	var structure: Dictionary = {
		"id": id,
		"anchor": anchor,
		"rotation": posmod(rotation, 4),
		"cells": cells,
		"timer": 0.0,
		"blocked": "",
		"blocked_for_inputs": false,
		"generated": generated,
		"condition": STRUCTURE_CONDITION_MAX,
	}
	_structures.append(structure)
	for cell in cells:
		_cell_to_structure[cell] = structure
		if id == BuildBlueprint.Id.CHARGE_PAD:
			_chunk_manager.set_tile_at(cell, TerrainGenerator.TILE_OUTLET)
		elif id == BuildBlueprint.Id.STORAGE_BIN and _stockpile_manager != null:
			_stockpile_manager.register_storage_bin(cell)
		EventBus.tile_changed.emit(cell, _chunk_manager.get_tile_at(cell))
	EventBus.structure_built.emit(self)
	queue_redraw()


func structure_at(grid: Vector2i) -> Dictionary:
	return _cell_to_structure.get(grid, {})


## Save layer: persist only player-built structures (world-generated lights
## regenerate from the seed) plus the set of generated lights the player
## scrapped, so those stay gone after a reload.
func capture_save() -> Dictionary:
	var built: Array = []
	for s in _structures:
		if bool(s.get("generated", false)):
			continue
		built.append({
			"id": int(s["id"]),
			"anchor": s["anchor"] as Vector2i,
			"rotation": int(s.get("rotation", 0)),
			"timer": float(s.get("timer", 0.0)),
			"condition": float(s.get("condition", STRUCTURE_CONDITION_MAX)),
		})
	var removed: Array = []
	for anchor in _removed_generated_lights:
		removed.append(anchor)
	return {"structures": built, "removed_generated_lights": removed}


func restore_save(data: Dictionary) -> void:
	# Re-apply scrapped world lights: record them, then drop any that setup()
	# already placed this session.
	for anchor in data.get("removed_generated_lights", []) as Array:
		_removed_generated_lights[anchor as Vector2i] = true
	for s in _structures.duplicate():
		if not bool(s.get("generated", false)):
			continue
		var ga: Vector2i = s["anchor"] as Vector2i
		if _removed_generated_lights.has(ga):
			_structures.erase(s)
			for raw_cell in (s["cells"] as Array):
				_cell_to_structure.erase(raw_cell as Vector2i)
	# Rebuild player-placed structures (stockpile zones must already exist so
	# storage bins can register their capacity bump).
	for entry in data.get("structures", []) as Array:
		var d: Dictionary = entry
		var anchor: Vector2i = d["anchor"] as Vector2i
		_add_structure(int(d["id"]), anchor, int(d.get("rotation", 0)), false)
		var placed: Dictionary = structure_at(anchor)
		if not placed.is_empty():
			placed["timer"] = float(d.get("timer", 0.0))
			placed["condition"] = float(d.get("condition", STRUCTURE_CONDITION_MAX))
			_maybe_queue_repair(placed)
	queue_redraw()


func structure_name_at(grid: Vector2i) -> String:
	var structure: Dictionary = structure_at(grid)
	if structure.is_empty() or not _is_structure_known(structure):
		return ""
	return BuildBlueprint.display_name(int(structure["id"]))


func structure_status_at(grid: Vector2i) -> Dictionary:
	var structure: Dictionary = structure_at(grid)
	if structure.is_empty() or not _is_structure_known(structure):
		return {}
	return _status_for(structure)


func structure_status_by_anchor(anchor: Vector2i) -> Dictionary:
	for structure in _structures:
		if (structure["anchor"] as Vector2i) == anchor:
			return _status_for(structure)
	return {}


func request_door_open(grid: Vector2i) -> void:
	var structure: Dictionary = structure_at(grid)
	if structure.is_empty() or int(structure["id"]) != BuildBlueprint.Id.DOOR:
		return
	var now: int = Time.get_ticks_msec()
	if not _door_open_at_msec.has(grid):
		_door_open_at_msec[grid] = now + int(DOOR_OPEN_DELAY_SECONDS * 1000.0)
	_door_close_at_msec[grid] = now + int((DOOR_OPEN_DELAY_SECONDS + DOOR_HOLD_OPEN_SECONDS) * 1000.0)
	queue_redraw()


func is_door_open(grid: Vector2i) -> bool:
	if not _door_open_at_msec.has(grid):
		return false
	return Time.get_ticks_msec() >= int(_door_open_at_msec[grid])


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
		if pathfinder != null:
			var route: Dictionary = pathfinder.find_path_with_teleporters(from, target, fog)
			var path: PackedVector2Array = route.get("path", PackedVector2Array()) as PackedVector2Array
			if path.is_empty() and from != target:
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
	if bool(structure.get("generated", false)) \
			and (id == BuildBlueprint.Id.SMALL_LIGHT_DEVICE or id == BuildBlueprint.Id.LARGE_LIGHT_DEVICE):
		return true
	return id == BuildBlueprint.Id.EXTRACTOR \
		or id == BuildBlueprint.Id.FABRICATOR \
		or id == BuildBlueprint.Id.FABRICATION_SPOT \
		or id == BuildBlueprint.Id.REPAIR_BENCH \
		or id == BuildBlueprint.Id.PARTS_LOOM \
		or id == BuildBlueprint.Id.MAINTENANCE_DOCK \
		or id == BuildBlueprint.Id.FABRICATOR_ADVANCED \
		or id == BuildBlueprint.Id.SENTIENCE_CRADLE


func reveal_sources() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for structure in _structures:
		var id: int = int(structure["id"])
		if id == BuildBlueprint.Id.SENSOR:
			out.append({
				"grid": structure["anchor"] as Vector2i,
				"radius": SENSOR_SIGHT_RADIUS,
			})
		elif id == BuildBlueprint.Id.RUDIMENTARY_SENSOR:
			out.append({
				"grid": structure["anchor"] as Vector2i,
				"radius": RUDIMENTARY_SENSOR_SIGHT_RADIUS,
			})
	return out


func visual_light_sources() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for structure in _structures:
		var id: int = int(structure["id"])
		if id == BuildBlueprint.Id.SMALL_LIGHT_DEVICE:
			out.append({
				"grid": structure["anchor"] as Vector2i,
				"radius": SMALL_LIGHT_VISUAL_RADIUS,
				"color": _object_color(Item.Kind.SMALL_LIGHT_DEVICE, Color(1.0, 0.78, 0.36, 1.0)),
				"intensity": SMALL_LIGHT_VISUAL_INTENSITY,
				"requires_visible_source": bool(structure.get("generated", false)),
			})
		elif id == BuildBlueprint.Id.LARGE_LIGHT_DEVICE:
			out.append({
				"grid": structure["anchor"] as Vector2i,
				"radius": LARGE_LIGHT_VISUAL_RADIUS,
				"color": _object_color(Item.Kind.LARGE_LIGHT_DEVICE, Color(1.0, 0.62, 0.28, 1.0)),
				"intensity": LARGE_LIGHT_VISUAL_INTENSITY,
				"requires_visible_source": bool(structure.get("generated", false)),
			})
		elif id == BuildBlueprint.Id.SENSOR:
			out.append({
				"grid": structure["anchor"] as Vector2i,
				"radius": SENSOR_VISUAL_RADIUS,
				"color": _brightest_workshop_color(id, Color(0.34, 0.86, 1.0, 1.0)),
				"intensity": SENSOR_VISUAL_INTENSITY,
			})
		elif id == BuildBlueprint.Id.RUDIMENTARY_SENSOR:
			out.append({
				"grid": structure["anchor"] as Vector2i,
				"radius": RUDIMENTARY_SENSOR_VISUAL_RADIUS,
				"color": _object_color(Item.Kind.RUDIMENTARY_SENSOR, Color(0.34, 0.86, 1.0, 1.0)),
				"intensity": RUDIMENTARY_SENSOR_VISUAL_INTENSITY,
			})
	return out


func has_scrappable_structure(grid: Vector2i) -> bool:
	var structure: Dictionary = structure_at(grid)
	return _is_scrappable_generated_light(structure)


func scrap_rewards_text_at(grid: Vector2i) -> String:
	var structure: Dictionary = structure_at(grid)
	if not _is_scrappable_generated_light(structure):
		return ""
	if int(structure["id"]) == BuildBlueprint.Id.LARGE_LIGHT_DEVICE:
		return "scrap x2-3, plating x1"
	return "scrap x1-2, plating x1 35%"


func scrap_stand_for(grid: Vector2i, from: Vector2i, pathfinder: Pathfinder) -> Vector2i:
	var structure: Dictionary = structure_at(grid)
	if not _is_scrappable_generated_light(structure):
		return Pathfinder.UNREACHABLE
	var anchor: Vector2i = structure["anchor"] as Vector2i
	if _chunk_manager.is_walkable(anchor) and (pathfinder == null or anchor == from or _route_exists(pathfinder, from, anchor)):
		return anchor
	var cells: Array = structure["cells"] as Array
	return _walkable_neighbor_of_cells(cells)


func _route_exists(pathfinder: Pathfinder, from: Vector2i, to: Vector2i) -> bool:
	var route: Dictionary = pathfinder.find_path_with_teleporters(from, to)
	var path: PackedVector2Array = route.get("path", PackedVector2Array()) as PackedVector2Array
	return not path.is_empty()


func scrap_structure_at(grid: Vector2i) -> Dictionary:
	var structure: Dictionary = structure_at(grid)
	if not _is_scrappable_generated_light(structure):
		return {}
	var anchor: Vector2i = structure["anchor"] as Vector2i
	var cells: Array = structure["cells"] as Array
	_structures.erase(structure)
	_removed_generated_lights[anchor] = true
	for raw_cell in cells:
		var cell: Vector2i = raw_cell as Vector2i
		_cell_to_structure.erase(cell)
		EventBus.tile_changed.emit(cell, _chunk_manager.get_tile_at(cell))
	EventBus.structure_built.emit(self)
	queue_redraw()
	var id: int = int(structure["id"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_site_seed, anchor.x, anchor.y, id, "generated_light_scrap"])
	var rewards: Dictionary = {Item.Kind.SCRAP: rng.randi_range(1, 2)}
	if id == BuildBlueprint.Id.LARGE_LIGHT_DEVICE:
		rewards[Item.Kind.SCRAP] = int(rewards[Item.Kind.SCRAP]) + 1
		rewards[Item.Kind.PLATING] = 1
	elif rng.randf() < 0.35:
		rewards[Item.Kind.PLATING] = 1
	return rewards


## Queue a dismantle job for the structure at `grid`. Returns true if a job
## was created. Workers will walk to the structure, spend time dismantling
## it, then 50% of its build ingredients drop as loose stacks.
func request_dismantle_at(grid: Vector2i) -> bool:
	var structure: Dictionary = structure_at(grid)
	if structure.is_empty():
		return false
	if bool(structure.get("generated", false)):
		return false
	if _job_board == null:
		return false
	var anchor: Vector2i = structure["anchor"] as Vector2i
	var id: int = int(structure["id"])
	if _job_board.has_dismantle_at(anchor):
		_job_board.cancel_dismantle_at(anchor)
		return true
	_job_board.add_dismantle_job(anchor, id)
	return true


## Immediately remove a structure and refund 50% of its ingredients (used by
## the dismantle job completion and the old instant-delete fallback path).
func complete_dismantle_at(anchor: Vector2i) -> bool:
	var structure: Dictionary = structure_at(anchor)
	if structure.is_empty():
		return false
	var id: int = int(structure["id"])
	var cells: Array = structure["cells"] as Array
	_structures.erase(structure)
	_clear_repair_job(anchor)
	for raw_cell in cells:
		var cell: Vector2i = raw_cell as Vector2i
		_cell_to_structure.erase(cell)
		if id == BuildBlueprint.Id.CHARGE_PAD:
			_chunk_manager.set_tile_at(cell, TerrainGenerator.TILE_FLOOR)
		if id == BuildBlueprint.Id.STORAGE_BIN and _stockpile_manager != null \
				and _stockpile_manager.has_method("unregister_storage_bin"):
			_stockpile_manager.call("unregister_storage_bin", cell)
		EventBus.tile_changed.emit(cell, _chunk_manager.get_tile_at(cell))
		_mark_delete_overlay(cell)
	_refund_ingredients(structure, anchor, 0.5)
	EventBus.structure_built.emit(self)
	queue_redraw()
	return true


## --- Condition / repair -------------------------------------------------

func _clear_repair_job(anchor: Vector2i) -> void:
	if _job_board != null and _job_board.has_method("cancel_repair_at"):
		_job_board.call("cancel_repair_at", anchor)


func condition_at(anchor: Vector2i) -> float:
	var structure: Dictionary = structure_at(anchor)
	if structure.is_empty():
		return STRUCTURE_CONDITION_MAX
	return float(structure.get("condition", STRUCTURE_CONDITION_MAX))


func condition_ratio_at(anchor: Vector2i) -> float:
	return clampf(condition_at(anchor) / STRUCTURE_CONDITION_MAX, 0.0, 1.0)


func is_structure_broken(anchor: Vector2i) -> bool:
	var structure: Dictionary = structure_at(anchor)
	if structure.is_empty():
		return false
	return float(structure.get("condition", STRUCTURE_CONDITION_MAX)) <= 0.0


## Machines wear down over time and stop functioning when broken. Pure-structure
## tiles (walls/floor/door/storage/outlet) take no ambient wear but can still be
## smashed and repaired.
func _is_machine(id: int) -> bool:
	if BuildBlueprint.is_worker_operated(id):
		return true
	return id == BuildBlueprint.Id.REPAIR_BENCH \
		or id == BuildBlueprint.Id.MAINTENANCE_DOCK \
		or id == BuildBlueprint.Id.DOCK \
		or id == BuildBlueprint.Id.MEDITATION_PAD \
		or id == BuildBlueprint.Id.CHARGE_PAD \
		or id == BuildBlueprint.Id.SENSOR \
		or id == BuildBlueprint.Id.RUDIMENTARY_SENSOR \
		or id == BuildBlueprint.Id.SMALL_LIGHT_DEVICE \
		or id == BuildBlueprint.Id.LARGE_LIGHT_DEVICE


## Deal `amount` condition damage to the structure under `grid`. Returns true if
## a structure was hit. Generated (world) structures are skipped — they are not
## part of the colony's upkeep loop. Auto-queues a repair job past the threshold.
func damage_structure_at(grid: Vector2i, amount: float) -> bool:
	var structure: Dictionary = structure_at(grid)
	if structure.is_empty() or bool(structure.get("generated", false)):
		return false
	var before: float = float(structure.get("condition", STRUCTURE_CONDITION_MAX))
	if before <= 0.0:
		return true
	var after: float = maxf(0.0, before - maxf(0.0, amount))
	structure["condition"] = after
	if after <= 0.0:
		structure["blocked"] = "broken"
	_maybe_queue_repair(structure)
	queue_redraw()
	return true


## Worker finished a repair job at `anchor`: restore condition to full, clear the
## broken flag, and remove the repair job from the board.
func repair_structure_at(anchor: Vector2i) -> bool:
	var structure: Dictionary = structure_at(anchor)
	if structure.is_empty():
		if _job_board != null and _job_board.has_method("cancel_repair_at"):
			_job_board.call("cancel_repair_at", anchor)
		return false
	structure["condition"] = STRUCTURE_CONDITION_MAX
	if (structure.get("blocked", "") as String) == "broken":
		structure["blocked"] = ""
	if _job_board != null and _job_board.has_method("cancel_repair_at"):
		_job_board.call("cancel_repair_at", anchor)
	queue_redraw()
	return true


## A structure needs repair when its condition has fallen below the threshold.
func _needs_repair(structure: Dictionary) -> bool:
	if bool(structure.get("generated", false)):
		return false
	return float(structure.get("condition", STRUCTURE_CONDITION_MAX)) < STRUCTURE_REPAIR_THRESHOLD


func _maybe_queue_repair(structure: Dictionary) -> void:
	if _job_board == null or not _job_board.has_method("add_repair_job"):
		return
	if not _needs_repair(structure):
		return
	var anchor: Vector2i = structure["anchor"] as Vector2i
	if _job_board.has_method("has_repair_at") and bool(_job_board.call("has_repair_at", anchor)):
		return
	_job_board.call("add_repair_job", anchor, int(structure["id"]))


## Berserk targeting: nearest player-placed structure anchor within `radius`
## (Chebyshev) of `from`, or UNREACHABLE. Prefers ones not already broken.
func nearest_damageable_structure(from: Vector2i, radius: int) -> Vector2i:
	var best: Vector2i = Pathfinder.UNREACHABLE
	var best_d: int = 0x7fffffff
	for structure in _structures:
		if bool(structure.get("generated", false)):
			continue
		if float(structure.get("condition", STRUCTURE_CONDITION_MAX)) <= 0.0:
			continue
		var anchor: Vector2i = structure["anchor"] as Vector2i
		var d: int = maxi(absi(anchor.x - from.x), absi(anchor.y - from.y))
		if d <= radius and d < best_d:
			best = anchor
			best_d = d
	return best


## Remove a structure for relocation without any refund. Returns its id and
## rotation so the caller can queue a build at the new position.
func remove_for_relocation(grid: Vector2i) -> Dictionary:
	var structure: Dictionary = structure_at(grid)
	if structure.is_empty() or bool(structure.get("generated", false)):
		return {}
	var id: int = int(structure["id"])
	var anchor: Vector2i = structure["anchor"] as Vector2i
	var rot: int = int(structure.get("rotation", 0))
	var cells: Array = structure["cells"] as Array
	_structures.erase(structure)
	_clear_repair_job(anchor)
	for raw_cell in cells:
		var cell: Vector2i = raw_cell as Vector2i
		_cell_to_structure.erase(cell)
		if id == BuildBlueprint.Id.CHARGE_PAD:
			_chunk_manager.set_tile_at(cell, TerrainGenerator.TILE_FLOOR)
		if id == BuildBlueprint.Id.STORAGE_BIN and _stockpile_manager != null \
				and _stockpile_manager.has_method("unregister_storage_bin"):
			_stockpile_manager.call("unregister_storage_bin", cell)
		EventBus.tile_changed.emit(cell, _chunk_manager.get_tile_at(cell))
	EventBus.structure_built.emit(self)
	queue_redraw()
	return {"id": id, "rotation": rot, "anchor": anchor}


## Global delete tool target. Removes ANY player-placed structure under
## `grid` and refunds 50% (rounded down, minimum 1 per non-zero ingredient
## that survives the halving) of its build ingredients as loose stacks near
## the structure. Returns true if a structure was removed. Generated
## (world-spawned) structures are deliberately not deletable here — use
## `scrap_structure_at` for the few that allow it.
func delete_structure_at(grid: Vector2i) -> bool:
	var structure: Dictionary = structure_at(grid)
	if structure.is_empty():
		return false
	if bool(structure.get("generated", false)):
		return false
	var id: int = int(structure["id"])
	var anchor: Vector2i = structure["anchor"] as Vector2i
	var cells: Array = structure["cells"] as Array
	_structures.erase(structure)
	_clear_repair_job(anchor)
	for raw_cell in cells:
		var cell: Vector2i = raw_cell as Vector2i
		_cell_to_structure.erase(cell)
		if id == BuildBlueprint.Id.CHARGE_PAD:
			_chunk_manager.set_tile_at(cell, TerrainGenerator.TILE_FLOOR)
		if id == BuildBlueprint.Id.STORAGE_BIN and _stockpile_manager != null \
				and _stockpile_manager.has_method("unregister_storage_bin"):
			_stockpile_manager.call("unregister_storage_bin", cell)
		EventBus.tile_changed.emit(cell, _chunk_manager.get_tile_at(cell))
		_mark_delete_overlay(cell)
	_refund_ingredients(structure, anchor, 0.5)
	EventBus.structure_built.emit(self)
	queue_redraw()
	return true


func _refund_ingredients(structure: Dictionary, anchor: Vector2i, ratio: float) -> void:
	if _items_root == null:
		return
	var id: int = int(structure["id"])
	var recipe: Dictionary = BuildBlueprint.ingredients(id)
	for kind in recipe.keys():
		var full: int = int(recipe[kind])
		var refund: int = int(floor(float(full) * ratio))
		if refund <= 0:
			continue
		# Spawn one stack per refunded unit at the nearest walkable cell to
		# the structure's anchor. _spawn_item_from already handles fallback.
		for _i in refund:
			if not _spawn_item_from(structure, int(kind)):
				# Final fallback: drop on the anchor itself even if blocked.
				var item := Item.new()
				_items_root.add_child(item)
				item.setup(anchor, int(kind), 1)
				if _stockpile_manager != null:
					_stockpile_manager.on_item_spawned(item)


func _mark_delete_overlay(cell: Vector2i) -> void:
	_delete_overlays[cell] = Time.get_ticks_msec() + int(DELETE_OVERLAY_SECONDS * 1000.0)


func _tick_delete_overlays() -> void:
	if _delete_overlays.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var expired: Array[Vector2i] = []
	for key in _delete_overlays.keys():
		if int(_delete_overlays[key]) <= now:
			expired.append(key as Vector2i)
	for key in expired:
		_delete_overlays.erase(key)
	# Always repaint while any overlay is live so the flash fades smoothly.
	queue_redraw()


func _draw_delete_overlays() -> void:
	if _delete_overlays.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	for key in _delete_overlays.keys():
		var cell: Vector2i = key as Vector2i
		var expires: int = int(_delete_overlays[key])
		if expires <= now:
			continue
		var remaining: float = float(expires - now) / 1000.0
		var alpha: float = clampf(remaining / DELETE_OVERLAY_SECONDS, 0.0, 1.0)
		var origin := Vector2(cell.x * Chunk.TILE_PIXELS, cell.y * Chunk.TILE_PIXELS)
		var rect := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(rect, Color(DELETE_OVERLAY_FILL.r, DELETE_OVERLAY_FILL.g, DELETE_OVERLAY_FILL.b, DELETE_OVERLAY_FILL.a * alpha))
		draw_rect(rect, Color(DELETE_OVERLAY_BORDER.r, DELETE_OVERLAY_BORDER.g, DELETE_OVERLAY_BORDER.b, DELETE_OVERLAY_BORDER.a * alpha), false, 1.5)


func light_speed_multiplier_at(grid: Vector2i) -> float:
	var best: float = 1.0
	for structure in _structures:
		var id: int = int(structure["id"])
		if id != BuildBlueprint.Id.SMALL_LIGHT_DEVICE \
				and id != BuildBlueprint.Id.LARGE_LIGHT_DEVICE:
			continue
		var anchor: Vector2i = structure["anchor"] as Vector2i
		var radius: int = _work_light_radius(id)
		var d: Vector2i = grid - anchor
		var dist2: int = d.x * d.x + d.y * d.y
		if dist2 > radius * radius:
			continue
		if _chunk_manager != null and not LineOfSight.has_los(_chunk_manager, anchor, grid):
			continue
		var dist: float = sqrt(float(dist2))
		var falloff: float = clampf(1.0 - dist / float(radius), 0.0, 1.0)
		best = maxf(best, lerpf(1.0, _work_light_max(id), falloff))
	return best


func add_craft_order(station_anchor: Vector2i, object_kind: int) -> bool:
	if _job_board == null or not Item.is_craftable_object_kind(object_kind):
		return false
	var structure: Dictionary = structure_at(station_anchor)
	if structure.is_empty() or int(structure["id"]) != BuildBlueprint.Id.FABRICATION_SPOT:
		return false
	_job_board.add_craft_job(station_anchor, object_kind)
	return true


func clear_craft_orders(station_anchor: Vector2i) -> int:
	if _job_board == null or not _job_board.has_method("cancel_craft_jobs_at"):
		return 0
	return int(_job_board.call("cancel_craft_jobs_at", station_anchor))


func can_operate_structure(anchor: Vector2i) -> bool:
	var structure: Dictionary = structure_at(anchor)
	if structure.is_empty():
		return false
	var id: int = int(structure["id"])
	if not BuildBlueprint.is_worker_operated(id):
		return false
	if float(structure.get("condition", STRUCTURE_CONDITION_MAX)) <= 0.0:
		structure["blocked"] = "broken"
		return false
	if _first_output_cell(structure) == Pathfinder.UNREACHABLE:
		structure["blocked"] = "output blocked"
		return false
	structure["blocked"] = ""
	return true


func complete_operation(anchor: Vector2i) -> bool:
	var structure: Dictionary = structure_at(anchor)
	if structure.is_empty():
		return false
	var id: int = int(structure["id"])
	if not can_operate_structure(anchor):
		return false
	if id == BuildBlueprint.Id.SENTIENCE_CRADLE:
		return _try_complete_cradle(structure, 0.0, false)
	var output_kind: int = _roll_output(id)
	if output_kind >= 0:
		if not _spawn_item_from(structure, output_kind):
			structure["blocked"] = "output blocked"
			return false
	structure["timer"] = 0.0
	structure["blocked"] = ""
	structure["blocked_for_inputs"] = false
	# Using a machine wears it; below the threshold a repair job is queued.
	var worn: float = maxf(0.0, float(structure.get("condition", STRUCTURE_CONDITION_MAX)) - STRUCTURE_WEAR_PER_OPERATION)
	structure["condition"] = worn
	_maybe_queue_repair(structure)
	return true


func spawn_crafted_object(station_anchor: Vector2i, object_kind: int) -> bool:
	if _items_root == null or not Item.is_craftable_object_kind(object_kind):
		return false
	var structure: Dictionary = structure_at(station_anchor)
	if structure.is_empty():
		return false
	var output: Vector2i = _first_output_cell(structure)
	if output == Pathfinder.UNREACHABLE:
		return false
	var item := Item.new()
	_items_root.add_child(item)
	item.setup(output, object_kind, 1)
	if _stockpile_manager != null:
		_stockpile_manager.on_item_spawned(item)
	return true


func activity_fx_sources() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for structure in _structures:
		var id: int = int(structure["id"])
		var interval: float = BuildBlueprint.production_interval(id)
		if interval <= 0.0:
			continue
		var timer: float = float(structure["timer"])
		if timer <= 0.0:
			continue
		out.append({
			"grid": structure["anchor"] as Vector2i,
			"kind": _fx_kind_for(id),
			"progress": clampf(timer / interval, 0.0, 1.0),
			"intensity": 0.65,
		})
	return out


func _process(delta: float) -> void:
	_tick_delete_overlays()
	_accum += delta
	if _accum < 1.0:
		_process_doors()
		return
	var tick: float = _accum
	_accum = 0.0
	_process_doors()
	for structure in _structures:
		if bool(structure.get("generated", false)):
			continue
		var sid: int = int(structure["id"])
		# Machines slowly wear; below the threshold a repair job is queued.
		if _is_machine(sid) and STRUCTURE_AMBIENT_WEAR_PER_SEC > 0.0:
			var cond: float = float(structure.get("condition", STRUCTURE_CONDITION_MAX))
			if cond > 0.0:
				structure["condition"] = maxf(0.0, cond - STRUCTURE_AMBIENT_WEAR_PER_SEC * tick)
		_maybe_queue_repair(structure)
	for structure in _structures:
		var id: int = int(structure["id"])
		if not BuildBlueprint.is_worker_operated(id):
			continue
		if _job_board == null:
			continue
		var anchor: Vector2i = structure["anchor"] as Vector2i
		if _job_board.operation_job_at(anchor) != null:
			continue
		if not can_operate_structure(anchor):
			continue
		structure["timer"] = float(structure["timer"]) + tick
		_job_board.add_operation_job(anchor, id)


func _on_chunk_loaded(chunk_coord: Vector2i) -> void:
	_generate_world_lights_for_chunk(chunk_coord)


func _on_visibility_changed(_changed_bounds: Rect2i) -> void:
	# Cheap repaint: the per-structure visibility check already filters by
	# explored cells, so the only cost is one queue_redraw per fog update.
	queue_redraw()


func _generate_world_lights_for_chunk(chunk_coord: Vector2i) -> void:
	if _site_seed == 0 or _chunk_manager == null or _generated_light_chunks.has(chunk_coord):
		return
	if not _chunk_manager.loaded_chunk_coords().has(chunk_coord):
		return
	_generated_light_chunks[chunk_coord] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_site_seed, chunk_coord.x, chunk_coord.y, "world_lights"])
	var room_sizes: Dictionary = _walkable_component_sizes(chunk_coord)
	var candidates: Array[Vector2i] = []
	var base: Vector2i = chunk_coord * Chunk.SIZE
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var cell: Vector2i = base + Vector2i(lx, ly)
			if not _is_world_light_candidate(cell, int(room_sizes.get(cell, 0))):
				continue
			candidates.append(cell)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _world_light_score(a, int(room_sizes.get(a, 0))) > _world_light_score(b, int(room_sizes.get(b, 0)))
	)
	var placed: int = 0
	var attempts: int = mini(candidates.size(), 18)
	for i in attempts:
		if placed >= WORLD_LIGHT_MAX_PER_CHUNK:
			break
		var candidate: Vector2i = candidates[i]
		var score: float = _world_light_score(candidate, int(room_sizes.get(candidate, 0)))
		if rng.randf() > clampf(score, 0.0, 0.85):
			continue
		var id: int = BuildBlueprint.Id.SMALL_LIGHT_DEVICE
		if int(room_sizes.get(candidate, 0)) >= WORLD_LIGHT_LARGE_ROOM_SIZE and rng.randf() < 0.45:
			id = BuildBlueprint.Id.LARGE_LIGHT_DEVICE
		if _try_place_world_light(id, candidate):
			placed += 1


func _try_place_world_light(id: int, anchor: Vector2i) -> bool:
	if _removed_generated_lights.has(anchor):
		return false
	if _near_generated_light(anchor, WORLD_LIGHT_MIN_SPACING):
		return false
	if not _can_place_world_light(anchor):
		return false
	_add_structure(id, anchor, 0, true)
	return true


func _can_place_world_light(anchor: Vector2i) -> bool:
	if _cell_to_structure.has(anchor):
		return false
	if not _chunk_manager.is_grid_in_map(anchor):
		return false
	if not WORLD_LIGHT_TILES.has(_chunk_manager.get_tile_at(anchor)):
		return false
	return _chunk_manager.is_walkable(anchor)


func _is_world_light_candidate(cell: Vector2i, room_size: int) -> bool:
	if room_size < WORLD_LIGHT_MIN_ROOM_SIZE or not _can_place_world_light(cell):
		return false
	var tile: int = _chunk_manager.get_tile_at(cell)
	# Never place lights directly on outlets — they should sit next to one so
	# workers can still reach the outlet to recharge.
	if tile == TerrainGenerator.TILE_OUTLET:
		return false
	if _has_outlet_neighbor_at(cell):
		return _floor_clearance(cell, 1)
	if tile == TerrainGenerator.TILE_CONDUIT:
		return _floor_clearance(cell, 1)
	return _has_wall_neighbor_at(cell) and _floor_clearance(cell, 2)


func _world_light_score(cell: Vector2i, room_size: int) -> float:
	var tile: int = _chunk_manager.get_tile_at(cell)
	var score: float = 0.02
	if _has_outlet_neighbor_at(cell):
		score += 0.50
	elif tile == TerrainGenerator.TILE_CONDUIT:
		score += 0.22
	if _has_wall_neighbor_at(cell):
		score += 0.20
	if room_size >= WORLD_LIGHT_LARGE_ROOM_SIZE:
		score += 0.22
	elif room_size >= 32:
		score += 0.12
	return score


func _has_outlet_neighbor_at(cell: Vector2i) -> bool:
	for y in range(-1, 2):
		for x in range(-1, 2):
			if x == 0 and y == 0:
				continue
			if _chunk_manager.get_tile_at(cell + Vector2i(x, y)) == TerrainGenerator.TILE_OUTLET:
				return true
	return false


func _walkable_component_sizes(chunk_coord: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	var visited: Dictionary = {}
	var base: Vector2i = chunk_coord * Chunk.SIZE
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var start: Vector2i = base + Vector2i(lx, ly)
			if visited.has(start) or not _is_component_floor(start):
				continue
			var cells: Array[Vector2i] = []
			var queue: Array[Vector2i] = [start]
			visited[start] = true
			var head: int = 0
			while head < queue.size():
				var cell: Vector2i = queue[head]
				head += 1
				cells.append(cell)
				for off in WORLD_LIGHT_NEIGHBORS:
					var next: Vector2i = cell + off
					if visited.has(next) or Chunk.grid_to_chunk(next) != chunk_coord or not _is_component_floor(next):
						continue
					visited[next] = true
					queue.append(next)
			for cell in cells:
				out[cell] = cells.size()
	return out


func _is_component_floor(cell: Vector2i) -> bool:
	if not _chunk_manager.is_grid_in_map(cell):
		return false
	return WORLD_LIGHT_TILES.has(_chunk_manager.get_tile_at(cell)) and _chunk_manager.is_walkable(cell)


func _has_wall_neighbor_at(cell: Vector2i) -> bool:
	for y in range(-1, 2):
		for x in range(-1, 2):
			if x == 0 and y == 0:
				continue
			var tile: int = _chunk_manager.get_tile_at(cell + Vector2i(x, y))
			if tile == TerrainGenerator.TILE_WALL \
					or tile == TerrainGenerator.TILE_RICH_WALL \
					or tile == TerrainGenerator.TILE_SERVICE_CORE:
				return true
	return false


func _floor_clearance(cell: Vector2i, radius: int) -> bool:
	for y in range(cell.y - radius, cell.y + radius + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			var check := Vector2i(x, y)
			if not _chunk_manager.is_grid_in_map(check):
				continue
			var tile: int = _chunk_manager.get_tile_at(check)
			if tile == TerrainGenerator.TILE_VOID or TileVisuals.is_water_or_acid_family(tile):
				return false
	return true


func _near_generated_light(anchor: Vector2i, radius: int) -> bool:
	var r2: int = radius * radius
	for structure in _structures:
		if not bool(structure.get("generated", false)):
			continue
		var id: int = int(structure["id"])
		if id != BuildBlueprint.Id.SMALL_LIGHT_DEVICE and id != BuildBlueprint.Id.LARGE_LIGHT_DEVICE:
			continue
		var other: Vector2i = structure["anchor"] as Vector2i
		var d: Vector2i = anchor - other
		if d.x * d.x + d.y * d.y <= r2:
			return true
	return false


func _is_scrappable_generated_light(structure: Dictionary) -> bool:
	if structure.is_empty() or not bool(structure.get("generated", false)):
		return false
	var id: int = int(structure["id"])
	return id == BuildBlueprint.Id.SMALL_LIGHT_DEVICE or id == BuildBlueprint.Id.LARGE_LIGHT_DEVICE


func _is_structure_known(structure: Dictionary) -> bool:
	if _fog == null:
		return true
	var cells: Array = structure["cells"] as Array
	for raw_cell in cells:
		var cell: Vector2i = raw_cell as Vector2i
		if bool(structure.get("generated", false)):
			if _fog.is_cell_visible(cell):
				return true
		elif _fog.is_explored(cell):
			return true
	return false


func _is_structure_draw_visible(structure: Dictionary) -> bool:
	if _fog == null:
		return true
	var cells: Array = structure["cells"] as Array
	for raw_cell in cells:
		var cell: Vector2i = raw_cell as Vector2i
		if _fog.is_explored(cell):
			return true
	return false


func _try_complete_cradle(structure: Dictionary, interval: float, consume_inputs: bool = true) -> bool:
	# Verify there is somewhere to land a bot before consuming inputs — saves the
	# refined parts from being spent on a cycle that can't deliver.
	var anchor: Vector2i = structure["anchor"] as Vector2i
	var spawn_target: Vector2i = _cradle_spawn_cell(structure)
	if spawn_target == Pathfinder.UNREACHABLE:
		structure["timer"] = interval
		structure["blocked"] = "no spawn cell adjacent"
		return false
	var recipe: Dictionary = BuildBlueprint.production_inputs(BuildBlueprint.Id.SENTIENCE_CRADLE)
	if consume_inputs and not _consume_recipe(recipe):
		structure["blocked_for_inputs"] = true
		structure["blocked"] = "missing input: " + BuildBlueprint.ingredients_text_from(recipe)
		EventBus.fabricator_needs_inputs.emit(structure["anchor"] as Vector2i, _missing_recipe_kinds(recipe))
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
	structure["blocked_for_inputs"] = false
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
		BuildBlueprint.Id.PARTS_LOOM:
			return Item.Kind.MECHANISM if randf() < 0.45 else Item.Kind.PLATING
		BuildBlueprint.Id.FABRICATOR_ADVANCED:
			var r: float = randf()
			if r < 0.45:
				return Item.Kind.DATACORE
			if r < 0.85:
				return Item.Kind.CHARGE_CELL
			return Item.Kind.RUDIMENTARY_SENSOR
		_:
			return -1


func _fx_kind_for(id: int) -> int:
	match id:
		BuildBlueprint.Id.EXTRACTOR:
			return 6
		BuildBlueprint.Id.PARTS_LOOM, BuildBlueprint.Id.FABRICATOR_ADVANCED:
			return 4
		BuildBlueprint.Id.SENTIENCE_CRADLE:
			return 5
		_:
			return 4


func _consume_recipe(recipe: Dictionary) -> bool:
	for kind in recipe.keys():
		var needed: int = int(recipe[kind])
		if _available_item_count(int(kind)) < needed:
			return false
	for kind in recipe.keys():
		for _i in range(int(recipe[kind])):
			_consume_one_item(int(kind))
	return true


func _has_recipe(recipe: Dictionary) -> bool:
	for kind in recipe.keys():
		if _available_item_count(int(kind)) < int(recipe[kind]):
			return false
	return true


func _missing_recipe_kinds(recipe: Dictionary) -> Array:
	var missing: Array = []
	for kind in recipe.keys():
		if _available_item_count(int(kind)) < int(recipe[kind]):
			missing.append(int(kind))
	return missing


func _process_doors() -> void:
	if _door_close_at_msec.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var closed: Array[Vector2i] = []
	for key in _door_close_at_msec.keys():
		var grid: Vector2i = key as Vector2i
		if now >= int(_door_close_at_msec[key]):
			closed.append(grid)
	for grid in closed:
		_door_close_at_msec.erase(grid)
		_door_open_at_msec.erase(grid)
	if not closed.is_empty():
		queue_redraw()


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
	var operation_job: OperateStructureJob = _job_board.operation_job_at(structure["anchor"] as Vector2i) if _job_board != null else null
	return {
		"id": id,
		"anchor": structure["anchor"] as Vector2i,
		"rotation": int(structure.get("rotation", 0)),
		"name": BuildBlueprint.display_name(id),
		"description": BuildBlueprint.description(id),
		"condition": float(structure.get("condition", STRUCTURE_CONDITION_MAX)),
		"condition_ratio": clampf(float(structure.get("condition", STRUCTURE_CONDITION_MAX)) / STRUCTURE_CONDITION_MAX, 0.0, 1.0),
		"repairing": _job_board != null and _job_board.has_method("has_repair_at") and bool(_job_board.call("has_repair_at", structure["anchor"] as Vector2i)),
		"timer": operation_job.progress if operation_job != null else timer,
		"interval": interval,
		"progress": clampf((operation_job.progress if operation_job != null else timer) / interval, 0.0, 1.0) if interval > 0.0 else 0.0,
		"production": BuildBlueprint.production_text(id),
		"inputs": BuildBlueprint.ingredients_text_from(BuildBlueprint.production_inputs(id)),
		"blocked": blocked,
		"craft_orders": _job_board.craft_count_at(structure["anchor"] as Vector2i) if _job_board != null and id == BuildBlueprint.Id.FABRICATION_SPOT else 0,
		"operation_orders": _job_board.operation_count_at(structure["anchor"] as Vector2i) if _job_board != null and BuildBlueprint.is_worker_operated(id) else 0,
		"craft_missing_stockpile": _craft_stockpile_missing_text(structure["anchor"] as Vector2i) if id == BuildBlueprint.Id.FABRICATION_SPOT else "",
	}


func _craft_stockpile_missing_text(anchor: Vector2i) -> String:
	if _job_board == null:
		return ""
	var missing: Dictionary = {}
	for job in _job_board.pending:
		if not (job is CraftJob) or (job as CraftJob).station_anchor != anchor:
			continue
		var craft := job as CraftJob
		for key in craft.ingredients.keys():
			var kind: int = int(key)
			var needed: int = int(craft.ingredients[kind]) - int(craft.delivered.get(kind, 0))
			if needed > 0:
				missing[kind] = int(missing.get(kind, 0)) + needed
	var parts: Array[String] = []
	for kind in missing.keys():
		var missing_count: int = maxi(0, int(missing[kind]) - _available_item_count(int(kind)))
		if missing_count > 0:
			parts.append("%s x%d" % [Item.kind_name(int(kind)), missing_count])
	return ", ".join(parts)


func _draw() -> void:
	_draw_delete_overlays()
	for structure in _structures:
		if not _is_structure_draw_visible(structure):
			continue
		var id: int = int(structure["id"])
		if BuildBlueprint.is_workshop(id):
			_draw_workshop(structure)
			continue
		var cells: Array = structure["cells"] as Array
		for raw_cell in cells:
			var cell: Vector2i = raw_cell as Vector2i
			var origin := Vector2(cell.x * Chunk.TILE_PIXELS, cell.y * Chunk.TILE_PIXELS)
			var dest := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
			if BuildBlueprint.is_object_placement(id):
				if id == BuildBlueprint.Id.SMALL_LIGHT_DEVICE or id == BuildBlueprint.Id.LARGE_LIGHT_DEVICE:
					_draw_light_glow(cell, id)
				var object_kind: int = BuildBlueprint.object_item_kind(id)
				var object_index: int = Item.object_atlas_index(object_kind)
				var object_source := Rect2(Vector2(object_index * int(OBJECT_SOURCE_CELL_SIZE.x), 0), OBJECT_SOURCE_CELL_SIZE)
				draw_texture_rect_region(OBJECT_ATLAS, dest, object_source)
			elif id == BuildBlueprint.Id.DOOR:
				var door_index: int = 1 if is_door_open(cell) else 0
				var door_source := Rect2(Vector2(door_index * int(DOOR_SOURCE_CELL_SIZE.x), 0), DOOR_SOURCE_CELL_SIZE)
				draw_texture_rect_region(DOOR_ATLAS, dest, door_source)


func _draw_workshop(structure: Dictionary) -> void:
	var id: int = int(structure["id"])
	var index: int = BuildBlueprint.workshop_atlas_index(id)
	if index < 0:
		return
	var anchor: Vector2i = structure["anchor"] as Vector2i
	var origin := Vector2(anchor.x * Chunk.TILE_PIXELS, anchor.y * Chunk.TILE_PIXELS)
	var atlas_x: int = index * int(WORKSHOP_SOURCE_CELL_SIZE.x)
	var visual_tiles: Vector2i = BuildBlueprint.visual_size_tiles(id)
	var pixel_size := Vector2(visual_tiles.x * Chunk.TILE_PIXELS, visual_tiles.y * Chunk.TILE_PIXELS)
	var dest := Rect2(origin, pixel_size)
	var source := Rect2(Vector2(atlas_x, 0), pixel_size)
	draw_texture_rect_region(WORKSHOP_ATLAS, dest, source)


func _draw_light_glow(cell: Vector2i, id: int) -> void:
	var center := Vector2(cell * Chunk.TILE_PIXELS) + Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS) * 0.5
	var radius: float = (4.6 if id == BuildBlueprint.Id.LARGE_LIGHT_DEVICE else 2.8) * float(Chunk.TILE_PIXELS)
	var color: Color = _object_color(
		BuildBlueprint.object_item_kind(id),
		Color(1.0, 0.78, 0.34, 1.0),
	)
	draw_circle(center, radius, Color(color.r, color.g, color.b, 0.045))
	draw_circle(center, radius * 0.45, Color(color.r, color.g, color.b, 0.10))


static func _color_for(id: int) -> Color:
	match id:
		BuildBlueprint.Id.DOOR:
			return DOOR_COLOR
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
		BuildBlueprint.Id.FABRICATOR_ADVANCED:
			return CALIBRATION_SHRINE_COLOR
		BuildBlueprint.Id.MEDITATION_PAD:
			return MEDITATION_PAD_COLOR
		BuildBlueprint.Id.SENTIENCE_CRADLE:
			return SENTIENCE_CRADLE_COLOR
		BuildBlueprint.Id.FABRICATION_SPOT:
			return FABRICATION_SPOT_COLOR
		_:
			return Color.WHITE


func _work_light_radius(id: int) -> int:
	match id:
		BuildBlueprint.Id.SMALL_LIGHT_DEVICE:
			return SMALL_LIGHT_WORK_BUFF_RADIUS
		BuildBlueprint.Id.LARGE_LIGHT_DEVICE:
			return LARGE_LIGHT_WORK_BUFF_RADIUS
		_:
			return LIGHT_WORK_BUFF_RADIUS


func _work_light_max(id: int) -> float:
	match id:
		BuildBlueprint.Id.SMALL_LIGHT_DEVICE:
			return SMALL_LIGHT_WORK_BUFF_MAX
		BuildBlueprint.Id.LARGE_LIGHT_DEVICE:
			return LARGE_LIGHT_WORK_BUFF_MAX
		_:
			return LIGHT_WORK_BUFF_MAX


func _object_color(object_kind: int, fallback: Color) -> Color:
	var image: Image = OBJECT_ATLAS.get_image()
	var index: int = Item.object_atlas_index(object_kind)
	if image == null or image.is_empty() or index < 0:
		return fallback
	var origin_x: int = index * int(OBJECT_SOURCE_CELL_SIZE.x)
	if origin_x >= image.get_width():
		return fallback
	var best_color: Color = fallback
	var best_score: float = -1.0
	var max_x: int = mini(origin_x + int(OBJECT_SOURCE_CELL_SIZE.x), image.get_width())
	var max_y: int = mini(int(OBJECT_SOURCE_CELL_SIZE.y), image.get_height())
	for y in range(0, max_y):
		for x in range(origin_x, max_x):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a < 0.12:
				continue
			var score: float = (pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722) * pixel.a
			if score > best_score:
				best_score = score
				best_color = Color(pixel.r, pixel.g, pixel.b, 1.0)
	return best_color


func _brightest_workshop_color(id: int, fallback: Color) -> Color:
	if _brightest_color_cache.has(id):
		return _brightest_color_cache[id] as Color
	var image: Image = WORKSHOP_ATLAS.get_image()
	if image == null or image.is_empty():
		_brightest_color_cache[id] = fallback
		return fallback
	var index: int = BuildBlueprint.workshop_atlas_index(id)
	if index < 0:
		_brightest_color_cache[id] = fallback
		return fallback
	var origin_x: int = index * int(WORKSHOP_SOURCE_CELL_SIZE.x)
	if origin_x >= image.get_width():
		_brightest_color_cache[id] = fallback
		return fallback
	var best_color: Color = fallback
	var best_score: float = -1.0
	var max_x: int = mini(origin_x + int(WORKSHOP_SOURCE_CELL_SIZE.x), image.get_width())
	var max_y: int = mini(int(WORKSHOP_SOURCE_CELL_SIZE.y), image.get_height())
	for y in range(0, max_y):
		for x in range(origin_x, max_x):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a < 0.12:
				continue
			var score: float = (pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722) * pixel.a
			if score > best_score:
				best_score = score
				best_color = Color(pixel.r, pixel.g, pixel.b, 1.0)
	_brightest_color_cache[id] = best_color
	return best_color
