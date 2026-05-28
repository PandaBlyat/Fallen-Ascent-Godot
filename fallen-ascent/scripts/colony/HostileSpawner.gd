extends Node
##
## Lifecycle manager for hostile bots. Spawns periodically up to a cap, far
## from the colony center. Listens to combatant_died to keep the count
## accurate.
##

const HOSTILE_SCRIPT: Script = preload("res://scripts/colony/HostileBot.gd")

const SPAWN_INTERVAL_SECONDS: float = 20.0
const INITIAL_SPAWN_BURST: int = 3
const MAX_ALIVE: int = 7
const MIN_DISTANCE_FROM_COLONY_TILES: int = 50
const SPAWN_ATTEMPTS_PER_TICK: int = 48

@export var chunk_manager_path: NodePath
@export var pathfinder_path: NodePath
@export var workers_root_path: NodePath
@export var neutrals_root_path: NodePath
@export var hostiles_root_path: NodePath
@export var fog_of_war_path: NodePath

var _chunk_manager: ChunkManager
var _pathfinder: Pathfinder
var _workers_root: Node2D
var _neutrals_root: Node2D
var _hostiles_root: Node2D
var _fog: FogOfWar
var _spawn_timer: Timer
var _alive: int = 0
var _rng := RandomNumberGenerator.new()
var _colony_center: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_chunk_manager = get_node_or_null(chunk_manager_path) as ChunkManager
	_pathfinder = get_node_or_null(pathfinder_path) as Pathfinder
	_workers_root = get_node_or_null(workers_root_path) as Node2D
	_neutrals_root = get_node_or_null(neutrals_root_path) as Node2D
	_hostiles_root = get_node_or_null(hostiles_root_path) as Node2D
	_fog = get_node_or_null(fog_of_war_path) as FogOfWar
	_rng.randomize()
	EventBus.combatant_died.connect(_on_combatant_died)
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = SPAWN_INTERVAL_SECONDS
	_spawn_timer.one_shot = false
	_spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(_spawn_timer)
	call_deferred("_initial_burst")


func _initial_burst() -> void:
	if _chunk_manager == null:
		return
	for _i in range(INITIAL_SPAWN_BURST):
		_try_spawn_one()
	_spawn_timer.start()


func _on_spawn_tick() -> void:
	if _alive >= MAX_ALIVE:
		return
	_try_spawn_one()


func _try_spawn_one() -> bool:
	if _chunk_manager == null or _hostiles_root == null:
		return false
	if _alive >= MAX_ALIVE:
		return false
	var bounds: Rect2i = _chunk_manager.map_grid_bounds()
	for _i in range(SPAWN_ATTEMPTS_PER_TICK):
		var cell := Vector2i(
			_rng.randi_range(bounds.position.x, bounds.position.x + bounds.size.x - 1),
			_rng.randi_range(bounds.position.y, bounds.position.y + bounds.size.y - 1),
		)
		if not _chunk_manager.is_walkable(cell):
			continue
		var d: int = maxi(absi(cell.x - _colony_center.x), absi(cell.y - _colony_center.y))
		if d < MIN_DISTANCE_FROM_COLONY_TILES:
			continue
		var bot := HOSTILE_SCRIPT.new() as HostileBot
		bot.name = "Hostile_%02d" % (_alive + 1)
		bot.setup(_chunk_manager, _pathfinder, _fog)
		bot.position = Chunk.grid_to_pixel_center(cell)
		_hostiles_root.add_child(bot)
		_alive += 1
		EventBus.hostile_spawned.emit(bot)
		return true
	return false


func _on_combatant_died(_node: Node, faction: int) -> void:
	if faction == HostileBot.FACTION_HOSTILE:
		_alive = maxi(0, _alive - 1)


func alive_count() -> int:
	return _alive
