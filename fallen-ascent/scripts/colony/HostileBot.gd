class_name HostileBot
extends Node2D
##
## Aggressive ambient bot. Wanders like NeutralBot, but raycasts every
## perception tick for nearby workers/neutrals; chases on detect, melees on
## adjacency. Same atlas region as NeutralBot, red modulate to differentiate.
##

const CombatStatsScript: Script = preload("res://scripts/combat/CombatStats.gd")
const CombatService: Script = preload("res://scripts/combat/CombatService.gd")
const LineOfSight: Script = preload("res://scripts/util/LineOfSight.gd")

const ENTITY_ATLAS: Texture2D = preload("res://resources/entities/bots_atlas.png")
const ENTITY_REGION_SIZE := Vector2(32, 32)
const HOSTILE_ROW: int = 1
const FACING_SOUTH: int = 0
const FACING_EAST: int = 1
const FACING_NORTH: int = 2
const FACING_WEST: int = 3
const HP_BAR_BG := Color(0.05, 0.05, 0.06, 0.9)
const HP_BAR_FILL := Color(0.95, 0.30, 0.30)

const FACTION_HOSTILE: int = 2

const MOVE_SPEED_PX_PER_SEC: float = 38.0
const ARRIVE_EPSILON_PX: float = 1.0
const DOOR_SLOW_SECONDS: float = 0.65
const DOOR_SLOW_MULTIPLIER: float = 0.72
const WANDER_RADIUS: int = 24
const PICK_ATTEMPTS: int = 32
## Short-hop wander uses a tighter radius; long paths are kept for chase
## so per-tick A* cost stays near zero for the ambient population.
const WANDER_HOP_RADIUS: int = 5
const WANDER_HOP_ATTEMPTS: int = 8

const PERCEPTION_RADIUS_TILES: int = 7
const LOS_CACHE_TTL_MSEC: int = 300
const CHASE_LOST_SECONDS: float = 3.0

const KNOCKBACK_DURATION: float = 0.12

enum State { WANDERING, CHASING, ATTACKING, DEAD }

var stats: CombatStats

var _chunk_manager: ChunkManager
var _pathfinder: Pathfinder
var _fog: FogOfWar
var _state: int = State.WANDERING
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _wander_timer: Timer
var _target: Node2D = null
var _last_seen_at: float = 0.0
var _knockback_remaining: float = 0.0
var _knockback_vec: Vector2 = Vector2.ZERO
var _stun_remaining: float = 0.0
var _door_slow_remaining: float = 0.0
var _last_door_slow_cell: Vector2i = Pathfinder.UNREACHABLE
var _dead: bool = false
var _facing: int = FACING_SOUTH
## LOS cache: target_instance_id -> {result: bool, expires_at_msec: int}.
var _los_cache: Dictionary = {}


func setup(chunk_manager: ChunkManager, pathfinder: Pathfinder, fog: FogOfWar = null) -> void:
	_chunk_manager = chunk_manager
	_pathfinder = pathfinder
	_fog = fog
	if _fog != null:
		EventBus.visibility_changed.connect(_on_visibility_changed)
		_apply_visibility()


func _ready() -> void:
	stats = CombatStatsScript.new() as CombatStats
	stats.max_hp = 80.0
	stats.hp = 80.0
	stats.damage_min = 10.0
	stats.damage_max = 16.0
	stats.attack_cooldown_seconds = 0.85
	stats.attack_range_tiles = 1
	stats.knockback_px = 8.0
	stats.stun_on_hit_seconds = 0.20
	stats.dodge_chance = 0.06
	_wander_timer = Timer.new()
	_wander_timer.one_shot = true
	_wander_timer.timeout.connect(_on_wander_timer_timeout)
	add_child(_wander_timer)
	EntityGrid.register(self, FACTION_HOSTILE, current_grid())
	AIScheduler.register(self)
	tree_exiting.connect(_on_tree_exiting)
	_schedule_wander(0.2, 2.0)


func _on_tree_exiting() -> void:
	EntityGrid.unregister(self)
	AIScheduler.unregister(self)


func current_grid() -> Vector2i:
	return Vector2i(
		int(floor(position.x / Chunk.TILE_PIXELS)),
		int(floor(position.y / Chunk.TILE_PIXELS)),
	)


func is_alive() -> bool:
	return not _dead and stats != null and stats.is_alive()


func faction() -> int:
	return FACTION_HOSTILE


func combat_stats() -> CombatStats:
	return stats


func display_name() -> String:
	return str(name) if not str(name).is_empty() else "hostile"


func state_label() -> String:
	if _dead:
		return "dead"
	match _state:
		State.WANDERING:
			return "wandering"
		State.CHASING:
			return "chasing"
		State.ATTACKING:
			return "attacking"
		_:
			return "unknown"


func current_target() -> Node:
	return _target


func take_damage(amount: float, attacker: Node) -> void:
	if _dead or stats == null:
		return
	stats.hp = maxf(0.0, stats.hp - amount)
	if attacker is Node2D and _target == null and is_instance_valid(attacker):
		_target = attacker as Node2D
		_last_seen_at = _now()
		if _state == State.WANDERING:
			_state = State.CHASING
	queue_redraw()
	if stats.hp <= 0.0:
		_die()


func apply_knockback(vec: Vector2, stun_seconds: float) -> void:
	if _dead:
		return
	_knockback_vec = vec
	_knockback_remaining = KNOCKBACK_DURATION
	_stun_remaining = maxf(_stun_remaining, stun_seconds)
	set_process(true)


func _process(delta: float) -> void:
	if _dead:
		return
	if _knockback_remaining > 0.0:
		var step: float = delta / KNOCKBACK_DURATION
		position += _knockback_vec * step
		_knockback_remaining = maxf(0.0, _knockback_remaining - delta)
		if _knockback_remaining <= 0.0:
			_snap_to_walkable()
		return
	if _stun_remaining > 0.0:
		_stun_remaining = maxf(0.0, _stun_remaining - delta)
		return
	if _door_slow_remaining > 0.0:
		_door_slow_remaining = maxf(0.0, _door_slow_remaining - delta)
	if _state == State.CHASING and _target != null and is_instance_valid(_target):
		var target_grid: Vector2i = (_target as Node2D).call("current_grid") as Vector2i
		var cheb: int = maxi(absi(target_grid.x - current_grid().x), absi(target_grid.y - current_grid().y))
		if cheb <= stats.attack_range_tiles:
			_path = PackedVector2Array()
			_state = State.ATTACKING
			_try_swing()
			return
	if _state == State.ATTACKING:
		if _target == null or not is_instance_valid(_target) or not _target_alive():
			_target = null
			_state = State.WANDERING
			_schedule_wander(0.4, 1.2)
			return
		var target_grid: Vector2i = (_target as Node2D).call("current_grid") as Vector2i
		var cheb: int = maxi(absi(target_grid.x - current_grid().x), absi(target_grid.y - current_grid().y))
		if cheb > stats.attack_range_tiles:
			_state = State.CHASING
			_repath_to_target()
			return
		_try_swing()
		return
	if _advance_path(delta):
		_path = PackedVector2Array()
		set_process(false)
		if _state == State.CHASING:
			_state = State.WANDERING
		_schedule_wander(1.0, 3.0)


func _advance_path(delta: float) -> bool:
	if _path.is_empty() or _path_index >= _path.size():
		return true
	var speed_mult: float = DOOR_SLOW_MULTIPLIER if _door_slow_remaining > 0.0 else 1.0
	var step: float = MOVE_SPEED_PX_PER_SEC * speed_mult * delta
	while step > 0.0 and _path_index < _path.size():
		var target_px: Vector2 = _path[_path_index]
		var target_grid := Vector2i(
			int(floor(target_px.x / Chunk.TILE_PIXELS)),
			int(floor(target_px.y / Chunk.TILE_PIXELS)),
		)
		if _chunk_manager != null:
			var structure: Dictionary = _chunk_manager.structure_at(target_grid)
			if not structure.is_empty() and int(structure["id"]) == BuildBlueprint.Id.DOOR:
				_chunk_manager.request_door_open(target_grid)
				if not _chunk_manager.is_door_open(target_grid):
					return false
				if _last_door_slow_cell != target_grid:
					_last_door_slow_cell = target_grid
					_door_slow_remaining = DOOR_SLOW_SECONDS
		var to_target: Vector2 = target_px - position
		var dist: float = to_target.length()
		if dist > ARRIVE_EPSILON_PX:
			_set_facing_from_vector(to_target)
		if dist <= step + ARRIVE_EPSILON_PX:
			position = target_px
			step -= dist
			_path_index += 1
		else:
			position += to_target / dist * step
			step = 0.0
	return _path_index >= _path.size()


func _set_facing_from_vector(delta_pos: Vector2) -> void:
	if absf(delta_pos.x) > absf(delta_pos.y):
		_facing = FACING_EAST if delta_pos.x > 0.0 else FACING_WEST
	else:
		_facing = FACING_SOUTH if delta_pos.y > 0.0 else FACING_NORTH
	queue_redraw()


func ai_tick(delta: float) -> void:
	if _dead:
		return
	_apply_visibility()
	EntityGrid.update_position(self, current_grid())
	_tick_acid_damage(delta)
	if _dead:
		return
	var best: Node2D = _scan_for_target()
	var now: float = _now()
	if best != null:
		_target = best
		_last_seen_at = now
		if _state == State.WANDERING:
			_state = State.CHASING
			_repath_to_target()
		elif _state == State.CHASING:
			_repath_to_target()
	else:
		if _target != null and now - _last_seen_at >= CHASE_LOST_SECONDS:
			_target = null
			if _state == State.CHASING or _state == State.ATTACKING:
				_state = State.WANDERING
				_schedule_wander(0.2, 1.0)


func _scan_for_target() -> Node2D:
	if _chunk_manager == null:
		return null
	var origin: Vector2i = current_grid()
	var candidates: Array = EntityGrid.query(
		EntityGrid.FACTION_COLONY, origin, PERCEPTION_RADIUS_TILES
	)
	candidates.append_array(
		EntityGrid.query(EntityGrid.FACTION_NEUTRAL, origin, PERCEPTION_RADIUS_TILES)
	)
	if candidates.is_empty():
		return null
	var best: Node2D = null
	var best_d: int = PERCEPTION_RADIUS_TILES + 1
	var now_msec: int = Time.get_ticks_msec()
	for child in candidates:
		if not is_instance_valid(child):
			continue
		if child.has_method("is_alive") and not bool(child.call("is_alive")):
			continue
		if not child.has_method("current_grid"):
			continue
		var g: Vector2i = child.call("current_grid") as Vector2i
		var d: int = maxi(absi(g.x - origin.x), absi(g.y - origin.y))
		if d > PERCEPTION_RADIUS_TILES or d >= best_d:
			continue
		if not _cached_has_los(child, origin, g, now_msec):
			continue
		best = child as Node2D
		best_d = d
	return best


func _cached_has_los(target: Node, origin: Vector2i, target_grid: Vector2i, now_msec: int) -> bool:
	var id: int = target.get_instance_id()
	var entry: Dictionary = _los_cache.get(id, {}) as Dictionary
	if not entry.is_empty() and int(entry.get("expires_at_msec", 0)) > now_msec:
		return bool(entry.get("result", false))
	var result: bool = LineOfSight.has_los(_chunk_manager, origin, target_grid)
	_los_cache[id] = {
		"result": result,
		"expires_at_msec": now_msec + LOS_CACHE_TTL_MSEC,
	}
	return result


func _repath_to_target() -> void:
	if _target == null or _pathfinder == null:
		return
	var target_grid: Vector2i = (_target as Node2D).call("current_grid") as Vector2i
	var stand: Vector2i = _pathfinder.walkable_neighbor_of(target_grid)
	if stand == Pathfinder.UNREACHABLE:
		return
	if stand == current_grid():
		_path = PackedVector2Array()
		_path_index = 0
		return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), stand)
	if path.is_empty():
		return
	_path = path
	_path_index = 0
	set_process(true)


func _try_swing() -> void:
	if _target == null:
		return
	CombatService.try_attack(self, _target, stats, _now())
	if not _target_alive():
		_target = null
		_state = State.WANDERING
		_schedule_wander(0.2, 0.8)


func _target_alive() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	if _target.has_method("is_alive"):
		return bool(_target.call("is_alive"))
	return true


func _snap_to_walkable() -> void:
	if _chunk_manager == null:
		return
	var here: Vector2i = current_grid()
	if _chunk_manager.is_walkable(here):
		return
	if _pathfinder != null:
		var stand: Vector2i = _pathfinder.walkable_neighbor_of(here)
		if stand != Pathfinder.UNREACHABLE:
			position = Chunk.grid_to_pixel_center(stand)


func _pick_next_wander() -> void:
	if _chunk_manager == null:
		_schedule_wander(1.0, 4.0)
		return
	var origin: Vector2i = current_grid()
	# Short-hop wander: no A*. Real paths are only spent on chase.
	for _i in range(WANDER_HOP_ATTEMPTS):
		var candidate := origin + Vector2i(
			randi_range(-WANDER_HOP_RADIUS, WANDER_HOP_RADIUS),
			randi_range(-WANDER_HOP_RADIUS, WANDER_HOP_RADIUS),
		)
		if candidate == origin:
			continue
		if not _chunk_manager.is_walkable(candidate):
			continue
		if not _clear_walk(origin, candidate):
			continue
		_path = PackedVector2Array([Chunk.grid_to_pixel_center(candidate)])
		_path_index = 0
		set_process(true)
		return
	_schedule_wander(1.0, 4.0)


func _clear_walk(from: Vector2i, to: Vector2i) -> bool:
	if _chunk_manager == null:
		return false
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
	while x != x1 or y != y1:
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
		if not _chunk_manager.is_walkable(Vector2i(x, y)):
			return false
	return true


func _schedule_wander(min_seconds: float, max_seconds: float) -> void:
	_wander_timer.start(randf_range(min_seconds, max_seconds))


func _on_wander_timer_timeout() -> void:
	if _dead or _state == State.CHASING or _state == State.ATTACKING:
		return
	_pick_next_wander()


func _tick_acid_damage(delta: float) -> void:
	if _chunk_manager == null or stats == null:
		return
	var tile: int = _chunk_manager.get_tile_at(current_grid())
	var dps: float = 0.0
	if tile == TerrainGenerator.TILE_ACID_SHALLOW:
		dps = 2.0
	elif tile == TerrainGenerator.TILE_ACID_PUDDLE:
		dps = 0.5
	if dps <= 0.0:
		return
	stats.hp = maxf(0.0, stats.hp - dps * delta)
	queue_redraw()
	if stats.hp <= 0.0:
		_die()


func _die() -> void:
	if _dead:
		return
	_dead = true
	_state = State.DEAD
	set_process(false)
	if _wander_timer != null:
		_wander_timer.stop()
	AIScheduler.unregister(self)
	EventBus.combatant_died.emit(self, FACTION_HOSTILE)
	queue_redraw()
	var fade := Timer.new()
	fade.one_shot = true
	fade.wait_time = 0.5
	add_child(fade)
	fade.timeout.connect(queue_free)
	fade.start()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_visibility_changed(_bounds: Rect2i) -> void:
	_apply_visibility()


func _apply_visibility() -> void:
	if _fog == null:
		visible = true
		return
	visible = _fog.is_cell_visible(current_grid())


func _draw() -> void:
	var modulate_color: Color = Color.WHITE
	if _dead:
		modulate_color = Color(0.4, 0.1, 0.1, 0.6)
	var source := Rect2(Vector2(_facing * int(ENTITY_REGION_SIZE.x), HOSTILE_ROW * int(ENTITY_REGION_SIZE.y)), ENTITY_REGION_SIZE)
	var dest_size := Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS)
	draw_texture_rect_region(ENTITY_ATLAS, Rect2(-dest_size * 0.5, dest_size), source, modulate_color)
	if _dead or stats == null:
		return
	var bar_pos := Vector2(-16, 17)
	var bar_size := Vector2(32, 3)
	draw_rect(Rect2(bar_pos, bar_size), HP_BAR_BG)
	draw_rect(Rect2(bar_pos, Vector2(bar_size.x * stats.hp_ratio(), bar_size.y)), HP_BAR_FILL)
