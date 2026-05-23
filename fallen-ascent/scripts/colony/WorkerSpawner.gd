class_name WorkerSpawner
extends Node
##
## Picks N walkable cells near the origin and spawns Workers there. Run from
## ColonySite._ready after the first chunk load so the terrain query works.
##

const INITIAL_WORKERS: int = 3
const MAX_SEARCH_RADIUS: int = 24
const WORKER_SCRIPT: Script = preload("res://scripts/colony/Worker.gd")


static func spawn(
	count: int,
	origin: Vector2i,
	chunk_manager: ChunkManager,
	job_board: JobBoard,
	pathfinder: Pathfinder,
	stockpile_manager: StockpileManager,
	items_root: Node2D,
	workers_root: Node2D,
	colony_site: Node,
) -> int:
	var spawned: int = 0
	for cell in _walkable_cells_near(origin, count, chunk_manager):
		var worker: Worker = WORKER_SCRIPT.new() as Worker
		worker.setup(job_board, pathfinder, chunk_manager, stockpile_manager, items_root, colony_site)
		worker.position = Chunk.grid_to_pixel_center(cell)
		workers_root.add_child(worker)
		spawned += 1
		if spawned >= count:
			break
	return spawned


## Spiral outward from origin, collecting up to `count` walkable cells.
static func _walkable_cells_near(
	origin: Vector2i,
	count: int,
	chunk_manager: ChunkManager,
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if chunk_manager.is_walkable(origin):
		out.append(origin)
		if out.size() >= count:
			return out
	for r in range(1, MAX_SEARCH_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				# Only the ring at radius r, not the interior we already scanned.
				if absi(dx) != r and absi(dy) != r:
					continue
				var cell := origin + Vector2i(dx, dy)
				if chunk_manager.is_walkable(cell):
					out.append(cell)
					if out.size() >= count:
						return out
	return out
