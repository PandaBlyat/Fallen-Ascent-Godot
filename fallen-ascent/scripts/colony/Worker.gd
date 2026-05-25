class_name Worker
extends Node2D
##
## One unit. Pulls jobs from the JobBoard, paths via the Pathfinder, executes
## them. State machine in one switch; movement scales with Engine.time_scale
## because `delta` already does.
##
## Direct orders from the player (selection + right-click) come in via the
## `command_*` methods. They release current jobs back to the board instead of
## orphaning claims.
##

enum State {
	IDLE,
	MOVING_TO_WORK,
	WORKING,
	MOVING_TO_PICKUP,
	CARRYING,
	MOVING_TO_DROP,
	MOVING_TO_BUILD_SITE,
	BUILDING,
	MOVING_TO_CRAFT_SITE,
	CRAFTING,
	MOVING_FREEFORM,
	MOVING_TO_CHARGE,
	CHARGING,
	ROAMING,
	WANDERING,
	MOVING_TO_REST,
	RESTING,
	MOVING_TO_REPAIR,
	REPAIRING,
	MOVING_TO_SOCIALIZE,
	SOCIALIZING,
	MOVING_TO_MEDITATE,
	MEDITATING,
	FIGHTING,
	DEAD,
}

const CombatStatsScript: Script = preload("res://scripts/combat/CombatStats.gd")
const CombatService: Script = preload("res://scripts/combat/CombatService.gd")
const COMBAT_HP_MAX: float = 100.0
const COMBAT_REPATH_INTERVAL: float = 0.5
const COMBAT_LOST_TIMEOUT: float = 3.0
const KNOCKBACK_DURATION: float = 0.12
const FACTION_COLONY: int = 0

const MOVE_SPEED_PX_PER_SEC: float = 48.0
const WATER_SHALLOW_SPEED_MULT: float = 0.5
const WATER_PUDDLE_SPEED_MULT: float = 0.85
const ACID_SHALLOW_SPEED_MULT: float = 0.4
const ACID_PUDDLE_SPEED_MULT: float = 0.75
const ACID_SHALLOW_DPS: float = 2.0
const ACID_PUDDLE_DPS: float = 0.5
const ACID_DEEP_DPS: float = 6.0
const ACID_SHALLOW_MOOD_DRAIN_PER_SEC: float = 4.0
const ACID_PUDDLE_MOOD_DRAIN_PER_SEC: float = 1.5
const ACID_DEEP_MOOD_DRAIN_PER_SEC: float = 9.0
const ACID_MOOD_SPIKE_PER_HP: float = 2.0
## Must match ActivityFxManager.KIND_BUILD_DUST.
const BUILD_DUST_FX_KIND: int = 7
const ARRIVE_EPSILON_PX: float = 1.0
const IDLE_RETRY_SECONDS: float = 0.5
const BODY_RADIUS: float = 12.0
const BODY_COLOR := Color(0.85, 0.85, 0.95)
const SELECTION_COLOR := Color(1.0, 0.95, 0.4, 0.55)
const ITEM_SCRIPT: Script = preload("res://scripts/colony/Item.gd")
const MAX_CARRY_STACK: int = 4
const ENERGY_MAX: float = 100.0
const ENERGY_LOW: float = 28.0
const ENERGY_CRITICAL: float = 10.0
const ENERGY_IDLE_DRAIN_PER_SEC: float = 0.25
const ENERGY_MOVE_DRAIN_PER_SEC: float = 0.7
const ENERGY_WORK_DRAIN_PER_SEC: float = 1.1
const ENERGY_CHARGE_PER_SEC: float = 4.0
const BATTERY_BG := Color(0.05, 0.05, 0.06, 0.9)
const BATTERY_GOOD := Color(0.3, 0.9, 0.55)
const BATTERY_LOW := Color(1.0, 0.78, 0.2)
const ACTION_FONT_SIZE: int = 12
const ENTITY_ATLAS_PATH := "res://resources/entities/worker_atlas.png"
const ACTION_FONT: Font = preload("res://resources/Orbitron-VariableFont_wght.ttf")
const ENTITY_REGION_SIZE := Vector2(32, 32)
const FACING_SOUTH: int = 0
const FACING_SOUTH_EAST: int = 1
const FACING_EAST: int = 2
const FACING_NORTH_EAST: int = 3
const FACING_NORTH: int = 4
const FACING_NORTH_WEST: int = 5
const FACING_WEST: int = 6
const FACING_SOUTH_WEST: int = 7
const CONDITION_MAX: float = 100.0
const MENTAL_TIRED_MAX: float = 100.0
const CONDITION_MOVE_DECAY_PER_SEC: float = 0.035
const CONDITION_WORK_DECAY_PER_SEC: float = 0.09
const MENTAL_IDLE_RISE_PER_SEC: float = 0.04
const MENTAL_WORK_RISE_PER_SEC: float = 0.16
const REST_RECOVERY_PER_SEC: float = 8.0
const REPAIR_RECOVERY_PER_SEC: float = 12.0
const SOCIAL_MAX: float = 100.0
const SOCIAL_GAIN_PER_SEC: float = 12.0          ## per-second gain while chatting
const SOCIAL_DECAY_PER_SEC: float = 0.18         ## passive decay when not chatting
const SOCIAL_ADJACENCY_RANGE: int = 1
const MOOD_MAX: float = 100.0
const MOOD_BASELINE: float = 80.0
const MOOD_RECOVERY_PER_SEC: float = 0.4         ## drift back to baseline when needs satisfied
const MOOD_NEED_DECAY_PER_SEC: float = 0.6       ## per-need extra decay while unsatisfied
const MOOD_LOW_THRESHOLD: float = 35.0
const CROWD_SLOW_SECONDS: float = 1.0
const CROWD_SLOW_MULTIPLIER: float = 0.55
const DOOR_SLOW_SECONDS: float = 0.65
const DOOR_SLOW_MULTIPLIER: float = 0.72
const RUST_CONDITION_DECAY_MULTIPLIER: float = 3.0
const TELEPORT_COOLDOWN_SECONDS: float = 1.0
const SCRAPE_RUST_DURATION: float = 1.4
const SCRAPE_BIOMASS_DURATION: float = 0.9
const IDLE_SAMPLE_LIMIT: int = 48
const IDLE_SCRAPE_RUST_RADIUS: int = 28
const ACTION_HISTORY_LIMIT: int = 96
const ACTION_BUBBLE_SCREEN_OFFSET := Vector2(0.0, -34.0)
const BLOCKED_ACTION_SECONDS: float = 2.0
const CROWD_FRAME_META: StringName = &"fa_crowd_frame"
const CROWD_CELLS_META: StringName = &"fa_crowd_cells"
const LIMB_NAMES: Array[String] = ["head", "core", "left arm", "right arm", "left leg", "right leg"]
const WISDOM_PER_SEC: float = 0.6
const WISDOM_FOCUSED_MULTIPLIER: float = 1.25
const ASSIGNED_DOCK_REST_MULTIPLIER: float = 1.6
const ASSIGNED_DOCK_MOOD_PER_SEC: float = 0.35
const ORDER_MOVE := &"move"
const ORDER_MINE := &"mine"
const ORDER_SCRAPE_RUST := &"scrape_rust"
const ORDER_SCRAPE_BIOMASS := &"scrape_biomass"
const ORDER_BUILD := &"build"
const ORDER_TAKE_BUILD_JOB := &"take_build_job"
const ORDER_CHARGE := &"charge"
const ORDER_ATTACK := &"attack"
## Throttle for RoomManager interaction in _update_mood; per-frame calls
## were O(workers * rooms) and dominated `_process` cost.
const NEEDS_REFRESH_SECONDS: float = 0.5
## Throttle for EntityGrid bucket sync; cheap dict op but no point per-frame.
const ENTITY_GRID_SYNC_SECONDS: float = 0.25

var _state: int = State.IDLE
var _job: Job = null
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _idle_cooldown: float = 0.0
var _carried: Item = null
var _selected: bool = false
var _energy: float = ENERGY_MAX
var _charge_target: Vector2i = Vector2i.ZERO
var _has_charge_reservation: bool = false
var _manual_charging: bool = false
var _action_text: String = ""
var _blocked_action_text: String = ""
var _blocked_action_timer: float = 0.0
var _condition: float = CONDITION_MAX
var _mental_tiredness: float = 0.0
var _social: float = 50.0
var _mood: float = MOOD_BASELINE
var _unsatisfied_needs: Array[String] = []
var _activity_timer: float = 0.0
var _activity_target: Vector2i = Vector2i.ZERO
var _activity_partner: Worker = null
var _entity_atlas: Texture2D
var _facing: int = FACING_SOUTH
var _action_history: Array[String] = []
var _wisdom_carry: float = 0.0
var _history_index: int = 0
var _limbs: Dictionary = {}
var _teleport_cooldown: float = 0.0
var _last_teleporter_grid: Vector2i = Pathfinder.UNREACHABLE
var _resume_job: Job = null
var _resume_state: int = State.IDLE
var _resume_path: PackedVector2Array = PackedVector2Array()
var _resume_path_index: int = 0
var _resume_carried: Item = null
var stats: CombatStats
var _combat_target: Node2D = null
var _combat_repath_cooldown: float = 0.0
var _last_combat_contact_at: float = 0.0
var _knockback_remaining: float = 0.0
var _knockback_vec: Vector2 = Vector2.ZERO
var _stun_remaining: float = 0.0
var _dead: bool = false
var _crowd_slow_remaining: float = 0.0
var _door_slow_remaining: float = 0.0
var _last_door_slow_cell: Vector2i = Pathfinder.UNREACHABLE
var _crowd_contacts: Dictionary = {}
var _direct_order_queue: Array[Dictionary] = []
var _needs_refresh_timer: float = 0.0
var _entity_grid_timer: float = 0.0
var _acid_damage_accum: float = 0.0

var _job_board: JobBoard
var _pathfinder: Pathfinder
var _chunk_manager: ChunkManager
var _stockpile_manager: StockpileManager
var _items_root: Node2D
var _colony_site: Node
var _fog: FogOfWar
var _structure_manager: StructureManager
var _room_manager: Node = null


func setup(
	job_board: JobBoard,
	pathfinder: Pathfinder,
	chunk_manager: ChunkManager,
	stockpile_manager: StockpileManager,
	items_root: Node2D,
	colony_site: Node,
	fog: FogOfWar = null,
	structure_manager: StructureManager = null,
	room_manager: Node = null,
) -> void:
	_job_board = job_board
	_pathfinder = pathfinder
	_chunk_manager = chunk_manager
	_stockpile_manager = stockpile_manager
	_items_root = items_root
	_colony_site = colony_site
	_fog = fog
	_structure_manager = structure_manager
	_room_manager = room_manager


func _ready() -> void:
	_entity_atlas = load(ENTITY_ATLAS_PATH) as Texture2D
	_init_limbs()
	stats = CombatStatsScript.new() as CombatStats
	stats.max_hp = COMBAT_HP_MAX
	stats.hp = COMBAT_HP_MAX
	stats.damage_min = 8.0
	stats.damage_max = 14.0
	stats.attack_cooldown_seconds = 0.9
	stats.attack_range_tiles = 1
	stats.knockback_px = 6.0
	stats.stun_on_hit_seconds = 0.15
	stats.dodge_chance = 0.12
	if _job_board != null:
		_job_board.job_cancelled.connect(_on_job_cancelled)
	EventBus.tile_changed.connect(_on_tile_changed)
	EntityGrid.register(self, FACTION_COLONY, current_grid())
	tree_exiting.connect(_on_tree_exiting)
	_remember("online at %d,%d" % [current_grid().x, current_grid().y])


func _on_tree_exiting() -> void:
	EntityGrid.unregister(self)


func is_alive() -> bool:
	return not _dead and stats != null and stats.is_alive()


func faction() -> int:
	return FACTION_COLONY


func combat_stats() -> CombatStats:
	return stats


func current_target() -> Node:
	return _combat_target


func take_damage(amount: float, attacker: Node) -> void:
	if _dead or stats == null:
		return
	stats.hp = maxf(0.0, stats.hp - amount)
	_damage_limb(amount / 1.6)
	_last_combat_contact_at = _now_seconds()
	if attacker is Node2D and is_instance_valid(attacker):
		if _state != State.FIGHTING:
			_abandon_job()
			_enter_fighting(attacker as Node2D)
			_remember("attacked, fighting back")
	queue_redraw()
	if stats.hp <= 0.0:
		_die()


func apply_knockback(vec: Vector2, stun_seconds: float) -> void:
	if _dead:
		return
	_knockback_vec = vec
	_knockback_remaining = KNOCKBACK_DURATION
	_stun_remaining = maxf(_stun_remaining, stun_seconds)


func command_attack(
	target: Node2D,
	preferred_stand: Vector2i = Pathfinder.UNREACHABLE,
	clear_queue: bool = true
) -> bool:
	if _dead or target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_alive") and not bool(target.call("is_alive")):
		return false
	if clear_queue:
		_direct_order_queue.clear()
	_abandon_job()
	_enter_fighting(target, preferred_stand)
	_remember("ordered to attack %s" % _target_label(target))
	return true


func _enter_fighting(target: Node2D, preferred_stand: Vector2i = Pathfinder.UNREACHABLE) -> void:
	var was_fighting: bool = _state == State.FIGHTING
	_combat_target = target
	_state = State.FIGHTING
	if not was_fighting:
		EventBus.worker_entered_combat.emit(self)
	_combat_repath_cooldown = 0.0
	_last_combat_contact_at = _now_seconds()
	if preferred_stand != Pathfinder.UNREACHABLE and _chunk_manager != null and _chunk_manager.is_walkable(preferred_stand):
		if preferred_stand == current_grid():
			_path = PackedVector2Array()
			_path_index = 0
		else:
			var path: PackedVector2Array = _pathfinder.find_path(current_grid(), preferred_stand)
			if not path.is_empty():
				_path = path
				_path_index = 0
				return
	_repath_to_combat_target()


func _repath_to_combat_target() -> void:
	if _combat_target == null or _pathfinder == null or _chunk_manager == null:
		return
	var target_grid: Vector2i = (_combat_target as Node2D).call("current_grid") as Vector2i
	var stand: Vector2i = _pathfinder.walkable_neighbor_of(target_grid)
	if stand == Pathfinder.UNREACHABLE:
		_path = PackedVector2Array()
		_path_index = 0
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


func _target_alive() -> bool:
	if _combat_target == null or not is_instance_valid(_combat_target):
		return false
	if _combat_target.has_method("is_alive"):
		return bool(_combat_target.call("is_alive"))
	return true


func _target_label(node: Node) -> String:
	if node != null and is_instance_valid(node):
		return str(node.name)
	return "target"


func _die() -> void:
	if _dead:
		return
	_dead = true
	_state = State.DEAD
	_path = PackedVector2Array()
	_path_index = 0
	if _carried != null:
		var here := current_grid()
		remove_child(_carried)
		_items_root.add_child(_carried)
		_carried.visible = true
		_carried.set_grid(here)
		_carried.reserved_by = null
		if _stockpile_manager != null:
			_stockpile_manager.on_item_spawned(_carried)
		_carried = null
	if _job != null and _job_board != null and _job_board.is_active(_job):
		_job_board.release(_job)
	_job = null
	_release_charge_reservation()
	if _room_manager != null and _room_manager.has_method("release_worker"):
		_room_manager.call("release_worker", self)
	EventBus.combatant_died.emit(self, FACTION_COLONY)
	queue_redraw()
	var fade := Timer.new()
	fade.one_shot = true
	fade.wait_time = 0.5
	add_child(fade)
	fade.timeout.connect(queue_free)
	fade.start()


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func current_grid() -> Vector2i:
	return Vector2i(
		int(floor(position.x / Chunk.TILE_PIXELS)),
		int(floor(position.y / Chunk.TILE_PIXELS)),
	)


func active_path_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	if _path.is_empty() or _path_index >= _path.size():
		return pts
	pts.resize(_path.size() - _path_index + 1)
	pts[0] = position
	for i in range(_path_index, _path.size()):
		pts[i - _path_index + 1] = _path[i]
	return pts


func set_selected(v: bool) -> void:
	if _selected == v:
		return
	_selected = v
	queue_redraw()


func is_selected() -> bool:
	return _selected


func display_name() -> String:
	return str(name) if not str(name).is_empty() else "bot"


func action_history() -> Array[String]:
	return _action_history.duplicate()


func energy_ratio() -> float:
	return clampf(_energy / ENERGY_MAX, 0.0, 1.0)


func condition_ratio() -> float:
	return clampf(_condition / CONDITION_MAX, 0.0, 1.0)


func mental_tiredness_ratio() -> float:
	return clampf(_mental_tiredness / MENTAL_TIRED_MAX, 0.0, 1.0)


func social_score() -> int:
	return int(roundf(_social))


func social_ratio() -> float:
	return clampf(_social / SOCIAL_MAX, 0.0, 1.0)


func mood_ratio() -> float:
	return clampf(_mood / MOOD_MAX, 0.0, 1.0)


func mood_value() -> int:
	return int(roundf(_mood))


func mood_label() -> String:
	if _mood >= 80.0:
		return "content"
	if _mood >= 55.0:
		return "neutral"
	if _mood >= MOOD_LOW_THRESHOLD:
		return "uneasy"
	return "broken"


func unsatisfied_needs() -> Array[String]:
	return _unsatisfied_needs.duplicate()


func limb_status_lines() -> Array[String]:
	var lines: Array[String] = []
	for limb_name in LIMB_NAMES:
		var value: float = float(_limbs.get(limb_name, CONDITION_MAX))
		lines.append("%s %d%%" % [limb_name, int(roundf(value))])
	return lines


func carried_label() -> String:
	if _carried == null:
		return "none"
	return Item.stack_label(_carried.kind, _carried.count)


func job_label() -> String:
	if _job is MineJob:
		return "mine"
	if _job is HaulJob:
		return "haul"
	if _job is BuildJob:
		return "build " + BuildBlueprint.display_name((_job as BuildJob).blueprint_id)
	if _job is OperateStructureJob:
		return "operate " + BuildBlueprint.display_name((_job as OperateStructureJob).structure_id)
	if _is_scrape_biomass_job(_job):
		return "scrape biomass"
	if _is_scrape_rust_job(_job):
		return "scrape rust"
	return "none"


func state_label() -> String:
	match _state:
		State.IDLE:
			return "idle"
		State.MOVING_TO_WORK:
			return "moving to mine"
		State.WORKING:
			return "mining"
		State.MOVING_TO_PICKUP:
			return "getting item"
		State.CARRYING, State.MOVING_TO_DROP:
			return "hauling"
		State.MOVING_TO_BUILD_SITE:
			return "delivering"
		State.BUILDING:
			return "building"
		State.MOVING_TO_CRAFT_SITE:
			return "delivering"
		State.CRAFTING:
			return "crafting"
		State.MOVING_FREEFORM:
			return "moving"
		State.MOVING_TO_CHARGE:
			return "moving to recharge"
		State.CHARGING:
			return "charging"
		State.ROAMING:
			return "roaming"
		State.WANDERING:
			return "wandering"
		State.MOVING_TO_REST:
			return "moving to dock"
		State.RESTING:
			return "resting"
		State.MOVING_TO_REPAIR:
			return "moving to repair"
		State.REPAIRING:
			return "repairing"
		State.MOVING_TO_SOCIALIZE:
			return "moving to chat"
		State.SOCIALIZING:
			return "chatting"
		State.MOVING_TO_MEDITATE:
			return "moving to meditate"
		State.MEDITATING:
			return "meditating"
		State.FIGHTING:
			return "fighting"
		State.DEAD:
			return "down"
		_:
			return "unknown"


func activity_fx() -> Variant:
	match _state:
		State.WORKING:
			if _job is MineJob:
				var mine := _job as MineJob
				return {
					"grid": mine.target,
					"kind": 1,
					"progress": clampf(mine.progress / MineJob.DURATION, 0.0, 1.0),
					"intensity": 0.9,
				}
			if _is_scrape_job(_job):
				var target: Vector2i = _job.get("target") as Vector2i
				var duration: float = SCRAPE_BIOMASS_DURATION if _is_scrape_biomass_job(_job) else SCRAPE_RUST_DURATION
				return {
					"grid": target,
					"kind": 1,
					"progress": clampf(float(_job.get("progress")) / duration, 0.0, 1.0),
					"intensity": 0.55,
				}
		State.BUILDING:
			var build := _job as BuildJob
			if build != null:
				var build_progress: float = clampf(build.progress / build.build_duration(), 0.0, 1.0)
				return [
					{
						"grid": build.anchor,
						"kind": 2,
						"progress": build_progress,
						"intensity": 0.85,
					},
					{
						"grid": current_grid(),
						"to_grid": build.anchor,
						"kind": BUILD_DUST_FX_KIND,
						"progress": build_progress,
						"intensity": 0.9,
					},
				]
		State.CHARGING:
			return {
				"grid": _charge_target if _charge_target != Vector2i.ZERO else current_grid(),
				"kind": 3,
				"progress": clampf(_energy / ENERGY_MAX, 0.0, 1.0),
				"intensity": 0.75,
			}
		State.REPAIRING:
			return {
				"grid": current_grid(),
				"kind": 4,
				"progress": clampf(_condition / CONDITION_MAX, 0.0, 1.0),
				"intensity": 0.55,
			}
		State.MEDITATING:
			return {
				"grid": _activity_target if _activity_target != Vector2i.ZERO else current_grid(),
				"kind": 5,
				"progress": 1.0,
				"intensity": 0.65,
			}
	return {}


func _on_job_added(_added_job: Job) -> void:
	if _state == State.IDLE:
		_idle_cooldown = 0.0


func _on_job_cancelled(job: Job) -> void:
	if _job == job:
		_abandon_job(false)


func _on_tile_changed(grid: Vector2i, _new_tile: int) -> void:
	if _path.is_empty():
		return
	# If the changed tile lies on the remaining path, re-plan.
	for i in range(_path_index, _path.size()):
		var p: Vector2 = _path[i]
		var g := Vector2i(
			int(floor(p.x / Chunk.TILE_PIXELS)),
			int(floor(p.y / Chunk.TILE_PIXELS)),
		)
		if g == grid:
			_replan()
			return


func _process(delta: float) -> void:
	if _dead:
		return
	if _knockback_remaining > 0.0:
		var step: float = delta / KNOCKBACK_DURATION
		position += _knockback_vec * step
		_knockback_remaining = maxf(0.0, _knockback_remaining - delta)
		queue_redraw()
		return
	if _stun_remaining > 0.0:
		_stun_remaining = maxf(0.0, _stun_remaining - delta)
		return
	if _crowd_slow_remaining > 0.0:
		_crowd_slow_remaining = maxf(0.0, _crowd_slow_remaining - delta)
	if _door_slow_remaining > 0.0:
		_door_slow_remaining = maxf(0.0, _door_slow_remaining - delta)
	if _teleport_cooldown > 0.0:
		_teleport_cooldown = maxf(0.0, _teleport_cooldown - delta)
	if _blocked_action_timer > 0.0:
		_blocked_action_timer = maxf(0.0, _blocked_action_timer - delta)
	_update_energy(delta)
	_update_body_stats(delta)
	_tick_acid_damage(delta)
	_entity_grid_timer -= delta
	if _entity_grid_timer <= 0.0:
		_entity_grid_timer = ENTITY_GRID_SYNC_SECONDS
		EntityGrid.update_position(self, current_grid())
	if _state != State.FIGHTING and _should_seek_charge():
		_begin_auto_charge()
		return
	match _state:
		State.IDLE:
			if _try_start_next_direct_order():
				return
			_idle_cooldown -= delta
			if _idle_cooldown <= 0.0:
				_idle_cooldown = IDLE_RETRY_SECONDS
				if not _try_claim_job():
					_choose_idle_behavior()
		State.MOVING_TO_WORK:
			if _advance_path(delta):
				_state = State.WORKING
		State.WORKING:
			var work_delta: float = delta * _light_speed_multiplier()
			if _job is MineJob:
				var mine := _job as MineJob
				mine.progress += work_delta
				if mine.progress >= MineJob.DURATION:
					_complete_mine(mine)
			elif _is_scrape_rust_job(_job):
				var scrape_progress: float = float(_job.get("progress")) + work_delta
				_job.set("progress", scrape_progress)
				if scrape_progress >= SCRAPE_RUST_DURATION:
					_complete_scrape_rust(_job)
			elif _is_scrape_biomass_job(_job):
				var biomass_progress: float = float(_job.get("progress")) + work_delta
				_job.set("progress", biomass_progress)
				if biomass_progress >= SCRAPE_BIOMASS_DURATION:
					_complete_scrape_biomass(_job)
			else:
				_abandon_job()
				return
		State.MOVING_TO_PICKUP:
			if _advance_path(delta):
				_pickup_item()
		State.CARRYING, State.MOVING_TO_DROP:
			if _advance_path(delta):
				_drop_item()
		State.MOVING_TO_BUILD_SITE:
			if _advance_path(delta):
				_arrive_at_build_site()
		State.BUILDING:
			var build := _job as BuildJob
			if build == null:
				_abandon_job()
				return
			build.progress += delta * _light_speed_multiplier()
			if build.progress >= build.build_duration():
				_complete_build(build)
		State.MOVING_TO_CRAFT_SITE:
			if _advance_path(delta):
				if _job is OperateStructureJob:
					_arrive_at_operation_site()
				else:
					_arrive_at_craft_site()
		State.CRAFTING:
			if _job is OperateStructureJob:
				var op := _job as OperateStructureJob
				op.progress += delta * _light_speed_multiplier() * _workshop_room_speed_multiplier(op.anchor)
				if op.progress >= op.operate_duration():
					_complete_operation(op)
			else:
				var craft := _job as CraftJob
				if craft == null:
					_abandon_job()
					return
				craft.progress += delta * _light_speed_multiplier() * _workshop_room_speed_multiplier(craft.station_anchor)
				if craft.progress >= craft.craft_duration():
					_complete_craft(craft)
		State.MOVING_FREEFORM:
			if _advance_path(delta):
				_state = State.IDLE
				_idle_cooldown = 0.0
		State.ROAMING, State.WANDERING:
			if _advance_path(delta):
				_state = State.IDLE
				_idle_cooldown = randf_range(0.6, 2.0)
		State.MOVING_TO_CHARGE:
			if _advance_path(delta):
				_state = State.CHARGING
		State.CHARGING:
			_energy = minf(ENERGY_MAX, _energy + ENERGY_CHARGE_PER_SEC * delta)
			queue_redraw()
			if _energy >= ENERGY_MAX:
				_manual_charging = false
				_release_charge_reservation()
				_state = State.IDLE
				_idle_cooldown = 0.0
		State.MOVING_TO_REST:
			if _advance_path(delta):
				_state = State.RESTING
				_activity_timer = randf_range(3.0, 6.0)
		State.RESTING:
			_activity_timer -= delta
			var rest_rate: float = REST_RECOVERY_PER_SEC
			if _resting_in_assigned_dock_room():
				rest_rate *= ASSIGNED_DOCK_REST_MULTIPLIER
				_mood = clampf(_mood + ASSIGNED_DOCK_MOOD_PER_SEC * delta, 0.0, MOOD_MAX)
			_mental_tiredness = maxf(0.0, _mental_tiredness - rest_rate * delta)
			if _activity_timer <= 0.0 or _mental_tiredness <= 1.0:
				_state = State.IDLE
				_idle_cooldown = randf_range(0.5, 1.5)
		State.MOVING_TO_REPAIR:
			if _advance_path(delta):
				if _structure_manager != null and _structure_manager.has_method("consume_repair_materials"):
					_structure_manager.call("consume_repair_materials")
				_state = State.REPAIRING
				_activity_timer = randf_range(2.0, 4.0)
		State.REPAIRING:
			_activity_timer -= delta
			_condition = minf(CONDITION_MAX, _condition + REPAIR_RECOVERY_PER_SEC * delta)
			_repair_limbs(REPAIR_RECOVERY_PER_SEC * delta)
			if _activity_timer <= 0.0 or _condition >= CONDITION_MAX:
				_state = State.IDLE
				_idle_cooldown = randf_range(0.5, 1.5)
		State.MOVING_TO_SOCIALIZE:
			if _advance_path(delta):
				if _activity_partner != null and is_instance_valid(_activity_partner) and _is_adjacent_to(_activity_partner):
					_state = State.SOCIALIZING
					if _activity_timer <= 0.0:
						_activity_timer = randf_range(7.0, 12.0)
					_remember("chatting with %s" % _activity_partner.display_name())
				else:
					_remember("chat cancelled: not adjacent")
					_resume_after_chat()
		State.SOCIALIZING:
			_activity_timer -= delta
			var adjacent: bool = _activity_partner != null and is_instance_valid(_activity_partner) and _is_adjacent_to(_activity_partner)
			if adjacent:
				_social = clampf(_social + SOCIAL_GAIN_PER_SEC * delta, 0.0, SOCIAL_MAX)
				_activity_partner.add_social(SOCIAL_GAIN_PER_SEC * 0.5 * delta)
			if not adjacent or _activity_timer <= 0.0:
				if _activity_partner != null and is_instance_valid(_activity_partner):
					_remember("finished chat with %s" % _activity_partner.display_name())
				_resume_after_chat()
		State.MOVING_TO_MEDITATE:
			if _advance_path(delta):
				_state = State.MEDITATING
				_activity_timer = randf_range(8.0, 14.0)
				_wisdom_carry = 0.0
				_remember("began meditating")
		State.MEDITATING:
			_activity_timer -= delta
			var rate: float = WISDOM_PER_SEC
			if TechManager != null and TechManager.is_unlocked(TechDatabase.FOCUSED_MIND):
				rate *= WISDOM_FOCUSED_MULTIPLIER
			_wisdom_carry += rate * delta
			# Small mood lift while meditating.
			_mood = clampf(_mood + 0.4 * delta, 0.0, MOOD_MAX)
			if _activity_timer <= 0.0:
				if TechManager != null and _wisdom_carry > 0.0:
					TechManager.add_wisdom(_wisdom_carry)
					_remember("gained %.1f wisdom" % _wisdom_carry)
				_wisdom_carry = 0.0
				_state = State.IDLE
				_idle_cooldown = randf_range(0.6, 2.0)
		State.FIGHTING:
			_process_fighting(delta)
	_check_teleporter()
	_refresh_action_text()


func _process_fighting(delta: float) -> void:
	if not _target_alive():
		_combat_target = null
		_state = State.IDLE
		_idle_cooldown = 0.0
		_path = PackedVector2Array()
		_path_index = 0
		return
	var now: float = _now_seconds()
	var target_grid: Vector2i = (_combat_target as Node2D).call("current_grid") as Vector2i
	var cheb: int = maxi(absi(target_grid.x - current_grid().x), absi(target_grid.y - current_grid().y))
	if cheb <= stats.attack_range_tiles:
		_path = PackedVector2Array()
		_path_index = 0
		var swung: bool = CombatService.try_attack(self, _combat_target, stats, now)
		if swung:
			_last_combat_contact_at = now
		return
	_combat_repath_cooldown -= delta
	if _path.is_empty() or _path_index >= _path.size() or _combat_repath_cooldown <= 0.0:
		_repath_to_combat_target()
		_combat_repath_cooldown = COMBAT_REPATH_INTERVAL
	if _advance_path(delta):
		_path = PackedVector2Array()
		_path_index = 0
		_combat_repath_cooldown = 0.0
	if now - _last_combat_contact_at >= COMBAT_LOST_TIMEOUT:
		_combat_target = null
		_state = State.IDLE
		_idle_cooldown = 0.0
		_path = PackedVector2Array()
		_path_index = 0


func _try_claim_job() -> bool:
	if _job_board == null or _pathfinder == null:
		return false
	var job: Job = _job_board.claim_next_for(self, current_grid())
	if job == null:
		return false
	_job = job
	if job is MineJob:
		_begin_mine(job as MineJob)
	elif job is HaulJob:
		_begin_haul(job as HaulJob)
	elif job is BuildJob:
		_begin_build(job as BuildJob)
	elif job is CraftJob:
		_begin_craft(job as CraftJob)
	elif job is OperateStructureJob:
		_begin_operation(job as OperateStructureJob)
	elif _is_scrape_rust_job(job):
		_begin_scrape_rust(job)
	elif _is_scrape_biomass_job(job):
		_begin_scrape_biomass(job)
	return true


func _try_start_next_direct_order() -> bool:
	while not _direct_order_queue.is_empty():
		var order: Dictionary = _direct_order_queue.pop_front()
		if _start_direct_order(order):
			return true
	return false


func _start_direct_order(order: Dictionary) -> bool:
	var kind: StringName = order.get("kind", &"") as StringName
	match kind:
		ORDER_MOVE:
			return command_move(order.get("target", current_grid()) as Vector2i, false)
		ORDER_MINE:
			return command_mine(order.get("target", current_grid()) as Vector2i, false)
		ORDER_SCRAPE_RUST:
			return command_scrape_rust(order.get("target", current_grid()) as Vector2i, false)
		ORDER_SCRAPE_BIOMASS:
			return command_scrape_biomass(order.get("target", current_grid()) as Vector2i, false)
		ORDER_BUILD:
			return command_build(
				order.get("target", current_grid()) as Vector2i,
				int(order.get("blueprint_id", BuildBlueprint.Id.WALL)),
				false
			)
		ORDER_TAKE_BUILD_JOB:
			var anchor: Vector2i = order.get("anchor", Pathfinder.UNREACHABLE) as Vector2i
			var build: BuildJob = _job_board.build_job_at(anchor) if _job_board != null else null
			return command_take_build_job(build, false)
		ORDER_CHARGE:
			return command_charge(order.get("target", current_grid()) as Vector2i, false)
		ORDER_ATTACK:
			var target := order.get("target") as Node2D
			var stand: Vector2i = order.get("stand", Pathfinder.UNREACHABLE) as Vector2i
			return command_attack(target, stand, false)
	return false


func _enqueue_direct_order(order: Dictionary, label: String) -> bool:
	_direct_order_queue.append(order)
	_idle_cooldown = 0.0
	_remember("queued " + label)
	return true


func add_social(amount: float) -> void:
	_social = clampf(_social + amount, 0.0, SOCIAL_MAX)


func _remember(text: String) -> void:
	_history_index += 1
	_action_history.append("%03d  %s" % [_history_index, text])
	if _action_history.size() > ACTION_HISTORY_LIMIT:
		_action_history.pop_front()


func _init_limbs() -> void:
	for limb_name in LIMB_NAMES:
		_limbs[limb_name] = CONDITION_MAX


func _is_scrape_rust_job(job: Job) -> bool:
	return job != null and job.kind == Job.Kind.SCRAPE_RUST


func _is_scrape_biomass_job(job: Job) -> bool:
	return job != null and job.kind == Job.Kind.SCRAPE_BIOMASS


func _is_scrape_job(job: Job) -> bool:
	return _is_scrape_rust_job(job) or _is_scrape_biomass_job(job)


func _choose_idle_behavior() -> void:
	if _condition <= 68.0 and _begin_structure_activity(
			[BuildBlueprint.Id.REPAIR_BENCH, BuildBlueprint.Id.MAINTENANCE_DOCK],
			State.MOVING_TO_REPAIR):
		return
	if _mental_tiredness >= 55.0 and _begin_assigned_dock_rest():
		return
	var roll: float = randf()
	if roll < 0.14:
		if not _begin_idle_scrape_rust():
			_idle_cooldown = randf_range(1.0, 2.5)
	elif roll < 0.18:
		# Meditation: low-priority wisdom generator. Skipped silently if no pad exists.
		if not _begin_structure_activity([BuildBlueprint.Id.MEDITATION_PAD], State.MOVING_TO_MEDITATE):
			_idle_cooldown = randf_range(1.0, 2.5)
	elif roll < 0.30:
		_idle_cooldown = randf_range(1.2, 4.0)
	elif roll < 0.46:
		if not _begin_roam(false):
			_idle_cooldown = randf_range(1.0, 2.5)
	elif roll < 0.60:
		if not _begin_roam(true):
			_idle_cooldown = randf_range(1.0, 2.5)
	elif roll < 0.72:
		var outlet: Vector2i = _nearest_outlet_via_explored()
		if outlet != Pathfinder.UNREACHABLE and _energy < ENERGY_MAX:
			_begin_charge(outlet)
		else:
			_idle_cooldown = randf_range(1.0, 2.5)
	elif roll < 0.86:
		if not _begin_socialize():
			_idle_cooldown = randf_range(1.0, 2.5)
	elif roll < 0.96:
		if not _begin_assigned_dock_rest() and not _begin_structure_activity([BuildBlueprint.Id.DOCK, BuildBlueprint.Id.MAINTENANCE_DOCK], State.MOVING_TO_REST):
			_idle_cooldown = randf_range(1.0, 2.5)
	else:
		_idle_cooldown = randf_range(3.0, 7.0)


func _begin_idle_scrape_rust() -> bool:
	if _chunk_manager == null or _job_board == null or _pathfinder == null:
		return false
	var target: Vector2i = _chunk_manager.random_nearby_rust(
		current_grid(),
		IDLE_SCRAPE_RUST_RADIUS,
		_pathfinder,
		_fog,
	)
	if target == Pathfinder.UNREACHABLE or _job_board.has_scrape_rust_at(target):
		return false
	var job: Job = _job_board.add_scrape_rust_job(target)
	job.claimed_by = self
	_job = job
	_begin_scrape_rust(job)
	_remember("idle scrape rust %d,%d" % [target.x, target.y])
	return true


func _begin_roam(frontier: bool) -> bool:
	var target: Vector2i = _random_idle_target(frontier)
	if target == Pathfinder.UNREACHABLE:
		return false
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), target)
	if path.is_empty() and current_grid() != target:
		return false
	_path = path
	_path_index = 0
	_activity_target = target
	_state = State.WANDERING if frontier else State.ROAMING
	return true


func _random_idle_target(frontier: bool) -> Vector2i:
	if _fog == null:
		return _random_walkable_near(current_grid(), 12)
	var explored: Array[Vector2i] = _fog.explored_cells()
	if explored.is_empty():
		return Pathfinder.UNREACHABLE
	for _i in range(IDLE_SAMPLE_LIMIT):
		var candidate: Vector2i = explored[randi() % explored.size()]
		if frontier and not _fog.is_frontier(candidate):
			continue
		if not _chunk_manager.is_walkable(candidate):
			continue
		if candidate == current_grid():
			continue
		if _pathfinder.has_path(current_grid(), candidate):
			return candidate
	return Pathfinder.UNREACHABLE


func _random_walkable_near(origin: Vector2i, radius: int) -> Vector2i:
	for _i in range(IDLE_SAMPLE_LIMIT):
		var candidate := origin + Vector2i(randi_range(-radius, radius), randi_range(-radius, radius))
		if _chunk_manager.is_walkable(candidate) and _pathfinder.has_path(origin, candidate):
			return candidate
	return Pathfinder.UNREACHABLE


func _begin_structure_activity(ids: Array, next_state: int) -> bool:
	if _structure_manager == null:
		return false
	var anchor: Vector2i = _structure_manager.nearest_structure_anchor(ids, current_grid(), _pathfinder, _fog)
	if anchor == Pathfinder.UNREACHABLE:
		return false
	var target: Vector2i = _structure_manager.interaction_cell_for(anchor)
	if target == Pathfinder.UNREACHABLE:
		return false
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), target)
	if path.is_empty() and current_grid() != target:
		return false
	_path = path
	_path_index = 0
	_activity_target = anchor
	_state = next_state
	return true


func _begin_assigned_dock_rest() -> bool:
	if _room_manager == null or not _room_manager.has_method("dock_anchor_for"):
		return _begin_structure_activity([BuildBlueprint.Id.DOCK, BuildBlueprint.Id.MAINTENANCE_DOCK], State.MOVING_TO_REST)
	var anchor: Vector2i = _room_manager.call("dock_anchor_for", self) as Vector2i
	if anchor == Pathfinder.UNREACHABLE or _structure_manager == null:
		return _begin_structure_activity([BuildBlueprint.Id.DOCK, BuildBlueprint.Id.MAINTENANCE_DOCK], State.MOVING_TO_REST)
	var target: Vector2i = _structure_manager.interaction_cell_for(anchor)
	if target == Pathfinder.UNREACHABLE:
		return false
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), target)
	if path.is_empty() and current_grid() != target:
		return false
	_path = path
	_path_index = 0
	_activity_target = anchor
	_state = State.MOVING_TO_REST
	return true


func _resting_in_assigned_dock_room() -> bool:
	if _room_manager == null or not _room_manager.has_method("dock_anchor_for"):
		return false
	return (_room_manager.call("dock_anchor_for", self) as Vector2i) == _activity_target


func _begin_socialize() -> bool:
	var partner: Worker = _nearest_partner()
	if partner == null:
		return false
	var target: Vector2i = _adjacent_chat_cell_near(partner.current_grid(), current_grid())
	if target == Pathfinder.UNREACHABLE:
		return false
	var path: PackedVector2Array = _social_path_to_partner(partner, target)
	if path.is_empty() and current_grid() != target:
		return false
	var duration: float = randf_range(7.0, 12.0)
	if not partner.accept_chat_invite(self, partner.current_grid(), duration):
		return false
	_activity_partner = partner
	_activity_timer = duration
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_SOCIALIZE
	_remember("invited %s to chat" % partner.display_name())
	return true


func accept_chat_invite(partner: Worker, target: Vector2i, duration: float) -> bool:
	if partner == null or not is_instance_valid(partner):
		return false
	if _state == State.MOVING_TO_SOCIALIZE or _state == State.SOCIALIZING:
		return false
	if not _chunk_manager.is_walkable(target):
		return false
	var path: PackedVector2Array = _find_explored_path(current_grid(), target)
	if path.is_empty() and current_grid() != target:
		return false
	_suspend_for_chat()
	_activity_partner = partner
	_activity_timer = duration
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_SOCIALIZE
	_remember("paused work to chat with %s" % partner.display_name())
	return true


func _adjacent_chat_cell_near(center: Vector2i, from: Vector2i) -> Vector2i:
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var best: Vector2i = Pathfinder.UNREACHABLE
	var best_d: int = 0x7fffffff
	for off in OFFSETS:
		var candidate: Vector2i = center + off
		if not _chunk_manager.is_walkable(candidate):
			continue
		var d: int = maxi(absi(candidate.x - from.x), absi(candidate.y - from.y))
		if d < best_d:
			best = candidate
			best_d = d
	return best


func _is_adjacent_to(other: Worker) -> bool:
	var d: Vector2i = other.current_grid() - current_grid()
	return maxi(absi(d.x), absi(d.y)) <= SOCIAL_ADJACENCY_RANGE


func _suspend_for_chat() -> void:
	if _resume_job != null:
		return
	_resume_job = _job
	_resume_state = _state
	_resume_path = _path
	_resume_path_index = _path_index
	_resume_carried = _carried
	_release_charge_reservation()


func _resume_after_chat() -> void:
	var resume_job: Job = _resume_job
	var resume_state: int = _resume_state
	var resume_path: PackedVector2Array = _resume_path
	var resume_path_index: int = _resume_path_index
	_clear_activity()
	_resume_job = null
	_resume_state = State.IDLE
	_resume_path = PackedVector2Array()
	_resume_path_index = 0
	_resume_carried = null
	if resume_job != null and _job_board != null and _job_board.is_active(resume_job):
		_job = resume_job
		_state = resume_state
		_path = resume_path
		_path_index = mini(resume_path_index, resume_path.size())
		_replan()
		_idle_cooldown = 0.0
	else:
		_job = null
		_path = PackedVector2Array()
		_path_index = 0
		_state = State.IDLE
		_idle_cooldown = randf_range(0.8, 2.0)


func _nearest_partner() -> Worker:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return null
	var best: Worker = null
	var best_d: int = 0x7fffffff
	for child in parent_node.get_children():
		var worker := child as Worker
		if worker == null or worker == self:
			continue
		if _fog != null and not _fog.is_explored(worker.current_grid()):
			continue
		var d: int = maxi(
			absi(worker.current_grid().x - current_grid().x),
			absi(worker.current_grid().y - current_grid().y),
		)
		if d < best_d and _can_socialize_with(worker):
			best = worker
			best_d = d
	return best


func _can_socialize_with(partner: Worker) -> bool:
	var target: Vector2i = _adjacent_chat_cell_near(partner.current_grid(), current_grid())
	if target == Pathfinder.UNREACHABLE:
		return false
	if current_grid() == target:
		return true
	return not _social_path_to_partner(partner, target).is_empty()


func _social_path_to_partner(partner: Worker, target: Vector2i) -> PackedVector2Array:
	var direct: PackedVector2Array = _find_explored_path(current_grid(), target)
	if not direct.is_empty() or current_grid() == target:
		return direct
	return _teleporter_path_toward(partner.current_grid())


func _teleporter_path_toward(_partner_grid: Vector2i) -> PackedVector2Array:
	if _chunk_manager == null or not _chunk_manager.has_method("teleporter_cells"):
		return PackedVector2Array()
	var best_path: PackedVector2Array = PackedVector2Array()
	var best_d: int = 0x7fffffff
	var teleporters: Array[Vector2i] = _chunk_manager.call("teleporter_cells") as Array[Vector2i]
	for teleporter in teleporters:
		if _fog != null and not _fog.is_explored(teleporter):
			continue
		var path: PackedVector2Array = _find_explored_path(current_grid(), teleporter)
		if path.is_empty() and current_grid() != teleporter:
			continue
		var d: int = maxi(absi(teleporter.x - current_grid().x), absi(teleporter.y - current_grid().y))
		if d < best_d:
			best_path = path
			best_d = d
	return best_path


func _find_explored_path(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	if _pathfinder == null:
		return PackedVector2Array()
	var path: PackedVector2Array = _pathfinder.find_path(from, to)
	if path.is_empty():
		return path
	if _fog == null:
		return path
	for waypoint in path:
		var grid := Vector2i(
			int(floor(waypoint.x / Chunk.TILE_PIXELS)),
			int(floor(waypoint.y / Chunk.TILE_PIXELS)),
		)
		if not _fog.is_explored(grid):
			return PackedVector2Array()
	return path


func _begin_mine(job: MineJob) -> void:
	if not _is_mineable_target(job.target):
		_cancel_mine_job(job)
		return
	var stand: Vector2i = _mine_stand_for(job.target)
	if stand == Pathfinder.UNREACHABLE:
		job.block_briefly()
		_release_and_idle()
		return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), stand)
	if path.is_empty() and current_grid() != stand:
		job.block_briefly()
		_release_and_idle()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_WORK


func _begin_scrape_rust(job: Job) -> void:
	var target: Vector2i = job.get("target") as Vector2i
	if _chunk_manager.get_tile_at(target) != TerrainGenerator.TILE_RUST:
		if _job_board != null:
			_job_board.cancel_scrape_rust_at(target)
		_job = null
		_state = State.IDLE
		return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), target)
	if path.is_empty() and current_grid() != target:
		_release_and_idle()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_WORK


func _begin_scrape_biomass(job: Job) -> void:
	var target: Vector2i = job.get("target") as Vector2i
	if not _chunk_manager.has_grass(target):
		if _job_board != null:
			_job_board.cancel_scrape_biomass_at(target)
		_job = null
		_state = State.IDLE
		return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), target)
	if path.is_empty() and current_grid() != target:
		_release_and_idle()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_WORK


func _begin_haul(job: HaulJob) -> void:
	if job.item == null or not is_instance_valid(job.item):
		_finish_job()
		return
	var item_grid: Vector2i = (job.item as Item).get_grid()
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), item_grid)
	if path.is_empty() and current_grid() != item_grid:
		var item := job.item as Item
		_clear_job_reservations()
		_finish_job()
		if _stockpile_manager != null:
			_stockpile_manager.on_item_spawned(item)
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_PICKUP


func _begin_build(job: BuildJob) -> void:
	if job.has_all_materials():
		var stand_ready: Vector2i = _pathfinder.walkable_neighbor_of(job.anchor)
		if stand_ready == Pathfinder.UNREACHABLE:
			_release_and_idle()
			return
		var ready_path: PackedVector2Array = _pathfinder.find_path(current_grid(), stand_ready)
		if ready_path.is_empty() and current_grid() != stand_ready:
			_release_and_idle()
			return
		_path = ready_path
		_path_index = 0
		_state = State.MOVING_TO_BUILD_SITE
		return
	job.material_kind = job.next_missing_kind()
	# Build needs one missing material at a time. Find nearest unreserved item
	# of that kind from loose items or stockpiles, claim it as source.
	var source: Item = _find_material_for_build(job)
	if source == null:
		_note_missing_build_material(job)
		_release_and_idle()
		return
	job.source_item = source
	source.reserved_by = self
	# Phase 1: walk to the source item.
	var sg: Vector2i = source.get_grid()
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), sg)
	if path.is_empty() and current_grid() != sg:
		source.reserved_by = null
		_release_and_idle()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_PICKUP


func _find_material_for_build(job: BuildJob) -> Item:
	# Prefer loose items first (cheaper to grab).
	var best: Item = null
	var best_d: int = 0x7fffffff
	var origin: Vector2i = current_grid()
	if _items_root != null:
		for child in _items_root.get_children():
			var it := child as Item
			if it == null or it.reserved_by != null or it.kind != job.material_kind:
				continue
			if it.get_grid() != origin and not _pathfinder.has_path(origin, it.get_grid()):
				continue
			var d: int = maxi(absi(it.get_grid().x - origin.x), absi(it.get_grid().y - origin.y))
			if d < best_d:
				best = it
				best_d = d
	if best != null:
		return best
	# Fall back to stockpiled items.
	if _stockpile_manager != null:
		for zone in _stockpile_manager.zones:
			for cell in zone.cells:
				var occ: Variant = zone.occupant.get(cell)
				if occ is Item:
					var it2 := occ as Item
					if it2.reserved_by == null and it2.kind == job.material_kind:
						if cell != origin and not _pathfinder.has_path(origin, cell):
							continue
						var d2: int = maxi(absi(cell.x - origin.x), absi(cell.y - origin.y))
						if d2 < best_d:
							best = it2
							best_d = d2
	return best


func _begin_craft(job: CraftJob) -> void:
	if _structure_manager == null:
		_release_and_idle()
		return
	if job.has_all_materials():
		var stand_ready: Vector2i = _structure_manager.interaction_cell_for(job.station_anchor)
		if stand_ready == Pathfinder.UNREACHABLE:
			_release_and_idle()
			return
		var ready_path: PackedVector2Array = _pathfinder.find_path(current_grid(), stand_ready)
		if ready_path.is_empty() and current_grid() != stand_ready:
			_release_and_idle()
			return
		_path = ready_path
		_path_index = 0
		_state = State.MOVING_TO_CRAFT_SITE
		return
	job.material_kind = job.next_missing_kind()
	var source: Item = _find_material_for_craft(job)
	if source == null:
		_note_missing_craft_material(job)
		_release_and_idle()
		return
	job.source_item = source
	source.reserved_by = self
	var sg: Vector2i = source.get_grid()
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), sg)
	if path.is_empty() and current_grid() != sg:
		source.reserved_by = null
		_release_and_idle()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_PICKUP


func _find_material_for_craft(job: CraftJob) -> Item:
	var best: Item = null
	var best_d: int = 0x7fffffff
	var origin: Vector2i = current_grid()
	if _items_root != null:
		for child in _items_root.get_children():
			var it := child as Item
			if it == null or it.reserved_by != null or it.kind != job.material_kind:
				continue
			if it.get_grid() != origin and not _pathfinder.has_path(origin, it.get_grid()):
				continue
			var d: int = maxi(absi(it.get_grid().x - origin.x), absi(it.get_grid().y - origin.y))
			if d < best_d:
				best = it
				best_d = d
	if best != null:
		return best
	if _stockpile_manager != null:
		for zone in _stockpile_manager.zones:
			for cell in zone.cells:
				var occ: Variant = zone.occupant.get(cell)
				if occ is Item:
					var it2 := occ as Item
					if it2.reserved_by == null and it2.kind == job.material_kind:
						if cell != origin and not _pathfinder.has_path(origin, cell):
							continue
						var d2: int = maxi(absi(cell.x - origin.x), absi(cell.y - origin.y))
						if d2 < best_d:
							best = it2
							best_d = d2
	return best


func _begin_operation(job: OperateStructureJob) -> void:
	if _structure_manager == null:
		_release_and_idle()
		return
	if not _structure_manager.can_operate_structure(job.anchor):
		job.block_briefly(2.0)
		_release_and_idle()
		return
	if job.has_all_materials():
		var stand_ready: Vector2i = _structure_manager.interaction_cell_for(job.anchor)
		if stand_ready == Pathfinder.UNREACHABLE:
			_release_and_idle()
			return
		var ready_path: PackedVector2Array = _pathfinder.find_path(current_grid(), stand_ready)
		if ready_path.is_empty() and current_grid() != stand_ready:
			_release_and_idle()
			return
		_path = ready_path
		_path_index = 0
		_state = State.MOVING_TO_CRAFT_SITE
		return
	job.material_kind = job.next_missing_kind()
	var source: Item = _find_material_for_operation(job)
	if source == null:
		_note_missing_operation_material(job)
		_release_and_idle()
		return
	job.source_item = source
	source.reserved_by = self
	var sg: Vector2i = source.get_grid()
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), sg)
	if path.is_empty() and current_grid() != sg:
		source.reserved_by = null
		_release_and_idle()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_PICKUP


func _find_material_for_operation(job: OperateStructureJob) -> Item:
	var best: Item = null
	var best_d: int = 0x7fffffff
	var origin: Vector2i = current_grid()
	if _items_root != null:
		for child in _items_root.get_children():
			var it := child as Item
			if it == null or it.reserved_by != null or it.kind != job.material_kind:
				continue
			if it.get_grid() != origin and not _pathfinder.has_path(origin, it.get_grid()):
				continue
			var d: int = maxi(absi(it.get_grid().x - origin.x), absi(it.get_grid().y - origin.y))
			if d < best_d:
				best = it
				best_d = d
	if best != null:
		return best
	if _stockpile_manager != null:
		for zone in _stockpile_manager.zones:
			for cell in zone.cells:
				var occ: Variant = zone.occupant.get(cell)
				if occ is Item:
					var it2 := occ as Item
					if it2.reserved_by == null and it2.kind == job.material_kind:
						if cell != origin and not _pathfinder.has_path(origin, cell):
							continue
						var d2: int = maxi(absi(cell.x - origin.x), absi(cell.y - origin.y))
						if d2 < best_d:
							best = it2
							best_d = d2
	return best


func _pickup_item() -> void:
	if _job is HaulJob:
		_pickup_for_haul()
	elif _job is BuildJob:
		_pickup_for_build()
	elif _job is CraftJob:
		_pickup_for_craft()
	elif _job is OperateStructureJob:
		_pickup_for_operation()
	else:
		_abandon_job()


func _pickup_for_haul() -> void:
	var haul := _job as HaulJob
	if haul == null or haul.item == null or not is_instance_valid(haul.item):
		_finish_job()
		return
	var item := haul.item as Item
	haul.item = _take_stack_for_haul(item)
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), haul.dropoff)
	if path.is_empty() and current_grid() != haul.dropoff:
		_drop_in_place()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_DROP


func _pickup_for_build() -> void:
	var build := _job as BuildJob
	if build == null or build.source_item == null or not is_instance_valid(build.source_item):
		if build == null:
			_abandon_job()
			return
		build.source_item = null
		var replacement: Item = _find_material_for_build(build)
		if replacement == null:
			_note_missing_build_material(build)
			_release_and_idle()
			return
		build.source_item = replacement
		replacement.reserved_by = self
	var item := build.source_item as Item
	# If the source was in a stockpile cell, free that occupant slot.
	var src_parent: Node = item.get_parent()
	if src_parent is StockpileZone:
		(src_parent as StockpileZone).take(item.get_grid())
	# Carry only one unit; if the stack has more, leave the remainder loose.
	# The StockpileManager will re-haul it if a slot is available.
	if item.count > 1:
		var remainder: Item = ITEM_SCRIPT.new() as Item
		_items_root.add_child(remainder)
		remainder.setup(item.get_grid(), item.kind, item.count - 1)
		_stockpile_manager.on_item_spawned(remainder)
		item.count = 1
	_take_into_hand(item)
	# Phase 2: walk adjacent to the build anchor.
	var stand: Vector2i = _pathfinder.walkable_neighbor_of(build.anchor)
	if stand == Pathfinder.UNREACHABLE:
		_drop_in_place()
		return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), stand)
	if path.is_empty() and current_grid() != stand:
		_drop_in_place()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_BUILD_SITE


func _pickup_for_craft() -> void:
	var craft := _job as CraftJob
	if craft == null or craft.source_item == null or not is_instance_valid(craft.source_item):
		if craft == null:
			_abandon_job()
			return
		craft.source_item = null
		var replacement: Item = _find_material_for_craft(craft)
		if replacement == null:
			_note_missing_craft_material(craft)
			_release_and_idle()
			return
		craft.source_item = replacement
		replacement.reserved_by = self
	var item := craft.source_item as Item
	var src_parent: Node = item.get_parent()
	if src_parent is StockpileZone:
		(src_parent as StockpileZone).take(item.get_grid())
	if item.count > 1:
		var remainder: Item = ITEM_SCRIPT.new() as Item
		_items_root.add_child(remainder)
		remainder.setup(item.get_grid(), item.kind, item.count - 1)
		_stockpile_manager.on_item_spawned(remainder)
		item.count = 1
	_take_into_hand(item)
	var stand: Vector2i = _structure_manager.interaction_cell_for(craft.station_anchor) if _structure_manager != null else Pathfinder.UNREACHABLE
	if stand == Pathfinder.UNREACHABLE:
		_drop_in_place()
		return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), stand)
	if path.is_empty() and current_grid() != stand:
		_drop_in_place()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_CRAFT_SITE


func _pickup_for_operation() -> void:
	var op := _job as OperateStructureJob
	if op == null or op.source_item == null or not is_instance_valid(op.source_item):
		if op == null:
			_abandon_job()
			return
		op.source_item = null
		var replacement: Item = _find_material_for_operation(op)
		if replacement == null:
			_note_missing_operation_material(op)
			_release_and_idle()
			return
		op.source_item = replacement
		replacement.reserved_by = self
	var item := op.source_item as Item
	var src_parent: Node = item.get_parent()
	if src_parent is StockpileZone:
		(src_parent as StockpileZone).take(item.get_grid())
	if item.count > 1:
		var remainder: Item = ITEM_SCRIPT.new() as Item
		_items_root.add_child(remainder)
		remainder.setup(item.get_grid(), item.kind, item.count - 1)
		_stockpile_manager.on_item_spawned(remainder)
		item.count = 1
	_take_into_hand(item)
	var stand: Vector2i = _structure_manager.interaction_cell_for(op.anchor) if _structure_manager != null else Pathfinder.UNREACHABLE
	if stand == Pathfinder.UNREACHABLE:
		_drop_in_place()
		return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), stand)
	if path.is_empty() and current_grid() != stand:
		_drop_in_place()
		return
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_CRAFT_SITE


func _arrive_at_build_site() -> void:
	var build := _job as BuildJob
	if build == null:
		_abandon_job()
		return
	if _carried != null:
		var delivered_kind: int = _carried.kind
		remove_child(_carried)
		_carried.queue_free()
		_carried = null
		build.source_item = null
		build.accept_delivered(delivered_kind, 1)
	if build.has_all_materials():
		_state = State.BUILDING
		return
	_begin_build(build)


func _arrive_at_craft_site() -> void:
	var craft := _job as CraftJob
	if craft == null:
		_abandon_job()
		return
	if _carried != null:
		var delivered_kind: int = _carried.kind
		remove_child(_carried)
		_carried.queue_free()
		_carried = null
		craft.source_item = null
		craft.accept_delivered(delivered_kind, 1)
	if craft.has_all_materials():
		_state = State.CRAFTING
		return
	_begin_craft(craft)


func _arrive_at_operation_site() -> void:
	var op := _job as OperateStructureJob
	if op == null:
		_abandon_job()
		return
	if _carried != null:
		var delivered_kind: int = _carried.kind
		remove_child(_carried)
		_carried.queue_free()
		_carried = null
		op.source_item = null
		op.accept_delivered(delivered_kind, 1)
	if op.has_all_materials():
		_state = State.CRAFTING
		return
	_begin_operation(op)


func _take_into_hand(item: Item) -> void:
	_remember("picked up %s" % Item.stack_label(item.kind, item.count))
	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	add_child(item)
	item.position = Vector2.ZERO
	item.visible = false
	_carried = item


func _take_stack_for_haul(item: Item) -> Item:
	if item.count <= MAX_CARRY_STACK:
		_take_into_hand(item)
		return item
	var carried: Item = ITEM_SCRIPT.new() as Item
	carried.setup(item.get_grid(), item.kind, MAX_CARRY_STACK)
	item.count -= MAX_CARRY_STACK
	item.reserved_by = null
	item.queue_redraw()
	_take_into_hand(carried)
	if _stockpile_manager != null:
		_stockpile_manager.on_item_spawned(item)
	return carried


func _drop_item() -> void:
	var haul := _job as HaulJob
	if haul == null or _carried == null:
		_abandon_job()
		return
	var zone := haul.dropoff_zone as StockpileZone
	if zone == null or not is_instance_valid(zone) or not zone.contains_cell(haul.dropoff):
		_drop_in_place()
		return
	zone.unreserve(haul.dropoff)
	var delivered: Item = _carried
	var room: int = zone.room_at(haul.dropoff, delivered.kind)
	if room <= 0:
		_drop_in_place()
		return
	remove_child(_carried)
	zone.add_child(_carried)
	_carried.visible = true
	_carried.set_grid(haul.dropoff)
	var placed: Item = zone.place(delivered, haul.dropoff)
	var overflow: Item = null
	if is_instance_valid(delivered) and delivered != placed and delivered.count > 0:
		overflow = delivered
		zone.remove_child(overflow)
		_items_root.add_child(overflow)
		overflow.visible = true
		overflow.set_grid(current_grid())
		overflow.reserved_by = null
	placed.reserved_by = null
	_carried = null
	_remember("stored %s at %d,%d" % [Item.stack_label(placed.kind, placed.count), haul.dropoff.x, haul.dropoff.y])
	_finish_job()
	if _stockpile_manager != null:
		_stockpile_manager.stockpile_changed.emit()
		if overflow != null:
			_stockpile_manager.on_item_spawned(overflow)


func _drop_in_place() -> void:
	var haul := _job as HaulJob
	if haul != null and haul.dropoff_zone is StockpileZone:
		(haul.dropoff_zone as StockpileZone).unreserve(haul.dropoff)
	var dropped: Item = null
	if _carried != null:
		var here := current_grid()
		remove_child(_carried)
		_items_root.add_child(_carried)
		_carried.visible = true
		_carried.set_grid(here)
		_carried.reserved_by = null
		dropped = _carried
		_carried = null
	if (_job is BuildJob) or (_job is CraftJob) or (_job is OperateStructureJob):
		_release_and_idle()
	else:
		_finish_job()
	if dropped != null:
		_remember("dropped %s at %d,%d" % [Item.stack_label(dropped.kind, dropped.count), dropped.grid.x, dropped.grid.y])
	if dropped != null and _stockpile_manager != null:
		_stockpile_manager.on_item_spawned(dropped)


func _complete_mine(mine: MineJob) -> void:
	if _has_mineable_static_prop(mine.target):
		if _colony_site != null and _colony_site.has_method("mine_static_prop_at"):
			var rewards: Dictionary = _colony_site.call("mine_static_prop_at", mine.target) as Dictionary
			for kind in rewards.keys():
				var amount: int = int(rewards[kind])
				if amount > 0:
					_colony_site.call("spawn_item_at", mine.target, int(kind), amount)
		_remember("salvaged prop at %d,%d" % [mine.target.x, mine.target.y])
		_finish_job()
		return
	var mined_tile: int = _chunk_manager.get_tile_at(mine.target)
	_chunk_manager.set_tile_at(mine.target, TerrainGenerator.TILE_FLOOR)
	if _colony_site != null and _colony_site.has_method("spawn_item_at"):
		if randf() < 0.55:
			_colony_site.call("spawn_item_at", mine.target, Item.Kind.SCRAP)
		if randf() < 0.22:
			_colony_site.call("spawn_item_at", mine.target, Item.Kind.PLATING)
		if mined_tile == TerrainGenerator.TILE_SERVICE_CORE:
			if randf() < 0.50:
				_colony_site.call("spawn_item_at", mine.target, Item.Kind.PLATING)
			if randf() < 0.35:
				_colony_site.call("spawn_item_at", mine.target, Item.Kind.MECHANISM)
			if randf() < 0.18:
				_colony_site.call("spawn_item_at", mine.target, Item.Kind.DATACORE)
			if randf() < 0.08:
				_colony_site.call("spawn_item_at", mine.target, Item.Kind.CHARGE_CELL)
		elif mined_tile == TerrainGenerator.TILE_RICH_WALL:
			if randf() < 0.50:
				_colony_site.call("spawn_item_at", mine.target, Item.Kind.PLATING)
			if randf() < 0.18:
				_colony_site.call("spawn_item_at", mine.target, Item.Kind.DATACORE)
		elif randf() < 0.04:
			_colony_site.call("spawn_item_at", mine.target, Item.Kind.MECHANISM)
	_remember("mined %d,%d" % [mine.target.x, mine.target.y])
	_finish_job()


func _complete_scrape_rust(scrape: Job) -> void:
	var target: Vector2i = scrape.get("target") as Vector2i
	if _chunk_manager.get_tile_at(target) == TerrainGenerator.TILE_RUST:
		_chunk_manager.set_tile_at(target, TerrainGenerator.TILE_FLOOR)
		_remember("scraped rust at %d,%d" % [target.x, target.y])
	_finish_job()


func _complete_scrape_biomass(scrape: Job) -> void:
	var target: Vector2i = scrape.get("target") as Vector2i
	if _chunk_manager.has_grass(target):
		_chunk_manager.clear_grass(target)
		if _colony_site != null and _colony_site.has_method("spawn_item_at") and randf() < 0.60:
			_colony_site.call("spawn_item_at", target, Item.Kind.BIOMASS, 1)
		_remember("scraped biomass at %d,%d" % [target.x, target.y])
	_finish_job()


func _complete_build(build: BuildJob) -> void:
	# Convert the completed blueprint to terrain or static object.
	if _carried != null:
		remove_child(_carried)
		_carried.queue_free()
		_carried = null
	if build.blueprint_id == BuildBlueprint.Id.WALL:
		_chunk_manager.set_tile_at(build.anchor, TerrainGenerator.TILE_WALL)
	elif _colony_site != null and _colony_site.has_method("build_structure"):
		_colony_site.call("build_structure", build.blueprint_id, build.anchor, build.rotation)
	_remember("built %s at %d,%d" % [
		BuildBlueprint.display_name(build.blueprint_id),
		build.anchor.x,
		build.anchor.y,
	])
	_finish_job()


func _complete_craft(craft: CraftJob) -> void:
	if _structure_manager == null or not _structure_manager.spawn_crafted_object(craft.station_anchor, craft.object_kind):
		craft.block_briefly(2.0)
		_show_blocked_action("Output blocked")
		_release_and_idle()
		return
	_remember("crafted %s at %d,%d" % [
		Item.kind_name(craft.object_kind),
		craft.station_anchor.x,
		craft.station_anchor.y,
	])
	_finish_job()


func _complete_operation(op: OperateStructureJob) -> void:
	if _structure_manager == null or not _structure_manager.complete_operation(op.anchor):
		op.block_briefly(2.0)
		_show_blocked_action("Output blocked")
		_release_and_idle()
		return
	_remember("operated %s at %d,%d" % [
		BuildBlueprint.display_name(op.structure_id),
		op.anchor.x,
		op.anchor.y,
	])
	_finish_job()


func _finish_job() -> void:
	_release_charge_reservation()
	if _job != null and _job_board != null:
		_job_board.complete(_job)
	_job = null
	_path = PackedVector2Array()
	_path_index = 0
	_state = State.IDLE
	_idle_cooldown = 0.0
	_clear_activity()
	_clear_resume()


func _release_and_idle() -> void:
	_release_charge_reservation()
	_clear_job_reservations()
	if _job != null and _job_board != null and _job_board.is_active(_job):
		_job_board.release(_job)
	_job = null
	_path = PackedVector2Array()
	_path_index = 0
	_state = State.IDLE
	_idle_cooldown = IDLE_RETRY_SECONDS
	_clear_activity()
	_clear_resume()


func _note_missing_build_material(job: BuildJob) -> void:
	job.block_briefly(2.0)
	var item_name: String = Item.kind_name(job.material_kind)
	_show_blocked_action("Lacks " + item_name)
	_remember("lacks %s for %s" % [item_name, BuildBlueprint.display_name(job.blueprint_id)])


func _note_missing_craft_material(job: CraftJob) -> void:
	job.block_briefly(2.0)
	var item_name: String = Item.kind_name(job.material_kind)
	_show_blocked_action("Lacks " + item_name)
	_remember("lacks %s to craft %s" % [item_name, Item.kind_name(job.object_kind)])


func _note_missing_operation_material(job: OperateStructureJob) -> void:
	job.block_briefly(2.0)
	var item_name: String = Item.kind_name(job.material_kind)
	_show_blocked_action("Lacks " + item_name)
	_remember("lacks %s to operate %s" % [item_name, BuildBlueprint.display_name(job.structure_id)])


func _abandon_job(release_claim: bool = true) -> void:
	# Used when the job was cancelled or invalid mid-flight. Drop anything
	# carried in place so we don't lose the item.
	_release_charge_reservation()
	_clear_job_reservations()
	var dropped: Item = null
	if _carried != null:
		var here := current_grid()
		remove_child(_carried)
		_items_root.add_child(_carried)
		_carried.visible = true
		_carried.set_grid(here)
		_carried.reserved_by = null
		dropped = _carried
		_carried = null
	var rematch_item: Item = null
	if release_claim and _job != null and _job_board != null and _job_board.is_active(_job):
		if _job is HaulJob:
			var haul := _job as HaulJob
			if haul.item != null and is_instance_valid(haul.item):
				rematch_item = haul.item as Item
			_job_board.complete(_job)
		else:
			_job_board.release(_job)
	_job = null
	_path = PackedVector2Array()
	_path_index = 0
	_state = State.IDLE
	_idle_cooldown = IDLE_RETRY_SECONDS
	_clear_activity()
	_clear_resume()
	if dropped != null and _stockpile_manager != null:
		_stockpile_manager.on_item_spawned(dropped)
	elif rematch_item != null and _stockpile_manager != null:
		_stockpile_manager.on_item_spawned(rematch_item)


func _cancel_mine_job(job: MineJob) -> void:
	if _job_board != null and _job_board.has_mine_at(job.target):
		_job_board.cancel_mine_at(job.target)
	_job = null
	_path = PackedVector2Array()
	_path_index = 0
	_state = State.IDLE
	_idle_cooldown = IDLE_RETRY_SECONDS
	_clear_activity()


func _release_charge_reservation() -> void:
	if _chunk_manager != null and _has_charge_reservation:
		_chunk_manager.release_outlet(_charge_target, self)
	_charge_target = Vector2i.ZERO
	_has_charge_reservation = false


func _clear_job_reservations() -> void:
	if _job is HaulJob:
		var haul := _job as HaulJob
		if haul.dropoff_zone is StockpileZone:
			(haul.dropoff_zone as StockpileZone).unreserve(haul.dropoff)
		if haul.item != null and is_instance_valid(haul.item):
			(haul.item as Item).reserved_by = null
	elif _job is BuildJob:
		var build := _job as BuildJob
		if build.source_item != null and is_instance_valid(build.source_item):
			(build.source_item as Item).reserved_by = null
	elif _job is CraftJob:
		var craft := _job as CraftJob
		if craft.source_item != null and is_instance_valid(craft.source_item):
			(craft.source_item as Item).reserved_by = null
	elif _job is OperateStructureJob:
		var op := _job as OperateStructureJob
		if op.source_item != null and is_instance_valid(op.source_item):
			(op.source_item as Item).reserved_by = null


func _clear_activity() -> void:
	_activity_timer = 0.0
	_activity_target = Vector2i.ZERO
	_activity_partner = null


func _clear_resume() -> void:
	_resume_job = null
	_resume_state = State.IDLE
	_resume_path = PackedVector2Array()
	_resume_path_index = 0
	_resume_carried = null


func _show_blocked_action(text: String) -> void:
	_blocked_action_text = text
	_blocked_action_timer = BLOCKED_ACTION_SECONDS
	queue_redraw()


func show_order_failed(text: String) -> void:
	_show_blocked_action(text)
	_remember("order failed: " + text.to_lower())


func _replan() -> void:
	if _job == null:
		if (_state == State.MOVING_FREEFORM \
				or _state == State.ROAMING \
				or _state == State.WANDERING \
				or _state == State.MOVING_TO_REST \
				or _state == State.MOVING_TO_REPAIR \
				or _state == State.MOVING_TO_SOCIALIZE \
				or _state == State.MOVING_TO_MEDITATE) and _path.size() > 0:
			# Try to re-path to the final waypoint.
			var dest_pixel: Vector2 = _path[_path.size() - 1]
			var dest: Vector2i = Vector2i(
				int(floor(dest_pixel.x / Chunk.TILE_PIXELS)),
				int(floor(dest_pixel.y / Chunk.TILE_PIXELS)),
			)
			var p: PackedVector2Array = _pathfinder.find_path(current_grid(), dest)
			if p.is_empty():
				_state = State.IDLE
				_path = PackedVector2Array()
				_path_index = 0
				return
			_path = p
			_path_index = 0
		return
	var target_grid: Vector2i
	match _state:
		State.MOVING_TO_WORK:
			if _job is MineJob:
				var mine_job := _job as MineJob
				var stand: Vector2i = _reachable_neighbor_of(mine_job.target)
				if stand == Pathfinder.UNREACHABLE:
					_cancel_mine_job(mine_job)
					return
				target_grid = stand
			elif _is_scrape_job(_job):
				target_grid = _job.get("target") as Vector2i
			else:
				return
		State.MOVING_TO_PICKUP:
			if _job is HaulJob:
				target_grid = (_job as HaulJob).item.call("get_grid") as Vector2i
			elif _job is BuildJob:
				target_grid = ((_job as BuildJob).source_item as Item).get_grid()
			elif _job is CraftJob:
				target_grid = ((_job as CraftJob).source_item as Item).get_grid()
			elif _job is OperateStructureJob:
				target_grid = ((_job as OperateStructureJob).source_item as Item).get_grid()
			else:
				return
		State.CARRYING, State.MOVING_TO_DROP:
			target_grid = (_job as HaulJob).dropoff
		State.MOVING_TO_BUILD_SITE:
			var b_stand: Vector2i = _pathfinder.walkable_neighbor_of((_job as BuildJob).anchor)
			if b_stand == Pathfinder.UNREACHABLE:
				if _carried != null:
					_drop_in_place()
				else:
					_release_and_idle()
				return
			target_grid = b_stand
		State.MOVING_TO_CRAFT_SITE:
			var op_anchor: Vector2i = (_job as OperateStructureJob).anchor if _job is OperateStructureJob else (_job as CraftJob).station_anchor
			var c_stand: Vector2i = _structure_manager.interaction_cell_for(op_anchor) if _structure_manager != null else Pathfinder.UNREACHABLE
			if c_stand == Pathfinder.UNREACHABLE:
				if _carried != null:
					_drop_in_place()
				else:
					_release_and_idle()
				return
			target_grid = c_stand
		_:
			return
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), target_grid)
	if path.is_empty() and current_grid() != target_grid:
		# Lost reachability. Carrying? Drop it. Otherwise release.
		if _carried != null:
			_drop_in_place()
		else:
			_release_and_idle()
		return
	_path = path
	_path_index = 0


func _reachable_neighbor_of(grid: Vector2i) -> Vector2i:
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var origin: Vector2i = current_grid()
	for off in OFFSETS:
		var candidate: Vector2i = grid + off
		if not _chunk_manager.is_walkable(candidate):
			continue
		if candidate == origin or _pathfinder.has_path(origin, candidate):
			return candidate
	return Pathfinder.UNREACHABLE


func _is_mineable_target(target: Vector2i) -> bool:
	if _has_mineable_static_prop(target):
		return true
	var tile: int = _chunk_manager.get_tile_at(target)
	return tile == TerrainGenerator.TILE_WALL \
		or tile == TerrainGenerator.TILE_SERVICE_CORE \
		or tile == TerrainGenerator.TILE_RICH_WALL


func _has_mineable_static_prop(target: Vector2i) -> bool:
	return _colony_site != null \
		and _colony_site.has_method("has_mineable_static_prop") \
		and bool(_colony_site.call("has_mineable_static_prop", target))


func _mine_stand_for(target: Vector2i) -> Vector2i:
	if _has_mineable_static_prop(target) \
			and _colony_site != null \
			and _colony_site.has_method("static_prop_mine_stand_for"):
		return _colony_site.call("static_prop_mine_stand_for", target, current_grid(), _pathfinder) as Vector2i
	return _reachable_neighbor_of(target)


# ----- Direct orders from the player ---------------------------------------

func queue_command_move(target: Vector2i) -> bool:
	if not _chunk_manager.is_walkable(target):
		show_order_failed("Blocked tile")
		return false
	return _enqueue_direct_order({
		"kind": ORDER_MOVE,
		"target": target,
	}, "move to %d,%d" % [target.x, target.y])


func queue_command_mine(target: Vector2i) -> bool:
	if not _is_mineable_target(target):
		return false
	return _enqueue_direct_order({
		"kind": ORDER_MINE,
		"target": target,
	}, "mine %d,%d" % [target.x, target.y])


func queue_command_scrape_rust(target: Vector2i) -> bool:
	if _chunk_manager.get_tile_at(target) != TerrainGenerator.TILE_RUST:
		return false
	return _enqueue_direct_order({
		"kind": ORDER_SCRAPE_RUST,
		"target": target,
	}, "scrape rust %d,%d" % [target.x, target.y])


func queue_command_scrape_biomass(target: Vector2i) -> bool:
	if not _chunk_manager.has_grass(target):
		return false
	return _enqueue_direct_order({
		"kind": ORDER_SCRAPE_BIOMASS,
		"target": target,
	}, "scrape biomass %d,%d" % [target.x, target.y])


func queue_command_build(target: Vector2i, blueprint_id: int = BuildBlueprint.Id.WALL) -> bool:
	return _enqueue_direct_order({
		"kind": ORDER_BUILD,
		"target": target,
		"blueprint_id": blueprint_id,
	}, "build %s at %d,%d" % [BuildBlueprint.display_name(blueprint_id), target.x, target.y])


func queue_command_take_build_job(job: BuildJob) -> bool:
	if job == null:
		return false
	return _enqueue_direct_order({
		"kind": ORDER_TAKE_BUILD_JOB,
		"anchor": job.anchor,
	}, "build %s at %d,%d" % [BuildBlueprint.display_name(job.blueprint_id), job.anchor.x, job.anchor.y])


func queue_command_charge(target: Vector2i) -> bool:
	if not _chunk_manager.is_outlet(target):
		return false
	return _enqueue_direct_order({
		"kind": ORDER_CHARGE,
		"target": target,
	}, "charge at %d,%d" % [target.x, target.y])


func queue_command_attack(target: Node2D, preferred_stand: Vector2i = Pathfinder.UNREACHABLE) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return _enqueue_direct_order({
		"kind": ORDER_ATTACK,
		"target": target,
		"stand": preferred_stand,
	}, "attack %s" % _target_label(target))


func command_move(target: Vector2i, clear_queue: bool = true) -> bool:
	if not _chunk_manager.is_walkable(target):
		show_order_failed("Blocked tile")
		return false
	var path: PackedVector2Array = _pathfinder.find_path(current_grid(), target)
	if path.is_empty() and current_grid() != target:
		show_order_failed("No path")
		return false
	# Abort whatever we were doing only after destination is valid.
	if clear_queue:
		_direct_order_queue.clear()
	_abandon_job()
	_path = path
	_path_index = 0
	_state = State.MOVING_FREEFORM
	_remember("ordered to move to %d,%d" % [target.x, target.y])
	return true


func command_mine(target: Vector2i, clear_queue: bool = true) -> bool:
	# Add a mine designation (if needed) and immediately take it for ourselves.
	# If something else already had this job claimed, cancelling drops their
	# claim cleanly via the job_cancelled signal.
	if not _is_mineable_target(target):
		return false
	if clear_queue:
		_direct_order_queue.clear()
	_abandon_job()
	if _job_board.has_mine_at(target):
		_job_board.cancel_mine_at(target)
	var job: MineJob = _job_board.add_mine_job(target)
	job.claimed_by = self
	_job = job
	_remember("ordered to mine %d,%d" % [target.x, target.y])
	_begin_mine(job)
	return true


func command_scrape_rust(target: Vector2i, clear_queue: bool = true) -> bool:
	if _chunk_manager.get_tile_at(target) != TerrainGenerator.TILE_RUST:
		return false
	if clear_queue:
		_direct_order_queue.clear()
	_abandon_job()
	if _job_board.has_scrape_rust_at(target):
		_job_board.cancel_scrape_rust_at(target)
	var job: Job = _job_board.add_scrape_rust_job(target)
	job.claimed_by = self
	_job = job
	_remember("ordered to scrape rust %d,%d" % [target.x, target.y])
	_begin_scrape_rust(job)
	return true


func command_scrape_biomass(target: Vector2i, clear_queue: bool = true) -> bool:
	if not _chunk_manager.has_grass(target):
		return false
	if clear_queue:
		_direct_order_queue.clear()
	_abandon_job()
	if _job_board.has_scrape_biomass_at(target):
		_job_board.cancel_scrape_biomass_at(target)
	var job: Job = _job_board.add_scrape_biomass_job(target)
	job.claimed_by = self
	_job = job
	_remember("ordered to scrape biomass %d,%d" % [target.x, target.y])
	_begin_scrape_biomass(job)
	return true


func command_build(
	target: Vector2i,
	blueprint_id: int = BuildBlueprint.Id.WALL,
	clear_queue: bool = true
) -> bool:
	if _colony_site != null and _colony_site.has_method("can_place_blueprint"):
		if not (_colony_site.call("can_place_blueprint", blueprint_id, target) as bool):
			return false
	elif not _chunk_manager.is_walkable(target):
		return false
	if clear_queue:
		_direct_order_queue.clear()
	_abandon_job()
	if _job_board.has_build_at(target):
		_job_board.cancel_build_at(target)
	var job: BuildJob = _job_board.add_build_job(target, blueprint_id)
	job.claimed_by = self
	_job = job
	_remember("ordered to build %s at %d,%d" % [
		BuildBlueprint.display_name(blueprint_id),
		target.x,
		target.y,
	])
	_begin_build(job)
	return true


func command_take_build_job(job: BuildJob, clear_queue: bool = true) -> bool:
	if job == null or _job_board == null or not _job_board.is_active(job):
		return false
	if clear_queue:
		_direct_order_queue.clear()
	_abandon_job()
	if not _job_board.force_claim(job, self):
		return false
	_job = job
	_remember("ordered to build %s at %d,%d" % [
		BuildBlueprint.display_name(job.blueprint_id),
		job.anchor.x,
		job.anchor.y,
	])
	_begin_build(job)
	return true


func command_charge(target: Vector2i, clear_queue: bool = true) -> bool:
	if not _chunk_manager.is_outlet(target):
		return false
	if _fog != null and not _fog.is_explored(target):
		return false
	if clear_queue:
		_direct_order_queue.clear()
	_abandon_job()
	_manual_charging = true
	_remember("ordered to charge at %d,%d" % [target.x, target.y])
	return _begin_charge(target)


func _advance_path(delta: float) -> bool:
	if _path.is_empty():
		return true
	if _path_index >= _path.size():
		return true
	var speed_mult: float = CROWD_SLOW_MULTIPLIER if _crowd_slow_remaining > 0.0 else 1.0
	if _door_slow_remaining > 0.0:
		speed_mult *= DOOR_SLOW_MULTIPLIER
	speed_mult *= _light_speed_multiplier()
	speed_mult *= _water_speed_multiplier()
	var step: float = MOVE_SPEED_PX_PER_SEC * speed_mult * delta
	while step > 0.0 and _path_index < _path.size():
		var target: Vector2 = _path[_path_index]
		var target_grid := Vector2i(
			int(floor(target.x / Chunk.TILE_PIXELS)),
			int(floor(target.y / Chunk.TILE_PIXELS)),
		)
		if _structure_manager != null:
			var structure: Dictionary = _structure_manager.structure_at(target_grid)
			if not structure.is_empty() and int(structure["id"]) == BuildBlueprint.Id.DOOR:
				_structure_manager.request_door_open(target_grid)
				if not _structure_manager.is_door_open(target_grid):
					return false
				if _last_door_slow_cell != target_grid:
					_last_door_slow_cell = target_grid
					_door_slow_remaining = DOOR_SLOW_SECONDS
		var to_target: Vector2 = target - position
		var dist: float = to_target.length()
		if dist > ARRIVE_EPSILON_PX:
			_set_facing_from_vector(to_target)
		if dist <= step + ARRIVE_EPSILON_PX:
			position = target
			step -= dist
			_path_index += 1
		else:
			position += to_target / dist * step
			step = 0.0
	_update_crowding_contacts()
	return _path_index >= _path.size()


func _light_speed_multiplier() -> float:
	if _structure_manager == null or not _structure_manager.has_method("light_speed_multiplier_at"):
		return 1.0
	return clampf(float(_structure_manager.call("light_speed_multiplier_at", current_grid())), 1.0, 1.5)


## Speed multiplier applied to crafts/operations at a workshop. Workshop Room
## adds a small bonus; standing outside any room imposes a small penalty. The
## room manager queries by the workshop's anchor cell so multi-tile workshops
## get a consistent reading.
func _workshop_room_speed_multiplier(anchor: Vector2i) -> float:
	if _room_manager == null or not _room_manager.has_method("workshop_speed_multiplier_at"):
		return 1.0
	return clampf(float(_room_manager.call("workshop_speed_multiplier_at", anchor)), 0.5, 1.5)


## Drains limb integrity while standing on acid tiles. Damage is accumulated
## so sub-HP-per-frame ticks don't get rounded away by `_damage_limb`.
func _tick_acid_damage(delta: float) -> void:
	if _chunk_manager == null:
		return
	var tile: int = _chunk_manager.get_tile_at(current_grid())
	var dps: float = 0.0
	var mood_drain: float = 0.0
	if tile == TerrainGenerator.TILE_ACID_SHALLOW:
		dps = ACID_SHALLOW_DPS
		mood_drain = ACID_SHALLOW_MOOD_DRAIN_PER_SEC
	elif tile == TerrainGenerator.TILE_ACID_PUDDLE:
		dps = ACID_PUDDLE_DPS
		mood_drain = ACID_PUDDLE_MOOD_DRAIN_PER_SEC
	elif tile == TerrainGenerator.TILE_ACID:
		dps = ACID_DEEP_DPS
		mood_drain = ACID_DEEP_MOOD_DRAIN_PER_SEC
	if dps <= 0.0:
		_acid_damage_accum = 0.0
		return
	# Standing on acid is miserable — drain mood every frame while exposed.
	if mood_drain > 0.0:
		_mood = maxf(0.0, _mood - mood_drain * delta)
	_acid_damage_accum += dps * delta
	if _acid_damage_accum >= 1.0:
		var whole: float = floorf(_acid_damage_accum)
		_acid_damage_accum -= whole
		_damage_limb(whole)
		# Spike mood every time acid burns enough to register HP loss.
		_mood = maxf(0.0, _mood - ACID_MOOD_SPIKE_PER_HP * whole)


## Shallow water/acid and puddles slow the worker; deep variants are impassable
## so the pathfinder never lands a worker on them.
func _water_speed_multiplier() -> float:
	if _chunk_manager == null:
		return 1.0
	var tile: int = _chunk_manager.get_tile_at(current_grid())
	if tile == TerrainGenerator.TILE_WATER_SHALLOW:
		return WATER_SHALLOW_SPEED_MULT
	if tile == TerrainGenerator.TILE_WATER_PUDDLE:
		return WATER_PUDDLE_SPEED_MULT
	if tile == TerrainGenerator.TILE_ACID_SHALLOW:
		return ACID_SHALLOW_SPEED_MULT
	if tile == TerrainGenerator.TILE_ACID_PUDDLE:
		return ACID_PUDDLE_SPEED_MULT
	return 1.0


func _set_facing_from_vector(delta_pos: Vector2) -> void:
	var ax: float = absf(delta_pos.x)
	var ay: float = absf(delta_pos.y)
	if ax > ay * 2.0:
		_facing = FACING_EAST if delta_pos.x > 0.0 else FACING_WEST
	elif ay > ax * 2.0:
		_facing = FACING_SOUTH if delta_pos.y > 0.0 else FACING_NORTH
	elif delta_pos.x > 0.0:
		_facing = FACING_SOUTH_EAST if delta_pos.y > 0.0 else FACING_NORTH_EAST
	else:
		_facing = FACING_SOUTH_WEST if delta_pos.y > 0.0 else FACING_NORTH_WEST
	queue_redraw()


func apply_crowding_slow() -> void:
	_crowd_slow_remaining = CROWD_SLOW_SECONDS


func _update_crowding_contacts() -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var here: Vector2i = current_grid()
	var seen: Dictionary = {}
	var cells: Dictionary = _crowd_cells_for(parent_node)
	var occupants: Array = cells.get(here, []) as Array
	for occupant in occupants:
		var other := occupant as Worker
		if other == null or other == self or not is_instance_valid(other):
			continue
		seen[other] = true
		if _crowd_contacts.has(other):
			continue
		_crowd_contacts[other] = true
		apply_crowding_slow()
		other.apply_crowding_slow()
	for other in _crowd_contacts.keys():
		if not seen.has(other):
			_crowd_contacts.erase(other)


func _crowd_cells_for(parent_node: Node) -> Dictionary:
	var frame: int = Engine.get_process_frames()
	if int(parent_node.get_meta(CROWD_FRAME_META, -1)) == frame:
		return parent_node.get_meta(CROWD_CELLS_META, {}) as Dictionary
	var cells: Dictionary = {}
	for child in parent_node.get_children():
		var worker := child as Worker
		if worker == null or not is_instance_valid(worker):
			continue
		var grid: Vector2i = worker.current_grid()
		var bucket: Array = cells.get(grid, []) as Array
		bucket.append(worker)
		cells[grid] = bucket
	parent_node.set_meta(CROWD_FRAME_META, frame)
	parent_node.set_meta(CROWD_CELLS_META, cells)
	return cells


func _update_energy(delta: float) -> void:
	var drain: float = ENERGY_IDLE_DRAIN_PER_SEC
	match _state:
		State.MOVING_TO_WORK, State.MOVING_TO_PICKUP, State.CARRYING, \
		State.MOVING_TO_DROP, State.MOVING_TO_BUILD_SITE, State.MOVING_TO_CRAFT_SITE, State.MOVING_FREEFORM, \
		State.MOVING_TO_CHARGE, State.ROAMING, State.WANDERING, \
		State.MOVING_TO_REST, State.MOVING_TO_REPAIR, State.MOVING_TO_SOCIALIZE, \
		State.MOVING_TO_MEDITATE:
			drain = ENERGY_MOVE_DRAIN_PER_SEC
		State.WORKING, State.BUILDING, State.CRAFTING, State.FIGHTING:
			drain = ENERGY_WORK_DRAIN_PER_SEC
		State.CHARGING, State.RESTING, State.MEDITATING:
			drain = 0.0
	_energy = clampf(_energy - drain * delta, 0.0, ENERGY_MAX)
	queue_redraw()


func _update_body_stats(delta: float) -> void:
	var condition_decay: float = 0.0
	match _state:
		State.MOVING_TO_WORK, State.MOVING_TO_PICKUP, State.CARRYING, \
		State.MOVING_TO_DROP, State.MOVING_TO_BUILD_SITE, State.MOVING_TO_CRAFT_SITE, State.MOVING_FREEFORM, \
		State.MOVING_TO_CHARGE, State.ROAMING, State.WANDERING, \
		State.MOVING_TO_REST, State.MOVING_TO_REPAIR, State.MOVING_TO_SOCIALIZE, \
		State.MOVING_TO_MEDITATE:
			condition_decay = CONDITION_MOVE_DECAY_PER_SEC * delta
			_mental_tiredness = minf(MENTAL_TIRED_MAX, _mental_tiredness + MENTAL_IDLE_RISE_PER_SEC * delta)
		State.WORKING, State.BUILDING, State.CRAFTING:
			condition_decay = CONDITION_WORK_DECAY_PER_SEC * delta
			_mental_tiredness = minf(MENTAL_TIRED_MAX, _mental_tiredness + MENTAL_WORK_RISE_PER_SEC * delta)
		State.RESTING:
			pass
		State.MEDITATING:
			# Meditation slowly lowers mental exhaustion as a side benefit.
			_mental_tiredness = maxf(0.0, _mental_tiredness - REST_RECOVERY_PER_SEC * 0.4 * delta)
		_:
			_mental_tiredness = minf(MENTAL_TIRED_MAX, _mental_tiredness + MENTAL_IDLE_RISE_PER_SEC * delta)
	# Social slowly decays unless actively chatting.
	if _state != State.SOCIALIZING:
		_social = maxf(0.0, _social - SOCIAL_DECAY_PER_SEC * delta)
	_update_mood(delta)
	if condition_decay <= 0.0:
		return
	if _chunk_manager != null and _chunk_manager.get_tile_at(current_grid()) == TerrainGenerator.TILE_RUST:
		condition_decay *= RUST_CONDITION_DECAY_MULTIPLIER
	_condition = maxf(0.0, _condition - condition_decay)
	_damage_limb(condition_decay)


func _update_mood(delta: float) -> void:
	_needs_refresh_timer -= delta
	if _needs_refresh_timer <= 0.0:
		_needs_refresh_timer = NEEDS_REFRESH_SECONDS
		_refresh_unsatisfied_needs()
	# Mood drift: recover toward baseline, but suffer per unsatisfied need.
	var target: float = MOOD_BASELINE
	if _social < 25.0:
		target -= 8.0
	if _mental_tiredness > 70.0:
		target -= 10.0
	if _condition < 50.0:
		target -= 6.0
	var penalty: float = float(_unsatisfied_needs.size()) * MOOD_NEED_DECAY_PER_SEC
	if _mood < target:
		_mood = minf(MOOD_MAX, _mood + MOOD_RECOVERY_PER_SEC * delta)
	if penalty > 0.0:
		_mood = maxf(0.0, _mood - penalty * delta)
	# Hard ceiling clamp.
	_mood = clampf(_mood, 0.0, MOOD_MAX)


func _refresh_unsatisfied_needs() -> void:
	_unsatisfied_needs.clear()
	if _room_manager != null and _room_manager.has_method("ensure_dock_room_for"):
		_room_manager.call("ensure_dock_room_for", self)
		var has_room: bool = false
		if _room_manager.has_method("has_dock_room"):
			has_room = bool(_room_manager.call("has_dock_room", self))
		if not has_room:
			_unsatisfied_needs.append("Needs dock room")


func _damage_limb(amount: float) -> void:
	if _limbs.is_empty():
		return
	var limb_name: String = LIMB_NAMES[randi() % LIMB_NAMES.size()]
	_limbs[limb_name] = maxf(0.0, float(_limbs.get(limb_name, CONDITION_MAX)) - amount * 1.6)


func _repair_limbs(amount: float) -> void:
	for limb_name in LIMB_NAMES:
		_limbs[limb_name] = minf(CONDITION_MAX, float(_limbs.get(limb_name, CONDITION_MAX)) + amount)


func repair_limbs_external(amount: float) -> void:
	if amount <= 0.0:
		return
	_repair_limbs(amount)
	_condition = minf(CONDITION_MAX, _condition + amount * 0.35)


func _check_teleporter() -> void:
	if _chunk_manager == null or _teleport_cooldown > 0.0:
		return
	var here: Vector2i = current_grid()
	if here == _last_teleporter_grid:
		return
	if not _chunk_manager.is_teleporter(here):
		_last_teleporter_grid = Pathfinder.UNREACHABLE
		return
	var target: Vector2i = _chunk_manager.random_linked_teleporter(here)
	if target == Pathfinder.UNREACHABLE:
		return
	position = Chunk.grid_to_pixel_center(target)
	_path = PackedVector2Array()
	_path_index = 0
	_teleport_cooldown = TELEPORT_COOLDOWN_SECONDS
	_last_teleporter_grid = target
	_remember("teleported from %d,%d to %d,%d" % [here.x, here.y, target.x, target.y])
	if _job == null:
		if _state == State.MOVING_TO_SOCIALIZE or _state == State.SOCIALIZING:
			if not _repath_socialize_after_teleport():
				_resume_after_chat()
		else:
			_state = State.IDLE
			_idle_cooldown = IDLE_RETRY_SECONDS
	else:
		_replan()
	queue_redraw()


func _repath_socialize_after_teleport() -> bool:
	if _activity_partner == null or not is_instance_valid(_activity_partner):
		return false
	var target: Vector2i = _adjacent_chat_cell_near(_activity_partner.current_grid(), current_grid())
	if target == Pathfinder.UNREACHABLE:
		return false
	var path: PackedVector2Array = _find_explored_path(current_grid(), target)
	if path.is_empty() and current_grid() != target:
		return false
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_SOCIALIZE
	return true


func _should_seek_charge() -> bool:
	if _state == State.MOVING_TO_CHARGE or _state == State.CHARGING:
		return false
	if _manual_charging:
		return false
	if _energy <= ENERGY_CRITICAL:
		return true
	return _state == State.IDLE and _energy <= ENERGY_LOW


func _begin_auto_charge() -> void:
	var outlet: Vector2i = _nearest_outlet_via_explored()
	if outlet == Pathfinder.UNREACHABLE:
		# No known route to any outlet. Fall back to walking toward a known
		# teleporter so the bot doesn't sit and die; the teleport scatter
		# might land it next to a known outlet on the next idle tick.
		if _begin_charge_via_teleporter():
			return
		return
	_abandon_job()
	_manual_charging = false
	_begin_charge(outlet)


## Picks the closest outlet reachable through fog-explored cells only. Bots
## must not magically know the path through undiscovered areas — if the
## only route to an outlet crosses fog, that outlet is hidden from auto and
## manual recharge planning.
func _nearest_outlet_via_explored() -> Vector2i:
	if _chunk_manager == null:
		return Pathfinder.UNREACHABLE
	var here: Vector2i = current_grid()
	var best: Vector2i = Pathfinder.UNREACHABLE
	var best_d: int = 0x7fffffff
	for outlet in _chunk_manager.outlet_cells():
		if _fog != null and not _fog.is_explored(outlet):
			continue
		if _chunk_manager.is_outlet_reserved_by_other(outlet, self):
			continue
		var d_chebyshev: int = maxi(absi(outlet.x - here.x), absi(outlet.y - here.y))
		if d_chebyshev >= best_d:
			continue
		var path: PackedVector2Array = _find_explored_path(here, outlet)
		if path.is_empty() and here != outlet:
			continue
		best = outlet
		best_d = d_chebyshev
	return best


## Routes the worker to the nearest known teleporter when no outlet is
## reachable via known terrain. Once arrived, `_check_teleporter()` performs
## the random hop; if it lands near a known outlet on a future idle tick,
## the worker will auto-charge there.
func _begin_charge_via_teleporter() -> bool:
	if _chunk_manager == null or _pathfinder == null:
		return false
	if not _chunk_manager.has_method("teleporter_cells"):
		return false
	var here: Vector2i = current_grid()
	var teleporters: Array[Vector2i] = _chunk_manager.call("teleporter_cells") as Array[Vector2i]
	var best_path: PackedVector2Array = PackedVector2Array()
	var best_d: int = 0x7fffffff
	for teleporter in teleporters:
		if _fog != null and not _fog.is_explored(teleporter):
			continue
		var path: PackedVector2Array = _find_explored_path(here, teleporter)
		if path.is_empty() and here != teleporter:
			continue
		var d: int = maxi(absi(teleporter.x - here.x), absi(teleporter.y - here.y))
		if d < best_d:
			best_path = path
			best_d = d
	if best_path.is_empty():
		return false
	_abandon_job()
	_manual_charging = false
	_path = best_path
	_path_index = 0
	# Treat the walk-to-teleporter trip as a recharge attempt so the HUD
	# shows the right action text and idle pacing kicks in after the hop.
	_state = State.MOVING_TO_CHARGE
	_charge_target = Vector2i.ZERO
	_has_charge_reservation = false
	return true


func _begin_charge(outlet: Vector2i) -> bool:
	if not _chunk_manager.reserve_outlet(outlet, self):
		_manual_charging = false
		return false
	var path: PackedVector2Array = _find_explored_path(current_grid(), outlet)
	if path.is_empty() and current_grid() != outlet:
		_chunk_manager.release_outlet(outlet, self)
		_manual_charging = false
		_state = State.IDLE
		_idle_cooldown = IDLE_RETRY_SECONDS
		return false
	_charge_target = outlet
	_has_charge_reservation = true
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_CHARGE
	return true


func _refresh_action_text() -> void:
	var next_text: String = ""
	if _blocked_action_timer > 0.0:
		next_text = _blocked_action_text
	else:
		match _state:
			State.MOVING_TO_WORK:
				if _is_scrape_biomass_job(_job):
					next_text = "Moving to biomass"
				elif _is_scrape_rust_job(_job):
					next_text = "Moving to rust"
				else:
					next_text = "Moving to mine"
			State.WORKING:
				if _is_scrape_biomass_job(_job):
					next_text = "Scraping biomass"
				elif _is_scrape_rust_job(_job):
					next_text = "Scraping rust"
				else:
					next_text = "Mining"
			State.MOVING_TO_PICKUP:
				if _job is BuildJob:
					next_text = "Getting " + Item.kind_name((_job as BuildJob).material_kind)
				elif _job is CraftJob:
					next_text = "Getting " + Item.kind_name((_job as CraftJob).material_kind)
				elif _job is OperateStructureJob:
					next_text = "Getting " + Item.kind_name((_job as OperateStructureJob).material_kind)
				elif _job is HaulJob:
					next_text = "Getting item"
			State.CARRYING, State.MOVING_TO_DROP:
				if _carried != null:
					next_text = "Hauling " + Item.kind_name(_carried.kind)
				else:
					next_text = "Hauling"
			State.MOVING_TO_BUILD_SITE:
				next_text = "Delivering"
			State.BUILDING:
				if _job is BuildJob:
					next_text = "Building " + BuildBlueprint.display_name((_job as BuildJob).blueprint_id)
				else:
					next_text = "Building"
			State.MOVING_TO_CRAFT_SITE:
				next_text = "Moving to operate" if _job is OperateStructureJob else "Delivering"
			State.CRAFTING:
				if _job is OperateStructureJob:
					next_text = "Operating " + BuildBlueprint.display_name((_job as OperateStructureJob).structure_id)
				elif _job is CraftJob:
					next_text = "Crafting " + Item.kind_name((_job as CraftJob).object_kind)
				else:
					next_text = "Crafting"
			State.MOVING_FREEFORM:
				next_text = "Moving"
			State.MOVING_TO_CHARGE:
				next_text = "Moving to recharge"
			State.CHARGING:
				next_text = "Charging"
			State.ROAMING:
				next_text = "Roaming"
			State.WANDERING:
				next_text = "Wandering"
			State.MOVING_TO_REST:
				next_text = "Moving to dock"
			State.RESTING:
				next_text = "Resting"
			State.MOVING_TO_REPAIR:
				next_text = "Moving to repair"
			State.REPAIRING:
				next_text = "Repairing"
			State.MOVING_TO_SOCIALIZE:
				next_text = "Moving to chat"
			State.SOCIALIZING:
				next_text = "Chatting"
			State.MOVING_TO_MEDITATE:
				next_text = "Moving to meditate"
			State.MEDITATING:
				next_text = "Meditating"
			State.FIGHTING:
				next_text = "Fighting"
			State.DEAD:
				next_text = ""
	if _action_text == next_text:
		return
	_action_text = next_text
	if not next_text.is_empty():
		_remember(next_text.to_lower())
	queue_redraw()


func _draw() -> void:
	_draw_action_bubble()
	if _selected:
		draw_circle(Vector2.ZERO, BODY_RADIUS + 3.0, Color(0, 0, 0, 0))
		draw_arc(Vector2.ZERO, BODY_RADIUS + 3.0, 0.0, TAU, 24, SELECTION_COLOR, 1.0)
	if _entity_atlas != null:
		var atlas_cell: Vector2i = _facing_atlas_cell()
		var source := Rect2(
			Vector2(atlas_cell.x * int(ENTITY_REGION_SIZE.x), atlas_cell.y * int(ENTITY_REGION_SIZE.y)),
			ENTITY_REGION_SIZE,
		)
		draw_texture_rect_region(_entity_atlas, Rect2(-ENTITY_REGION_SIZE * 0.5, ENTITY_REGION_SIZE), source)
	else:
		draw_circle(Vector2.ZERO, BODY_RADIUS, BODY_COLOR)
	if _carried != null:
		draw_circle(Vector2(0, -BODY_RADIUS - 2), 2.0, Item.kind_color(_carried.kind))
	var bar_pos := Vector2(-BODY_RADIUS, BODY_RADIUS + 3.0)
	var bar_size := Vector2(BODY_RADIUS * 2.0, 2.0)
	draw_rect(Rect2(bar_pos, bar_size), BATTERY_BG)
	var fill_color: Color = BATTERY_LOW if _energy <= ENERGY_LOW else BATTERY_GOOD
	draw_rect(Rect2(bar_pos, Vector2(bar_size.x * (_energy / ENERGY_MAX), bar_size.y)), fill_color)
	if stats != null and stats.hp < stats.max_hp:
		var hp_pos := Vector2(-BODY_RADIUS, BODY_RADIUS + 6.0)
		draw_rect(Rect2(hp_pos, bar_size), BATTERY_BG)
		draw_rect(Rect2(hp_pos, Vector2(bar_size.x * stats.hp_ratio(), bar_size.y)), Color(0.95, 0.30, 0.30))


func _draw_action_bubble() -> void:
	if _action_text.is_empty():
		return
	var font: Font = ACTION_FONT
	var text_size := font.get_string_size(_action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ACTION_FONT_SIZE)
	var pad := Vector2(4, 3)
	var screen_scale: Vector2 = get_global_transform_with_canvas().get_scale()
	if is_zero_approx(screen_scale.x) or is_zero_approx(screen_scale.y):
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 / screen_scale.x, 1.0 / screen_scale.y))
	var origin := Vector2(
		roundf(ACTION_BUBBLE_SCREEN_OFFSET.x - text_size.x * 0.5 - pad.x),
		roundf(ACTION_BUBBLE_SCREEN_OFFSET.y - BODY_RADIUS - text_size.y - pad.y),
	)
	var rect := Rect2(origin, text_size + pad * 2.0)
	draw_rect(rect, Color(0.02, 0.02, 0.03, 0.82))
	draw_rect(rect, Color(0.9, 0.9, 1.0, 0.6), false, 1.0)
	draw_string(font, origin + Vector2(pad.x, text_size.y + pad.y - 1.0),
		_action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ACTION_FONT_SIZE, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _facing_atlas_cell() -> Vector2i:
	match _facing:
		FACING_SOUTH_EAST:
			return Vector2i(1, 0)
		FACING_EAST:
			return Vector2i(2, 0)
		FACING_NORTH_EAST:
			return Vector2i(0, 1)
		FACING_NORTH:
			return Vector2i(1, 1)
		FACING_NORTH_WEST:
			return Vector2i(2, 1)
		FACING_WEST:
			return Vector2i(0, 2)
		FACING_SOUTH_WEST:
			return Vector2i(1, 2)
		_:
			return Vector2i(0, 0)
