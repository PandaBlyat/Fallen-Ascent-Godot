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
