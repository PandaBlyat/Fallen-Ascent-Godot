class_name Pathfinder
extends Node
##
## Wraps AStarGrid2D over the currently-loaded chunk region. Rebuilds the
## grid when chunks load/unload; single-cell updates on tile_changed.
##

const UNREACHABLE: Vector2i = Vector2i(2147483647, 2147483647)

## Multiplier on the original path length above which the "dry" alternative
## is rejected (bots wade through fluid rather than take an absurd detour).
## Acid is much higher than water because wading through it costs hp; we'd
## rather a worker walk a long way around than take a few damaging steps.
const WATER_AVOID_FACTOR: float = 1.5
const ACID_AVOID_FACTOR: float = 12.0

@export var chunk_manager_path: NodePath

var _chunk_manager: ChunkManager
## Default grid for normal pathing. Teleporters are marked solid here so
## jobs never route through them — a worker stepping on a teleporter mid-job
## would get warped to a random destination and break their plan. Players /
## explicit teleporter-charge logic uses _astar_with_teleport instead.
var _astar: AStarGrid2D
## Same as `_astar` but with teleporters walkable. Used by callers that
## intentionally want to reach a teleporter cell (e.g. seek-charge fallback).
var _astar_with_teleport: AStarGrid2D
## Parallel grid where water and acid cells are marked solid (and teleporters
## too). Used as a "would there be a reasonable dry route?" query — see find_path().
var _astar_dry: AStarGrid2D
var _region: Rect2i = Rect2i()
var _rebuild_pending: bool = false
var _bulk_loading: bool = false
## Coords (chunk-space) whose cells need solidness re-evaluated next rebuild.
var _dirty_chunks: Dictionary = {}
## Persistent solidness map. AStarGrid2D.update() wipes solidness whenever
## the region changes; replaying from this dict keeps a one-chunk pan from
## touching the full loaded region. Bounded by total cells ever loaded.
var _solid_cache: Dictionary = {}
## Cells that are water/acid family. Used to fast-check whether a returned
## path crosses fluid (so we only run the second A* when it might matter).
var _fluid_cache: Dictionary = {}
## Cells that are teleporter tiles (any teleporter, blocked or not). Used to
## mark solidness on the default grid without re-querying tile types.
var _teleporter_cache: Dictionary = {}


func _ready() -> void:
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_astar = AStarGrid2D.new()
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar_with_teleport = AStarGrid2D.new()
	_astar_with_teleport.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar_dry = AStarGrid2D.new()
	_astar_dry.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
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


func _on_tile_changed(grid: Vector2i, new_tile: int) -> void:
	if not _region.has_point(grid):
		return
	var solid: bool = not _chunk_manager.is_walkable(grid)
	_solid_cache[grid] = solid
	var teleporter: bool = new_tile == TerrainGenerator.TILE_TELEPORTER
	if teleporter:
		_teleporter_cache[grid] = true
	else:
		_teleporter_cache.erase(grid)
	_astar.set_point_solid(grid, solid or teleporter)
	_astar_with_teleport.set_point_solid(grid, solid)
	var fluid: bool = TileVisuals.is_water_or_acid_family(new_tile)
	if fluid:
		_fluid_cache[grid] = true
	else:
		_fluid_cache.erase(grid)
	_astar_dry.set_point_solid(grid, solid or fluid or teleporter)


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
		_astar_with_teleport.region = _region
		_astar_with_teleport.cell_size = Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS)
		_astar_with_teleport.update()
		_astar_dry.region = _region
		_astar_dry.cell_size = Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS)
		_astar_dry.update()
		# update() wiped solidness — replay every cell we've ever computed.
		# Bounded by total cells loaded over the session, not the region area.
		for g in _solid_cache.keys():
			var s: bool = bool(_solid_cache[g])
			var teleport_here: bool = _teleporter_cache.has(g)
			_astar.set_point_solid(g, s or teleport_here)
			_astar_with_teleport.set_point_solid(g, s)
			_astar_dry.set_point_solid(g, s or _fluid_cache.has(g) or teleport_here)
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
				var tile: int = _chunk_manager.get_tile_at(g)
				var teleporter: bool = tile == TerrainGenerator.TILE_TELEPORTER
				if teleporter:
					_teleporter_cache[g] = true
				else:
					_teleporter_cache.erase(g)
				_astar.set_point_solid(g, solid or teleporter)
				_astar_with_teleport.set_point_solid(g, solid)
				var fluid: bool = TileVisuals.is_water_or_acid_family(tile)
				if fluid:
					_fluid_cache[g] = true
				else:
					_fluid_cache.erase(g)
				_astar_dry.set_point_solid(g, solid or fluid or teleporter)
	_dirty_chunks.clear()


## Returns pixel-center waypoints from `from` (exclusive) to `to` (inclusive).
## Empty if unreachable or either endpoint is outside the loaded region.
## When the natural shortest path crosses water or acid we try a "dry"
## alternative; we accept it if it's not absurdly longer (WATER_AVOID_FACTOR
## / ACID_AVOID_FACTOR) so bots keep responsive movement when a sane detour
## exists but still wade through fluid when there's no real alternative.
## Teleporters are excluded from the default path — workers should never
## stumble through one mid-job and get warped off-task.
func find_path(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	if not _region.has_point(from) or not _region.has_point(to):
		return PackedVector2Array()
	# Allow `from` on a teleporter cell (worker may have just teleported in)
	# by temporarily unsolidifying it for the query.
	var unmark_from: bool = _teleporter_cache.has(from) and _astar.is_point_solid(from)
	if unmark_from:
		_astar.set_point_solid(from, false)
	# A teleporter destination also has to be temporarily walkable so the
	# pathfinder can reach it — needed when player commands a teleporter step.
	var unmark_to: bool = from != to and _teleporter_cache.has(to) and _astar.is_point_solid(to)
	if unmark_to:
		_astar.set_point_solid(to, false)
	var grid_path: Array[Vector2i] = []
	if not _astar.is_point_solid(to):
		grid_path = _astar.get_id_path(from, to)
	if unmark_from:
		_astar.set_point_solid(from, true)
	if unmark_to:
		_astar.set_point_solid(to, true)
	if grid_path.is_empty():
		return PackedVector2Array()
	grid_path = _prefer_dry_path(grid_path, from, to)
	var pts := PackedVector2Array()
	pts.resize(grid_path.size() - 1)
	for i in range(1, grid_path.size()):
		pts[i - 1] = Chunk.grid_to_pixel_center(grid_path[i])
	return pts


## Same as `find_path` but allows the route to step on teleporter tiles.
## Used by callers that intentionally want to walk to / through a teleporter
## (e.g. seek-charge fallback that hops to a random destination hoping to
## land near a known outlet).
func find_path_via_teleporter(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	if not _region.has_point(from) or not _region.has_point(to):
		return PackedVector2Array()
	if _astar_with_teleport.is_point_solid(to):
		return PackedVector2Array()
	var grid_path: Array[Vector2i] = _astar_with_teleport.get_id_path(from, to)
	if grid_path.is_empty():
		return PackedVector2Array()
	var pts := PackedVector2Array()
	pts.resize(grid_path.size() - 1)
	for i in range(1, grid_path.size()):
		pts[i - 1] = Chunk.grid_to_pixel_center(grid_path[i])
	return pts


## If the path crosses any fluid cell and a near-equivalent dry path exists,
## swap to the dry one. Cheap-out paths (worker starts on or ends on a fluid
## cell — e.g. already standing in a puddle) are left alone since the dry
## grid would refuse them as solid endpoints.
func _prefer_dry_path(wet: Array[Vector2i], from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if wet.size() <= 1 or _fluid_cache.is_empty():
		return wet
	var crosses_water: bool = false
	var crosses_acid: bool = false
	for g in wet:
		if not _fluid_cache.has(g):
			continue
		var t: int = _chunk_manager.get_tile_at(g)
		if TileVisuals.is_acid_family(t):
			crosses_acid = true
		else:
			crosses_water = true
	if not crosses_water and not crosses_acid:
		return wet
	# Endpoints must be dry-walkable for the dry-grid query to succeed.
	if _astar_dry.is_point_solid(from) or _astar_dry.is_point_solid(to):
		return wet
	var dry: Array[Vector2i] = _astar_dry.get_id_path(from, to)
	if dry.is_empty():
		return wet
	var factor: float = ACID_AVOID_FACTOR if crosses_acid else WATER_AVOID_FACTOR
	if float(dry.size()) <= float(wet.size()) * factor:
		return dry
	return wet


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
	# Mirror find_path: allow teleporter endpoints by temporarily un-marking.
	var unmark_from: bool = _teleporter_cache.has(from) and _astar.is_point_solid(from)
	if unmark_from:
		_astar.set_point_solid(from, false)
	var unmark_to: bool = from != to and _teleporter_cache.has(to) and _astar.is_point_solid(to)
	if unmark_to:
		_astar.set_point_solid(to, false)
	var ok: bool = not _astar.is_point_solid(to) and not _astar.get_id_path(from, to).is_empty()
	if unmark_from:
		_astar.set_point_solid(from, true)
	if unmark_to:
		_astar.set_point_solid(to, true)
	return ok
