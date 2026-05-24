class_name ChunkManager
extends Node2D
##
## Streams chunks around the camera. Listens to EventBus.camera_moved so it
## only does work when the camera actually moves, not every frame.
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

var _site_seed: int = 0
var _noise: FastNoiseLite
var _loaded: Dictionary = {}                      ## Vector2i -> Chunk
## Session-lifetime diff cache: chunk_coord -> { local_coord -> tile_id }.
## Lets mined cells survive unload/reload until a real save system lands.
var _diffs: Dictionary = {}
var _last_cam_chunk: Vector2i = Vector2i(0x7fffffff, 0x7fffffff)
var _load_queue: Array[Vector2i] = []
var _load_pending: Dictionary = {}                ## Vector2i -> true (in _load_queue)
var _initial_loaded: bool = false                 ## first batch loads sync


func setup(site_seed: int) -> void:
	_site_seed = site_seed
	_noise = TerrainGenerator.make_noise(site_seed)


func _ready() -> void:
	EventBus.camera_moved.connect(_on_camera_moved)


func _on_camera_moved(world_pos: Vector2, _zoom: Vector2) -> void:
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
				if _loaded.has(coord) or _load_pending.has(coord):
					continue
				_load_queue.append(coord)
				_load_pending[coord] = true


func _process(_delta: float) -> void:
	_drain_queue(max_loads_per_frame)


func _drain_queue(budget: int) -> void:
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
		EventBus.chunk_loaded.emit(coord)
		budget -= 1


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
		EventBus.chunk_unloaded.emit(c)
		chunk.queue_free()


func loaded_count() -> int:
	return _loaded.size()


## Returns the bounding rect of loaded chunks in chunk coords (inclusive lo,
## exclusive hi). Used by pathfinder to size its AStarGrid2D region.
func loaded_chunk_bounds() -> Rect2i:
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
	var ccoord := Chunk.grid_to_chunk(grid)
	if not _loaded.has(ccoord):
		return TerrainGenerator.TILE_VOID
	var chunk: Chunk = _loaded[ccoord]
	return chunk.get_tile(Chunk.grid_to_local(grid))


## Writes a tile id at a global grid coord and emits tile_changed. No-op if
## the chunk isn't loaded (mining unloaded terrain is not supported).
func set_tile_at(grid: Vector2i, t: int) -> void:
	var ccoord := Chunk.grid_to_chunk(grid)
	if not _loaded.has(ccoord):
		return
	var chunk: Chunk = _loaded[ccoord]
	var local: Vector2i = Chunk.grid_to_local(grid)
	chunk.set_tile(local, t)
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
	return t == TerrainGenerator.TILE_FLOOR or t == TerrainGenerator.TILE_DEBRIS


static func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	var px: int = Chunk.SIZE * Chunk.TILE_PIXELS
	return Vector2i(
		int(floor(world_pos.x / px)),
		int(floor(world_pos.y / px)),
	)
