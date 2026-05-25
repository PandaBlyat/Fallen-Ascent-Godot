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
@export var max_scrape_jobs: int = 64

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
var _teleporters: Array[Vector2i] = []
var _teleporter_lookup: Dictionary = {}             ## Vector2i -> true
var _rust_timer: float = 0.0
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
		or t == TerrainGenerator.TILE_WATER_PUDDLE
	if not terrain_walkable:
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
	return get_tile_at(grid) == TerrainGenerator.TILE_TELEPORTER


func random_linked_teleporter(from: Vector2i) -> Vector2i:
	if _teleporters.size() < 2:
		return Pathfinder.UNREACHABLE
	for _attempt in range(12):
		var candidate: Vector2i = _teleporters[randi() % _teleporters.size()]
		if candidate != from:
			return candidate
	for candidate in _teleporters:
		if candidate != from:
			return candidate
	return Pathfinder.UNREACHABLE


func teleporter_cells() -> Array[Vector2i]:
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
	var seed: Vector2i = _nearest_walkable_for_outlet(origin)
	if seed == Pathfinder.UNREACHABLE:
		return Pathfinder.UNREACHABLE
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var queue: Array[Vector2i] = [seed]
	var seen: Dictionary = {seed: true}
	var best_floor: Vector2i = Pathfinder.UNREACHABLE
	var best_d: int = 0x7fffffff
	var head: int = 0
	while head < queue.size() and seen.size() <= 512:
		var cell: Vector2i = queue[head]
		head += 1
		var tile: int = get_tile_at(cell)
		if tile == TerrainGenerator.TILE_OUTLET:
			return cell
		if _can_force_outlet_on(tile):
			var d: int = maxi(absi(cell.x - seed.x), absi(cell.y - seed.y))
			if d < best_d:
				best_floor = cell
				best_d = d
		for off in OFFSETS:
			var next: Vector2i = cell + off
			if seen.has(next) or not is_grid_in_map(next):
				continue
			var next_tile: int = get_tile_at(next)
			if not _can_force_outlet_on(next_tile) and next_tile != TerrainGenerator.TILE_OUTLET:
				continue
			seen[next] = true
			queue.append(next)
	if best_floor != Pathfinder.UNREACHABLE:
		set_tile_at(best_floor, TerrainGenerator.TILE_OUTLET)
	return best_floor


func _nearest_walkable_for_outlet(origin: Vector2i) -> Vector2i:
	if is_walkable(origin):
		return origin
	for r in range(1, 32):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var cell := origin + Vector2i(dx, dy)
				if is_walkable(cell):
					return cell
	return Pathfinder.UNREACHABLE


static func _can_force_outlet_on(tile: int) -> bool:
	return tile == TerrainGenerator.TILE_FLOOR \
		or tile == TerrainGenerator.TILE_DEBRIS \
		or tile == TerrainGenerator.TILE_CONDUIT \
		or tile == TerrainGenerator.TILE_RUST


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
