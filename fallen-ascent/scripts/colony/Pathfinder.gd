class_name Pathfinder
extends Node
##
## Wraps AStarGrid2D over the currently-loaded chunk region. Rebuilds the
## grid when chunks load/unload; single-cell updates on tile_changed.
##

const UNREACHABLE: Vector2i = Vector2i(2147483647, 2147483647)

@export var chunk_manager_path: NodePath

var _chunk_manager: ChunkManager
var _astar: AStarGrid2D
var _region: Rect2i = Rect2i()
var _rebuild_pending: bool = false
var _bulk_loading: bool = false
## Coords (chunk-space) whose cells need solidness re-evaluated next rebuild.
var _dirty_chunks: Dictionary = {}
## Persistent solidness map. AStarGrid2D.update() wipes solidness whenever
## the region changes; replaying from this dict keeps a one-chunk pan from
## touching the full loaded region. Bounded by total cells ever loaded.
var _solid_cache: Dictionary = {}


func _ready() -> void:
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_astar = AStarGrid2D.new()
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	EventBus.chunk_loaded.connect(_on_chunk_loaded)
	EventBus.chunk_unloaded.connect(_on_chunk_unloaded)
	EventBus.tile_changed.connect(_on_tile_changed)


func _on_chunk_loaded(coord: Vector2i) -> void:
	_dirty_chunks[coord] = true
	if _bulk_loading:
		return
	_schedule_rebuild()


func _on_chunk_unloaded(coord: Vector2i) -> void:
	# Cells fall back to TILE_VOID once unloaded; rebuild will flag them
	# solid in the cache and on the grid. The region itself doesn't shrink.
	_dirty_chunks[coord] = true
	if _bulk_loading:
		return
	_schedule_rebuild()


func set_bulk_loading(active: bool) -> void:
	if _bulk_loading == active:
		return
	_bulk_loading = active
	if not _bulk_loading and not _dirty_chunks.is_empty():
		_schedule_rebuild()


func flush_rebuild() -> void:
	if _dirty_chunks.is_empty() and not _rebuild_pending:
		return
	_rebuild()


func _schedule_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_rebuild")


func _on_tile_changed(grid: Vector2i, _new_tile: int) -> void:
	if not _region.has_point(grid):
		return
	var solid: bool = not _chunk_manager.is_walkable(grid)
	_solid_cache[grid] = solid
	_astar.set_point_solid(grid, solid)


func _rebuild() -> void:
	_rebuild_pending = false
	var bounds: Rect2i = _chunk_manager.loaded_chunk_bounds()
	if bounds.size == Vector2i.ZERO:
		_dirty_chunks.clear()
		return
	var loaded_region := Rect2i(
		bounds.position * Chunk.SIZE,
		bounds.size * Chunk.SIZE,
	)
	# Region grows monotonically — never shrinks during a session. Camera
	# panning therefore only triggers astar.update() the first time it
	# reaches new ground; thereafter it stays grew=false and we only refill
	# newly-loaded chunks.
	var grew: bool = false
	if _region.size == Vector2i.ZERO:
		_region = loaded_region
		grew = true
	elif not _region.encloses(loaded_region):
		_region = _region.merge(loaded_region)
		grew = true
	if grew:
		_astar.region = _region
		_astar.cell_size = Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS)
		_astar.update()
		# update() wiped solidness — replay every cell we've ever computed.
		# Bounded by total cells loaded over the session, not the region area.
		for g in _solid_cache.keys():
			_astar.set_point_solid(g, bool(_solid_cache[g]))
	# Refill cells in newly-loaded or just-unloaded chunks. Whether or not
	# the region grew, this also primes/refreshes the solid_cache.
	for coord in _dirty_chunks.keys():
		var c: Vector2i = coord as Vector2i
		var base := c * Chunk.SIZE
		for ly in Chunk.SIZE:
			for lx in Chunk.SIZE:
				var g := base + Vector2i(lx, ly)
				if not _region.has_point(g):
					continue
				var solid: bool = not _chunk_manager.is_walkable(g)
				_solid_cache[g] = solid
				_astar.set_point_solid(g, solid)
	_dirty_chunks.clear()


## Returns pixel-center waypoints from `from` (exclusive) to `to` (inclusive).
## Empty if unreachable or either endpoint is outside the loaded region.
func find_path(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	if not _region.has_point(from) or not _region.has_point(to):
		return PackedVector2Array()
	if _astar.is_point_solid(to):
		return PackedVector2Array()
	var grid_path: Array[Vector2i] = _astar.get_id_path(from, to)
	if grid_path.is_empty():
		return PackedVector2Array()
	var pts := PackedVector2Array()
	pts.resize(grid_path.size() - 1)
	for i in range(1, grid_path.size()):
		pts[i - 1] = Chunk.grid_to_pixel_center(grid_path[i])
	return pts


## Returns an adjacent walkable tile to `grid`, preferring 4-neighbors then
## diagonals. UNREACHABLE if none of the 8 neighbors are walkable.
func walkable_neighbor_of(grid: Vector2i) -> Vector2i:
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	for off in OFFSETS:
		var n: Vector2i = grid + off
		if _chunk_manager.is_walkable(n):
			return n
	return UNREACHABLE


func has_path(from: Vector2i, to: Vector2i) -> bool:
	if not _region.has_point(from) or not _region.has_point(to):
		return false
	if _astar.is_point_solid(to):
		return false
	return not _astar.get_id_path(from, to).is_empty()
