class_name TerrainGenerator
extends RefCounted
##
## Per-chunk terrain selection. Pure — same (site_seed, chunk_coord, tile)
## always yields the same tile id.
##
## Returns a small enum so Chunk can render with `draw_rect` until a real
## TileSet exists. Tile ids: 0=floor, 1=wall, 2=debris, 3=void.

const TILE_FLOOR: int = 0
const TILE_WALL: int = 1
const TILE_DEBRIS: int = 2
const TILE_VOID: int = 3


static func make_noise(site_seed: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = site_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.05
	return n


## Fills `out` (size = chunk_size * chunk_size) with tile ids for one chunk.
## `out` is passed in to avoid per-chunk allocation churn.
static func populate(
	noise: FastNoiseLite,
	chunk_coord: Vector2i,
	chunk_size: int,
	out: PackedInt32Array,
) -> void:
	var base_x: int = chunk_coord.x * chunk_size
	var base_y: int = chunk_coord.y * chunk_size
	for ly in chunk_size:
		for lx in chunk_size:
			var wx: int = base_x + lx
			var wy: int = base_y + ly
			var s: float = noise.get_noise_2d(wx, wy)
			out[ly * chunk_size + lx] = _tile_from_sample(s)


static func _tile_from_sample(s: float) -> int:
	if s < -0.50: return TILE_VOID
	if s < -0.10: return TILE_DEBRIS
	if s <  0.55: return TILE_FLOOR
	return TILE_WALL


static func tile_color(t: int) -> Color:
	match t:
		TILE_FLOOR:  return Color(0.22, 0.24, 0.28)
		TILE_WALL:   return Color(0.55, 0.55, 0.58)
		TILE_DEBRIS: return Color(0.35, 0.30, 0.25)
		TILE_VOID:   return Color(0.06, 0.06, 0.09)
	return Color.MAGENTA
