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

const ENTITY_ATLAS: Texture2D = preload("res://resources/entities/placeholder_entities_atlas.png")
const NEUTRAL_REGION := Rect2(Vector2(16, 0), Vector2(16, 16))
const HOSTILE_MODULATE := Color(1.0, 0.36, 0.30, 1.0)
const HP_BAR_BG := Color(0.05, 0.05, 0.06, 0.9)
const HP_BAR_FILL := Color(0.95, 0.30, 0.30)

const FACTION_HOSTILE: int = 2

const MOVE_SPEED_PX_PER_SEC: float = 38.0
const ARRIVE_EPSILON_PX: float = 1.0
const WANDER_RADIUS: int = 24
const PICK_ATTEMPTS: int = 32

const PERCEPTION_TICK_MIN: float = 0.20
const PERCEPTION_TICK_MAX: float = 0.40
const PERCEPTION_RADIUS_TILES: int = 7
const CHASE_LOST_SECONDS: float = 3.0

const KNOCKBACK_DURATION: float = 0.12

enum State { WANDERING, CHASING, ATTACKING, DEAD }

var stats: CombatStats

var _chunk_manager: ChunkManager
var _pathfinder: Pathfinder
var _workers_root: Node2D
var _neutrals_root: Node2D
var _fog: FogOfWar
var _state: int = State.WANDERING
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _wander_timer: Timer
var _perception_timer: Timer
var _target: Node2D = null
var _last_seen_at: float = 0.0
var _knockback_remaining: float = 0.0
var _knockback_vec: Vector2 = Vector2.ZERO
var _stun_remaining: float = 0.0
var _dead: bool = false


func setup(chunk_manager: ChunkManager, pathfinder: Pathfinder, workers_root: Node2D, neutrals_root: Node2D, fog: FogOfWar = null) -> void:
	_chunk_manager = chunk_manager
	_pathfinder = pathfinder
	_workers_root = workers_root
	_neutrals_root = neutrals_root
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
	_perception_timer = Timer.new()
	_perception_timer.one_shot = false
	_perception_timer.wait_time = randf_range(PERCEPTION_TICK_MIN, PERCEPTION_TICK_MAX)
	_perception_timer.timeout.connect(_on_perception_tick)
	add_child(_perception_timer)
	_perception_timer.start()
	_schedule_wander(0.2, 2.0)


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
	var step: float = MOVE_SPEED_PX_PER_SEC * delta
	while step > 0.0 and _path_index < _path.size():
		var target_px: Vector2 = _path[_path_index]
		var to_target: Vector2 = target_px - position
		var dist: float = to_target.length()
		if dist <= step + ARRIVE_EPSILON_PX:
			position = target_px
			step -= dist
			_path_index += 1
		else:
			position += to_target / dist * step
			step = 0.0
	return _path_index >= _path.size()


func _on_perception_tick() -> void:
	if _dead:
		return
	_perception_timer.wait_time = randf_range(PERCEPTION_TICK_MIN, PERCEPTION_TICK_MAX)
	_apply_visibility()
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
	var best: Node2D = null
	var best_d: int = PERCEPTION_RADIUS_TILES + 1
	for root in [_workers_root, _neutrals_root]:
		if root == null:
			continue
		for child in root.get_children():
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
			if not LineOfSight.has_los(_chunk_manager, origin, g):
				continue
			best = child as Node2D
			best_d = d
	return best


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
	if _chunk_manager == null or _pathfinder == null:
		_schedule_wander(1.0, 4.0)
		return
	var origin: Vector2i = current_grid()
	for _i in range(PICK_ATTEMPTS):
		var candidate := origin + Vector2i(
			randi_range(-WANDER_RADIUS, WANDER_RADIUS),
			randi_range(-WANDER_RADIUS, WANDER_RADIUS),
		)
		if not _chunk_manager.is_walkable(candidate):
			continue
		var candidate_path: PackedVector2Array = _pathfinder.find_path(origin, candidate)
		if candidate_path.is_empty():
			continue
		_path = candidate_path
		_path_index = 0
		set_process(true)
		return
	_schedule_wander(1.0, 4.0)


func _schedule_wander(min_seconds: float, max_seconds: float) -> void:
	_wander_timer.start(randf_range(min_seconds, max_seconds))


func _on_wander_timer_timeout() -> void:
	if _dead or _state == State.CHASING or _state == State.ATTACKING:
		return
	_pick_next_wander()


func _die() -> void:
	if _dead:
		return
	_dead = true
	_state = State.DEAD
	set_process(false)
	if _wander_timer != null:
		_wander_timer.stop()
	if _perception_timer != null:
		_perception_timer.stop()
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
	var modulate_color: Color = HOSTILE_MODULATE
	if _dead:
		modulate_color = Color(0.4, 0.1, 0.1, 0.6)
	draw_texture_rect_region(ENTITY_ATLAS, Rect2(Vector2(-8, -8), Vector2(16, 16)), NEUTRAL_REGION, modulate_color)
	if _dead or stats == null:
		return
	var bar_pos := Vector2(-8, 9)
	var bar_size := Vector2(16, 2)
	draw_rect(Rect2(bar_pos, bar_size), HP_BAR_BG)
	draw_rect(Rect2(bar_pos, Vector2(bar_size.x * stats.hp_ratio(), bar_size.y)), HP_BAR_FILL)
