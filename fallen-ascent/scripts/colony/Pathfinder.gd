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


func _ready() -> void:
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_astar = AStarGrid2D.new()
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	EventBus.chunk_loaded.connect(_on_chunks_changed)
	EventBus.chunk_unloaded.connect(_on_chunks_changed)
	EventBus.tile_changed.connect(_on_tile_changed)


func _on_chunks_changed(_coord: Vector2i) -> void:
	# Coalesce: a burst of chunk_loaded events should produce one rebuild,
	# not N. Schedule once per frame.
	if _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_rebuild")


func _on_tile_changed(grid: Vector2i, _new_tile: int) -> void:
	if not _region.has_point(grid):
		return
	_astar.set_point_solid(grid, not _chunk_manager.is_walkable(grid))


func _rebuild() -> void:
	_rebuild_pending = false
	var bounds: Rect2i = _chunk_manager.loaded_chunk_bounds()
	if bounds.size == Vector2i.ZERO:
		return
	_region = Rect2i(
		bounds.position * Chunk.SIZE,
		bounds.size * Chunk.SIZE,
	)
	_astar.region = _region
	_astar.cell_size = Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS)
	_astar.update()
	for gy in range(_region.position.y, _region.position.y + _region.size.y):
		for gx in range(_region.position.x, _region.position.x + _region.size.x):
			var g := Vector2i(gx, gy)
			_astar.set_point_solid(g, not _chunk_manager.is_walkable(g))


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
