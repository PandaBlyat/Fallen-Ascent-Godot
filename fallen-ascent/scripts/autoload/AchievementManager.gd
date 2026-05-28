extends Node
##
## Tracks and persists achievements across all playthroughs, plus the
## achievement-point (AP) economy they feed. Achievements unlock on first-time
## events (colony milestones, combat, etc.) and each grants a fixed number of
## points. Points are a persistent currency the player spends — once, and
## permanently — in the embark screen to unlock higher part tiers and extra
## starting worker slots.
## Save file: user://achievements.cfg
##

const SAVE_PATH: String = "user://achievements.cfg"

## Static achievement registry. Each entry: id, name, desc, points.
## Add new achievements here; unlock state + spent points live in the save file.
const ACHIEVEMENTS: Array = [
	{"id": &"first_mine", "name": "Into the Rock", "desc": "Mine your first wall tile.", "points": 5},
	{"id": &"first_build", "name": "Foundations", "desc": "Place your first structure.", "points": 5},
	{"id": &"first_stockpile", "name": "Hoarder", "desc": "Designate your first stockpile zone.", "points": 5},
	{"id": &"first_embark", "name": "Into the Dark", "desc": "Start your first colony.", "points": 5},
	{"id": &"first_room", "name": "Shelter", "desc": "Designate your first room.", "points": 10},
	{"id": &"first_workshop", "name": "Workshop", "desc": "Place your first workshop structure.", "points": 10},
	{"id": &"first_worker_dead", "name": "Sacrifice", "desc": "Lose your first worker.", "points": 10},
	{"id": &"first_hostile_killed", "name": "Survivors", "desc": "Destroy your first hostile bot.", "points": 15},
	{"id": &"first_tech_unlock", "name": "Curious Minds", "desc": "Unlock your first technology.", "points": 15},
	{"id": &"first_save", "name": "No Bot Left Behind", "desc": "Rescue a downed worker.", "points": 20},
	{"id": &"workers_5", "name": "Growing Crew", "desc": "Have 5 workers active at once.", "points": 20},
	{"id": &"first_cradle_spawn", "name": "New Life", "desc": "Produce a worker from a Replication Cradle.", "points": 25},
	{"id": &"workers_10", "name": "Small Colony", "desc": "Have 10 workers active at once.", "points": 40},
]

## AP cost to permanently unlock each part tier (tier 1 is free/always on).
const TIER_UNLOCK_COSTS: Dictionary = {2: 10, 3: 25, 4: 50, 5: 90}
## AP cost for each extra starting-worker slot beyond the base count.
const WORKER_SLOT_COSTS: Array[int] = [15, 30, 50]
const BASE_WORKER_SLOTS: int = 3

## Emitted whenever unlock state OR spend state changes, so menus refresh.
signal unlocks_changed

## In-memory set of unlocked achievement ids.
var _unlocked: Dictionary = {}
## Persistent spend state.
var _unlocked_tier: int = 1
var _extra_worker_slots: int = 0
var _spent_points: int = 0


func _ready() -> void:
	_load_achievements()
	_connect_signals()


func _connect_signals() -> void:
	EventBus.tile_changed.connect(_on_tile_changed)
	EventBus.structure_built.connect(_on_structure_built)
	EventBus.combatant_died.connect(_on_combatant_died)
	EventBus.tech_unlocked.connect(_on_tech_unlocked)
	EventBus.worker_spawned_from_cradle.connect(_on_worker_spawned_from_cradle)


## Returns all achievements as Dicts with an "unlocked" key merged in.
func all_achievements() -> Array:
	var out: Array = []
	for ach in ACHIEVEMENTS:
		var copy: Dictionary = (ach as Dictionary).duplicate()
		copy["unlocked"] = _unlocked.has(ach["id"] as StringName)
		out.append(copy)
	return out


## Unlocks an achievement by id. No-ops if already unlocked.
func unlock(id: StringName) -> void:
	if _unlocked.has(id):
		return
	_unlocked[id] = true
	_save_achievements()
	EventBus.achievement_unlocked.emit(id)
	unlocks_changed.emit()


func is_unlocked(id: StringName) -> bool:
	return _unlocked.has(id)


func unlocked_count() -> int:
	return _unlocked.size()


# ---- Achievement-point economy ----------------------------------------------

## Total points earned from every unlocked achievement (lifetime).
func total_points() -> int:
	var sum: int = 0
	for ach in ACHIEVEMENTS:
		if _unlocked.has(ach["id"] as StringName):
			sum += int(ach["points"])
	return sum


## Points still available to spend (earned minus permanently spent).
func available_points() -> int:
	return maxi(0, total_points() - _spent_points)


func spent_points() -> int:
	return _spent_points


## Highest part tier the player has permanently unlocked (1..PartDatabase.MAX_TIER).
func unlocked_tier() -> int:
	return _unlocked_tier


func extra_worker_slots() -> int:
	return _extra_worker_slots


## Number of starting worker slots the player may fill in the embark screen.
func starting_worker_slots() -> int:
	return BASE_WORKER_SLOTS + _extra_worker_slots


## AP cost to unlock the next tier, or -1 when all tiers are unlocked.
func next_tier_cost() -> int:
	var next_tier: int = _unlocked_tier + 1
	if TIER_UNLOCK_COSTS.has(next_tier):
		return int(TIER_UNLOCK_COSTS[next_tier])
	return -1


## AP cost for the next extra worker slot, or -1 at the cap.
func next_worker_slot_cost() -> int:
	if _extra_worker_slots >= WORKER_SLOT_COSTS.size():
		return -1
	return WORKER_SLOT_COSTS[_extra_worker_slots]


## Spend AP to unlock the next part tier. Returns true on success.
func purchase_tier_unlock() -> bool:
	var cost: int = next_tier_cost()
	if cost < 0 or cost > available_points():
		return false
	_unlocked_tier += 1
	_spent_points += cost
	_save_achievements()
	unlocks_changed.emit()
	return true


## Spend AP to unlock the next extra worker slot. Returns true on success.
func purchase_worker_slot() -> bool:
	var cost: int = next_worker_slot_cost()
	if cost < 0 or cost > available_points():
		return false
	_extra_worker_slots += 1
	_spent_points += cost
	_save_achievements()
	unlocks_changed.emit()
	return true


## Called when the player starts a new colony (called from _start_game flow).
func on_new_game_started() -> void:
	unlock(&"first_embark")


func _on_tile_changed(_grid: Vector2i, new_tile: int) -> void:
	if new_tile == TerrainGenerator.TILE_FLOOR:
		unlock(&"first_mine")


func _on_structure_built(_manager: Node) -> void:
	unlock(&"first_build")


func _on_combatant_died(_node: Node, faction: int) -> void:
	if faction == 0:
		unlock(&"first_worker_dead")
	else:
		unlock(&"first_hostile_killed")


func _on_tech_unlocked(_tech_id: StringName) -> void:
	unlock(&"first_tech_unlock")


func _on_worker_spawned_from_cradle(_worker: Node) -> void:
	unlock(&"first_cradle_spawn")


## Called by ColonyHud or RoomManager when a room/stockpile is designated.
func on_stockpile_designated() -> void:
	unlock(&"first_stockpile")


func on_room_designated() -> void:
	unlock(&"first_room")


func on_workshop_placed() -> void:
	unlock(&"first_workshop")


func on_worker_saved() -> void:
	unlock(&"first_save")


func on_worker_count_changed(count: int) -> void:
	if count >= 5:
		unlock(&"workers_5")
	if count >= 10:
		unlock(&"workers_10")


func _load_achievements() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var ids: Array = cfg.get_value("achievements", "unlocked", []) as Array
	for id in ids:
		_unlocked[id as StringName] = true
	_unlocked_tier = clampi(int(cfg.get_value("economy", "unlocked_tier", 1)), 1, PartDatabase.MAX_TIER)
	_extra_worker_slots = maxi(0, int(cfg.get_value("economy", "extra_worker_slots", 0)))
	_spent_points = maxi(0, int(cfg.get_value("economy", "spent_points", 0)))


func _save_achievements() -> void:
	var cfg := ConfigFile.new()
	var ids: Array[StringName] = []
	for id in _unlocked:
		ids.append(id as StringName)
	cfg.set_value("achievements", "unlocked", ids)
	cfg.set_value("economy", "unlocked_tier", _unlocked_tier)
	cfg.set_value("economy", "extra_worker_slots", _extra_worker_slots)
	cfg.set_value("economy", "spent_points", _spent_points)
	cfg.save(SAVE_PATH)
