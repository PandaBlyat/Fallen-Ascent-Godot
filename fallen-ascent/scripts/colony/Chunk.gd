class_name Chunk
extends Node2D
##
## A SIZE×SIZE block of terrain. Rendered for now via `_draw()` of flat
## colored rects; swap for a TileMapLayer when real art lands without
## changing the public interface (chunk_coord, populate, SIZE, TILE_PIXELS).
##

const SIZE: int = 32                ## tiles per chunk side
const TILE_PIXELS: int = 16         ## visual size of one tile
const _TILE_COUNT: int = SIZE * SIZE

var chunk_coord: Vector2i = Vector2i.ZERO
var _tiles: PackedInt32Array


func _init() -> void:
	_tiles = PackedInt32Array()
	_tiles.resize(_TILE_COUNT)


func populate(coord: Vector2i, noise: FastNoiseLite) -> void:
	chunk_coord = coord
	position = Vector2(coord * SIZE * TILE_PIXELS)
	TerrainGenerator.populate(noise, coord, SIZE, _tiles)
	queue_redraw()


func get_tile(local: Vector2i) -> int:
	return _tiles[local.y * SIZE + local.x]


func set_tile(local: Vector2i, t: int) -> void:
	_tiles[local.y * SIZE + local.x] = t
	queue_redraw()


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


func _draw() -> void:
	# Single-pass draw of every cell. With TileMapLayer this becomes one
	# set_cells_terrain_connect / set_cell call per tile instead.
	for ly in SIZE:
		for lx in SIZE:
			var t: int = _tiles[ly * SIZE + lx]
			var r := Rect2(
				Vector2(lx * TILE_PIXELS, ly * TILE_PIXELS),
				Vector2(TILE_PIXELS, TILE_PIXELS),
			)
			draw_rect(r, TerrainGenerator.tile_color(t))
