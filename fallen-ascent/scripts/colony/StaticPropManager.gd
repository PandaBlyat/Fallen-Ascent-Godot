class_name StaticPropManager
extends Node2D
##
## Deterministic mineable world-prop layer. Spawn tuning, clustering, and
## resource payouts live in PROP_DEFS so map flavor can be adjusted in one spot.
##

const PROP_ATLAS: Texture2D = preload("res://resources/objects/placeholder_static_objects_atlas.png")
const ATLAS_CELL_PIXELS: int = 32

enum Kind {
	RUSTY_STORAGE_BIN,
	RUSTY_BROKEN_GRILLE,
	RUSTY_FAN,
	PILE_OF_SCRAP,
	BROKEN_THERMOMETOR_BOX,
	BROKEN_VENT,
	PILE_OF_RUSTY_GIRDLE,
	SECOND_PILE_OF_RUSTY_GIRDLE,
	PILE_OF_COMPONENTS,
	BROKEN_BATTERIES,
	PILE_OF_BATTERIES,
	STORAGE_TANK,
	SATELLITE_DISH,
}

const PROP_DEFS: Dictionary = {
	Kind.RUSTY_STORAGE_BIN: {
		"name": "rusty storage bin",
		"atlas": Rect2i(0, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0034,
		"zone_weights": [0.20, 0.90, 1.90, 0.35, 0.85],
		"small_room_weight": 2.10,
		"large_room_weight": 0.70,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 2, "max": 4, "chance": 1.0},
			{"kind": Item.Kind.PLATING, "min": 1, "max": 2, "chance": 0.55},
			{"kind": Item.Kind.MECHANISM, "min": 1, "max": 1, "chance": 0.18},
		],
		"clusters": [
			{"kind": Kind.PILE_OF_SCRAP, "chance": 0.24, "radius": 3},
			{"kind": Kind.BROKEN_THERMOMETOR_BOX, "chance": 0.14, "radius": 4},
		],
	},
	Kind.RUSTY_BROKEN_GRILLE: {
		"name": "rusty broken grille",
		"atlas": Rect2i(1, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0024,
		"zone_weights": [0.35, 1.25, 0.95, 0.60, 1.10],
		"small_room_weight": 0.75,
		"large_room_weight": 1.10,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 1, "max": 2, "chance": 1.0},
			{"kind": Item.Kind.PLATING, "min": 1, "max": 1, "chance": 0.45},
		],
		"clusters": [
			{"kind": Kind.BROKEN_VENT, "chance": 0.32, "radius": 3},
			{"kind": Kind.RUSTY_FAN, "chance": 0.20, "radius": 4},
		],
	},
	Kind.RUSTY_FAN: {
		"name": "rusty fan",
		"atlas": Rect2i(2, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0021,
		"zone_weights": [0.20, 1.45, 0.85, 0.40, 1.15],
		"small_room_weight": 0.80,
		"large_room_weight": 1.10,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 1, "max": 2, "chance": 1.0},
			{"kind": Item.Kind.MECHANISM, "min": 1, "max": 1, "chance": 0.32},
			{"kind": Item.Kind.PLATING, "min": 1, "max": 1, "chance": 0.25},
		],
		"clusters": [
			{"kind": Kind.RUSTY_BROKEN_GRILLE, "chance": 0.24, "radius": 4},
			{"kind": Kind.BROKEN_VENT, "chance": 0.30, "radius": 4},
		],
	},
	Kind.PILE_OF_SCRAP: {
		"name": "pile of scrap",
		"atlas": Rect2i(3, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0046,
		"zone_weights": [0.70, 1.35, 0.80, 1.10, 0.95],
		"small_room_weight": 0.90,
		"large_room_weight": 1.25,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 2, "max": 5, "chance": 1.0},
			{"kind": Item.Kind.PLATING, "min": 1, "max": 1, "chance": 0.28},
		],
		"clusters": [
			{"kind": Kind.PILE_OF_SCRAP, "chance": 0.58, "radius": 3},
			{"kind": Kind.PILE_OF_RUSTY_GIRDLE, "chance": 0.38, "radius": 4},
			{"kind": Kind.SECOND_PILE_OF_RUSTY_GIRDLE, "chance": 0.34, "radius": 4},
		],
	},
	Kind.BROKEN_THERMOMETOR_BOX: {
		"name": "broken thermometor box",
		"atlas": Rect2i(4, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0016,
		"zone_weights": [0.12, 1.20, 0.85, 0.30, 1.25],
		"small_room_weight": 1.20,
		"large_room_weight": 0.90,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 1, "max": 1, "chance": 1.0},
			{"kind": Item.Kind.MECHANISM, "min": 1, "max": 1, "chance": 0.24},
			{"kind": Item.Kind.DATACORE, "min": 1, "max": 1, "chance": 0.10},
		],
		"clusters": [
			{"kind": Kind.BROKEN_BATTERIES, "chance": 0.16, "radius": 4},
			{"kind": Kind.PILE_OF_COMPONENTS, "chance": 0.18, "radius": 4},
		],
	},
	Kind.BROKEN_VENT: {
		"name": "broken vent",
		"atlas": Rect2i(5, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0023,
		"zone_weights": [0.25, 1.30, 0.95, 0.40, 1.10],
		"small_room_weight": 0.85,
		"large_room_weight": 1.00,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 1, "max": 2, "chance": 1.0},
			{"kind": Item.Kind.PLATING, "min": 1, "max": 1, "chance": 0.36},
		],
		"clusters": [
			{"kind": Kind.RUSTY_FAN, "chance": 0.24, "radius": 4},
			{"kind": Kind.RUSTY_BROKEN_GRILLE, "chance": 0.30, "radius": 3},
		],
	},
	Kind.PILE_OF_RUSTY_GIRDLE: {
		"name": "pile of rusty girdle",
		"atlas": Rect2i(6, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0025,
		"zone_weights": [0.65, 1.35, 0.40, 1.15, 1.25],
		"small_room_weight": 0.55,
		"large_room_weight": 1.35,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 1, "max": 3, "chance": 1.0},
			{"kind": Item.Kind.PLATING, "min": 1, "max": 2, "chance": 0.72},
		],
		"clusters": [
			{"kind": Kind.PILE_OF_SCRAP, "chance": 0.42, "radius": 4},
			{"kind": Kind.SECOND_PILE_OF_RUSTY_GIRDLE, "chance": 0.36, "radius": 4},
		],
	},
	Kind.SECOND_PILE_OF_RUSTY_GIRDLE: {
		"name": "2nd pile of rusty girdle",
		"atlas": Rect2i(7, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0021,
		"zone_weights": [0.65, 1.30, 0.35, 1.10, 1.20],
		"small_room_weight": 0.55,
		"large_room_weight": 1.35,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 1, "max": 2, "chance": 1.0},
			{"kind": Item.Kind.PLATING, "min": 1, "max": 2, "chance": 0.68},
		],
		"clusters": [
			{"kind": Kind.PILE_OF_SCRAP, "chance": 0.34, "radius": 4},
			{"kind": Kind.PILE_OF_RUSTY_GIRDLE, "chance": 0.38, "radius": 4},
		],
	},
	Kind.PILE_OF_COMPONENTS: {
		"name": "pile of components",
		"atlas": Rect2i(8, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0019,
		"zone_weights": [0.20, 1.65, 0.60, 0.50, 1.15],
		"small_room_weight": 0.90,
		"large_room_weight": 1.10,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 1, "max": 2, "chance": 1.0},
			{"kind": Item.Kind.MECHANISM, "min": 1, "max": 2, "chance": 0.78},
			{"kind": Item.Kind.DATACORE, "min": 1, "max": 1, "chance": 0.12},
		],
		"clusters": [
			{"kind": Kind.BROKEN_THERMOMETOR_BOX, "chance": 0.18, "radius": 4},
			{"kind": Kind.BROKEN_BATTERIES, "chance": 0.20, "radius": 4},
		],
	},
	Kind.BROKEN_BATTERIES: {
		"name": "broken batteries",
		"atlas": Rect2i(9, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0015,
		"zone_weights": [0.18, 1.20, 0.70, 0.35, 1.00],
		"small_room_weight": 0.95,
		"large_room_weight": 1.00,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 1, "max": 2, "chance": 1.0},
			{"kind": Item.Kind.CHARGE_CELL, "min": 1, "max": 1, "chance": 0.42},
			{"kind": Item.Kind.MECHANISM, "min": 1, "max": 1, "chance": 0.18},
		],
		"clusters": [
			{"kind": Kind.PILE_OF_BATTERIES, "chance": 0.26, "radius": 3},
			{"kind": Kind.PILE_OF_COMPONENTS, "chance": 0.16, "radius": 4},
		],
	},
	Kind.PILE_OF_BATTERIES: {
		"name": "pile of batteries",
		"atlas": Rect2i(10, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0013,
		"zone_weights": [0.16, 1.05, 0.75, 0.30, 0.95],
		"small_room_weight": 1.05,
		"large_room_weight": 0.90,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 1, "max": 2, "chance": 1.0},
			{"kind": Item.Kind.CHARGE_CELL, "min": 1, "max": 2, "chance": 0.72},
		],
		"clusters": [
			{"kind": Kind.BROKEN_BATTERIES, "chance": 0.30, "radius": 3},
			{"kind": Kind.RUSTY_STORAGE_BIN, "chance": 0.12, "radius": 4},
		],
	},
	Kind.STORAGE_TANK: {
		"name": "storage tank",
		"atlas": Rect2i(11, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0012,
		"zone_weights": [0.22, 1.35, 0.45, 0.55, 1.10],
		"small_room_weight": 0.50,
		"large_room_weight": 1.55,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 2, "max": 3, "chance": 1.0},
			{"kind": Item.Kind.PLATING, "min": 1, "max": 2, "chance": 0.75},
			{"kind": Item.Kind.CHARGE_CELL, "min": 1, "max": 1, "chance": 0.12},
		],
		"clusters": [
			{"kind": Kind.BROKEN_VENT, "chance": 0.18, "radius": 4},
			{"kind": Kind.PILE_OF_SCRAP, "chance": 0.22, "radius": 4},
		],
	},
	Kind.SATELLITE_DISH: {
		"name": "satellite dish",
		"atlas": Rect2i(12, 0, 1, 1),
		"footprint": Vector2i(1, 1),
		"base_chance": 0.0009,
		"zone_weights": [0.10, 1.30, 0.45, 0.45, 1.45],
		"small_room_weight": 0.55,
		"large_room_weight": 1.45,
		"drops": [
			{"kind": Item.Kind.SCRAP, "min": 1, "max": 2, "chance": 1.0},
			{"kind": Item.Kind.MECHANISM, "min": 1, "max": 2, "chance": 0.58},
			{"kind": Item.Kind.DATACORE, "min": 1, "max": 1, "chance": 0.28},
		],
		"clusters": [
			{"kind": Kind.PILE_OF_COMPONENTS, "chance": 0.22, "radius": 4},
			{"kind": Kind.BROKEN_THERMOMETOR_BOX, "chance": 0.16, "radius": 4},
		],
	},
}
const BASE_FLOOR_TILES: Array[int] = [
	TerrainGenerator.TILE_FLOOR,
	TerrainGenerator.TILE_DEBRIS,
	TerrainGenerator.TILE_CONDUIT,
	TerrainGenerator.TILE_RUST,
]
const STAND_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

@export var chunk_manager_path: NodePath
@export var spawn_density_multiplier: float = 1.0
@export var cluster_density_multiplier: float = 1.0
@export var max_props_per_chunk: int = 18
@export var max_generated_chunks_per_frame: int = 3

var _chunk_manager: ChunkManager
var _noise: FastNoiseLite
var _site_seed: int = 0
var _generated_chunks: Dictionary = {}          ## Vector2i -> true
var _generating_chunks: Dictionary = {}         ## Vector2i -> true
var _generation_queue: Array[Vector2i] = []
var _generation_pending: Dictionary = {}        ## Vector2i -> true
var _props: Dictionary = {}                     ## anchor -> prop Dictionary
var _cell_to_anchor: Dictionary = {}            ## occupied cell -> anchor


func _ready() -> void:
	z_index = -12
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_chunk_manager.set_static_prop_manager(self)
	EventBus.chunk_loaded.connect(_on_chunk_loaded)


func setup(site_seed: int) -> void:
	_site_seed = site_seed
	_noise = TerrainGenerator.make_noise(site_seed)
	if _chunk_manager != null:
		for coord in _chunk_manager.loaded_chunk_coords():
			_enqueue_chunk(coord)


func _process(_delta: float) -> void:
	var budget: int = max_generated_chunks_per_frame
	while budget > 0 and not _generation_queue.is_empty():
		var chunk_coord: Vector2i = _generation_queue.pop_front()
		_generation_pending.erase(chunk_coord)
		if _generated_chunks.has(chunk_coord):
			continue
		if not _chunk_manager.loaded_chunk_coords().has(chunk_coord):
			continue
		_generate_chunk_now(chunk_coord)
		budget -= 1


func prop_at(grid: Vector2i) -> Dictionary:
	_ensure_chunk_generated_for(grid)
	var anchor: Vector2i = _cell_to_anchor.get(grid, Pathfinder.UNREACHABLE) as Vector2i
	if anchor == Pathfinder.UNREACHABLE:
		return {}
	return _props.get(anchor, {}) as Dictionary


func has_mineable_prop(grid: Vector2i) -> bool:
	return not prop_at(grid).is_empty()


func prop_name_at(grid: Vector2i) -> String:
	var prop: Dictionary = prop_at(grid)
	if prop.is_empty():
		return ""
	var def: Dictionary = PROP_DEFS[int(prop["kind"])] as Dictionary
	return def["name"] as String


func mine_rewards_text_at(grid: Vector2i) -> String:
	var prop: Dictionary = prop_at(grid)
	if prop.is_empty():
		return ""
	var def: Dictionary = PROP_DEFS[int(prop["kind"])] as Dictionary
	var parts: Array[String] = []
	for drop in def["drops"] as Array:
		var d: Dictionary = drop as Dictionary
		var kind: int = int(d["kind"])
		var lo: int = int(d["min"])
		var hi: int = int(d["max"])
		var chance: float = float(d["chance"])
		var qty: String = str(lo) if lo == hi else "%d-%d" % [lo, hi]
		if chance >= 0.999:
			parts.append("%s x%s" % [Item.kind_name(kind), qty])
		else:
			parts.append("%s x%s %.0f%%" % [Item.kind_name(kind), qty, chance * 100.0])
	return _join_strings(parts, ", ")


func blocks_cell(grid: Vector2i) -> bool:
	return _cell_to_anchor.has(grid)


func generate_now_at(grid: Vector2i) -> void:
	_ensure_chunk_generated_for(grid)


func generate_all_pending_now() -> void:
	var coords: Array[Vector2i] = []
	for coord in _generation_queue:
		coords.append(coord as Vector2i)
	_generation_queue.clear()
	_generation_pending.clear()
	for coord in _chunk_manager.loaded_chunk_coords():
		if not _generated_chunks.has(coord):
			coords.append(coord)
	var seen: Dictionary = {}
	for coord in coords:
		if seen.has(coord):
			continue
		seen[coord] = true
		if _generated_chunks.has(coord):
			continue
		if not _chunk_manager.loaded_chunk_coords().has(coord):
			continue
		_generate_chunk_now(coord)


func pending_generation_count() -> int:
	var count: int = _generation_queue.size()
	for coord in _chunk_manager.loaded_chunk_coords():
		if not _generated_chunks.has(coord) and not _generation_pending.has(coord):
			count += 1
	return count


func mine_stand_for(grid: Vector2i, from: Vector2i, pathfinder: Pathfinder) -> Vector2i:
	var prop: Dictionary = prop_at(grid)
	if prop.is_empty():
		return Pathfinder.UNREACHABLE
	var cells: Array = prop["cells"] as Array
	var best: Vector2i = Pathfinder.UNREACHABLE
	var best_d: int = 0x7fffffff
	for raw_cell in cells:
		var cell: Vector2i = raw_cell as Vector2i
		for off in STAND_OFFSETS:
			var candidate: Vector2i = cell + off
			if _cell_to_anchor.has(candidate):
				continue
			if not _chunk_manager.is_walkable(candidate):
				continue
			if pathfinder != null and candidate != from:
				var route: Dictionary = pathfinder.find_path_with_teleporters(from, candidate)
				var path: PackedVector2Array = route.get("path", PackedVector2Array()) as PackedVector2Array
				if path.is_empty():
					continue
			var d: int = maxi(absi(candidate.x - from.x), absi(candidate.y - from.y))
			if d < best_d:
				best = candidate
				best_d = d
	return best


func mine_prop_at(grid: Vector2i) -> Dictionary:
	var prop: Dictionary = prop_at(grid)
	if prop.is_empty():
		return {}
	var anchor: Vector2i = prop["anchor"] as Vector2i
	var kind: int = int(prop["kind"])
	var cells: Array = prop["cells"] as Array
	var rewards: Dictionary = _roll_rewards(kind, anchor)
	_props.erase(anchor)
	for raw_cell in cells:
		var cell: Vector2i = raw_cell as Vector2i
		_cell_to_anchor.erase(cell)
		EventBus.tile_changed.emit(cell, _chunk_manager.get_tile_at(cell))
	queue_redraw()
	return rewards


func _on_chunk_loaded(chunk_coord: Vector2i) -> void:
	if _site_seed == 0:
		return
	if _generated_chunks.has(chunk_coord):
		return
	_enqueue_chunk(chunk_coord)


func _enqueue_chunk(chunk_coord: Vector2i) -> void:
	if _generated_chunks.has(chunk_coord) or _generation_pending.has(chunk_coord):
		return
	_generation_queue.append(chunk_coord)
	_generation_pending[chunk_coord] = true


func _ensure_chunk_generated_for(grid: Vector2i) -> void:
	if _site_seed == 0:
		return
	var chunk_coord: Vector2i = Chunk.grid_to_chunk(grid)
	if _generated_chunks.has(chunk_coord) or _generating_chunks.has(chunk_coord):
		return
	if not _chunk_manager.is_chunk_in_map(chunk_coord):
		return
	if not _chunk_manager.loaded_chunk_coords().has(chunk_coord):
		_enqueue_chunk(chunk_coord)
		return
	_generation_pending.erase(chunk_coord)
	_generation_queue.erase(chunk_coord)
	_generate_chunk_now(chunk_coord)


func _generate_chunk_now(chunk_coord: Vector2i) -> void:
	if _generated_chunks.has(chunk_coord):
		return
	_generated_chunks[chunk_coord] = true
	_generating_chunks[chunk_coord] = true
	_generate_chunk(chunk_coord)
	_generating_chunks.erase(chunk_coord)


func _generate_chunk(chunk_coord: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_site_seed, chunk_coord.x, chunk_coord.y, "static_props"])
	var zone: int = TerrainGenerator.get_zone(_noise, chunk_coord)
	var room_sizes: Dictionary = _open_component_sizes(chunk_coord)
	var placed: int = 0
	var base: Vector2i = chunk_coord * Chunk.SIZE
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			if placed >= max_props_per_chunk:
				queue_redraw()
				return
			var cell: Vector2i = base + Vector2i(lx, ly)
			if _cell_to_anchor.has(cell):
				continue
			var kind: int = _pick_prop_kind(cell, zone, int(room_sizes.get(cell, 0)), rng)
			if kind < 0:
				continue
			if _try_place(kind, cell, rng):
				placed += 1
				placed += _place_clusters(kind, cell, zone, room_sizes, rng, max_props_per_chunk - placed)
	queue_redraw()


func _open_component_sizes(chunk_coord: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	var visited: Dictionary = {}
	var base: Vector2i = chunk_coord * Chunk.SIZE
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var start: Vector2i = base + Vector2i(lx, ly)
			if visited.has(start) or not _is_prop_floor(start):
				continue
			var cells: Array[Vector2i] = []
			var queue: Array[Vector2i] = [start]
			visited[start] = true
			var head: int = 0
			while head < queue.size():
				var cell: Vector2i = queue[head]
				head += 1
				cells.append(cell)
				for i in range(4):
					var off: Vector2i = STAND_OFFSETS[i]
					var next: Vector2i = cell + off
					if visited.has(next) or not _same_chunk(next, chunk_coord) or not _is_prop_floor(next):
						continue
					visited[next] = true
					queue.append(next)
			for cell in cells:
				out[cell] = cells.size()
	return out


func _pick_prop_kind(cell: Vector2i, zone: int, room_size: int, rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	var weights: Dictionary = {}
	for kind in PROP_DEFS.keys():
		var def: Dictionary = PROP_DEFS[kind] as Dictionary
		if not _can_place(int(kind), cell):
			continue
		var chance: float = float(def["base_chance"]) * spawn_density_multiplier
		chance *= _zone_weight(def, zone)
		chance *= _room_weight(def, room_size)
		if bool(def.get("requires_wall_neighbor", false)) and not _has_wall_neighbor(cell, def["footprint"] as Vector2i):
			continue
		total += chance
		weights[int(kind)] = chance
	if total <= 0.0 or rng.randf() > total:
		return -1
	var roll: float = rng.randf() * total
	var accum: float = 0.0
	for kind in weights.keys():
		accum += float(weights[kind])
		if roll <= accum:
			return int(kind)
	return -1


func _try_place(kind: int, anchor: Vector2i, rng: RandomNumberGenerator) -> bool:
	if not _can_place(kind, anchor):
		return false
	var def: Dictionary = PROP_DEFS[kind] as Dictionary
	var footprint: Vector2i = def["footprint"] as Vector2i
	var cells: Array[Vector2i] = []
	for y in footprint.y:
		for x in footprint.x:
			cells.append(anchor + Vector2i(x, y))
	var prop: Dictionary = {
		"kind": kind,
		"anchor": anchor,
		"cells": cells,
		"flip_h": rng.randf() < 0.5,
	}
	_props[anchor] = prop
	for cell in cells:
		_cell_to_anchor[cell] = anchor
		EventBus.tile_changed.emit(cell, _chunk_manager.get_tile_at(cell))
	return true


func _place_clusters(
	source_kind: int,
	source: Vector2i,
	zone: int,
	room_sizes: Dictionary,
	rng: RandomNumberGenerator,
	budget: int,
) -> int:
	if budget <= 0:
		return 0
	var def: Dictionary = PROP_DEFS[source_kind] as Dictionary
	var clusters: Array = def.get("clusters", []) as Array
	var placed: int = 0
	for cluster in clusters:
		if placed >= budget:
			break
		var c: Dictionary = cluster as Dictionary
		var chance: float = float(c["chance"]) * cluster_density_multiplier
		var radius: int = int(c["radius"])
		for _attempt in 4:
			if placed >= budget or rng.randf() > chance:
				continue
			var offset := Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
			if offset == Vector2i.ZERO or offset.length_squared() > radius * radius:
				continue
			var candidate: Vector2i = source + offset
			if not _chunk_manager.is_grid_in_map(candidate):
				continue
			if not _same_chunk(candidate, Chunk.grid_to_chunk(source)):
				continue
			var kind: int = int(c["kind"])
			var room_size: int = int(room_sizes.get(candidate, 0))
			var candidate_def: Dictionary = PROP_DEFS[kind] as Dictionary
			if room_size > 0 and rng.randf() < _zone_weight(candidate_def, zone) * _room_weight(candidate_def, room_size):
				if _try_place(kind, candidate, rng):
					placed += 1
	return placed


func _can_place(kind: int, anchor: Vector2i) -> bool:
	var def: Dictionary = PROP_DEFS[kind] as Dictionary
	var footprint: Vector2i = def["footprint"] as Vector2i
	for y in footprint.y:
		for x in footprint.x:
			var cell: Vector2i = anchor + Vector2i(x, y)
			if _cell_to_anchor.has(cell):
				return false
			if not _chunk_manager.is_grid_in_map(cell):
				return false
			if not _is_prop_floor(cell):
				return false
	return true


func _is_prop_floor(cell: Vector2i) -> bool:
	if not _chunk_manager.is_grid_in_map(cell):
		return false
	var tile: int = _chunk_manager.get_tile_at(cell)
	if not BASE_FLOOR_TILES.has(tile):
		return false
	if tile == TerrainGenerator.TILE_RUST:
		return true
	return _chunk_manager.is_walkable(cell)


func _zone_weight(def: Dictionary, zone: int) -> float:
	var weights: Array = def["zone_weights"] as Array
	if zone < 0 or zone >= weights.size():
		return 1.0
	return float(weights[zone])


func _room_weight(def: Dictionary, room_size: int) -> float:
	if room_size <= 0:
		return 0.25
	if room_size <= 22:
		return float(def.get("small_room_weight", 1.0))
	if room_size >= 72:
		return float(def.get("large_room_weight", 1.0))
	return 1.0


func _has_wall_neighbor(anchor: Vector2i, footprint: Vector2i) -> bool:
	for y in range(-1, footprint.y + 1):
		for x in range(-1, footprint.x + 1):
			if x >= 0 and x < footprint.x and y >= 0 and y < footprint.y:
				continue
			var tile: int = _chunk_manager.get_tile_at(anchor + Vector2i(x, y))
			if tile == TerrainGenerator.TILE_WALL \
					or tile == TerrainGenerator.TILE_RICH_WALL \
					or tile == TerrainGenerator.TILE_SERVICE_CORE:
				return true
	return false


func _roll_rewards(kind: int, anchor: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_site_seed, anchor.x, anchor.y, kind, "prop_rewards"])
	var def: Dictionary = PROP_DEFS[kind] as Dictionary
	var rewards: Dictionary = {}
	for drop in def["drops"] as Array:
		var d: Dictionary = drop as Dictionary
		if rng.randf() > float(d["chance"]):
			continue
		var item_kind: int = int(d["kind"])
		var amount: int = rng.randi_range(int(d["min"]), int(d["max"]))
		rewards[item_kind] = int(rewards.get(item_kind, 0)) + amount
	return rewards


func _same_chunk(cell: Vector2i, chunk_coord: Vector2i) -> bool:
	return Chunk.grid_to_chunk(cell) == chunk_coord


static func _join_strings(parts: Array[String], delimiter: String) -> String:
	var out: String = ""
	for part in parts:
		if not out.is_empty():
			out += delimiter
		out += part
	return out


func _draw() -> void:
	for anchor_key in _props.keys():
		var prop: Dictionary = _props[anchor_key] as Dictionary
		var kind: int = int(prop["kind"])
		var def: Dictionary = PROP_DEFS[kind] as Dictionary
		var atlas: Rect2i = def["atlas"] as Rect2i
		var anchor: Vector2i = prop["anchor"] as Vector2i
		var source := Rect2(
			Vector2(atlas.position * ATLAS_CELL_PIXELS),
			Vector2(atlas.size * ATLAS_CELL_PIXELS),
		)
		var dest := Rect2(
			Vector2(anchor * Chunk.TILE_PIXELS),
			Vector2(atlas.size * Chunk.TILE_PIXELS),
		)
		draw_texture_rect_region(PROP_ATLAS, dest, source)
