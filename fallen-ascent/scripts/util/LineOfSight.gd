extends RefCounted

## Stateless line-of-sight helper. Bresenham trace from 'from' to 'to', blocked
## by sight-opaque terrain (walls / service-core / rich-wall).

static func has_los(chunk_manager: ChunkManager, from: Vector2i, to: Vector2i) -> bool:
	if chunk_manager == null: 
		return false
	if from == to: 
		return true
		
	var x0: int = from.x
	var y0: int = from.y
	var x1: int = to.x
	var y1: int = to.y
	
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	
	var x: int = x0
	var y: int = y0
	
	while true:
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
			
		if x == x1 and y == y1:
			return true
			
		# Construct Vector2i only when we must check physical properties
		if _blocks_sight(chunk_manager, Vector2i(x, y)):
			return false
			
	return true

static func _blocks_sight(chunk_manager: ChunkManager, grid: Vector2i) -> bool:
	var tile: int = chunk_manager.get_tile_at(grid)
	return tile == TerrainGenerator.TILE_WALL \
		or tile == TerrainGenerator.TILE_SERVICE_CORE \
		or tile == TerrainGenerator.TILE_RICH_WALL
