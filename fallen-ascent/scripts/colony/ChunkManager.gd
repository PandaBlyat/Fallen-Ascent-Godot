class_name ChunkManager
extends Node2D
##
## Owns the finite colony map. By default all chunks are generated once on
## scene entry, RimWorld-style, so camera movement never triggers terrain
## generation or Pathfinder region shifts.
##
## Algorithm (each camera_moved):
##   1. Compute the camera's current chunk coord (cam_chunk).
##   2. Build the target set = all chunks within `view_radius` of cam_chunk.
##   3. Spawn any target chunk not currently loaded.
##   4. Free any loaded chunk OUTSIDE target + 1-cell hysteresis buffer.
##
## The hysteresis buffer prevents thrashing when the camera oscillates right
## on a chunk boundary (we only unload one extra chunk away from the active
## radius, so a small movement back doesn't trigger reload).

@export var view_radius: int = 4                  ## chunks loaded around camera
@export var unload_padding: int = 1               ## hysteresis, in chunks
@export var max_loads_per_frame: int = 2          ## stagger spawns to smooth FPS
@export var initial_max_loads_per_frame: int = 6
@export var map_size_chunks: Vector2i = Vector2i(12, 12)
@export var preload_entire_map: bool = true
@export var job_board_path: NodePath
@export var fog_of_war_path: NodePath
@export var rust_spread_interval: float = 18.0
@export var rust_spread_chance: float = 0.35
@export var grass_spread_interval: float = 30.0
@export var grass_spread_chance: float = 0.28
@export var max_scrape_jobs: int = 64
@export var max_grass_per_chunk: int = 260

var _site_seed: int = 0
var _noise: FastNoiseLite
var _loaded: Dictionary = {}                      ## Vector2i -> Chunk
## Session-lifetime diff cache: chunk_coord -> { local_coord -> tile_id }.
## Lets mined cells survive unload/reload until a real save system lands.
var _diffs: Dictionary = {}
var _last_cam_chunk: Vector2i = Vector2i(0x7fffffff, 0x7fffffff)
var _load_queue: Array[Vector2i] = []
var _load_pending: Dictionary = {}                ## Vector2i -> true (in _load_queue)
var _initial_loaded: bool = false
var _initial_loading: bool = false
var _initial_load_total: int = 0
var _outlets: Dictionary = {}                      ## Vector2i -> true
var _outlet_reservations: Dictionary = {}          ## Vector2i -> Array[Worker]
var _rust_cells: Dictionary = {}                    ## Vector2i -> true
var _grass_cells: Dictionary = {}                   ## Vector2i -> int border mask
var _teleporters: Array[Vector2i] = []
var _teleporter_lookup: Dictionary = {}             ## Vector2i -> true
var _blocked_teleporters: Dictionary = {}           ## Vector2i -> true (player-disabled)
var _rust_timer: float = 0.0
var _grass_timer: float = 0.0
var _structure_manager: Node = null
var _static_prop_manager: Node = null
var _job_board: JobBoard = null
var _fog: FogOfWar = null


func setup(site_seed: int) -> void:
	_site_seed = site_seed
	_noise = TerrainGenerator.make_noise(site_seed)


func _ready() -> void:
	_job_board = get_node_or_null(job_board_path) as JobBoard
	_fog = get_node_or_null(fog_of_war_path) as FogOfWar
	EventBus.camera_moved.connect(_on_camera_moved)
	EventBus.visibility_changed.connect(_on_visibility_changed)


func _on_camera_moved(world_pos: Vector2, _zoom: Vector2) -> void:
	if preload_entire_map:
		if not _initial_loaded:
			_enqueue_entire_map()
			_begin_initial_load()
		return
	# Camera_moved fires roughly every pixel of motion; chunk streaming only
	# needs to react when the camera crosses a chunk boundary.
	var cam_chunk: Vector2i = _world_to_chunk(world_pos)
	if cam_chunk == _last_cam_chunk:
		return
	_last_cam_chunk = cam_chunk
	_load_around(cam_chunk)
	if not _initial_loaded:
		# Drain synchronously so worker spawn / pathfinder have terrain.
		_drain_queue(_load_queue.size())
		_initial_loaded = true
		EventBus.colony_load_progress.emit(_loaded.size(), _loaded.size())
	_unload_outside(cam_chunk)


func _load_around(center: Vector2i) -> void:
	# Enqueue any not-yet-loaded chunks; the actual spawn happens in _process
	# with a per-frame budget. Innermost chunks first so the camera area
	# materializes before the periphery.
	for r in range(view_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var coord := Vector2i(center.x + dx, center.y + dy)
				if not is_chunk_in_map(coord):
					continue
				if _loaded.has(coord) or _load_pending.has(coord):
					continue
				_load_queue.append(coord)
				_load_pending[coord] = true


func _enqueue_entire_map() -> void:
	var bounds: Rect2i = map_chunk_bounds()
	for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			var coord := Vector2i(x, y)
			if _loaded.has(coord) or _load_pending.has(coord):
				continue
			_load_queue.append(coord)
			_load_pending[coord] = true


func _process(delta: float) -> void:
	var budget: int = initial_max_loads_per_frame if _initial_loading else max_loads_per_frame
	_drain_queue(budget)
	_process_rust(delta)
	_process_grass(delta)


func _drain_queue(budget: int) -> void:
	var loaded_this_call: bool = false
	while budget > 0 and not _load_queue.is_empty():
		var coord: Vector2i = _load_queue.pop_front()
		_load_pending.erase(coord)
		if _loaded.has(coord):
			continue
		var chunk: Chunk = Chunk.new()
		add_child(chunk)
		chunk.populate(coord, _noise)
		_apply_diffs(chunk, coord)
		_loaded[coord] = chunk
		_index_special_tiles(chunk, coord)
		_seed_grass_for_chunk(chunk, coord)
		EventBus.chunk_loaded.emit(coord)
		loaded_this_call = true
		budget -= 1
	if _initial_loading and loaded_this_call:
		var loaded: int = _initial_load_total - _load_queue.size()
		EventBus.colony_load_progress.emit(loaded, _initial_load_total)
	if _initial_loading and _load_queue.is_empty():
		_finish_initial_load()


func _begin_initial_load() -> void:
	_initial_loading = true
	_initial_load_total = _load_queue.size()
	_set_pathfinder_bulk_loading(true)
	EventBus.colony_load_progress.emit(_initial_load_total - _load_queue.size(), _initial_load_total)


func _finish_initial_load() -> void:
	if not _initial_loading:
		return
	_initial_loading = false
	_initial_loaded = true
	_set_pathfinder_bulk_loading(false)
	EventBus.colony_load_progress.emit(_initial_load_total, _initial_load_total)


func _set_pathfinder_bulk_loading(active: bool) -> void:
	var pathfinder: Node = get_node_or_null("../Pathfinder")
	if pathfinder != null and pathfinder.has_method("set_bulk_loading"):
		pathfinder.call("set_bulk_loading", active)
	if not active and pathfinder != null and pathfinder.has_method("flush_rebuild"):
		pathfinder.call("flush_rebuild")


func _unload_outside(center: Vector2i) -> void:
	var keep_radius: int = view_radius + unload_padding
	var to_free: Array[Vector2i] = []
	for coord in _loaded.keys():
		var c: Vector2i = coord as Vector2i
		if absi(c.x - center.x) > keep_radius or absi(c.y - center.y) > keep_radius:
			to_free.append(c)
	for c in to_free:
		var chunk: Chunk = _loaded[c]
		_loaded.erase(c)
		_unindex_special_tiles(c)
		EventBus.chunk_unloaded.emit(c)
		chunk.queue_free()


func loaded_count() -> int:
	return _loaded.size()


func loaded_chunk_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for coord in _loaded.keys():
		out.append(coord as Vector2i)
	return out


func outlet_count() -> int:
	return _outlets.size()


func outlet_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key in _outlets.keys():
		out.append(key as Vector2i)
	return out


func set_structure_manager(manager: Node) -> void:
	_structure_manager = manager


func set_static_prop_manager(manager: Node) -> void:
	_static_prop_manager = manager


## Returns the bounding rect of loaded chunks in chunk coords (inclusive lo,
## exclusive hi). Used by pathfinder to size its AStarGrid2D region.
func loaded_chunk_bounds() -> Rect2i:
	if preload_entire_map:
		return map_chunk_bounds()
	if _loaded.is_empty():
		return Rect2i()
	var first := true
	var lo := Vector2i.ZERO
	var hi := Vector2i.ZERO
	for coord in _loaded.keys():
		var c: Vector2i = coord as Vector2i
		if first:
			lo = c
			hi = c + Vector2i.ONE
			first = false
		else:
			lo.x = mini(lo.x, c.x)
			lo.y = mini(lo.y, c.y)
			hi.x = maxi(hi.x, c.x + 1)
			hi.y = maxi(hi.y, c.y + 1)
	return Rect2i(lo, hi - lo)


## Returns the tile id at a global grid coord. If the chunk isn't loaded,
## reports TILE_VOID — callers treat that as impassable.
func get_tile_at(grid: Vector2i) -> int:
	if not is_grid_in_map(grid):
		return TerrainGenerator.TILE_VOID
	var ccoord := Chunk.grid_to_chunk(grid)
	if not _loaded.has(ccoord):
		return TerrainGenerator.TILE_VOID
	var chunk: Chunk = _loaded[ccoord]
	return chunk.get_tile(Chunk.grid_to_local(grid))


## Writes a tile id at a global grid coord and emits tile_changed. No-op if
## the chunk isn't loaded (mining unloaded terrain is not supported).
func set_tile_at(grid: Vector2i, t: int) -> void:
	if not is_grid_in_map(grid):
		return
	var ccoord := Chunk.grid_to_chunk(grid)
	if not _loaded.has(ccoord):
		return
	var chunk: Chunk = _loaded[ccoord]
	var local: Vector2i = Chunk.grid_to_local(grid)
	var old_tile: int = chunk.get_tile(local)
	chunk.set_tile(local, t)
	if old_tile == TerrainGenerator.TILE_OUTLET:
		_outlets.erase(grid)
		_outlet_reservations.erase(grid)
	elif old_tile == TerrainGenerator.TILE_RUST:
		_rust_cells.erase(grid)
		if _job_board != null:
			_job_board.cancel_scrape_rust_at(grid)
	elif old_tile == TerrainGenerator.TILE_TELEPORTER:
		_remove_teleporter(grid)
	if t == TerrainGenerator.TILE_OUTLET:
		_outlets[grid] = true
	elif t == TerrainGenerator.TILE_RUST:
		_rust_cells[grid] = true
	elif t == TerrainGenerator.TILE_TELEPORTER:
		_add_teleporter(grid)
	_record_diff(ccoord, local, t)
	if not _can_grow_grass_on(t):
		clear_grass(grid)
	else:
		_recompute_grass_masks_around(grid)
	EventBus.tile_changed.emit(grid, t)


## Replays any cached diffs onto a freshly-populated chunk so mining
## persists across unload/reload during a session. Uses chunk.set_tile
## directly (not set_tile_at) to avoid re-emitting tile_changed for
## already-known mutations.
func _apply_diffs(chunk: Chunk, coord: Vector2i) -> void:
	if not _diffs.has(coord):
		return
	var per_chunk: Dictionary = _diffs[coord]
	for local in per_chunk.keys():
		chunk.set_tile(local as Vector2i, per_chunk[local] as int)


func _record_diff(coord: Vector2i, local: Vector2i, t: int) -> void:
	var per_chunk: Dictionary = _diffs.get(coord, {})
	per_chunk[local] = t
	_diffs[coord] = per_chunk


func is_walkable(grid: Vector2i) -> bool:
	var t: int = get_tile_at(grid)
	var terrain_walkable: bool = t == TerrainGenerator.TILE_FLOOR \
		or t == TerrainGenerator.TILE_DEBRIS \
		or t == TerrainGenerator.TILE_OUTLET \
		or t == TerrainGenerator.TILE_CONDUIT \
		or t == TerrainGenerator.TILE_RUST \
		or t == TerrainGenerator.TILE_TELEPORTER \
		or t == TerrainGenerator.TILE_WATER_SHALLOW \
		or t == TerrainGenerator.TILE_WATER_PUDDLE \
		or t == TerrainGenerator.TILE_ACID_SHALLOW \
		or t == TerrainGenerator.TILE_ACID_PUDDLE
	if not terrain_walkable:
		return false
	if t == TerrainGenerator.TILE_TELEPORTER and _blocked_teleporters.has(grid):
		return false
	if _structure_manager != null and _structure_manager.has_method("blocks_cell"):
		if bool(_structure_manager.call("blocks_cell", grid)):
			return false
	if _static_prop_manager != null and _static_prop_manager.has_method("blocks_cell"):
		if bool(_static_prop_manager.call("blocks_cell", grid)):
			return false
	return true


func is_outlet(grid: Vector2i) -> bool:
	return get_tile_at(grid) == TerrainGenerator.TILE_OUTLET


func is_teleporter(grid: Vector2i) -> bool:
	if _blocked_teleporters.has(grid):
		return false
	return get_tile_at(grid) == TerrainGenerator.TILE_TELEPORTER


func is_any_teleporter(grid: Vector2i) -> bool:
	return get_tile_at(grid) == TerrainGenerator.TILE_TELEPORTER


func is_teleporter_blocked(grid: Vector2i) -> bool:
	return _blocked_teleporters.has(grid)


func toggle_teleporter_block(grid: Vector2i) -> bool:
	if get_tile_at(grid) != TerrainGenerator.TILE_TELEPORTER:
		return false
	if _blocked_teleporters.has(grid):
		_blocked_teleporters.erase(grid)
	else:
		_blocked_teleporters[grid] = true
	# Re-emit so Pathfinder rebuilds the walkability cache for this cell and
	# any worker pathing through it can replan.
	EventBus.tile_changed.emit(grid, TerrainGenerator.TILE_TELEPORTER)
	return true


func has_grass(grid: Vector2i) -> bool:
	return _grass_cells.has(grid)


func add_grass(grid: Vector2i) -> void:
	if not is_grid_in_map(grid) or not _can_grow_grass_on(get_tile_at(grid)):
		return
	_grass_cells[grid] = 1
	_recompute_grass_masks_around(grid)


func clear_grass(grid: Vector2i) -> void:
	if not _grass_cells.has(grid):
		return
	_grass_cells.erase(grid)
	var ccoord := Chunk.grid_to_chunk(grid)
	if _loaded.has(ccoord):
		var chunk: Chunk = _loaded[ccoord]
		chunk.set_grass_mask(Chunk.grid_to_local(grid), 0)
	_recompute_grass_masks_around(grid)


func grass_count() -> int:
	return _grass_cells.size()


func random_linked_teleporter(from: Vector2i) -> Vector2i:
	if _teleporters.size() < 2:
		return Pathfinder.UNREACHABLE
	for _attempt in range(12):
		var candidate: Vector2i = _teleporters[randi() % _teleporters.size()]
		if candidate != from and not _blocked_teleporters.has(candidate):
			return candidate
	for candidate in _teleporters:
		if candidate != from and not _blocked_teleporters.has(candidate):
			return candidate
	return Pathfinder.UNREACHABLE


func teleporter_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in _teleporters:
		if _blocked_teleporters.has(cell):
			continue
		out.append(cell)
	return out


func teleporter_cells_all() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in _teleporters:
		out.append(cell)
	return out


func reserve_outlet(grid: Vector2i, worker: Node) -> bool:
	if not is_outlet(grid):
		return false
	var reservations: Array = _outlet_reservations.get(grid, []) as Array
	if reservations.has(worker):
		return true
	if reservations.size() >= outlet_capacity(grid):
		return false
	reservations.append(worker)
	_outlet_reservations[grid] = reservations
	return true


func release_outlet(grid: Vector2i, worker: Node) -> void:
	if not _outlet_reservations.has(grid):
		return
	var reservations: Array = _outlet_reservations[grid] as Array
	reservations.erase(worker)
	if reservations.is_empty():
		_outlet_reservations.erase(grid)
	else:
		_outlet_reservations[grid] = reservations


func is_outlet_reserved_by_other(grid: Vector2i, worker: Node) -> bool:
	var reservations: Array = _outlet_reservations.get(grid, []) as Array
	if reservations.has(worker):
		return false
	return reservations.size() >= outlet_capacity(grid)


func outlet_capacity(grid: Vector2i) -> int:
	if _structure_manager != null and _structure_manager.has_method("structure_at"):
		var structure: Dictionary = _structure_manager.call("structure_at", grid) as Dictionary
		if not structure.is_empty() and int(structure["id"]) == BuildBlueprint.Id.OUTLET_EXTENSION:
			return 2
	return 1


func structure_at(grid: Vector2i) -> Dictionary:
	if _structure_manager != null and _structure_manager.has_method("structure_at"):
		return _structure_manager.call("structure_at", grid) as Dictionary
	return {}


func request_door_open(grid: Vector2i) -> void:
	if _structure_manager != null and _structure_manager.has_method("request_door_open"):
		_structure_manager.call("request_door_open", grid)


func is_door_open(grid: Vector2i) -> bool:
	if _structure_manager != null and _structure_manager.has_method("is_door_open"):
		return bool(_structure_manager.call("is_door_open", grid))
	return false


func nearest_outlet(from: Vector2i, pathfinder: Pathfinder = null, fog: FogOfWar = null, worker: Node = null) -> Vector2i:
	var best := Vector2i(2147483647, 2147483647)
	var best_d: int = 0x7fffffff
	for key in _outlets.keys():
		var outlet: Vector2i = key as Vector2i
		if fog != null and not fog.is_explored(outlet):
			continue
		if is_outlet_reserved_by_other(outlet, worker):
			continue
		var d: int = maxi(absi(outlet.x - from.x), absi(outlet.y - from.y))
		if d >= best_d:
			continue
		if pathfinder != null and not pathfinder.has_path(from, outlet):
			continue
		best = outlet
		best_d = d
	return best


func ensure_outlet_near(origin: Vector2i) -> Vector2i:
	var seed: Vector2i = _nearest_floor_family_for_outlet(origin)
	if seed == Pathfinder.UNREACHABLE:
		return Pathfinder.UNREACHABLE
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	# Flood only floor-family cells. Worker walkability crosses doors and
	# corridors, which can place spawn outlet outside the perceived room.
	var queue: Array[Vector2i] = [seed]
	var seen: Dictionary = {seed: true}
	var best_floor: Vector2i = Pathfinder.UNREACHABLE
	var best_score: int = -0x7fffffff
	var head: int = 0
	while head < queue.size() and seen.size() <= 1024:
		var cell: Vector2i = queue[head]
		head += 1
		var tile: int = get_tile_at(cell)
		if tile == TerrainGenerator.TILE_OUTLET:
			return cell
		if _can_force_outlet_on(tile):
			var d_seed: int = maxi(absi(cell.x - seed.x), absi(cell.y - seed.y))
			var wall_clearance: int = _floor_wall_clearance(cell, 3)
			var door_penalty: int = 12 if _adjacent_to_door(cell) else 0
			var score: int = wall_clearance * 10 - d_seed - door_penalty
			if score > best_score:
				best_floor = cell
				best_score = score
		for off in OFFSETS:
			var next: Vector2i = cell + off
			if seen.has(next) or not is_grid_in_map(next):
				continue
			var next_tile: int = get_tile_at(next)
			if next_tile != TerrainGenerator.TILE_OUTLET and not _is_floor_family_for_outlet(next_tile):
				continue
			seen[next] = true
			queue.append(next)
	if best_floor != Pathfinder.UNREACHABLE:
		set_tile_at(best_floor, TerrainGenerator.TILE_OUTLET)
		if _floor_family_reachable(seed, best_floor):
			return best_floor
		var fallback: Vector2i = _fallback_outlet_next_to(seed)
		if fallback != Pathfinder.UNREACHABLE:
			set_tile_at(fallback, TerrainGenerator.TILE_OUTLET)
			return fallback
	return best_floor


func _nearest_floor_family_for_outlet(origin: Vector2i) -> Vector2i:
	if _is_floor_family_for_outlet(get_tile_at(origin)):
		return origin
	for r in range(1, 32):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var cell := origin + Vector2i(dx, dy)
				if _is_floor_family_for_outlet(get_tile_at(cell)):
					return cell
	return Pathfinder.UNREACHABLE


static func _is_floor_family_for_outlet(tile: int) -> bool:
	return tile == TerrainGenerator.TILE_FLOOR \
		or tile == TerrainGenerator.TILE_DEBRIS \
		or tile == TerrainGenerator.TILE_CONDUIT \
		or tile == TerrainGenerator.TILE_RUST \
		or tile == TerrainGenerator.TILE_OUTLET


static func _can_force_outlet_on(tile: int) -> bool:
	return tile == TerrainGenerator.TILE_FLOOR \
		or tile == TerrainGenerator.TILE_DEBRIS \
		or tile == TerrainGenerator.TILE_CONDUIT \
		or tile == TerrainGenerator.TILE_RUST


func _adjacent_to_door(cell: Vector2i) -> bool:
	if _structure_manager == null or not _structure_manager.has_method("structure_at"):
		return false
	const OFFSETS: Array[Vector2i] = [
		Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for off in OFFSETS:
		var structure: Dictionary = _structure_manager.call("structure_at", cell + off) as Dictionary
		if not structure.is_empty() and int(structure.get("id", -1)) == BuildBlueprint.Id.DOOR:
			return true
	return false


func _floor_wall_clearance(cell: Vector2i, max_radius: int) -> int:
	for radius in range(1, max_radius + 1):
		for y in range(cell.y - radius, cell.y + radius + 1):
			for x in range(cell.x - radius, cell.x + radius + 1):
				if maxi(absi(x - cell.x), absi(y - cell.y)) != radius:
					continue
				if not _is_floor_family_for_outlet(get_tile_at(Vector2i(x, y))):
					return radius - 1
	return max_radius


func _floor_family_reachable(from: Vector2i, to: Vector2i) -> bool:
	if from == to:
		return true
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var queue: Array[Vector2i] = [from]
	var seen: Dictionary = {from: true}
	var head: int = 0
	while head < queue.size() and seen.size() <= 1024:
		var cell: Vector2i = queue[head]
		head += 1
		for off in OFFSETS:
			var next: Vector2i = cell + off
			if next == to:
				return true
			if seen.has(next) or not is_grid_in_map(next):
				continue
			if not _is_floor_family_for_outlet(get_tile_at(next)):
				continue
			seen[next] = true
			queue.append(next)
	return false


func _fallback_outlet_next_to(seed: Vector2i) -> Vector2i:
	const OFFSETS: Array[Vector2i] = [
		Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for off in OFFSETS:
		var candidate: Vector2i = seed + off
		if _can_force_outlet_on(get_tile_at(candidate)):
			return candidate
	return Pathfinder.UNREACHABLE


func random_nearby_rust(from: Vector2i, radius: int, pathfinder: Pathfinder = null, fog: FogOfWar = null) -> Vector2i:
	if _rust_cells.is_empty():
		return Pathfinder.UNREACHABLE
	var keys: Array = _rust_cells.keys()
	var best: Vector2i = Pathfinder.UNREACHABLE
	var best_d: int = 0x7fffffff
	for _attempt in range(mini(128, keys.size())):
		var candidate: Vector2i = keys[randi() % keys.size()] as Vector2i
		var d: int = maxi(absi(candidate.x - from.x), absi(candidate.y - from.y))
		if d > radius or d >= best_d:
			continue
		if fog != null and not fog.is_explored(candidate):
			continue
		if get_tile_at(candidate) != TerrainGenerator.TILE_RUST:
			continue
		if pathfinder != null and not pathfinder.has_path(from, candidate):
			continue
		best = candidate
		best_d = d
	return best


func map_chunk_bounds() -> Rect2i:
	var size := Vector2i(maxi(1, map_size_chunks.x), maxi(1, map_size_chunks.y))
	var pos := Vector2i(-size.x / 2, -size.y / 2)
	return Rect2i(pos, size)


func map_grid_bounds() -> Rect2i:
	var chunk_bounds: Rect2i = map_chunk_bounds()
	return Rect2i(chunk_bounds.position * Chunk.SIZE, chunk_bounds.size * Chunk.SIZE)


func map_world_rect() -> Rect2:
	var grid_bounds: Rect2i = map_grid_bounds()
	return Rect2(
		Vector2(grid_bounds.position * Chunk.TILE_PIXELS),
		Vector2(grid_bounds.size * Chunk.TILE_PIXELS),
	)


func is_chunk_in_map(coord: Vector2i) -> bool:
	return map_chunk_bounds().has_point(coord)


func is_grid_in_map(grid: Vector2i) -> bool:
	return map_grid_bounds().has_point(grid)


func _index_special_tiles(chunk: Chunk, coord: Vector2i) -> void:
	var base: Vector2i = coord * Chunk.SIZE
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var local := Vector2i(lx, ly)
			var grid: Vector2i = base + local
			var tile: int = chunk.get_tile(local)
			if tile == TerrainGenerator.TILE_OUTLET:
				_outlets[grid] = true
			elif tile == TerrainGenerator.TILE_RUST:
				_rust_cells[grid] = true
			elif tile == TerrainGenerator.TILE_TELEPORTER:
				_add_teleporter(grid)


func _unindex_special_tiles(coord: Vector2i) -> void:
	var base: Vector2i = coord * Chunk.SIZE
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var grid: Vector2i = base + Vector2i(lx, ly)
			_outlets.erase(grid)
			_rust_cells.erase(grid)
			_grass_cells.erase(grid)
			_remove_teleporter(grid)


func _process_rust(delta: float) -> void:
	if _rust_cells.is_empty():
		return
	_rust_timer += delta
	if _rust_timer < rust_spread_interval:
		return
	_rust_timer = 0.0
	if randf() > rust_spread_chance:
		return
	var source: Vector2i = _random_rust_cell()
	if source == Pathfinder.UNREACHABLE:
		return
	var target: Vector2i = _rust_spread_target(source)
	if target == Pathfinder.UNREACHABLE:
		return
	set_tile_at(target, TerrainGenerator.TILE_RUST)


func _process_grass(delta: float) -> void:
	if _grass_cells.is_empty():
		return
	_grass_timer += delta
	if _grass_timer < grass_spread_interval:
		return
	_grass_timer = 0.0
	if randf() > grass_spread_chance:
		return
	var source: Vector2i = _random_grass_cell()
	if source == Pathfinder.UNREACHABLE:
		return
	var target: Vector2i = _grass_spread_target(source)
	if target != Pathfinder.UNREACHABLE:
		add_grass(target)


func _seed_grass_for_chunk(chunk: Chunk, coord: Vector2i) -> void:
	var base: Vector2i = coord * Chunk.SIZE
	var distances: PackedInt32Array = _water_distances_for_chunk(chunk)
	var candidates: Array[Vector2i] = []
	# Single deterministic RNG seeded by chunk — calling randf() instead of
	# rebuilding RandomNumberGenerator per cell saves ~1024 allocations per
	# chunk load. Cell determinism is still preserved per chunk.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_site_seed, coord.x, coord.y, "grass_seed"])
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var local := Vector2i(lx, ly)
			if not _can_grow_grass_on(chunk.get_tile(local)):
				continue
			var dist: int = distances[ly * Chunk.SIZE + lx]
			var density: float = _grass_density_for_dist(dist)
			var grid: Vector2i = base + local
			if _near_acid(grid, 3):
				density = maxf(density, 0.18)
			if rng.randf() <= density:
				candidates.append(grid)
	if candidates.size() > max_grass_per_chunk:
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return absi(hash([_site_seed, a.x, a.y, "grass_cap"])) < absi(hash([_site_seed, b.x, b.y, "grass_cap"]))
		)
		candidates.resize(max_grass_per_chunk)
	for grid in candidates:
		_grass_cells[grid] = 1
	# Batch the per-cell mask cascade: collect every cell that needs a fresh
	# mask once (each candidate marks itself + 4 neighbors) so we don't redo
	# the same neighbor lookup N times when N adjacent cells get seeded.
	var dirty: Dictionary = {}
	for grid in candidates:
		dirty[grid] = true
		dirty[grid + Vector2i(0, -1)] = true
		dirty[grid + Vector2i(1, 0)] = true
		dirty[grid + Vector2i(0, 1)] = true
		dirty[grid + Vector2i(-1, 0)] = true
	for raw in dirty.keys():
		var cell: Vector2i = raw as Vector2i
		if not _grass_cells.has(cell):
			continue
		var mask: int = _grass_mask_for(cell)
		_grass_cells[cell] = mask
		var ccoord := Chunk.grid_to_chunk(cell)
		if _loaded.has(ccoord):
			var loaded_chunk: Chunk = _loaded[ccoord]
			loaded_chunk.set_grass_mask(Chunk.grid_to_local(cell), mask)


func _water_distances_for_chunk(chunk: Chunk) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(Chunk.SIZE * Chunk.SIZE)
	for i in dist.size():
		dist[i] = 999
	var queue: Array[Vector2i] = []
	for ly in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var local := Vector2i(lx, ly)
			var tile: int = chunk.get_tile(local)
			if tile == TerrainGenerator.TILE_WATER \
					or tile == TerrainGenerator.TILE_WATER_SHALLOW \
					or tile == TerrainGenerator.TILE_WATER_PUDDLE:
				dist[ly * Chunk.SIZE + lx] = 0
				queue.append(local)
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var base_d: int = dist[cell.y * Chunk.SIZE + cell.x]
		if base_d >= 12:
			continue
		for off in OFFSETS:
			var next: Vector2i = cell + off
			if next.x < 0 or next.x >= Chunk.SIZE or next.y < 0 or next.y >= Chunk.SIZE:
				continue
			var idx: int = next.y * Chunk.SIZE + next.x
			if dist[idx] <= base_d + 1:
				continue
			dist[idx] = base_d + 1
			queue.append(next)
	return dist


func _grass_density_for_dist(dist: int) -> float:
	if dist <= 2:
		return 0.82
	if dist <= 6:
		return lerpf(0.54, 0.18, float(dist - 3) / 3.0)
	return 0.08


func _random_grass_cell() -> Vector2i:
	if _grass_cells.is_empty():
		return Pathfinder.UNREACHABLE
	var keys: Array = _grass_cells.keys()
	return keys[randi() % keys.size()] as Vector2i


func _grass_spread_target(source: Vector2i) -> Vector2i:
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var options: Array[Vector2i] = []
	for off in OFFSETS:
		var candidate: Vector2i = source + off
		if _grass_cells.has(candidate):
			continue
		if not _can_grow_grass_on(get_tile_at(candidate)):
			continue
		var water_score: float = _grass_density_for_dist(_distance_to_water(candidate, 8))
		if _near_acid(candidate, 3):
			water_score = maxf(water_score, 0.18)
		if randf() <= maxf(0.08, water_score):
			options.append(candidate)
	if options.is_empty():
		return Pathfinder.UNREACHABLE
	return options[randi() % options.size()]


func _distance_to_water(cell: Vector2i, radius: int) -> int:
	var best: int = 999
	for y in range(cell.y - radius, cell.y + radius + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			var candidate := Vector2i(x, y)
			var d: int = maxi(absi(x - cell.x), absi(y - cell.y))
			if d >= best:
				continue
			var tile: int = get_tile_at(candidate)
			if tile == TerrainGenerator.TILE_WATER \
					or tile == TerrainGenerator.TILE_WATER_SHALLOW \
					or tile == TerrainGenerator.TILE_WATER_PUDDLE:
				best = d
	return best


static func _can_grow_grass_on(tile: int) -> bool:
	return tile == TerrainGenerator.TILE_FLOOR \
		or tile == TerrainGenerator.TILE_DEBRIS \
		or tile == TerrainGenerator.TILE_CONDUIT \
		or tile == TerrainGenerator.TILE_OUTLET \
		or tile == TerrainGenerator.TILE_TELEPORTER


func _recompute_grass_masks_around(grid: Vector2i) -> void:
	const OFFSETS: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]
	for off in OFFSETS:
		var cell: Vector2i = grid + off
		if not _grass_cells.has(cell):
			continue
		var mask: int = _grass_mask_for(cell)
		_grass_cells[cell] = mask
		var ccoord := Chunk.grid_to_chunk(cell)
		if _loaded.has(ccoord):
			var chunk: Chunk = _loaded[ccoord]
			chunk.set_grass_mask(Chunk.grid_to_local(cell), mask)


func _grass_mask_for(cell: Vector2i) -> int:
	var mask: int = 0
	if _can_grow_grass_on(get_tile_at(cell + Vector2i(0, -1))):
		mask |= TileVisuals.MASK_NORTH
	if _can_grow_grass_on(get_tile_at(cell + Vector2i(1, 0))):
		mask |= TileVisuals.MASK_EAST
	if _can_grow_grass_on(get_tile_at(cell + Vector2i(0, 1))):
		mask |= TileVisuals.MASK_SOUTH
	if _can_grow_grass_on(get_tile_at(cell + Vector2i(-1, 0))):
		mask |= TileVisuals.MASK_WEST
	if mask == 0:
		mask = 15
	if _near_acid(cell, 3):
		mask |= TileVisuals.GRASS_ACID_FLAG
	return mask


func _near_acid(cell: Vector2i, radius: int) -> bool:
	for y in range(cell.y - radius, cell.y + radius + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			var tile: int = get_tile_at(Vector2i(x, y))
			if tile == TerrainGenerator.TILE_ACID \
					or tile == TerrainGenerator.TILE_ACID_SHALLOW \
					or tile == TerrainGenerator.TILE_ACID_PUDDLE:
				return true
	return false


func _random_rust_cell() -> Vector2i:
	if _rust_cells.is_empty():
		return Pathfinder.UNREACHABLE
	var keys: Array = _rust_cells.keys()
	return keys[randi() % keys.size()] as Vector2i


func _rust_spread_target(source: Vector2i) -> Vector2i:
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var options: Array[Vector2i] = []
	for off in OFFSETS:
		var candidate: Vector2i = source + off
		var tile: int = get_tile_at(candidate)
		if tile == TerrainGenerator.TILE_FLOOR \
				or tile == TerrainGenerator.TILE_DEBRIS \
				or tile == TerrainGenerator.TILE_CONDUIT:
			options.append(candidate)
	if options.is_empty():
		return Pathfinder.UNREACHABLE
	return options[randi() % options.size()]


func _maybe_add_scrape_job(grid: Vector2i) -> void:
	if _job_board == null:
		return
	if _fog != null and not _fog.is_cell_visible(grid):
		return
	if _job_board.scrape_rust_count() >= max_scrape_jobs:
		return
	_job_board.add_scrape_rust_job(grid)


func random_nearby_grass(from: Vector2i, radius: int, pathfinder: Pathfinder = null, fog: FogOfWar = null) -> Vector2i:
	if _grass_cells.is_empty():
		return Pathfinder.UNREACHABLE
	var keys: Array = _grass_cells.keys()
	var best: Vector2i = Pathfinder.UNREACHABLE
	var best_d: int = 0x7fffffff
	for _attempt in range(mini(128, keys.size())):
		var candidate: Vector2i = keys[randi() % keys.size()] as Vector2i
		var d: int = maxi(absi(candidate.x - from.x), absi(candidate.y - from.y))
		if d > radius or d >= best_d:
			continue
		if fog != null and not fog.is_explored(candidate):
			continue
		if not has_grass(candidate):
			continue
		if pathfinder != null and not pathfinder.has_path(from, candidate):
			continue
		best = candidate
		best_d = d
	return best


func _on_visibility_changed(bounds: Rect2i) -> void:
	# Rust cleanup is intentional idle behavior now, not automatic colony work.
	pass


func _add_teleporter(grid: Vector2i) -> void:
	if _teleporter_lookup.has(grid):
		return
	_teleporter_lookup[grid] = true
	_teleporters.append(grid)


func _remove_teleporter(grid: Vector2i) -> void:
	if not _teleporter_lookup.has(grid):
		return
	_teleporter_lookup.erase(grid)
	_teleporters.erase(grid)


static func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	var px: int = Chunk.SIZE * Chunk.TILE_PIXELS
	return Vector2i(
		int(floor(world_pos.x / px)),
		int(floor(world_pos.y / px)),
	)
