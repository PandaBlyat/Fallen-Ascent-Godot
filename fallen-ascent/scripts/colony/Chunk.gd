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
const TERRAIN_Z_OVERLAY: int = -28
const _TILE_COUNT: int = SIZE * SIZE
const _TILESET: TileSet = preload("res://resources/tiles/placeholder_tiles.tres")
const _WATER_SHADER: Shader = preload("res://resources/shaders/water_tile.gdshader")
const _REPAINT_OFFSETS: Array[Vector2i] = [
	Vector2i.ZERO,
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

var chunk_coord: Vector2i = Vector2i.ZERO
var _tiles: PackedInt32Array
var _base_layer: TileMapLayer
var _water_layer: TileMapLayer
var _wall_layer: TileMapLayer
var _overlay_layer: TileMapLayer


func _init() -> void:
	_tiles = PackedInt32Array()
	_tiles.resize(_TILE_COUNT)
	_base_layer = _make_layer("BaseTerrain", TERRAIN_Z_BASE)
	_water_layer = _make_layer("WaterTerrain", TERRAIN_Z_BASE + 1)
	_water_layer.material = _water_material()
	_wall_layer = _make_layer("RaisedTerrain", TERRAIN_Z_WALL)
	_overlay_layer = _make_layer("Overlays", TERRAIN_Z_OVERLAY)
	add_child(_base_layer)
	add_child(_water_layer)
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


func _repaint_plus_neighbors(local: Vector2i) -> void:
	for offset in _REPAINT_OFFSETS:
		var cell: Vector2i = local + offset
		if _is_local_cell(cell):
			_repaint_cell(cell)


func _repaint_cell(local: Vector2i) -> void:
	var tile: int = get_tile(local)
	var mask: int = _connection_mask(local, tile)
	var base_source: int = TileVisuals.base_source(tile)
	if tile == TerrainGenerator.TILE_WATER:
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
