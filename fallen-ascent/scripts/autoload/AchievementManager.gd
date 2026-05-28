extends Node
##
## Tracks and persists achievements across all playthroughs.
## Achievements unlock on first-time events (colony milestones, combat, etc.).
## Save file: user://achievements.cfg
##

const SAVE_PATH: String = "user://achievements.cfg"

## Static achievement registry. Each entry: id (StringName), name, desc.
## Add new achievements here; the unlock state is stored in the save file.
const ACHIEVEMENTS: Array = [
	{
		"id": &"first_mine",
		"name": "Into the Rock",
		"desc": "Mine your first wall tile.",
	},
	{
		"id": &"first_build",
		"name": "Foundations",
		"desc": "Place your first structure.",
	},
	{
		"id": &"first_worker_dead",
		"name": "Sacrifice",
		"desc": "Lose your first worker.",
	},
	{
		"id": &"first_hostile_killed",
		"name": "Survivors",
		"desc": "Destroy your first hostile bot.",
	},
	{
		"id": &"first_tech_unlock",
		"name": "Curious Minds",
		"desc": "Unlock your first technology.",
	},
	{
		"id": &"first_stockpile",
		"name": "Hoarder",
		"desc": "Designate your first stockpile zone.",
	},
	{
		"id": &"first_room",
		"name": "Shelter",
		"desc": "Designate your first room.",
	},
	{
		"id": &"first_workshop",
		"name": "Workshop",
		"desc": "Place your first workshop structure.",
	},
	{
		"id": &"workers_5",
		"name": "Growing Crew",
		"desc": "Have 5 workers active at once.",
	},
	{
		"id": &"workers_10",
		"name": "Small Colony",
		"desc": "Have 10 workers active at once.",
	},
	{
		"id": &"first_cradle_spawn",
		"name": "New Life",
		"desc": "Produce a worker from a Replication Cradle.",
	},
	{
		"id": &"first_save",
		"name": "No Bot Left Behind",
		"desc": "Rescue a downed worker.",
	},
	{
		"id": &"first_embark",
		"name": "Into the Dark",
		"desc": "Start your first colony.",
	},
]

## In-memory set of unlocked achievement ids.
var _unlocked: Dictionary = {}


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


func is_unlocked(id: StringName) -> bool:
	return _unlocked.has(id)


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


func _save_achievements() -> void:
	var cfg := ConfigFile.new()
	var ids: Array[StringName] = []
	for id in _unlocked:
		ids.append(id as StringName)
	cfg.set_value("achievements", "unlocked", ids)
	cfg.save(SAVE_PATH)
