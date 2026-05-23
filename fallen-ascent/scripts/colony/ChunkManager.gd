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

var _site_seed: int = 0
var _noise: FastNoiseLite
var _loaded: Dictionary = {}                      ## Vector2i -> Chunk


func setup(site_seed: int) -> void:
	_site_seed = site_seed
	_noise = TerrainGenerator.make_noise(site_seed)


func _ready() -> void:
	EventBus.camera_moved.connect(_on_camera_moved)


func _on_camera_moved(world_pos: Vector2, _zoom: Vector2) -> void:
	var cam_chunk: Vector2i = _world_to_chunk(world_pos)
	_load_around(cam_chunk)
	_unload_outside(cam_chunk)


func _load_around(center: Vector2i) -> void:
	for dy in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			var coord := Vector2i(center.x + dx, center.y + dy)
			if _loaded.has(coord):
				continue
			var chunk: Chunk = Chunk.new()
			add_child(chunk)
			chunk.populate(coord, _noise)
			_loaded[coord] = chunk
			EventBus.chunk_loaded.emit(coord)


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
	chunk.set_tile(Chunk.grid_to_local(grid), t)
	EventBus.tile_changed.emit(grid, t)


func is_walkable(grid: Vector2i) -> bool:
	var t: int = get_tile_at(grid)
	return t == TerrainGenerator.TILE_FLOOR or t == TerrainGenerator.TILE_DEBRIS


static func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	var px: int = Chunk.SIZE * Chunk.TILE_PIXELS
	return Vector2i(
		int(floor(world_pos.x / px)),
		int(floor(world_pos.y / px)),
	)
