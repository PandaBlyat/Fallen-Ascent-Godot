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

const ENTITY_ATLAS: Texture2D = preload("res://resources/entities/bots_atlas.png")
const ENTITY_REGION_SIZE := Vector2(32, 32)
const NEUTRAL_ROW: int = 0
const FACING_SOUTH: int = 0
const FACING_EAST: int = 1
const FACING_NORTH: int = 2
const FACING_WEST: int = 3
const HP_BAR_BG := Color(0.05, 0.05, 0.06, 0.9)
const HP_BAR_FILL := Color(0.55, 0.85, 0.55)
const MOVE_SPEED_PX_PER_SEC: float = 34.0
const ARRIVE_EPSILON_PX: float = 1.0
const WANDER_RADIUS: int = 28
const PICK_ATTEMPTS: int = 36
## Short-hop wander uses a tighter radius; long paths are kept for flee/retaliate
## so per-tick A* cost stays near zero for the ambient population.
const WANDER_HOP_RADIUS: int = 5
const WANDER_HOP_ATTEMPTS: int = 8
const FLEE_RADIUS: int = 14

const PERCEPTION_RADIUS_TILES: int = 5
const LOS_CACHE_TTL_MSEC: int = 400
const RETALIATE_DURATION: float = 3.0
const KNOCKBACK_DURATION: float = 0.12

const FACTION_NEUTRAL: int = 1

enum State { WANDERING, FLEEING, RETALIATING, DEAD }

var stats: CombatStats

var _chunk_manager: ChunkManager
var _pathfinder: Pathfinder
var _fog: FogOfWar
var _state: int = State.WANDERING
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _wander_timer: Timer
var _threat: Node2D = null
var _retaliate_until: float = 0.0
var _knockback_remaining: float = 0.0
var _knockback_vec: Vector2 = Vector2.ZERO
var _stun_remaining: float = 0.0
var _dead: bool = false
var _facing: int = FACING_SOUTH
## LOS cache: target_instance_id -> {result: bool, expires_at_msec: int}.
## Halves LOS calls when the same hostile candidate is rescanned within TTL.
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
	set_process(false)
	EntityGrid.register(self, FACTION_NEUTRAL, current_grid())
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


func ai_tick(_delta: float) -> void:
	if _dead:
		return
	_apply_visibility()
	EntityGrid.update_position(self, current_grid())
	if _state == State.RETALIATING:
		return
	var threat: Node2D = _scan_for_hostile()
	if threat != null:
		_threat = threat
		_state = State.FLEEING
		_flee_from(threat)


func _scan_for_hostile() -> Node2D:
	if _chunk_manager == null:
		return null
	var origin: Vector2i = current_grid()
	var candidates: Array = EntityGrid.query(
		EntityGrid.FACTION_HOSTILE, origin, PERCEPTION_RADIUS_TILES
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
	if _chunk_manager == null:
		_schedule_wander(1.0, 4.0)
		return
	var origin: Vector2i = current_grid()
	# Short-hop wander: skip A* entirely, pick a nearby tile with a clear
	# straight walk. Long paths only happen on flee/retaliate triggers.
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


## Bresenham walk from `from` to `to`; returns true only if every cell is
## walkable. Cheap enough to run per wander attempt instead of full A*.
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
	AIScheduler.unregister(self)
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
	var source := Rect2(Vector2(_facing * int(ENTITY_REGION_SIZE.x), NEUTRAL_ROW * int(ENTITY_REGION_SIZE.y)), ENTITY_REGION_SIZE)
	var dest_size := Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS)
	draw_texture_rect_region(ENTITY_ATLAS, Rect2(-dest_size * 0.5, dest_size), source, modulate_color)
	if _dead or stats == null:
		return
	var bar_pos := Vector2(-16, 17)
	var bar_size := Vector2(32, 3)
	draw_rect(Rect2(bar_pos, bar_size), HP_BAR_BG)
	draw_rect(Rect2(bar_pos, Vector2(bar_size.x * stats.hp_ratio(), bar_size.y)), HP_BAR_FILL)
