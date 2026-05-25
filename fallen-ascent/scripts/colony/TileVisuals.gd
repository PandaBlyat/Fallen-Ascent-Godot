class_name TileVisuals
extends RefCounted

const SOURCE_FLOOR: int = 0
const SOURCE_WATER: int = 1
const SOURCE_WALL: int = 2
const SOURCE_RICH_WALL: int = 3
const SOURCE_SERVICE_CORE: int = 4
const SOURCE_RUST: int = 5
const SOURCE_GRASS: int = 6

const NO_SOURCE: int = -1
const FLOOR_ROW: int = 0
const DEBRIS_ROW: int = 1
const CONDUIT_ROW: int = 2
const OUTLET_ROW: int = 3
const TELEPORTER_ROW: int = 4
const VOID_ROW: int = 5
const MASK_NONE: int = 0
const MASK_NORTH: int = 1
const MASK_EAST: int = 2
const MASK_SOUTH: int = 4
const MASK_WEST: int = 8
const RUST_VARIANTS: int = 16
const GRASS_VARIANTS: int = 10
const GRASS_ACID_FLAG: int = 16


static func base_source(tile: int) -> int:
	if is_water_family(tile) or is_acid_family(tile):
		return SOURCE_WATER
	if is_floor_family(tile) or tile == TerrainGenerator.TILE_VOID:
		return SOURCE_FLOOR
	return NO_SOURCE


static func base_atlas_coords(tile: int, mask: int) -> Vector2i:
	match tile:
		TerrainGenerator.TILE_DEBRIS:
			return Vector2i(mask, DEBRIS_ROW)
		TerrainGenerator.TILE_CONDUIT:
			return Vector2i(mask, CONDUIT_ROW)
		TerrainGenerator.TILE_OUTLET:
			return Vector2i(mask, OUTLET_ROW)
		TerrainGenerator.TILE_TELEPORTER:
			return Vector2i(mask, TELEPORTER_ROW)
		TerrainGenerator.TILE_VOID:
			return Vector2i(MASK_NONE, VOID_ROW)
		TerrainGenerator.TILE_WATER:
			return Vector2i(mask, 0)
		TerrainGenerator.TILE_WATER_SHALLOW:
			return Vector2i(mask, 1)
		TerrainGenerator.TILE_WATER_PUDDLE:
			return Vector2i(mask, 2)
		TerrainGenerator.TILE_ACID:
			return Vector2i(mask, 3)
		TerrainGenerator.TILE_ACID_SHALLOW:
			return Vector2i(mask, 4)
		TerrainGenerator.TILE_ACID_PUDDLE:
			return Vector2i(mask, 5)
		_:
			return Vector2i(mask, FLOOR_ROW)


static func wall_source(tile: int) -> int:
	match tile:
		TerrainGenerator.TILE_WALL:
			return SOURCE_WALL
		TerrainGenerator.TILE_RICH_WALL:
			return SOURCE_RICH_WALL
		TerrainGenerator.TILE_SERVICE_CORE:
			return SOURCE_SERVICE_CORE
		_:
			return NO_SOURCE


static func wall_atlas_coords(mask: int) -> Vector2i:
	return Vector2i(mask, 0)


static func rust_atlas_coords(grid: Vector2i) -> Vector2i:
	var mixed: int = absi(hash([grid.x, grid.y, "rust_overlay"]))
	return Vector2i(mixed % RUST_VARIANTS, 0)


static func grass_atlas_coords(mask: int, grid: Vector2i) -> Vector2i:
	var mixed: int = absi(hash([grid.x, grid.y, "grass_overlay"]))
	var roll: int = mixed % 100
	var row: int = 0
	if (mask & GRASS_ACID_FLAG) != 0:
		if roll < 35:
			row = 6
		elif roll < 65:
			row = 7
		elif roll < 90:
			row = 8
		else:
			row = 9
	else:
		if roll < 18:
			row = 0
		elif roll < 45:
			row = 1
		elif roll < 72:
			row = 2
		elif roll < 88:
			row = 3
		elif roll < 97:
			row = 4
		else:
			row = 5
	return Vector2i(mask & 15, row)


static func is_floor_family(tile: int) -> bool:
	return tile == TerrainGenerator.TILE_FLOOR \
		or tile == TerrainGenerator.TILE_DEBRIS \
		or tile == TerrainGenerator.TILE_OUTLET \
		or tile == TerrainGenerator.TILE_CONDUIT \
		or tile == TerrainGenerator.TILE_RUST \
		or tile == TerrainGenerator.TILE_TELEPORTER


static func is_water_family(tile: int) -> bool:
	return tile == TerrainGenerator.TILE_WATER \
		or tile == TerrainGenerator.TILE_WATER_SHALLOW \
		or tile == TerrainGenerator.TILE_WATER_PUDDLE


static func is_acid_family(tile: int) -> bool:
	return tile == TerrainGenerator.TILE_ACID \
		or tile == TerrainGenerator.TILE_ACID_SHALLOW \
		or tile == TerrainGenerator.TILE_ACID_PUDDLE


static func is_water_or_acid_family(tile: int) -> bool:
	return is_water_family(tile) or is_acid_family(tile)


static func connects(tile: int, neighbor: int) -> bool:
	# Each water/acid depth connects only to itself so the 4-bit mask
	# geometry stays meaningful per depth band.
	if is_water_family(tile) or is_acid_family(tile):
		return neighbor == tile
	if is_floor_family(tile):
		return is_floor_family(neighbor)
	return tile == neighbor and wall_source(tile) != NO_SOURCE
