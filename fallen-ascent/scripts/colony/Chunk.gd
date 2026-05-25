class_name Chunk
extends Node2D
##
## A SIZE×SIZE block of terrain. Presentation goes through a TileMapLayer
## child pointed at resources/tiles/placeholder_tiles.tres. `_tiles` stays
## the canonical source of truth — Pathfinder / ChunkManager.is_walkable
## read from it via get_tile().
##

const SIZE: int = 32                ## tiles per chunk side
const TILE_PIXELS: int = 32         ## visual size of one tile
const TERRAIN_Z_BASE: int = -30
const TERRAIN_Z_WALL: int = -29
const TERRAIN_Z_GRASS: int = -28
const TERRAIN_Z_OVERLAY: int = -27
const _TILE_COUNT: int = SIZE * SIZE
const _TILESET: TileSet = preload("res://resources/tiles/placeholder_tiles.tres")
const _WATER_SHADER: Shader = preload("res://resources/shaders/water_tile.gdshader")
const _GRASS_SHADER: Shader = preload("res://resources/shaders/grass_overlay.gdshader")
const _FLOOR_VARIATION_SHADER: Shader = preload("res://resources/shaders/floor_variation.gdshader")
## Single material shared across every chunk's base layer — the shader keys
## off world-space tile coords, so one material handles all of them.
static var _floor_variation_material: ShaderMaterial = null
const _REPAINT_OFFSETS: Array[Vector2i] = [
	Vector2i.ZERO,
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

var chunk_coord: Vector2i = Vector2i.ZERO
var _tiles: PackedInt32Array
var _grass_masks: PackedInt32Array
var _base_layer: TileMapLayer
var _water_layer: TileMapLayer
var _grass_layer: TileMapLayer
var _wall_layer: TileMapLayer
var _overlay_layer: TileMapLayer
var _grass_material: ShaderMaterial
var _has_grass: bool = false
var _walker_positions: PackedVector2Array = PackedVector2Array()
var _nearby_workers: Array = []
## Throttle the grass-walker shader update — 10Hz is more than smooth enough
## for the visual wake effect and cuts EntityGrid queries by 6x.
const _WALKER_UPDATE_INTERVAL: float = 0.1
const _WALKER_UPDATE_INTERVAL_MS: int = 100
var _walker_update_accum: float = 0.0
var _last_walker_update_ms: int = 0
var _last_walker_count: int = -1


func _init() -> void:
	_tiles = PackedInt32Array()
	_tiles.resize(_TILE_COUNT)
	_grass_masks = PackedInt32Array()
	_grass_masks.resize(_TILE_COUNT)
	_walker_positions.resize(8)
	_base_layer = _make_layer("BaseTerrain", TERRAIN_Z_BASE)
	_base_layer.material = _floor_variation_material_shared()
	_water_layer = _make_layer("WaterTerrain", TERRAIN_Z_BASE + 1)
	_water_layer.material = _water_material()
	_grass_layer = _make_layer("GrassOverlay", TERRAIN_Z_GRASS)
	_grass_material = _grass_material_new()
	_grass_layer.material = _grass_material
	_wall_layer = _make_layer("RaisedTerrain", TERRAIN_Z_WALL)
	_overlay_layer = _make_layer("Overlays", TERRAIN_Z_OVERLAY)
	add_child(_base_layer)
	add_child(_water_layer)
	add_child(_grass_layer)
	add_child(_wall_layer)
	add_child(_overlay_layer)


func populate(coord: Vector2i, noise: FastNoiseLite) -> void:
	chunk_coord = coord
	position = Vector2(coord * SIZE * TILE_PIXELS)
	TerrainGenerator.populate(noise, coord, SIZE, _tiles)
	_repaint_all()


func get_tile(local: Vector2i) -> int:
	return _tiles[local.y * SIZE + local.x]


func set_tile(local: Vector2i, t: int) -> void:
	_tiles[local.y * SIZE + local.x] = t
	_repaint_plus_neighbors(local)


func set_grass_mask(local: Vector2i, mask: int) -> void:
	_grass_masks[local.y * SIZE + local.x] = maxi(0, mask)
	_repaint_cell(local)
	_has_grass = _grass_masks_has_any()


func grass_mask(local: Vector2i) -> int:
	return _grass_masks[local.y * SIZE + local.x]


## Vector2i.MAX-style sentinel returned by grid_to_chunk when called with
## negative coords would be inconvenient; these helpers use Euclidean math so
## negative grid indices map correctly.
static func grid_to_chunk(grid: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(grid.x) / SIZE)),
		int(floor(float(grid.y) / SIZE)),
	)


static func grid_to_local(grid: Vector2i) -> Vector2i:
	return Vector2i(
		posmod(grid.x, SIZE),
		posmod(grid.y, SIZE),
	)


static func grid_to_pixel_center(grid: Vector2i) -> Vector2:
	return Vector2(
		grid.x * TILE_PIXELS + TILE_PIXELS * 0.5,
		grid.y * TILE_PIXELS + TILE_PIXELS * 0.5,
	)


func _repaint_all() -> void:
	for ly in SIZE:
		for lx in SIZE:
			_repaint_cell(Vector2i(lx, ly))


func _make_layer(layer_name: String, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = _TILESET
	layer.z_index = z
	return layer


func _water_material() -> ShaderMaterial:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = _WATER_SHADER
	return shader_material


static func _floor_variation_material_shared() -> ShaderMaterial:
	if _floor_variation_material == null:
		_floor_variation_material = ShaderMaterial.new()
		_floor_variation_material.shader = _FLOOR_VARIATION_SHADER
		_floor_variation_material.set_shader_parameter("tile_size", float(TILE_PIXELS))
	return _floor_variation_material


func _grass_material_new() -> ShaderMaterial:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = _GRASS_SHADER
	shader_material.set_shader_parameter("wind_speed", 1.15)
	shader_material.set_shader_parameter("wind_amplitude", 0.9)
	shader_material.set_shader_parameter("walker_count", 0)
	return shader_material


func _repaint_plus_neighbors(local: Vector2i) -> void:
	for offset in _REPAINT_OFFSETS:
		var cell: Vector2i = local + offset
		if _is_local_cell(cell):
			_repaint_cell(cell)


func _repaint_cell(local: Vector2i) -> void:
	var tile: int = get_tile(local)
	var mask: int = _connection_mask(local, tile)
	var base_source: int = TileVisuals.base_source(tile)
	if TileVisuals.is_water_or_acid_family(tile):
		_base_layer.erase_cell(local)
		_water_layer.set_cell(local, TileVisuals.SOURCE_WATER, TileVisuals.base_atlas_coords(tile, mask))
	elif base_source == TileVisuals.NO_SOURCE:
		_base_layer.erase_cell(local)
		_water_layer.erase_cell(local)
	else:
		_base_layer.set_cell(local, base_source, TileVisuals.base_atlas_coords(tile, mask))
		_water_layer.erase_cell(local)

	var wall_source: int = TileVisuals.wall_source(tile)
	if wall_source == TileVisuals.NO_SOURCE:
		_wall_layer.erase_cell(local)
	else:
		_wall_layer.set_cell(local, wall_source, TileVisuals.wall_atlas_coords(mask))

	if tile == TerrainGenerator.TILE_RUST:
		_overlay_layer.set_cell(local, TileVisuals.SOURCE_RUST, TileVisuals.rust_atlas_coords(_global_cell(local)))
	else:
		_overlay_layer.erase_cell(local)

	var overlay_mask: int = grass_mask(local)
	if overlay_mask > 0 and TileVisuals.is_floor_family(tile):
		_grass_layer.set_cell(local, TileVisuals.SOURCE_GRASS, TileVisuals.grass_atlas_coords(overlay_mask, _global_cell(local)))
	else:
		_grass_layer.erase_cell(local)


func _connection_mask(local: Vector2i, tile: int) -> int:
	if tile == TerrainGenerator.TILE_VOID:
		return TileVisuals.MASK_NONE
	var mask: int = 0
	if _connects_at(local, tile, Vector2i(0, -1)):
		mask |= TileVisuals.MASK_NORTH
	if _connects_at(local, tile, Vector2i(1, 0)):
		mask |= TileVisuals.MASK_EAST
	if _connects_at(local, tile, Vector2i(0, 1)):
		mask |= TileVisuals.MASK_SOUTH
	if _connects_at(local, tile, Vector2i(-1, 0)):
		mask |= TileVisuals.MASK_WEST
	return mask


func _connects_at(local: Vector2i, tile: int, offset: Vector2i) -> bool:
	var neighbor: Vector2i = local + offset
	if not _is_local_cell(neighbor):
		return false
	return TileVisuals.connects(tile, get_tile(neighbor))


func _is_local_cell(local: Vector2i) -> bool:
	return local.x >= 0 and local.x < SIZE and local.y >= 0 and local.y < SIZE


func _global_cell(local: Vector2i) -> Vector2i:
	return chunk_coord * SIZE + local


func _process(_delta: float) -> void:
	if not _has_grass or _grass_material == null:
		return
	# Off-screen chunks: don't query workers or update shader params at all.
	# (TileMapLayer culls draw calls but _process still runs on the node.)
	if not _grass_layer.is_visible_in_tree():
		return
	# Wall-clock throttle so high `Engine.time_scale` doesn't drive grass
	# walker queries 3-4x per real second per chunk.
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_walker_update_ms < _WALKER_UPDATE_INTERVAL_MS:
		return
	_last_walker_update_ms = now_ms
	var rect := Rect2(global_position, Vector2(SIZE * TILE_PIXELS, SIZE * TILE_PIXELS)).grow(24.0)
	var center_grid: Vector2i = chunk_coord * SIZE + Vector2i(SIZE / 2, SIZE / 2)
	EntityGrid.query_into(EntityGrid.FACTION_COLONY, center_grid, SIZE / 2 + 2, _nearby_workers)
	var count: int = 0
	for candidate in _nearby_workers:
		var worker := candidate as Node2D
		if worker == null or not is_instance_valid(worker):
			continue
		if not rect.has_point(worker.global_position):
			continue
		_walker_positions[count] = worker.global_position
		count += 1
		if count >= 8:
			break
	# Skip the shader parameter sync when there's nothing to push and last
	# tick was already zero — the most common case in unpopulated areas.
	if count == 0 and _last_walker_count == 0:
		return
	_grass_material.set_shader_parameter("walker_positions", _walker_positions)
	_grass_material.set_shader_parameter("walker_count", count)
	_last_walker_count = count


func _grass_masks_has_any() -> bool:
	for value in _grass_masks:
		if value > 0:
			return true
	return false
