class_name NeutralBot
extends Node2D
##
## Ambient neutral bot. Wanders by default, flees from visible hostiles,
## retaliates briefly if struck. Same atlas region as the hostile; combat
## stats run through the shared CombatService.
##

const CombatStatsScript: Script = preload("res://scripts/combat/CombatStats.gd")
const CombatService: Script = preload("res://scripts/combat/CombatService.gd")
const LineOfSight: Script = preload("res://scripts/util/LineOfSight.gd")

const ENTITY_ATLAS: Texture2D = preload("res://resources/entities/placeholder_entities_atlas.png")
const NEUTRAL_REGION := Rect2(Vector2(16, 0), Vector2(16, 16))
const HP_BAR_BG := Color(0.05, 0.05, 0.06, 0.9)
const HP_BAR_FILL := Color(0.55, 0.85, 0.55)
const MOVE_SPEED_PX_PER_SEC: float = 34.0
const ARRIVE_EPSILON_PX: float = 1.0
const WANDER_RADIUS: int = 28
const PICK_ATTEMPTS: int = 36
const FLEE_RADIUS: int = 14

const PERCEPTION_TICK_MIN: float = 0.35
const PERCEPTION_TICK_MAX: float = 0.55
const PERCEPTION_RADIUS_TILES: int = 5
const RETALIATE_DURATION: float = 3.0
const KNOCKBACK_DURATION: float = 0.12

const FACTION_NEUTRAL: int = 1

enum State { WANDERING, FLEEING, RETALIATING, DEAD }

var stats: CombatStats

var _chunk_manager: ChunkManager
var _pathfinder: Pathfinder
var _hostiles_root: Node2D
var _fog: FogOfWar
var _state: int = State.WANDERING
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _wander_timer: Timer
var _perception_timer: Timer
var _threat: Node2D = null
var _retaliate_until: float = 0.0
var _knockback_remaining: float = 0.0
var _knockback_vec: Vector2 = Vector2.ZERO
var _stun_remaining: float = 0.0
var _dead: bool = false


func setup(chunk_manager: ChunkManager, pathfinder: Pathfinder, hostiles_root: Node2D = null, fog: FogOfWar = null) -> void:
	_chunk_manager = chunk_manager
	_pathfinder = pathfinder
	_hostiles_root = hostiles_root
	_fog = fog
	if _fog != null:
		EventBus.visibility_changed.connect(_on_visibility_changed)
		_apply_visibility()


func _ready() -> void:
	stats = CombatStatsScript.new() as CombatStats
	stats.max_hp = 60.0
	stats.hp = 60.0
	stats.damage_min = 4.0
	stats.damage_max = 8.0
	stats.attack_cooldown_seconds = 1.2
	stats.attack_range_tiles = 1
	stats.knockback_px = 4.0
	stats.stun_on_hit_seconds = 0.10
	stats.dodge_chance = 0.08
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
	set_process(false)
	_schedule_wander(0.2, 2.0)


func current_grid() -> Vector2i:
	return Vector2i(
		int(floor(position.x / Chunk.TILE_PIXELS)),
		int(floor(position.y / Chunk.TILE_PIXELS)),
	)


func is_alive() -> bool:
	return not _dead and stats != null and stats.is_alive()


func faction() -> int:
	return FACTION_NEUTRAL


func combat_stats() -> CombatStats:
	return stats


func display_name() -> String:
	return str(name) if not str(name).is_empty() else "neutral"


func state_label() -> String:
	if _dead:
		return "dead"
	match _state:
		State.WANDERING:
			return "wandering"
		State.FLEEING:
			return "fleeing"
		State.RETALIATING:
			return "retaliating"
		_:
			return "unknown"


func current_target() -> Node:
	return _threat


func take_damage(amount: float, attacker: Node) -> void:
	if _dead or stats == null:
		return
	stats.hp = maxf(0.0, stats.hp - amount)
	if attacker is Node2D and is_instance_valid(attacker):
		_threat = attacker as Node2D
		_retaliate_until = _now() + RETALIATE_DURATION
		_state = State.RETALIATING
		_repath_to_threat()
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
	if _state == State.RETALIATING and _threat != null and is_instance_valid(_threat):
		if _now() >= _retaliate_until or not _threat_alive():
			_state = State.FLEEING
			_threat = null
			_path = PackedVector2Array()
			_flee_from_last_known()
			return
		var threat_grid: Vector2i = (_threat as Node2D).call("current_grid") as Vector2i
		var cheb: int = maxi(absi(threat_grid.x - current_grid().x), absi(threat_grid.y - current_grid().y))
		if cheb <= stats.attack_range_tiles:
			CombatService.try_attack(self, _threat, stats, _now())
			if not _threat_alive():
				_state = State.WANDERING
				_threat = null
				_schedule_wander(0.2, 0.8)
			return
		# Out of melee: keep closing during retaliation window.
	if _advance_path(delta):
		_path = PackedVector2Array()
		set_process(false)
		match _state:
			State.FLEEING:
				_state = State.WANDERING
				_schedule_wander(0.4, 1.2)
			_:
				_schedule_wander(1.0, 4.0)


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
	if _state == State.RETALIATING:
		return
	var threat: Node2D = _scan_for_hostile()
	if threat != null:
		_threat = threat
		_state = State.FLEEING
		_flee_from(threat)


func _scan_for_hostile() -> Node2D:
	if _hostiles_root == null or _chunk_manager == null:
		return null
	var origin: Vector2i = current_grid()
	var best: Node2D = null
	var best_d: int = PERCEPTION_RADIUS_TILES + 1
	for child in _hostiles_root.get_children():
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


func _flee_from(threat: Node2D) -> void:
	if _pathfinder == null or _chunk_manager == null:
		return
	var origin: Vector2i = current_grid()
	var threat_grid: Vector2i = threat.call("current_grid") as Vector2i
	var away: Vector2i = origin - threat_grid
	if away == Vector2i.ZERO:
		away = Vector2i(1, 0)
	for _i in range(PICK_ATTEMPTS):
		var jitter := Vector2i(randi_range(-3, 3), randi_range(-3, 3))
		var candidate: Vector2i = origin + Vector2i(
			sign(away.x) * FLEE_RADIUS + jitter.x,
			sign(away.y) * FLEE_RADIUS + jitter.y,
		)
		if not _chunk_manager.is_walkable(candidate):
			continue
		var path: PackedVector2Array = _pathfinder.find_path(origin, candidate)
		if path.is_empty():
			continue
		_path = path
		_path_index = 0
		set_process(true)
		return
	# Fallback: regular wander.
	_pick_next_wander()


func _flee_from_last_known() -> void:
	if _threat != null and is_instance_valid(_threat):
		_flee_from(_threat)
	else:
		_pick_next_wander()


func _repath_to_threat() -> void:
	if _threat == null or _pathfinder == null:
		return
	var threat_grid: Vector2i = (_threat as Node2D).call("current_grid") as Vector2i
	var stand: Vector2i = _pathfinder.walkable_neighbor_of(threat_grid)
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


func _threat_alive() -> bool:
	if _threat == null or not is_instance_valid(_threat):
		return false
	if _threat.has_method("is_alive"):
		return bool(_threat.call("is_alive"))
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
	if _dead or _state == State.FLEEING or _state == State.RETALIATING:
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
	EventBus.combatant_died.emit(self, FACTION_NEUTRAL)
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
		modulate_color = Color(0.5, 0.5, 0.5, 0.6)
	draw_texture_rect_region(ENTITY_ATLAS, Rect2(Vector2(-8, -8), Vector2(16, 16)), NEUTRAL_REGION, modulate_color)
	if _dead or stats == null:
		return
	var bar_pos := Vector2(-8, 9)
	var bar_size := Vector2(16, 2)
	draw_rect(Rect2(bar_pos, bar_size), HP_BAR_BG)
	draw_rect(Rect2(bar_pos, Vector2(bar_size.x * stats.hp_ratio(), bar_size.y)), HP_BAR_FILL)
