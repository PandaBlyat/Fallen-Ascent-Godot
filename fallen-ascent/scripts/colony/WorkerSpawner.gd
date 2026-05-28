class_name WorkerSpawner
extends Node
##
## Picks N walkable cells near the origin and spawns Workers there. Run from
## ColonySite._ready after the first chunk load so the terrain query works.
##

const INITIAL_WORKERS: int = 3
const MAX_SEARCH_RADIUS: int = 24
const WORKER_SCRIPT: Script = preload("res://scripts/colony/Worker.gd")
const BOT_NAMES: Array[String] = [
	# Original Names
	"Echo", "Rook", "Cipher", "Spark", "Null", "Tweak", "Scrap", "Clink",
	"Bolt", "Quirk", "Shift", "Flick", "Sync", "Blink", "Glitch", "Vector",
	"Patch", "Jolt", "Latch", "Knurl", "Relay", "Fuze", "Pip", "Socket",

	# Hardware & Assembly
	"Cog", "Gear", "Rivet", "Cam", "Valve", "Sprocket", "Rotor", "Spindle",
	"Crank", "Gasket", "Shunt", "Clamp", "Shim", "Solder", "Bevel", "Spool",
	"Weld", "Piston", "Anvil", "Sledge", "Dynamo", "Bracket", "Flange", "Grip",

	# Software, Logic & Data
	"Bit", "Byte", "Pixel", "Hex", "Bug", "Cache", "Ram", "Stack",
	"Node", "Loop", "Trace", "Kernel", "Shell", "Daemon", "Ping", "Baud",
	"Port", "Bus", "Gate", "Logic", "Array", "Index", "Hash", "Buffer",

	# Electrical & Signals
	"Flux", "Volt", "Ohm", "Watt", "Amp", "Surge", "Phase", "Core",
	"Hertz", "Freq", "Sparkle", "Grid", "Coil", "Static", "Terminal", "Breaker",

	# Acoustic & Mechanical Sounds
	"Whir", "Buzz", "Chirp", "Click", "Tick", "Beep", "Boop", "Snap",
	"Zip", "Zap", "Hum", "Clank", "Thrum", "Clatter", "Clonk", "Chime",

	# Materials & Elements
	"Rust", "Iron", "Brass", "Zinc", "Lead", "Tin", "Steel", "Chrome",
	"Nickel", "Cobalt", "Slate", "Flint", "Ash", "Carbon", "Copper", "Bronze",

	# Spatial & System States
	"Nano", "Micro", "Ion", "Nova", "Apex", "Helix", "Zenith", "Drift",
	"Tilt", "Warp", "Orbit", "Gauge", "Scale", "Range", "Scope", "Sector"
]


## Spawns the starting crew. When `loadouts` is non-empty (the embark screen
## chose them), one worker is spawned and configured per loadout; otherwise
## `count` random default bots are spawned. Names always come from BOT_NAMES —
## the embark screen draws from this same pool, so there is one source of truth.
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
	fog: FogOfWar = null,
	structure_manager: StructureManager = null,
	room_manager: Node = null,
	loadouts: Array = [],
	forbidden_zone_manager: ForbiddenZoneManager = null,
) -> Array[Vector2i]:
	var target_count: int = loadouts.size() if not loadouts.is_empty() else count
	var used: Array[Vector2i] = []
	for cell in _walkable_cells_near(origin, target_count, chunk_manager):
		var index: int = workers_root.get_child_count() + used.size()
		var worker: Worker = _make_worker(
			cell, index, chunk_manager, job_board, pathfinder,
			stockpile_manager, items_root, colony_site, fog,
			structure_manager, room_manager, forbidden_zone_manager,
		)
		workers_root.add_child(worker)
		# apply_loadout runs AFTER add_child so the worker's _ready has built its
		# CombatStats, which the loadout then overwrites.
		var slot: int = used.size()
		if slot < loadouts.size() and loadouts[slot] is WorkerLoadout:
			worker.apply_loadout(loadouts[slot] as WorkerLoadout)
		used.append(cell)
		if used.size() >= target_count:
			break
	return used


## Spawns a single Worker at a walkable cell adjacent to `anchor`. Used by the
## Replication Cradle to drop a fresh bot next to its footprint after a cycle.
## Returns null if no walkable adjacent cell exists.
static func spawn_one_at(
	anchor: Vector2i,
	chunk_manager: ChunkManager,
	job_board: JobBoard,
	pathfinder: Pathfinder,
	stockpile_manager: StockpileManager,
	items_root: Node2D,
	workers_root: Node2D,
	colony_site: Node,
	fog: FogOfWar = null,
	structure_manager: StructureManager = null,
	room_manager: Node = null,
	forbidden_zone_manager: ForbiddenZoneManager = null,
) -> Worker:
	var target: Vector2i = _walkable_adjacent_or_self(anchor, chunk_manager)
	if target == Pathfinder.UNREACHABLE:
		return null
	var index: int = workers_root.get_child_count()
	var worker: Worker = _make_worker(
		target, index, chunk_manager, job_board, pathfinder,
		stockpile_manager, items_root, colony_site, fog,
		structure_manager, room_manager, forbidden_zone_manager,
	)
	workers_root.add_child(worker)
	return worker


static func _make_worker(
	cell: Vector2i,
	index: int,
	chunk_manager: ChunkManager,
	job_board: JobBoard,
	pathfinder: Pathfinder,
	stockpile_manager: StockpileManager,
	items_root: Node2D,
	colony_site: Node,
	fog: FogOfWar,
	structure_manager: StructureManager,
	room_manager: Node,
	forbidden_zone_manager: ForbiddenZoneManager = null,
) -> Worker:
	var worker: Worker = WORKER_SCRIPT.new() as Worker
	worker.name = _generated_name(index)
	worker.setup(job_board, pathfinder, chunk_manager, stockpile_manager, items_root, colony_site, fog, structure_manager, room_manager, forbidden_zone_manager)
	worker.position = Chunk.grid_to_pixel_center(cell)
	return worker


static func _walkable_adjacent_or_self(anchor: Vector2i, chunk_manager: ChunkManager) -> Vector2i:
	if chunk_manager.is_walkable(anchor):
		return anchor
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	for off in OFFSETS:
		var candidate: Vector2i = anchor + off
		if chunk_manager.is_walkable(candidate):
			return candidate
	for r in range(2, MAX_SEARCH_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var candidate2 := anchor + Vector2i(dx, dy)
				if chunk_manager.is_walkable(candidate2):
					return candidate2
	return Pathfinder.UNREACHABLE


static func _generated_name(index: int) -> String:
	var base: String = BOT_NAMES[index % BOT_NAMES.size()]
	if index < BOT_NAMES.size():
		return base
	return "%s_%02d" % [base, int(index / BOT_NAMES.size()) + 1]


## Spiral outward from origin, collecting up to `count` walkable cells.
static func _walkable_cells_near(
	origin: Vector2i,
	count: int,
	chunk_manager: ChunkManager,
) -> Array[Vector2i]:
	var seed: Vector2i = _nearest_walkable(origin, chunk_manager)
	if seed != Pathfinder.UNREACHABLE:
		var connected: Array[Vector2i] = _connected_walkable_cells(seed, count, chunk_manager)
		if connected.size() >= count:
			return connected
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


static func _nearest_walkable(origin: Vector2i, chunk_manager: ChunkManager) -> Vector2i:
	if chunk_manager.is_walkable(origin):
		return origin
	for r in range(1, MAX_SEARCH_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var cell := origin + Vector2i(dx, dy)
				if chunk_manager.is_walkable(cell):
					return cell
	return Pathfinder.UNREACHABLE


static func _connected_walkable_cells(
	seed: Vector2i,
	count: int,
	chunk_manager: ChunkManager,
) -> Array[Vector2i]:
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var out: Array[Vector2i] = []
	var queue: Array[Vector2i] = [seed]
	var seen: Dictionary = {seed: true}
	var limit: int = maxi(count * 24, 96)
	while not queue.is_empty() and out.size() < count and seen.size() <= limit:
		var cell: Vector2i = queue.pop_front()
		if chunk_manager.is_walkable(cell):
			out.append(cell)
		for off in OFFSETS:
			var next: Vector2i = cell + off
			if seen.has(next):
				continue
			if not chunk_manager.is_walkable(next):
				continue
			seen[next] = true
			queue.append(next)
	return out
