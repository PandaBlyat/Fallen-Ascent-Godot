class_name Chunk
extends Node2D
##
## A SIZE×SIZE block of terrain. Presentation goes through a TileMapLayer
## child pointed at resources/tiles/placeholder_tiles.tres. `_tiles` stays
## the canonical source of truth — Pathfinder / ChunkManager.is_walkable
## read from it via get_tile().
##

const SIZE: int = 32                ## tiles per chunk side
const TILE_PIXELS: int = 16         ## visual size of one tile
const _TILE_COUNT: int = SIZE * SIZE
const _ATLAS_SOURCE_ID: int = 0
const _TILESET: TileSet = preload("res://resources/tiles/placeholder_tiles.tres")

var chunk_coord: Vector2i = Vector2i.ZERO
var _tiles: PackedInt32Array
var _layer: TileMapLayer


func _init() -> void:
	_tiles = PackedInt32Array()
	_tiles.resize(_TILE_COUNT)
	_layer = TileMapLayer.new()
	_layer.tile_set = _TILESET
	add_child(_layer)


func populate(coord: Vector2i, noise: FastNoiseLite) -> void:
	chunk_coord = coord
	position = Vector2(coord * SIZE * TILE_PIXELS)
	TerrainGenerator.populate(noise, coord, SIZE, _tiles)
	_repaint_all()


func get_tile(local: Vector2i) -> int:
	return _tiles[local.y * SIZE + local.x]


func set_tile(local: Vector2i, t: int) -> void:
	_tiles[local.y * SIZE + local.x] = t
	_layer.set_cell(local, _ATLAS_SOURCE_ID, Vector2i(t, 0))


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
			var t: int = _tiles[ly * SIZE + lx]
			_layer.set_cell(Vector2i(lx, ly), _ATLAS_SOURCE_ID, Vector2i(t, 0))
