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
	# Rescue states: a non-downed worker carries a downed worker to an outlet
	# or repair bench. MOVING_TO_SAVE = walking to the downed body;
	# CARRYING_WORKER = downed has been picked up; MOVING_TO_DELIVER = the
	# carrier is en route to the chosen delivery point.
	MOVING_TO_SAVE,
	CARRYING_WORKER,
	MOVING_TO_DELIVER,
	REBOOTING,
	DEAD,
}

enum Personality {
	DUTIFUL,
	GRUMPY,
	CHEERFUL,
	PHILOSOPHICAL,
	PARANOID,
	STOIC,
	NOSTALGIC,
	COMPETITIVE,
	GLITCHY,
}

## Order matches Personality and WorkerLines flavour buckets 1:1.
const PERSONALITY_LABELS: Array[String] = [
	"Dutiful", "Grumpy", "Cheerful", "Philosophical", "Paranoid", "Stoic",
	"Nostalgic", "Competitive", "Glitchy",
]

const CombatStatsScript: Script = preload("res://scripts/combat/CombatStats.gd")
const CombatService: Script = preload("res://scripts/combat/CombatService.gd")
const MINING_SFX: AudioStream = preload("res://mining_sound.mp3")
const MOVING_SFX: AudioStream = preload("res://bot_moving_sound.mp3")
## Positional sound max_distance (px) at camera zoom 1.0. Scaled by zoom updates.
const SOUND_BASE_MAX_DIST: float = 400.0
const COMBAT_HP_MAX: float = 100.0
const COMBAT_REPATH_INTERVAL: float = 0.5
const COMBAT_LOST_TIMEOUT: float = 3.0
const KNOCKBACK_DURATION: float = 0.12
const FACTION_COLONY: int = 0

const MOVE_SPEED_PX_PER_SEC: float = 68.0
const WATER_SHALLOW_SPEED_MULT: float = 0.3
const WATER_PUDDLE_SPEED_MULT: float = 0.55
const ACID_SHALLOW_SPEED_MULT: float = 0.3
const ACID_PUDDLE_SPEED_MULT: float = 0.2
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
const IDLE_RETRY_SECONDS: float = 0.25
const IDLE_FALLBACK_RETRY_SECONDS: float = 0.6
const BODY_RADIUS: float = 12.0
const BODY_COLOR := Color(0.85, 0.85, 0.95)
const SELECTION_COLOR := Color(1.0, 0.95, 0.4, 0.55)
const ITEM_SCRIPT: Script = preload("res://scripts/colony/Item.gd")
const MAX_CARRY_STACK: int = 4
const ENERGY_MAX: float = 100.0
const ENERGY_LOW: float = 28.0
const ENERGY_CRITICAL: float = 10.0
const ENERGY_IDLE_DRAIN_PER_SEC: float = 0.05
const ENERGY_MOVE_DRAIN_PER_SEC: float = 0.1
const ENERGY_WORK_DRAIN_PER_SEC: float = 0.3
const ENERGY_CHARGE_PER_SEC: float = 2.0
const ENERGY_SLOW_THRESHOLD: float = 50.0
const ENERGY_LOW_MODE_THRESHOLD: float = 15.0
const ENERGY_LOW_MODE_DRAIN_MULT: float = 0.5
const ENERGY_LOW_MODE_SPEED_MULT: float = 0.45
const ENERGY_RECHARGE_MIN_THRESHOLD: float = 30.0
const ENERGY_RECHARGE_MAX_THRESHOLD: float = 55.0
const BATTERY_BG := Color(0.05, 0.05, 0.06, 0.9)
const BATTERY_GOOD := Color(0.3, 0.9, 0.55)
const BATTERY_LOW := Color(1.0, 0.78, 0.2)
const ACTION_FONT_SIZE: int = 12
const NAME_FONT_SIZE: int = 11
const ENTITY_ATLAS_PATH := "res://resources/entities/worker_atlas.png"
const HIGHLIGHTER_ATLAS_PATH := "res://resources/entities/Highlighters.png"
const ACTION_FONT: Font = preload("res://resources/Orbitron-VariableFont_wght.ttf")
const ENTITY_REGION_SIZE := Vector2(32, 32)
## Highlight cell indices in Highlighters.png (96x32, 3 cells of 32x32).
const HIGHLIGHT_CELL_GREY: int = 0   ## move order
const HIGHLIGHT_CELL_GREEN: int = 1  ## charge / repair order
const HIGHLIGHT_CELL_RED: int = 2    ## attack order
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
const CONDITION_MOVE_DECAY_PER_SEC: float = 0.010
const CONDITION_WORK_DECAY_PER_SEC: float = 0.05
const MENTAL_IDLE_RISE_PER_SEC: float = 0.04
const MENTAL_WORK_RISE_PER_SEC: float = 0.16
const REST_RECOVERY_PER_SEC: float = 8.0
const REPAIR_RECOVERY_PER_SEC: float = 1.6
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
const WISDOM_PER_SEC: float = 0.28
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
const ORDER_SAVE := &"save"
## Throttle for RoomManager interaction in _update_mood; per-frame calls
## were O(workers * rooms) and dominated `_process` cost.
const NEEDS_REFRESH_SECONDS: float = 0.5
## Throttle for EntityGrid bucket sync; cheap dict op but no point per-frame.
const ENTITY_GRID_SYNC_SECONDS: float = 0.25
const AI_DECISION_SECONDS: float = 0.22
const AI_DECISION_JITTER_SECONDS: float = 0.08
const ROUTE_CACHE_MSEC: int = 450
const STUCK_WATCHDOG_SECONDS: float = 3.0
const STUCK_PROGRESS_EPSILON_PX: float = 0.5

var _personality: int = Personality.DUTIFUL
## Display name override from an embark loadout (falls back to the node name).
var _display_name: String = ""
## Equipped build + skills, set by apply_loadout. Empty until/unless loadout-spawned.
var _loadout: WorkerLoadout = null
var _skills: Dictionary = {}
## Derived stats. Defaults equal the pre-parts balance so workers spawned WITHOUT
## a loadout (cradle, neutral conversions, legacy saves) behave exactly as before.
## apply_loadout overwrites these from PartDatabase + skills + personality.
var _move_speed: float = MOVE_SPEED_PX_PER_SEC
var _work_speed_mult: float = 1.0
var _mine_speed_mult: float = 1.0
var _build_speed_mult: float = 1.0
var _carry_capacity: int = MAX_CARRY_STACK
var _armor: float = 0.0
var _sight_bonus: int = 0
var _energy_recharge_mult: float = 1.0
var _energy_drain_mult: float = 1.0
var _wisdom_mult: float = 1.0
var _mood_baseline: float = MOOD_BASELINE
var _mood_recovery_mult: float = 1.0
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
## Per-equipped-part condition, keyed by SLOT_LAYOUT index → 0..CONDITION_MAX.
## Only equipped slots are tracked; a part-less shell has none (its overall
## `_condition` meter covers wear instead). Combat/acid/wear damage a random
## equipped part; docks repair them.
var _part_conditions: Dictionary = {}
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
var _ai_decision_timer: float = 0.0
var _acid_damage_accum: float = 0.0
var _last_action_state: int = -1
var _last_action_job: Job = null
var _last_sound_state: int = -1
var _last_sound_job: Job = null
var _mining_player: AudioStreamPlayer2D
var _moving_player: AudioStreamPlayer2D
var _last_energy_for_draw: float = ENERGY_MAX
var _highlighter_atlas: Texture2D
## Alert threshold tracking — reset when stat recovers above the threshold band.
var _energy_alert_25_sent: bool = false
var _energy_alert_10_sent: bool = false
var _condition_alert_25_sent: bool = false
var _condition_alert_10_sent: bool = false
var _route_cache: Dictionary = {}
var _stuck_watchdog_timer: float = 0.0
var _stuck_last_position: Vector2 = Vector2.INF
var _no_repair_bench_complaint_timer: float = 0.0
var _research_urge_cooldown: float = 0.0
var _paused: bool = false
var _failed_jobs_cooldowns: Dictionary = {}
# Rescue (save downed worker) state. The carrier holds a reference to the
# downed worker plus the cell it intends to drop them off in. While carried,
# `_carried_worker` is reparented to the carrier and hidden.
var _carried_worker: Worker = null
var _save_target: Worker = null
var _save_destination: Vector2i = Pathfinder.UNREACHABLE
var _save_destination_kind: int = -1   ## BuildBlueprint.Id of the destination structure, or -1 for stockpile/outlet tile
const REBOOT_CONDITION_THRESHOLD: float = 0.5
const SAVE_REVIVE_CONDITION: float = 30.0
const SAVE_REVIVE_ENERGY: float = 35.0
const DOWNED_NONE := &""
const DOWNED_ENERGY := &"energy"
const DOWNED_CONDITION := &"condition"
const DOWNED_BOTH := &"both"
var _downed_reason: StringName = DOWNED_NONE
var _teleport_charge_cooldown: float = 0.0
# Fix for Rescue carry state tracking
var carried_by: Worker = null
var _door_stuck_timer: float = 0.0
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
	_highlighter_atlas = load(HIGHLIGHTER_ATLAS_PATH) as Texture2D
	_ai_decision_timer = randf_range(0.0, AI_DECISION_SECONDS)
	_personality = randi() % PERSONALITY_LABELS.size()
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
		if _job_board.has_signal("job_added"):
			_job_board.job_added.connect(_on_job_added)
	EventBus.tile_changed.connect(_on_tile_changed)
	EntityGrid.register(self, FACTION_COLONY, current_grid())
	tree_exiting.connect(_on_tree_exiting)
	_setup_audio_players()
	_remember("online at %d,%d" % [current_grid().x, current_grid().y])


func _on_tree_exiting() -> void:
	EntityGrid.unregister(self)


func _setup_audio_players() -> void:
	_mining_player = AudioStreamPlayer2D.new()
	_mining_player.stream = MINING_SFX
	_mining_player.volume_db = -6.0
	_mining_player.bus = &"SFX"
	_mining_player.max_distance = AudioManager.current_max_dist
	add_child(_mining_player)
	_mining_player.finished.connect(func() -> void:
		if _state == State.WORKING and _job is MineJob:
			_mining_player.play()
	)

	_moving_player = AudioStreamPlayer2D.new()
	_moving_player.stream = MOVING_SFX
	_moving_player.volume_db = -10.0
	_moving_player.bus = &"SFX"
	_moving_player.max_distance = AudioManager.current_max_dist
	add_child(_moving_player)
	_moving_player.finished.connect(func() -> void:
		if _is_moving_sound_state(_state):
			_moving_player.play()
	)

	EventBus.camera_moved.connect(_on_worker_camera_moved)
	EventBus.game_speed_changed.connect(_on_game_speed_changed)


func _on_game_speed_changed(_speed: float) -> void:
	_update_sounds()


func _on_worker_camera_moved(_world_pos: Vector2, zoom: Vector2) -> void:
	var zoom_factor: float = (zoom.x + zoom.y) * 0.5
	# Scale WITH zoom so zoomed-out view silences individual worker sounds.
	var dist: float = SOUND_BASE_MAX_DIST * clampf(zoom_factor, 0.1, 2.0)
	_mining_player.max_distance = dist
	_moving_player.max_distance = dist


func _update_sounds() -> void:
	if GameState.is_paused():
		if _mining_player.playing:
			_mining_player.stop()
		if _moving_player.playing:
			_moving_player.stop()
		return

	var should_mine: bool = _state == State.WORKING and _job is MineJob
	if should_mine:
		if not _mining_player.playing:
			_mining_player.play()
	elif _mining_player.playing:
		_mining_player.stop()

	var should_move: bool = _is_moving_sound_state(_state)
	if should_move:
		if not _moving_player.playing:
			_moving_player.play()
	elif _moving_player.playing:
		_moving_player.stop()


func _check_energy_alerts() -> void:
	if _dead:
		return
	var ratio: float = _energy / ENERGY_MAX
	# Reset flags when energy recovers above threshold bands.
	if ratio > 0.3:
		_energy_alert_25_sent = false
	if ratio > 0.15:
		_energy_alert_10_sent = false
	if ratio <= 0.25 and not _energy_alert_25_sent:
		_energy_alert_25_sent = true
		EventBus.worker_low_energy.emit(self, ratio)
	elif ratio <= 0.10 and not _energy_alert_10_sent:
		_energy_alert_10_sent = true
		EventBus.worker_low_energy.emit(self, ratio)


func _check_condition_alerts() -> void:
	if _dead:
		return
	var ratio: float = _condition / CONDITION_MAX
	if ratio > 0.3:
		_condition_alert_25_sent = false
	if ratio > 0.15:
		_condition_alert_10_sent = false
	if ratio <= 0.25 and not _condition_alert_25_sent:
		_condition_alert_25_sent = true
		EventBus.worker_low_condition.emit(self, ratio)
	elif ratio <= 0.10 and not _condition_alert_10_sent:
		_condition_alert_10_sent = true
		EventBus.worker_low_condition.emit(self, ratio)


func _is_moving_sound_state(s: int) -> bool:
	return s == State.MOVING_TO_WORK \
		or s == State.MOVING_TO_PICKUP \
		or s == State.CARRYING \
		or s == State.MOVING_TO_DROP \
		or s == State.MOVING_TO_BUILD_SITE \
		or s == State.MOVING_TO_CRAFT_SITE \
		or s == State.MOVING_FREEFORM \
		or s == State.MOVING_TO_CHARGE \
		or s == State.ROAMING \
		or s == State.WANDERING \
		or s == State.MOVING_TO_REST \
		or s == State.MOVING_TO_REPAIR \
		or s == State.MOVING_TO_SOCIALIZE \
		or s == State.MOVING_TO_MEDITATE \
		or s == State.MOVING_TO_SAVE \
		or s == State.CARRYING_WORKER \
		or s == State.MOVING_TO_DELIVER


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
	# Armor (from Utility parts / personality) soaks a flat amount, but a hit
	# always lands for at least a sliver so heavy armor isn't full immunity.
	var taken: float = maxf(0.5, amount - _armor)
	stats.hp = maxf(0.0, stats.hp - taken)
	_damage_part(taken / 1.6)
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
			var path: PackedVector2Array = _find_explored_path(current_grid(), preferred_stand)
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
	var path: PackedVector2Array = _find_explored_path(current_grid(), stand)
	if path.is_empty():
		_path = PackedVector2Array()
		_path_index = 0
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
	if _mining_player != null:
		_mining_player.stop()
	if _moving_player != null:
		_moving_player.stop()
	# If we were mid-rescue, drop the rescued worker here (still downed) so
	# another teammate can pick the save back up where the carrier fell.
	if _carried_worker != null and is_instance_valid(_carried_worker):
		_carried_worker.carried_by = null # Drop safely if dead
		_carried_worker.position = position
		_carried_worker.visible = true
		_carried_worker = null
		_save_target = null
		_save_destination = Pathfinder.UNREACHABLE
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
	if not _display_name.is_empty():
		return _display_name
	return str(name) if not str(name).is_empty() else "bot"


func personality() -> int:
	return _personality


func personality_label() -> String:
	return PERSONALITY_LABELS[clampi(_personality, 0, PERSONALITY_LABELS.size() - 1)]


## Apply an embark loadout: name, personality, equipped parts, skills, and all
## the stats they derive. Safe to call after _ready (stats already exist) — the
## WorkerSpawner calls it right after add_child.
func apply_loadout(loadout: WorkerLoadout) -> void:
	if loadout == null:
		return
	_loadout = loadout
	if not loadout.display_name.is_empty():
		_display_name = loadout.display_name
	_personality = clampi(loadout.personality, 0, PERSONALITY_LABELS.size() - 1)
	_skills = loadout.skills.duplicate()
	_init_part_conditions()
	_apply_derived_stats(loadout.derive())


## Seed full condition for every equipped part slot. Called when a loadout is
## applied; restore_save overwrites these with saved values afterwards.
func _init_part_conditions() -> void:
	_part_conditions.clear()
	if _loadout == null:
		return
	for i in _loadout.part_ids.size():
		if PartDatabase.has_part(StringName(_loadout.part_ids[i])):
			_part_conditions[i] = CONDITION_MAX


## Push a derived stats dict (see WorkerLoadout.derive / PartDatabase) onto the
## live worker. Combat stats flow through `stats`; the rest into local fields
## the per-frame code already reads.
func _apply_derived_stats(s: Dictionary) -> void:
	_move_speed = float(s.get("move_speed", _move_speed))
	_work_speed_mult = maxf(0.1, float(s.get("work_speed", _work_speed_mult)))
	_mine_speed_mult = maxf(0.1, float(s.get("mine_speed", _mine_speed_mult)))
	_build_speed_mult = maxf(0.1, float(s.get("build_speed", _build_speed_mult)))
	_carry_capacity = maxi(1, int(round(s.get("carry", _carry_capacity))))
	_armor = maxf(0.0, float(s.get("armor", _armor)))
	_sight_bonus = int(s.get("sight", _sight_bonus))
	_energy_recharge_mult = maxf(0.1, float(s.get("energy_recharge", _energy_recharge_mult)))
	_energy_drain_mult = maxf(0.1, float(s.get("energy_drain", _energy_drain_mult)))
	_wisdom_mult = maxf(0.1, float(s.get("wisdom", _wisdom_mult)))
	_mood_baseline = clampf(float(s.get("mood_baseline", _mood_baseline)), 10.0, MOOD_MAX)
	_mood_recovery_mult = maxf(0.1, float(s.get("mood_recovery_mult", _mood_recovery_mult)))
	if stats != null:
		stats.max_hp = maxf(10.0, float(s.get("max_hp", stats.max_hp)))
		stats.hp = stats.max_hp
		stats.damage_min = maxf(0.5, float(s.get("bash_min", stats.damage_min)))
		stats.damage_max = maxf(stats.damage_min, float(s.get("bash_max", stats.damage_max)))
		stats.dodge_chance = clampf(float(s.get("dodge", stats.dodge_chance)), 0.0, 0.9)
	_mood = _mood_baseline
	queue_redraw()


func skill_level(skill: StringName) -> int:
	return int(_skills.get(skill, 0))


## Human-readable build summary for the worker inspect panel.
func loadout_summary_lines() -> Array[String]:
	var lines: Array[String] = []
	if _loadout == null:
		lines.append("Standard chassis")
		return lines
	for i in _loadout.part_ids.size():
		var part_id: StringName = StringName(_loadout.part_ids[i])
		var slot: int = PartDatabase.SLOT_LAYOUT[i] if i < PartDatabase.SLOT_LAYOUT.size() else 0
		var part_def: Dictionary = PartDatabase.part(part_id)
		if part_def.is_empty():
			lines.append("%s: —" % PartDatabase.slot_label(slot))
		else:
			lines.append("%s: %s" % [PartDatabase.slot_label(slot), str(part_def["name"])])
	return lines


## Skill levels as "Label Lv" strings (only non-zero), for the inspect panel.
func skill_summary_lines() -> Array[String]:
	var lines: Array[String] = []
	for skill in WorkerLoadout.SKILL_KEYS:
		var lvl: int = skill_level(skill)
		if lvl > 0:
			lines.append("%s %d" % [str(WorkerLoadout.SKILL_LABELS[skill]), lvl])
	return lines


func action_history() -> Array[String]:
	return _action_history.duplicate()


## Save layer: persist identity, position, and the persistent stats. Transient
## state (current job, path, combat target, carried item) is dropped; the bot
## resumes idle and re-claims work after load. A carried stack is reported so
## the caller can re-drop it as a loose item.
func capture_save() -> Dictionary:
	var part_conditions: Dictionary = {}
	for slot_index in _part_conditions:
		part_conditions[slot_index] = float(_part_conditions[slot_index])
	var d: Dictionary = {
		"name": str(name),
		"pos": position,
		"personality": _personality,
		"energy": _energy,
		"condition": _condition,
		"mental": _mental_tiredness,
		"social": _social,
		"mood": _mood,
		"part_conditions": part_conditions,
		"hp": stats.hp if stats != null else COMBAT_HP_MAX,
		"history": _action_history.duplicate(),
		"history_index": _history_index,
		"display_name": _display_name,
	}
	if _loadout != null:
		d["loadout"] = _loadout.to_dict()
	if _carried != null and is_instance_valid(_carried):
		d["carried"] = {"kind": _carried.kind, "count": _carried.count}
	return d


func restore_save(data: Dictionary) -> void:
	# Re-derive the bot's build first so max_hp / stat fields are correct, then
	# overwrite the live values (hp, mood, …) with the saved snapshot below.
	_display_name = str(data.get("display_name", _display_name))
	if data.has("loadout"):
		apply_loadout(WorkerLoadout.from_dict(data["loadout"] as Dictionary))
	_personality = int(data.get("personality", _personality))
	_energy = float(data.get("energy", ENERGY_MAX))
	_condition = float(data.get("condition", CONDITION_MAX))
	_mental_tiredness = float(data.get("mental", 0.0))
	_social = float(data.get("social", 50.0))
	_mood = float(data.get("mood", MOOD_BASELINE))
	var part_conditions: Dictionary = data.get("part_conditions", {}) as Dictionary
	for slot_index in part_conditions:
		_part_conditions[int(slot_index)] = float(part_conditions[slot_index])
	if stats != null:
		stats.hp = clampf(float(data.get("hp", stats.max_hp)), 0.0, stats.max_hp)
	_action_history.clear()
	for h in data.get("history", []) as Array:
		_action_history.append(str(h))
	_history_index = int(data.get("history_index", _action_history.size()))
	_state = State.IDLE
	_idle_cooldown = 0.0
	queue_redraw()


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


func sight_radius() -> int:
	return 4 if _is_low_energy_mode() else FogOfWar.WORKER_SIGHT_RADIUS + _sight_bonus


func status_modifiers() -> Array[String]:
	var out: Array[String] = []
	if _is_low_energy_mode():
		out.append("Low energy mode: -50% energy drain, reduced vision")
	if _energy < ENERGY_SLOW_THRESHOLD:
		out.append("Low energy: reduced movement speed")
	return out


func downed_reason() -> StringName:
	return _downed_reason


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


## Per-equipped-part condition for the worker stat panel. Each entry is
## {name, slot, ratio}. A part-less shell reports a single "Chassis" entry that
## mirrors the overall condition so the panel never renders empty.
func part_condition_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _loadout != null:
		for i in _loadout.part_ids.size():
			var def: Dictionary = PartDatabase.part(StringName(_loadout.part_ids[i]))
			if def.is_empty():
				continue
			var slot: int = PartDatabase.SLOT_LAYOUT[i] if i < PartDatabase.SLOT_LAYOUT.size() else 0
			var cond: float = float(_part_conditions.get(i, CONDITION_MAX))
			out.append({
				"name": str(def["name"]),
				"slot": PartDatabase.slot_label(slot),
				"ratio": clampf(cond / CONDITION_MAX, 0.0, 1.0),
			})
	if out.is_empty():
		out.append({"name": "Chassis", "slot": "Frame", "ratio": condition_ratio()})
	return out


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


func is_paused() -> bool:
	return _paused


func set_paused(paused: bool) -> void:
	if _paused == paused:
		return
	_paused = paused
	if paused:
		_idle_cooldown = 0.0
	queue_redraw()


func state_label() -> String:
	if _paused:
		return "paused"
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
		State.MOVING_TO_SAVE:
			return "moving to save"
		State.CARRYING_WORKER, State.MOVING_TO_DELIVER:
			return "carrying"
		State.REBOOTING:
			return "rebooting"
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
	_route_cache.clear()
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
	if _paused:
		# Player-paused workers freeze in place: no AI, no path progression,
		# no idle behavior. Combat and direct orders are also gated until the
		# player resumes the worker explicitly. Drawing still ticks via the
		# selection layer.
		return

	# If this worker is currently being carried by another bot, suppress all AI, 
	# movement, and state updates, pinning position to the carrier.
	if carried_by != null and is_instance_valid(carried_by):
		position = carried_by.position
		visible = false
		queue_redraw()
		return
		
	if _teleport_charge_cooldown > 0.0:
		_teleport_charge_cooldown = maxf(0.0, _teleport_charge_cooldown - delta)

	# Update reboot state from condition. Workers entering REBOOTING release
	# any in-flight job so the rest of the colony can claim it; workers
	# whose condition has recovered (e.g. via a save → repair bench) exit
	# REBOOTING and resume idle behavior on their own.
	_update_reboot_state()
	if _state == State.REBOOTING:
		# Downed bots only update their stats; they cannot pursue jobs, fight,
		# or move on their own. They wait for a teammate to save them.
		queue_redraw()
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
	if _no_repair_bench_complaint_timer > 0.0:
		_no_repair_bench_complaint_timer = maxf(0.0, _no_repair_bench_complaint_timer - delta)
	if _research_urge_cooldown > 0.0:
		_research_urge_cooldown = maxf(0.0, _research_urge_cooldown - delta)
	_ai_decision_timer -= delta
	var ai_due: bool = _ai_decision_timer <= 0.0
	if ai_due:
		_ai_decision_timer = AI_DECISION_SECONDS + randf_range(0.0, AI_DECISION_JITTER_SECONDS)
	_update_energy(delta)
	_update_body_stats(delta)
	_tick_acid_damage(delta)
	_entity_grid_timer -= delta
	if _entity_grid_timer <= 0.0:
		_entity_grid_timer = ENTITY_GRID_SYNC_SECONDS
		EntityGrid.update_position(self, current_grid())
	# Rescuers can't drop the body to chase charge — finish the delivery first.
	var rescuing: bool = _state == State.MOVING_TO_SAVE \
		or _state == State.CARRYING_WORKER \
		or _state == State.MOVING_TO_DELIVER
	if ai_due and _state != State.FIGHTING and not rescuing and _should_seek_charge():
		if _begin_auto_charge():
			return
	match _state:
		State.IDLE:
			if _try_start_next_direct_order():
				return
			_idle_cooldown -= delta
			if ai_due and _idle_cooldown <= 0.0:
				_idle_cooldown = IDLE_RETRY_SECONDS
				# Heavily damaged workers cut the line: try a repair bench
				# before the regular job board. If none is reachable, complain
				# (throttled) and fall through to the normal idle flow.
				if _condition <= 45.0:
					if _begin_structure_activity(
							[BuildBlueprint.Id.REPAIR_BENCH, BuildBlueprint.Id.MAINTENANCE_DOCK],
							State.MOVING_TO_REPAIR):
						_no_repair_bench_complaint_timer = 0.0
						return
					if _no_repair_bench_complaint_timer <= 0.0:
						_remember("Can't repair myself, no repair bench")
						_no_repair_bench_complaint_timer = 18.0
				if not _try_claim_job():
					_choose_idle_behavior()
		State.MOVING_TO_WORK:
			if _advance_path(delta):
				_state = State.WORKING
		State.WORKING:
			var work_delta: float = delta * _light_speed_multiplier()
			if _job is MineJob:
				var mine := _job as MineJob
				mine.progress += work_delta * _mine_speed_mult
				if mine.progress >= MineJob.DURATION:
					_complete_mine(mine)
			elif _is_scrape_rust_job(_job):
				var scrape_progress: float = float(_job.get("progress")) + work_delta * _work_speed_mult
				_job.set("progress", scrape_progress)
				if scrape_progress >= SCRAPE_RUST_DURATION:
					_complete_scrape_rust(_job)
			elif _is_scrape_biomass_job(_job):
				var biomass_progress: float = float(_job.get("progress")) + work_delta * _work_speed_mult
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
			build.progress += delta * _light_speed_multiplier() * _build_speed_mult
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
				op.progress += delta * _light_speed_multiplier() * _workshop_room_speed_multiplier(op.anchor) * _work_speed_mult
				if op.progress >= op.operate_duration():
					_complete_operation(op)
			else:
				var craft := _job as CraftJob
				if craft == null:
					_abandon_job()
					return
				craft.progress += delta * _light_speed_multiplier() * _workshop_room_speed_multiplier(craft.station_anchor) * _work_speed_mult
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
			_energy = minf(ENERGY_MAX, _energy + ENERGY_CHARGE_PER_SEC * delta * _energy_recharge_mult)
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
				_activity_timer = randf_range(6.0, 12.0)
		State.REPAIRING:
			_activity_timer -= delta
			_condition = minf(CONDITION_MAX, _condition + REPAIR_RECOVERY_PER_SEC * delta)
			_repair_parts(REPAIR_RECOVERY_PER_SEC * delta)
			if _activity_timer <= 0.0 or _condition >= CONDITION_MAX:
				_state = State.IDLE
				_idle_cooldown = randf_range(0.5, 1.5)
		State.MOVING_TO_SOCIALIZE:
			var reached: bool = _advance_path(delta)
			var partner_valid: bool = _activity_partner != null and is_instance_valid(_activity_partner)
			if partner_valid and _is_adjacent_to(_activity_partner):
				_state = State.SOCIALIZING
				if _activity_timer <= 0.0:
					_activity_timer = randf_range(7.0, 12.0)
				_remember("chatting with %s" % _activity_partner.display_name())
			elif reached:
				# Hold position and wait for the slower partner to walk adjacent
				var partner_still_coming: bool = partner_valid and \
					(_activity_partner._state == State.MOVING_TO_SOCIALIZE or _activity_partner._state == State.SOCIALIZING) and \
					_activity_partner._activity_partner == self
				if not partner_still_coming:
					_remember("chat cancelled: partner abandoned")
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
			rate *= _wisdom_mult
			_wisdom_carry += rate * delta
			# Research is mentally taxing — chips away at mood while the bot
			# is hunched over a research bench.
			_mood = clampf(_mood - 0.6 * delta, 0.0, MOOD_MAX)
			if _activity_timer <= 0.0:
				if TechManager != null and _wisdom_carry > 0.0:
					TechManager.add_wisdom(_wisdom_carry)
					_remember("gained %.1f wisdom" % _wisdom_carry)
				_wisdom_carry = 0.0
				_state = State.IDLE
				_idle_cooldown = randf_range(0.6, 2.0)
		State.FIGHTING:
			_process_fighting(delta)
		State.MOVING_TO_SAVE:
			if _advance_path(delta):
				_pickup_downed_worker()
		State.CARRYING_WORKER:
			if _carried_worker == null or not is_instance_valid(_carried_worker):
				_abort_save()
				return
			
			var path: PackedVector2Array = _find_explored_path(current_grid(), _save_destination)
			if path.is_empty() and current_grid() != _save_destination:
				_abort_save()
				_show_blocked_action("No path to deliver")
				return
				
			_path = path
			_path_index = 0
			_state = State.MOVING_TO_DELIVER
		State.MOVING_TO_DELIVER:
			# Verify the target downed worker remains active and valid
			if _carried_worker == null or not is_instance_valid(_carried_worker) or _carried_worker._dead:
				_abort_save()
			else:
				_carried_worker.position = position
				if _advance_path(delta):
					_drop_off_carried_worker()
	_check_teleporter()
	_update_stuck_watchdog(delta)
	# Action text only depends on state/job/blocked timer — skip the match
	# statement allocation entirely when nothing relevant changed.
	if _state != _last_action_state or _job != _last_action_job or _blocked_action_timer > 0.0:
		_last_action_state = _state
		_last_action_job = _job
		_refresh_action_text()
	if _state != _last_sound_state or _job != _last_sound_job:
		_last_sound_state = _state
		_last_sound_job = _job
		_update_sounds()


## True when this worker is in the rebooting (downed) state — condition has
## hit zero and they cannot act on their own. A teammate can rescue them via
## `command_save`. Excludes fully dead bots (HP-0 fadeout); those can't be
## saved.
func is_downed() -> bool:
	return _state == State.REBOOTING and not _dead


func _update_reboot_state() -> void:
	if _dead:
		return
		
	var next_downed_reason: StringName = _compute_downed_reason()
	var should_be_rebooting: bool = next_downed_reason != DOWNED_NONE
	
	if should_be_rebooting:
		# Force-abort the rescue state to drop the downed worker safely onto the grid
		if _state == State.MOVING_TO_SAVE or _state == State.CARRYING_WORKER or _state == State.MOVING_TO_DELIVER:
			_abort_save()
			
	if should_be_rebooting and _state != State.REBOOTING:
		_downed_reason = next_downed_reason
		_abandon_job()
		_path = PackedVector2Array()
		_path_index = 0
		_direct_order_queue.clear()
		_release_charge_reservation()
		_state = State.REBOOTING
		_remember("rebooting (%s)" % str(_downed_reason))
	elif not should_be_rebooting and _state == State.REBOOTING:
		_downed_reason = DOWNED_NONE
		_state = State.IDLE
		_idle_cooldown = 0.0
		_remember("recovered from reboot")
	elif should_be_rebooting:
		_downed_reason = next_downed_reason


func _compute_downed_reason() -> StringName:
	var energy_down: bool = _energy <= 0.0
	var condition_down: bool = _condition <= REBOOT_CONDITION_THRESHOLD
	if energy_down and condition_down:
		return DOWNED_BOTH
	if energy_down:
		return DOWNED_ENERGY
	if condition_down:
		return DOWNED_CONDITION
	return DOWNED_NONE


## Player-issued rescue. The carrier walks to `target`, picks them up, then
## hauls them to a Repair Bench / Mechanic Dock (preferred) or Outlet
## (charging) or, failing both, the nearest stockpile zone. Returns false
## with a thought-bubble explanation when no destination can be reached.
func command_save(target: Worker, clear_queue: bool = true) -> bool:
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if not target.is_downed():
		return false
	if _dead or _state == State.REBOOTING:
		return false
	if _pathfinder == null or _chunk_manager == null:
		return false
	var stand: Vector2i = _pathfinder.walkable_neighbor_of(target.current_grid())
	if stand == Pathfinder.UNREACHABLE:
		_remember("Can't save, no path")
		return false
	var dest_info: Dictionary = _find_save_destination(stand, target.downed_reason())
	if dest_info.is_empty():
		_remember("Can't save, no service point")
		return false
	if clear_queue:
		_direct_order_queue.clear()
	_abandon_job()
	var path: PackedVector2Array = _find_explored_path(current_grid(), stand)
	if path.is_empty() and current_grid() != stand:
		_remember("Can't save, no path")
		return false
	_save_target = target
	_save_destination = dest_info["cell"] as Vector2i
	_save_destination_kind = int(dest_info.get("kind", -1))
	_path = path
	_path_index = 0
	_state = State.MOVING_TO_SAVE
	_remember("Saving %s" % target.display_name())
	return true


## Resolve where a carried downed worker should be dropped off. Priority:
## Repair Bench / Mechanic Dock → Outlet (visible) → nearest stockpile zone.
## Each candidate is filtered through pathing from `stand` so we never start
## a rescue we can't finish.
func _find_save_destination(stand: Vector2i, reason: StringName) -> Dictionary:
	if reason == DOWNED_ENERGY:
		var outlet_first: Vector2i = _nearest_outlet_via_explored(stand)
		if outlet_first != Pathfinder.UNREACHABLE and _route_exists(stand, outlet_first, true):
			return {"cell": outlet_first, "kind": -2}
	if _structure_manager != null:
		var bench: Vector2i = _structure_manager.nearest_structure_anchor(
			[BuildBlueprint.Id.REPAIR_BENCH, BuildBlueprint.Id.MAINTENANCE_DOCK],
			stand,
			_pathfinder,
			_fog,
		)
		if bench != Pathfinder.UNREACHABLE:
			var interaction: Vector2i = _structure_manager.interaction_cell_for(bench)
			if interaction != Pathfinder.UNREACHABLE and _route_exists(stand, interaction, true):
				var structure: Dictionary = _structure_manager.structure_at(bench)
				var destination_kind: int = int(structure.get("id", BuildBlueprint.Id.REPAIR_BENCH))
				return {"cell": interaction, "kind": destination_kind}
	# Outlets — workers ARE allowed to stand on outlet tiles, so deliver
	# directly onto the outlet cell to start a passive charge.
	var outlet: Vector2i = _nearest_outlet_via_explored(stand)
	if outlet != Pathfinder.UNREACHABLE and _route_exists(stand, outlet, true):
		return {"cell": outlet, "kind": -2}
	# Stockpile fallback — dump the body somewhere the colony will notice.
	if _stockpile_manager != null and _stockpile_manager.has_method("any_zone_cell"):
		var stockpile_cell: Vector2i = _stockpile_manager.call("any_zone_cell") as Vector2i
		if stockpile_cell != Pathfinder.UNREACHABLE and _route_exists(stand, stockpile_cell, true):
			return {"cell": stockpile_cell, "kind": -3}
	return {}


func _pickup_downed_worker() -> void:
	if _save_target == null or not is_instance_valid(_save_target) or not _save_target.is_downed():
		_abort_save()
		return
	_carried_worker = _save_target
	_carried_worker.carried_by = self
	_carried_worker.visible = false
	_carried_worker.position = position
	_state = State.CARRYING_WORKER # Set carrying state. Let _process coordinate delivering path next frame.


func _drop_off_carried_worker() -> void:
	var carried := _carried_worker
	_carried_worker = null
	_save_target = null
	_state = State.IDLE
	_idle_cooldown = 0.0
	if carried == null or not is_instance_valid(carried):
		return
	carried.carried_by = null # Deregister carrying
	carried.position = position
	carried.visible = true
	
	var condition_bonus: float = SAVE_REVIVE_CONDITION
	var energy_bonus: float = SAVE_REVIVE_ENERGY
	if _save_destination_kind == BuildBlueprint.Id.REPAIR_BENCH or _save_destination_kind == BuildBlueprint.Id.MAINTENANCE_DOCK:
		condition_bonus = 60.0
		energy_bonus = 20.0
	elif _save_destination_kind == -2:
		condition_bonus = 15.0
		energy_bonus = 80.0
	carried._revive(condition_bonus, energy_bonus)
	_remember("dropped off %s" % carried.display_name())
	_save_destination = Pathfinder.UNREACHABLE
	_save_destination_kind = -1


func _abort_save() -> void:
	if _carried_worker != null and is_instance_valid(_carried_worker):
		_carried_worker.carried_by = null # Deregister carrying
		_carried_worker.visible = true
		_carried_worker.position = position
	_carried_worker = null
	_save_target = null
	_save_destination = Pathfinder.UNREACHABLE
	_save_destination_kind = -1
	_state = State.IDLE
	_idle_cooldown = 0.0
	_remember("save aborted")



## Restore condition / energy after being rescued. Called by the carrier.
func _revive(condition_bonus: float, energy_bonus: float) -> void:
	_condition = clampf(_condition + condition_bonus, 0.0, CONDITION_MAX)
	_energy = clampf(_energy + energy_bonus, 0.0, ENERGY_MAX)
	# Repair limbs proportionally to the condition bonus so a rescued bot
	# isn't immediately downed again from limb damage.
	_repair_parts(condition_bonus)
	
	# Wake up only if both condition and energy are restored above minimums
	if _condition > REBOOT_CONDITION_THRESHOLD and _energy > 0.0 and _state == State.REBOOTING:
		_downed_reason = DOWNED_NONE
		_state = State.IDLE
		_idle_cooldown = 0.0
		_remember("woken up after save")


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

## Registers a job as temporarily un-executable for this worker.
## Seconds a job that a worker couldn't reach is skipped before anyone retries
## it. Long enough that hundreds of unreachable jobs don't get re-pathed in a
## tight loop, short enough that opening a wall makes the area workable soon.
const FAILED_JOB_COOLDOWN_SECONDS: float = 8.0


func _mark_job_failed(job: Job) -> void:
	if job != null:
		_failed_jobs_cooldowns[job] = _now_seconds() + FAILED_JOB_COOLDOWN_SECONDS
		# Block at the board level too so neither this worker's claim loop nor
		# any other idle worker keeps re-pathing the same unreachable job every
		# tick — the dominant cost when a huge designation drops hundreds of jobs.
		job.block_briefly(FAILED_JOB_COOLDOWN_SECONDS)


func _try_claim_job() -> bool:
	if _job_board == null or _pathfinder == null:
		return false
	
	var claimed_this_tick: Array[Job] = []
	var now := _now_seconds()
	
	# Clean up expired or invalid failed jobs
	var active_keys := _failed_jobs_cooldowns.keys()
	for f_job in active_keys:
		if not is_instance_valid(f_job) or now >= _failed_jobs_cooldowns[f_job]:
			_failed_jobs_cooldowns.erase(f_job)
	
	# Keep pulling jobs until one starts successfully. Failed claims are held
	# until this tick ends so the board can offer another candidate.
	# Bounded attempts per tick: each iteration runs a board scan + a pathfind,
	# so a high cap multiplies cost when hundreds of jobs exist. Failed jobs are
	# blocked board-side (see _mark_job_failed), so a few attempts suffice.
	var safety_limit := 6
	while safety_limit > 0:
		safety_limit -= 1
		var job: Job = _job_board.claim_next_for(self, current_grid())
		if job == null:
			break
		
		if _failed_jobs_cooldowns.has(job):
			# Hold this job claim temporarily so the board doesn't return 
			# it to us on the next iteration of this loop.
			claimed_this_tick.append(job)
			continue
		
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

		if _job == job and _state != State.IDLE:
			for f_job in claimed_this_tick:
				_job_board.release(f_job)
			return true
		_mark_job_failed(job)
		if _job_board.is_active(job):
			_job_board.release(job)
		if _job == job:
			_job = null

	for f_job in claimed_this_tick:
		_job_board.release(f_job)
	return false



func _try_start_next_direct_order() -> bool:
	if _direct_order_queue.is_empty():
		return false
		
	# Peek at the command instead of popping it immediately
	var order: Dictionary = _direct_order_queue[0]
	if _start_direct_order(order):
		_direct_order_queue.pop_front() # Remove only when successfully initiated
		return true
	else:
		# The step failed. Clear queue to prevent out-of-order execution and notify player.
		_direct_order_queue.clear()
		show_order_failed("Queue blocked")
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
		ORDER_SAVE:
			var save_target := order.get("target") as Worker
			return command_save(save_target, false)
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


func _is_scrape_rust_job(job: Job) -> bool:
	return job != null and job.kind == Job.Kind.SCRAPE_RUST


func _is_scrape_biomass_job(job: Job) -> bool:
	return job != null and job.kind == Job.Kind.SCRAPE_BIOMASS


func _is_scrape_job(job: Job) -> bool:
	return _is_scrape_rust_job(job) or _is_scrape_biomass_job(job)


func _choose_idle_behavior() -> void:
	if _condition <= 68.0:
		if _begin_structure_activity(
				[BuildBlueprint.Id.REPAIR_BENCH, BuildBlueprint.Id.MAINTENANCE_DOCK],
				State.MOVING_TO_REPAIR):
			_no_repair_bench_complaint_timer = 0.0
			return
		# No reachable repair bench — complain occasionally so the player sees
		# the thought without it spamming every idle tick.
		if _no_repair_bench_complaint_timer <= 0.0:
			_remember("Can't repair myself, no repair bench")
			_no_repair_bench_complaint_timer = 18.0

	# Prioritize recharging if energy is low, rather than letting it compete 
	# with other low-priority idle behaviors in the shuffled array.
	if _energy <= ENERGY_LOW:
		if _idle_try_top_off_charge():
			return

	if _mental_tiredness >= 55.0 and _begin_assigned_dock_rest():
		return
	# Random research urge: occasionally jump to a research bench instead of
	# cycling through the usual idle chores, so research drips in even when
	# the player hasn't queued anything.
	if _research_urge_cooldown <= 0.0 and randf() < 0.15:
		if _begin_structure_activity([BuildBlueprint.Id.MEDITATION_PAD], State.MOVING_TO_MEDITATE):
			_research_urge_cooldown = randf_range(45.0, 90.0)
			_remember("decided to research")
			return
	# Idle bots cycle through low-priority chores so they look alive even when
	# the job board is empty. We try the rolled behavior, then fall through to
	# alternative chores so a single failure (no rust nearby, no chat partner
	# in range, etc.) doesn't freeze the bot for seconds.
	var behaviors: Array[Callable] = _idle_behavior_order()
	for behavior in behaviors:
		if behavior.call() as bool:
			return
	# Last-resort wander: pick any walkable cell nearby so a worker in a
	# sparse area (no rust/grass/explored frontier/chat partners/structures)
	# still moves around instead of freezing in place. This is the
	# safety-net that guarantees idle ticks always have *something* to do.
	if _begin_short_wander():
		return
	_idle_cooldown = randf_range(0.4, IDLE_FALLBACK_RETRY_SECONDS)


func _begin_short_wander() -> bool:
	if _chunk_manager == null or _pathfinder == null:
		return false
	var here: Vector2i = current_grid()
	var target: Vector2i = _random_walkable_near(here, 6)
	if target == Pathfinder.UNREACHABLE or target == here:
		return false
	var path: PackedVector2Array = _find_explored_path(here, target)
	if path.is_empty():
		return false
	_path = path
	_path_index = 0
	_activity_target = target
	_state = State.WANDERING
	return true


func _idle_behavior_order() -> Array[Callable]:
	# Weighted shuffle: the bot rolls once for a primary chore, but we always
	# walk every behavior eventually so one always succeeds.
	var ordered: Array[Callable] = [
		_idle_try_scrape_rust,
		_idle_try_scrape_biomass,
		_idle_try_roam_explored,
		_idle_try_roam_frontier,
		_idle_try_socialize,
		_idle_try_meditate,
		_idle_try_top_off_charge,
		_idle_try_assigned_dock_rest,
	]
	var roll: int = randi() % ordered.size()
	# Bring the rolled chore to the front so the bot tries it first.
	if roll > 0:
		var first: Callable = ordered[roll]
		ordered.remove_at(roll)
		ordered.insert(0, first)
	return ordered


func _idle_try_scrape_rust() -> bool:
	return _begin_idle_scrape_rust()


func _idle_try_scrape_biomass() -> bool:
	return _begin_idle_scrape_biomass()


func _idle_try_roam_explored() -> bool:
	return _begin_roam(false)


func _idle_try_roam_frontier() -> bool:
	return _begin_roam(true)


func _idle_try_socialize() -> bool:
	return _begin_socialize()


func _idle_try_meditate() -> bool:
	return _begin_structure_activity([BuildBlueprint.Id.MEDITATION_PAD], State.MOVING_TO_MEDITATE)


func _idle_try_top_off_charge() -> bool:
	# Shift threshold to 80.0 to prevent workers from oscillating 
	# in and out of charge states during idle periods.
	if _energy >= 80.0:
		return false
	var outlet: Vector2i = _nearest_outlet_via_explored()
	if outlet == Pathfinder.UNREACHABLE:
		return false
	_begin_charge(outlet)
	return true


func _idle_try_assigned_dock_rest() -> bool:
	if _begin_assigned_dock_rest():
		return true
	return _begin_structure_activity([BuildBlueprint.Id.DOCK, BuildBlueprint.Id.MAINTENANCE_DOCK], State.MOVING_TO_REST)


func _begin_idle_scrape_biomass() -> bool:
	if _chunk_manager == null or _job_board == null or _pathfinder == null:
		return false
	var target: Vector2i = _chunk_manager.random_nearby_grass(
		current_grid(),
		IDLE_SCRAPE_RUST_RADIUS,
		_pathfinder,
		_fog,
	)
	if target == Pathfinder.UNREACHABLE or _job_board.has_scrape_biomass_at(target):
		return false
	var job: Job = _job_board.add_scrape_biomass_job(target)
	job.claimed_by = self
	_job = job
	_begin_scrape_biomass(job)
	_remember("idle scrape biomass %d,%d" % [target.x, target.y])
	return true


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
	var path: PackedVector2Array = _find_explored_path(current_grid(), target)
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
		# Wandering is leisure — never pick a cell that bites back. Acid is
		# walkable but always damaging; let workers idle elsewhere.
		if _is_acid_tile_at(candidate):
			continue
		if candidate == current_grid():
			continue
		if _route_exists(current_grid(), candidate, true):
			return candidate
	return Pathfinder.UNREACHABLE


func _random_walkable_near(origin: Vector2i, radius: int) -> Vector2i:
	for _i in range(IDLE_SAMPLE_LIMIT):
		var candidate := origin + Vector2i(randi_range(-radius, radius), randi_range(-radius, radius))
		if not _chunk_manager.is_walkable(candidate):
			continue
		if _is_acid_tile_at(candidate):
			continue
		if _route_exists(origin, candidate, true):
			return candidate
	return Pathfinder.UNREACHABLE


func _is_acid_tile_at(grid: Vector2i) -> bool:
	if _chunk_manager == null:
		return false
	var tile: int = _chunk_manager.get_tile_at(grid)
	return tile == TerrainGenerator.TILE_ACID_SHALLOW \
		or tile == TerrainGenerator.TILE_ACID_PUDDLE \
		or tile == TerrainGenerator.TILE_ACID


func _begin_structure_activity(ids: Array, next_state: int) -> bool:
	if _structure_manager == null:
		return false
	var anchor: Vector2i = _structure_manager.nearest_structure_anchor(ids, current_grid(), _pathfinder, _fog)
	if anchor == Pathfinder.UNREACHABLE:
		return false
	var target: Vector2i = _structure_manager.interaction_cell_for(anchor)
	if target == Pathfinder.UNREACHABLE:
		return false
	var path: PackedVector2Array = _find_explored_path(current_grid(), target)
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
	var path: PackedVector2Array = _find_explored_path(current_grid(), target)
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
	
	# Cleanly clear active variables so the worker has a fresh state during the chat
	_job = null
	_path = PackedVector2Array()
	_path_index = 0
	_carried = null
	_release_charge_reservation()


func _resume_after_chat() -> void:
	var resume_job: Job = _resume_job
	var resume_state: int = _resume_state
	var resume_path: PackedVector2Array = _resume_path
	var resume_path_index: int = _resume_path_index
	var resume_carried: Item = _resume_carried
	
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
		_carried = resume_carried
		_replan()
		_idle_cooldown = 0.0
	else:
		_job = null
		_path = PackedVector2Array()
		_path_index = 0
		_state = State.IDLE
		_idle_cooldown = randf_range(0.8, 2.0)
		
		if resume_carried != null and is_instance_valid(resume_carried):
			resume_carried.visible = true
			resume_carried.reserved_by = null
			if resume_carried.get_parent() == self:
				remove_child(resume_carried)
			if _items_root != null:
				_items_root.add_child(resume_carried)
			resume_carried.set_grid(current_grid())
			if _stockpile_manager != null:
				_stockpile_manager.on_item_spawned(resume_carried)
		
		if resume_job is HaulJob:
			var haul := resume_job as HaulJob
			if haul.dropoff_zone is StockpileZone:
				(haul.dropoff_zone as StockpileZone).unreserve(haul.dropoff)
			if haul.item != null and is_instance_valid(haul.item):
				(haul.item as Item).reserved_by = null
		elif resume_job is BuildJob:
			var build := resume_job as BuildJob
			if build.source_item != null and is_instance_valid(build.source_item):
				(build.source_item as Item).reserved_by = null
		elif resume_job is CraftJob:
			var craft := resume_job as CraftJob
			if craft.source_item != null and is_instance_valid(craft.source_item):
				(craft.source_item as Item).reserved_by = null
		elif resume_job is OperateStructureJob:
			var op := resume_job as OperateStructureJob
			if op.source_item != null and is_instance_valid(op.source_item):
				(op.source_item as Item).reserved_by = null


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
	return _route_path(_route_between(from, to, true))


func _route_path(route: Dictionary) -> PackedVector2Array:
	return route.get("path", PackedVector2Array()) as PackedVector2Array


func _route_between(from: Vector2i, to: Vector2i, explored_only: bool = true) -> Dictionary:
	var empty_route: Dictionary = {
		"path": PackedVector2Array(),
		"entry": Pathfinder.UNREACHABLE,
		"exit": Pathfinder.UNREACHABLE,
		"uses_teleporter": false,
	}
	if _pathfinder == null:
		return empty_route
	if from == to:
		return empty_route
	var now_msec: int = Time.get_ticks_msec()
	var key: String = "%d,%d>%d,%d:%d" % [from.x, from.y, to.x, to.y, 1 if explored_only else 0]
	var cached: Dictionary = _route_cache.get(key, {}) as Dictionary
	if not cached.is_empty() and now_msec - int(cached.get("time", 0)) <= ROUTE_CACHE_MSEC:
		return cached.get("route", empty_route) as Dictionary
	var fog_arg: Object = _fog if explored_only else null
	var route: Dictionary = _pathfinder.find_path_with_teleporters(from, to, fog_arg)
	_route_cache[key] = {
		"time": now_msec,
		"route": route,
	}
	if _route_cache.size() > 96:
		_route_cache.clear()
	return route


func _route_exists(from: Vector2i, to: Vector2i, explored_only: bool = true) -> bool:
	return from == to or not _route_path(_route_between(from, to, explored_only)).is_empty()


func _set_path_to(target: Vector2i, explored_only: bool = true) -> bool:
	var route: Dictionary = _route_between(current_grid(), target, explored_only)
	var path: PackedVector2Array = _route_path(route)
	if path.is_empty() and current_grid() != target:
		return false
	_path = path
	_path_index = 0
	_stuck_watchdog_timer = 0.0
	_stuck_last_position = position
	return true


func _grid_from_waypoint(point: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(point.x / Chunk.TILE_PIXELS)),
		int(floor(point.y / Chunk.TILE_PIXELS)),
	)


func _begin_mine(job: MineJob) -> void:
	if not _is_mineable_target(job.target):
		_cancel_mine_job(job)
		return
	var stand: Vector2i = _mine_stand_for(job.target)
	if stand == Pathfinder.UNREACHABLE:
		job.block_briefly()
		_release_and_idle()
		return
	var path: PackedVector2Array = _find_explored_path(current_grid(), stand)
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
	var path: PackedVector2Array = _find_explored_path(current_grid(), target)
	if path.is_empty() and current_grid() != target:
		if job.has_method("block_briefly"):
			job.block_briefly(2.0)
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
	var path: PackedVector2Array = _find_explored_path(current_grid(), target)
	if path.is_empty() and current_grid() != target:
		if job.has_method("block_briefly"):
			job.block_briefly(2.0)
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
	var path: PackedVector2Array = _find_explored_path(current_grid(), item_grid)
	if path.is_empty() and current_grid() != item_grid:
		var item := job.item as Item
		_clear_job_reservations()
		if job.has_method("block_briefly"):
			job.block_briefly(2.0)
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
			job.block_briefly(2.0)
			_mark_job_failed(job)
			_release_and_idle()
			return
		var ready_path: PackedVector2Array = _find_explored_path(current_grid(), stand_ready)
		if ready_path.is_empty() and current_grid() != stand_ready:
			job.block_briefly(2.0)
			_mark_job_failed(job)
			_release_and_idle()
			return
		_path = ready_path
		_path_index = 0
		_state = State.MOVING_TO_BUILD_SITE
		return
	job.material_kind = job.next_missing_kind()
	var source: Item = _find_material_for_build(job)
	if source == null:
		_note_missing_build_material(job)
		_release_and_idle()
		return
	job.source_item = source
	source.reserved_by = self
	var sg: Vector2i = source.get_grid()
	var path: PackedVector2Array = _find_explored_path(current_grid(), sg)
	if path.is_empty() and current_grid() != sg:
		source.reserved_by = null
		job.block_briefly(2.0)
		_mark_job_failed(job)
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
			if it.get_grid() != origin and not _route_exists(origin, it.get_grid(), true):
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
						if cell != origin and not _route_exists(origin, cell, true):
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
			job.block_briefly(2.0)
			_mark_job_failed(job)
			_release_and_idle()
			return
		var ready_path: PackedVector2Array = _find_explored_path(current_grid(), stand_ready)
		if ready_path.is_empty() and current_grid() != stand_ready:
			job.block_briefly(2.0)
			_mark_job_failed(job)
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
	var path: PackedVector2Array = _find_explored_path(current_grid(), sg)
	if path.is_empty() and current_grid() != sg:
		source.reserved_by = null
		job.block_briefly(2.0)
		_mark_job_failed(job)
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
			if it.get_grid() != origin and not _route_exists(origin, it.get_grid(), true):
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
						if cell != origin and not _route_exists(origin, cell, true):
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
		_mark_job_failed(job)
		_release_and_idle()
		return
	if job.has_all_materials():
		var stand_ready: Vector2i = _structure_manager.interaction_cell_for(job.anchor)
		if stand_ready == Pathfinder.UNREACHABLE:
			job.block_briefly(2.0)
			_mark_job_failed(job)
			_release_and_idle()
			return
		var ready_path: PackedVector2Array = _find_explored_path(current_grid(), stand_ready)
		if ready_path.is_empty() and current_grid() != stand_ready:
			job.block_briefly(2.0)
			_mark_job_failed(job)
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
	var path: PackedVector2Array = _find_explored_path(current_grid(), sg)
	if path.is_empty() and current_grid() != sg:
		source.reserved_by = null
		job.block_briefly(2.0)
		_mark_job_failed(job)
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
			if it.get_grid() != origin and not _route_exists(origin, it.get_grid(), true):
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
						if cell != origin and not _route_exists(origin, cell, true):
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
	var path: PackedVector2Array = _find_explored_path(current_grid(), haul.dropoff)
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
	var path: PackedVector2Array = _find_explored_path(current_grid(), stand)
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
	var path: PackedVector2Array = _find_explored_path(current_grid(), stand)
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
	var path: PackedVector2Array = _find_explored_path(current_grid(), stand)
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
	if item.count <= _carry_capacity:
		_take_into_hand(item)
		return item
	var carried: Item = ITEM_SCRIPT.new() as Item
	carried.setup(item.get_grid(), item.kind, _carry_capacity)
	item.count -= _carry_capacity
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
	if _carried != null and is_instance_valid(_carried):
		var here := current_grid()
		if _carried.get_parent() == self:
			remove_child(_carried)
		if _items_root != null:
			_items_root.add_child(_carried)
		_carried.visible = true
		_carried.set_grid(here)
		_carried.reserved_by = null
		# Briefly bar re-hauling so a failed delivery (unreachable / full
		# stockpile) doesn't immediately re-post a haul and loop the worker
		# through pick-up/drop on the same item.
		_carried.haul_blocked_until_msec = Time.get_ticks_msec() + StockpileManager.HAUL_RETRY_COOLDOWN_MS
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
	AudioManager.play_mine_complete(position)
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
	_mark_job_failed(job)
	var item_name: String = Item.kind_name(job.material_kind)
	_show_blocked_action("Lacks " + item_name)
	_remember("lacks %s for %s" % [item_name, BuildBlueprint.display_name(job.blueprint_id)])


func _note_missing_craft_material(job: CraftJob) -> void:
	job.block_briefly(2.0)
	_mark_job_failed(job)
	var item_name: String = Item.kind_name(job.material_kind)
	_show_blocked_action("Lacks " + item_name)
	_remember("lacks %s to craft %s" % [item_name, Item.kind_name(job.object_kind)])


func _note_missing_operation_material(job: OperateStructureJob) -> void:
	job.block_briefly(2.0)
	_mark_job_failed(job)
	var item_name: String = Item.kind_name(job.material_kind)
	_show_blocked_action("Lacks " + item_name)
	_remember("lacks %s to operate %s" % [item_name, BuildBlueprint.display_name(job.structure_id)])


func _abandon_job(release_claim: bool = true) -> void:
	# Used when the job was cancelled or invalid mid-flight. Drop anything
	# carried in place so we don't lose the item.
	_release_charge_reservation()
	_clear_job_reservations()
	var dropped: Item = null
	if _carried != null and is_instance_valid(_carried):
		var here := current_grid()
		if _carried.get_parent() == self:
			remove_child(_carried)
		_items_root.add_child(_carried)
		_carried.visible = true
		_carried.set_grid(here)
		_carried.reserved_by = null
		dropped = _carried
	_carried = null # Explicitly clear the reference
	
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
			var p: PackedVector2Array = _find_explored_path(current_grid(), dest)
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
	var path: PackedVector2Array = _find_explored_path(current_grid(), target_grid)
	if path.is_empty() and current_grid() != target_grid:
		# Lost reachability. Carrying? Drop it. Otherwise release.
		if _carried != null:
			_drop_in_place()
		else:
			_release_and_idle()
		return
	_path = path
	_path_index = 0


func _update_stuck_watchdog(delta: float) -> void:
	if not _is_moving_state():
		_stuck_watchdog_timer = 0.0
		_stuck_last_position = position
		return
	if _path.is_empty() or _path_index >= _path.size():
		_stuck_watchdog_timer += delta
	elif _stuck_last_position == Vector2.INF or position.distance_to(_stuck_last_position) > STUCK_PROGRESS_EPSILON_PX:
		_stuck_watchdog_timer = 0.0
		_stuck_last_position = position
	else:
		_stuck_watchdog_timer += delta
	if _stuck_watchdog_timer < STUCK_WATCHDOG_SECONDS:
		return
	_stuck_watchdog_timer = 0.0
	_stuck_last_position = position
	_recover_stuck_movement()


func _is_moving_state() -> bool:
	return _state == State.MOVING_TO_WORK \
		or _state == State.MOVING_TO_PICKUP \
		or _state == State.CARRYING \
		or _state == State.MOVING_TO_DROP \
		or _state == State.MOVING_TO_BUILD_SITE \
		or _state == State.MOVING_TO_CRAFT_SITE \
		or _state == State.MOVING_FREEFORM \
		or _state == State.MOVING_TO_CHARGE \
		or _state == State.ROAMING \
		or _state == State.WANDERING \
		or _state == State.MOVING_TO_REST \
		or _state == State.MOVING_TO_REPAIR \
		or _state == State.MOVING_TO_SOCIALIZE \
		or _state == State.MOVING_TO_MEDITATE \
		or _state == State.MOVING_TO_SAVE \
		or _state == State.CARRYING_WORKER \
		or _state == State.MOVING_TO_DELIVER


func _recover_stuck_movement() -> void:
	_route_cache.clear()
	if _state == State.MOVING_TO_SAVE or _state == State.CARRYING_WORKER or _state == State.MOVING_TO_DELIVER:
		if _state == State.MOVING_TO_DELIVER and _save_destination != Pathfinder.UNREACHABLE:
			if _set_path_to(_save_destination):
				return
		_abort_save()
		_show_blocked_action("Save blocked")
		return
	if _job != null:
		_replan()
		if _path.is_empty() and _state != State.WORKING and _state != State.BUILDING and _state != State.CRAFTING:
			_release_and_idle()
		return
	_state = State.IDLE
	_path = PackedVector2Array()
	_path_index = 0
	_idle_cooldown = 0.0


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
		if candidate == origin or _route_exists(origin, candidate, true):
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


func queue_command_save(target: Worker) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return _enqueue_direct_order({
		"kind": ORDER_SAVE,
		"target": target,
	}, "save %s" % target.display_name())


func command_move(target: Vector2i, clear_queue: bool = true) -> bool:
	if not _chunk_manager.is_walkable(target):
		show_order_failed("Blocked tile")
		return false
	var path: PackedVector2Array = _find_explored_path(current_grid(), target)
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
	queue_redraw()
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


## Player-issued order to go to a specific repair bench or maintenance dock.
func command_repair_at(anchor: Vector2i, clear_queue: bool = true) -> bool:
	if _structure_manager == null:
		return false
	var structure: Dictionary = _structure_manager.structure_at(anchor)
	if structure.is_empty():
		return false
	var id: int = int(structure.get("id", -1))
	if id != BuildBlueprint.Id.REPAIR_BENCH and id != BuildBlueprint.Id.MAINTENANCE_DOCK:
		return false
	var target: Vector2i = _structure_manager.interaction_cell_for(anchor)
	if target == Pathfinder.UNREACHABLE:
		return false
	if _fog != null and not _fog.is_explored(target):
		return false
	var path: PackedVector2Array = _find_explored_path(current_grid(), target)
	if path.is_empty() and current_grid() != target:
		return false
	if clear_queue:
		_direct_order_queue.clear()
	_abandon_job()
	_path = path
	_path_index = 0
	_activity_target = anchor
	_state = State.MOVING_TO_REPAIR
	_remember("ordered to repair at %d,%d" % [anchor.x, anchor.y])
	return true


func _advance_path(delta: float) -> bool:
	if _energy <= 0.0:
		return false
	if _path.is_empty():
		return true
	if _path_index >= _path.size():
		return true
	if _chunk_manager != null and _chunk_manager.is_teleporter(current_grid()):
		var next_grid: Vector2i = _grid_from_waypoint(_path[_path_index])
		if next_grid != current_grid() and _chunk_manager.is_teleporter(next_grid):
			return false
	var speed_mult: float = CROWD_SLOW_MULTIPLIER if _crowd_slow_remaining > 0.0 else 1.0
	if _door_slow_remaining > 0.0:
		speed_mult *= DOOR_SLOW_MULTIPLIER
	speed_mult *= _light_speed_multiplier()
	speed_mult *= _water_speed_multiplier()
	speed_mult *= _energy_speed_multiplier()
	var step: float = _move_speed * speed_mult * delta
	while step > 0.0 and _path_index < _path.size():
		var target: Vector2 = _path[_path_index]
		var target_grid := _grid_from_waypoint(target)
		if _structure_manager != null:
			var structure: Dictionary = _structure_manager.structure_at(target_grid)
			if not structure.is_empty() and int(structure["id"]) == BuildBlueprint.Id.DOOR:
				_structure_manager.request_door_open(target_grid)
				if not _structure_manager.is_door_open(target_grid):
					_door_stuck_timer += delta
					if _door_stuck_timer >= 4.0:
						_door_stuck_timer = 0.0
						_show_blocked_action("Door blocked")
						_replan()
					return false
		_door_stuck_timer = 0.0
		var to_target: Vector2 = target - position
		var dist: float = to_target.length()
		if dist > ARRIVE_EPSILON_PX:
			_set_facing_from_vector(to_target)
		if dist <= step + ARRIVE_EPSILON_PX:
			position = target
			step -= dist
			_path_index += 1
			if _chunk_manager != null and _chunk_manager.is_teleporter(target_grid):
				_update_crowding_contacts()
				return false
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


## Drains part integrity while standing on acid tiles. Damage is accumulated
## so sub-HP-per-frame ticks don't get rounded away by `_damage_part`.
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
		_damage_part(whole)
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


func _is_low_energy_mode() -> bool:
	return _energy <= ENERGY_LOW_MODE_THRESHOLD


func _energy_speed_multiplier() -> float:
	if _energy >= ENERGY_SLOW_THRESHOLD:
		return 1.0
	var t: float = clampf(
		(_energy - ENERGY_LOW_MODE_THRESHOLD) / (ENERGY_SLOW_THRESHOLD - ENERGY_LOW_MODE_THRESHOLD),
		0.0,
		1.0
	)
	return lerpf(ENERGY_LOW_MODE_SPEED_MULT, 1.0, t)


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
	drain *= _energy_drain_mult
	if drain > 0.0 and _is_low_energy_mode():
		drain *= ENERGY_LOW_MODE_DRAIN_MULT
	var previous_energy: float = _energy
	_energy = clampf(_energy - drain * delta, 0.0, ENERGY_MAX)
	var crossed_threshold: bool = (previous_energy > ENERGY_LOW_MODE_THRESHOLD and _energy <= ENERGY_LOW_MODE_THRESHOLD) \
		or (previous_energy > ENERGY_SLOW_THRESHOLD and _energy <= ENERGY_SLOW_THRESHOLD)
	if crossed_threshold or absf(_energy - _last_energy_for_draw) >= 0.25:
		_last_energy_for_draw = _energy
		queue_redraw()
	_check_energy_alerts()


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
	_damage_part(condition_decay)
	_check_condition_alerts()


func _update_mood(delta: float) -> void:
	_needs_refresh_timer -= delta
	if _needs_refresh_timer <= 0.0:
		_needs_refresh_timer = NEEDS_REFRESH_SECONDS
		_refresh_unsatisfied_needs()
	# Mood drift: recover toward baseline, but suffer per unsatisfied need.
	# Baseline + recovery speed are personality/parts-derived (see WorkerLoadout).
	var target: float = _mood_baseline
	if _social < 25.0:
		target -= 8.0
	if _mental_tiredness > 70.0:
		target -= 10.0
	if _condition < 50.0:
		target -= 6.0
	var penalty: float = float(_unsatisfied_needs.size()) * MOOD_NEED_DECAY_PER_SEC
	if _mood < target:
		_mood = minf(MOOD_MAX, _mood + MOOD_RECOVERY_PER_SEC * _mood_recovery_mult * delta)
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


func _damage_part(amount: float) -> void:
	if _part_conditions.is_empty():
		return
	var keys: Array = _part_conditions.keys()
	var idx: int = int(keys[randi() % keys.size()])
	_part_conditions[idx] = maxf(0.0, float(_part_conditions[idx]) - amount * 1.6)


func _repair_parts(amount: float) -> void:
	for idx in _part_conditions:
		_part_conditions[idx] = minf(CONDITION_MAX, float(_part_conditions[idx]) + amount)


func repair_parts_external(amount: float) -> void:
	if amount <= 0.0:
		return
	_repair_parts(amount)
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
	var planned: bool = false
	var target: Vector2i = Pathfinder.UNREACHABLE
	if _path_index < _path.size():
		var next_grid: Vector2i = _grid_from_waypoint(_path[_path_index])
		if next_grid != here and _chunk_manager.is_teleporter(next_grid):
			target = next_grid
			planned = true
	if target == Pathfinder.UNREACHABLE:
		target = _chunk_manager.random_linked_teleporter(here)
	if target == Pathfinder.UNREACHABLE:
		return
		
	# If we are currently traveling to find charge, set the cooldown to 
	# prevent instant bounce-backs through the network.
	if _state == State.MOVING_TO_CHARGE:
		_teleport_charge_cooldown = 12.0

	position = Chunk.grid_to_pixel_center(target)
	_teleport_cooldown = TELEPORT_COOLDOWN_SECONDS
	_last_teleporter_grid = target
	_remember("teleported from %d,%d to %d,%d" % [here.x, here.y, target.x, target.y])
	if planned:
		while _path_index < _path.size() and _grid_from_waypoint(_path[_path_index]) == target:
			_path_index += 1
		queue_redraw()
		return
	_path = PackedVector2Array()
	_path_index = 0
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
	# If teleporter cooldown is active, only allow seeking charge if a 
	# physical local charger is nearby.
	if _teleport_charge_cooldown > 0.0:
		return _nearest_outlet_via_explored() != Pathfinder.UNREACHABLE
	if _energy <= ENERGY_CRITICAL:
		return true
	# Seek charge if energy drops below the low threshold, unless the worker 
	# is currently engaged in combat.
	if _energy <= _recharge_threshold():
		return _state != State.FIGHTING
	return false


func _recharge_threshold() -> float:
	var outlet: Vector2i = _nearest_outlet_via_explored()
	if outlet == Pathfinder.UNREACHABLE:
		return ENERGY_RECHARGE_MAX_THRESHOLD
	var route: PackedVector2Array = _find_explored_path(current_grid(), outlet)
	var distance_bonus: float = clampf(float(route.size()) * 0.35, 0.0, 25.0)
	return clampf(ENERGY_RECHARGE_MIN_THRESHOLD + distance_bonus, ENERGY_RECHARGE_MIN_THRESHOLD, ENERGY_RECHARGE_MAX_THRESHOLD)


func _begin_auto_charge() -> bool:
	var outlet: Vector2i = _nearest_outlet_via_explored()
	if outlet != Pathfinder.UNREACHABLE:
		if _chunk_manager.is_outlet_reserved_by_other(outlet, self):
			return false
		var path: PackedVector2Array = _find_explored_path(current_grid(), outlet)
		if path.is_empty() and current_grid() != outlet:
			return false
		_abandon_job()
		_manual_charging = false
		return _begin_charge(outlet)
	
	# Only execute blind teleport charges if we aren't cooling down from a recent jump
	if _teleport_charge_cooldown <= 0.0:
		return _begin_charge_via_teleporter()
		
	return false

## Picks the closest outlet reachable through fog-explored cells only. Bots
## must not magically know the path through undiscovered areas — if the
## only route to an outlet crosses fog, that outlet is hidden from auto and
## manual recharge planning.
func _nearest_outlet_via_explored(origin: Vector2i = Pathfinder.UNREACHABLE) -> Vector2i:
	if _chunk_manager == null:
		return Pathfinder.UNREACHABLE
	var here: Vector2i = current_grid() if origin == Pathfinder.UNREACHABLE else origin
	var best: Vector2i = Pathfinder.UNREACHABLE
	var best_cost: int = 0x7fffffff
	for outlet in _chunk_manager.outlet_cells():
		if _fog != null and not _fog.is_explored(outlet):
			continue
		if _chunk_manager.is_outlet_reserved_by_other(outlet, self):
			continue
		var path: PackedVector2Array = _find_explored_path(here, outlet)
		if path.is_empty() and here != outlet:
			continue
		var cost: int = path.size()
		if cost >= best_cost:
			continue
		best = outlet
		best_cost = cost
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


func _highlight_cell() -> int:
	# Green for all player-issued orders (move, repair, build, recharge).
	# Red for destructive orders (mine, scrape, salvage, attack).
	# Returns -1 for autonomous AI behaviors (wandering, auto-charge, etc.)
	match _state:
		State.FIGHTING:
			return HIGHLIGHT_CELL_RED
		State.MOVING_TO_CHARGE, State.CHARGING:
			return HIGHLIGHT_CELL_GREEN if _manual_charging else -1
		State.MOVING_TO_REPAIR, State.REPAIRING:
			return HIGHLIGHT_CELL_GREEN
		State.MOVING_FREEFORM:
			return HIGHLIGHT_CELL_GREEN
		State.MOVING_TO_BUILD_SITE, State.BUILDING:
			return HIGHLIGHT_CELL_GREEN
		State.MOVING_TO_WORK, State.WORKING:
			if _job is MineJob or _is_scrape_job(_job):
				return HIGHLIGHT_CELL_RED
	return -1


## World-space position the order highlight should mark: the attack target, the
## mine/scrape target, the end of the active path, or the worker once arrived.
func _order_highlight_world_target() -> Vector2:
	if _state == State.FIGHTING and _combat_target != null and is_instance_valid(_combat_target):
		return (_combat_target as Node2D).position
	if (_state == State.MOVING_TO_WORK or _state == State.WORKING) and _job != null:
		if _job is MineJob:
			return Chunk.grid_to_pixel_center((_job as MineJob).target)
		if _job is ScrapeRustJob:
			return Chunk.grid_to_pixel_center((_job as ScrapeRustJob).target)
		if _job is ScrapeBiomassJob:
			return Chunk.grid_to_pixel_center((_job as ScrapeBiomassJob).target)
	if not _path.is_empty():
		return _path[_path.size() - 1]
	if (_state == State.MOVING_TO_CHARGE or _state == State.CHARGING) and _charge_target != Vector2i.ZERO:
		return Chunk.grid_to_pixel_center(_charge_target)
	return position


func _draw() -> void:
	_draw_action_bubble()
	# Draw the 32x32 order highlight on the target tile (move destination, charge
	# / repair point, or attack target) so it reads as a marker on the world,
	# not hidden underneath the worker sprite.
	if _highlighter_atlas != null:
		var cell: int = _highlight_cell()
		if cell >= 0:
			var local_center: Vector2 = _order_highlight_world_target() - position
			var src := Rect2(Vector2(cell * 32.0, 0.0), Vector2(32.0, 32.0))
			draw_texture_rect_region(
				_highlighter_atlas,
				Rect2(local_center - Vector2(16.0, 16.0), Vector2(32.0, 32.0)),
				src,
			)
	if _selected:
		draw_circle(Vector2.ZERO, BODY_RADIUS + 3.0, Color(0, 0, 0, 0))
		draw_arc(Vector2.ZERO, BODY_RADIUS + 3.0, 0.0, TAU, 24, SELECTION_COLOR, 1.0)
	# Rebooting / downed bots get a dim red halo so the player can spot them
	# from across the colony and right-click a save order.
	var downed: bool = _state == State.REBOOTING and not _dead
	
	
	if downed:
		var pulse: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.004)
		draw_arc(Vector2.ZERO, BODY_RADIUS + 5.0, 0.0, TAU, 24, Color(0.95, 0.32, 0.30, pulse), 1.5)
	if _entity_atlas != null:
		var atlas_cell: Vector2i = _facing_atlas_cell()
		var source := Rect2(
			Vector2(atlas_cell.x * int(ENTITY_REGION_SIZE.x), atlas_cell.y * int(ENTITY_REGION_SIZE.y)),
			ENTITY_REGION_SIZE,
		)
		var sprite_modulate: Color = Color(0.7, 0.45, 0.45, 0.85) if downed else Color(1, 1, 1, 1)
		draw_texture_rect_region(
			_entity_atlas,
			Rect2(-ENTITY_REGION_SIZE * 0.5, ENTITY_REGION_SIZE),
			source,
			sprite_modulate,
		)
	else:
		var body_color: Color = BODY_COLOR if not downed else Color(0.55, 0.25, 0.25)
		draw_circle(Vector2.ZERO, BODY_RADIUS, body_color)
	if _carried != null and is_instance_valid(_carried):
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
	var font: Font = ACTION_FONT
	var screen_scale: Vector2 = get_global_transform_with_canvas().get_scale()
	if is_zero_approx(screen_scale.x) or is_zero_approx(screen_scale.y):
		return
	var abs_scale := Vector2(absf(screen_scale.x), absf(screen_scale.y))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 / screen_scale.x, 1.0 / screen_scale.y))
	var anchor := Vector2(
		ACTION_BUBBLE_SCREEN_OFFSET.x * abs_scale.x,
		(-BODY_RADIUS - 8.0) * abs_scale.y,
	)
	var top_y: float = anchor.y
	if not _action_text.is_empty():
		var text_size := font.get_string_size(_action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ACTION_FONT_SIZE)
		var pad := Vector2(4, 3)
		var origin := Vector2(
			roundf(anchor.x - text_size.x * 0.5 - pad.x),
			roundf(anchor.y - text_size.y - pad.y),
		)
		var rect := Rect2(origin, text_size + pad * 2.0)
		draw_rect(rect, Color(0.02, 0.02, 0.03, 0.82))
		draw_rect(rect, Color(0.9, 0.9, 1.0, 0.6), false, 1.0)
		draw_string(font, origin + Vector2(pad.x, text_size.y + pad.y - 1.0),
			_action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ACTION_FONT_SIZE, Color.WHITE)
		top_y = origin.y
	var name_text: String = display_name()
	if not name_text.is_empty():
		var name_size := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE)
		var name_pos := Vector2(
			roundf(anchor.x - name_size.x * 0.5),
			roundf(top_y - name_size.y - 3.0),
		)
		draw_string(font, name_pos + Vector2(1, 1), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE, Color(0.0, 0.0, 0.0, 0.75))
		draw_string(font, name_pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE, Color(0.88, 0.94, 1.0, 0.95))
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
