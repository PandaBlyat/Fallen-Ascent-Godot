extends Node
##
## Owns colony save/load. Snapshots are plain-data Dictionaries written with
## FileAccess.store_var (handles Vector2i / Color / nested Array+Dictionary
## without manual JSON), so no Object references are ever serialized.
##
## ColonySite.capture_save() builds the snapshot; ColonySite applies a snapshot
## on _ready when one is pending (see begin_load -> consume_pending_load).
##
## Multiple save slots are stored as user://save_0.sav, user://save_1.sav, …
## The default quick-save slot is save_0.sav (SAVE_PATH). Legacy user://save.sav
## is treated as slot 0 if present and the new slot file is absent.
##

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://save_0.sav"
const SAVE_LEGACY_PATH: String = "user://save.sav"
const SAVE_SLOT_COUNT: int = 5
const COLONY_SCENE_PATH: String = "res://scenes/colony/ColonySite.tscn"

## Stashed between begin_load() and the colony scene's _ready, since the snapshot
## can only be applied after the new scene's nodes exist.
var _pending_load: Dictionary = {}


func has_save(path: String = "") -> bool:
	if path.is_empty():
		return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_LEGACY_PATH)
	return FileAccess.file_exists(path)


## Returns a list of all available save slots, newest first.
## Each entry: { path, slot, modified_unix, size_bytes }
func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Check slot files.
	for i in SAVE_SLOT_COUNT:
		var path: String = _slot_path(i)
		if FileAccess.file_exists(path):
			out.append(_save_entry(path, i))
	# Include legacy save if present and not duplicated by slot 0.
	if FileAccess.file_exists(SAVE_LEGACY_PATH) and not FileAccess.file_exists(SAVE_PATH):
		out.append(_save_entry(SAVE_LEGACY_PATH, 0))
	# Sort newest first.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("modified_unix", 0)) > int(b.get("modified_unix", 0))
	)
	return out


## Delete a save file. Returns true on success.
func delete_save(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	DirAccess.remove_absolute(path)
	return not FileAccess.file_exists(path)


## Capture the currently running colony and write it to disk. Returns false if
## no colony scene is active (e.g. called from the main menu).
func save_current_game(path: String = SAVE_PATH) -> bool:
	var scene: Node = _current_scene()
	if scene == null or not scene.has_method("capture_save"):
		return false
	var data: Dictionary = scene.call("capture_save")
	data["version"] = SAVE_VERSION
	return _write(data, path)


## Read a save and switch to the colony scene, which restores from the snapshot.
## Returns false if the save is missing or unreadable.
func begin_load(path: String = "") -> bool:
	if path.is_empty():
		# Default: prefer new slot file, fall back to legacy.
		if FileAccess.file_exists(SAVE_PATH):
			path = SAVE_PATH
		elif FileAccess.file_exists(SAVE_LEGACY_PATH):
			path = SAVE_LEGACY_PATH
		else:
			return false
	return _do_load(path)


func _do_load(path: String) -> bool:
	var data: Dictionary = _read(path)
	if data.is_empty():
		return false
	# Seed / map size must be set on GameState before ColonySite._ready boots
	# the deterministic world generation.
	GameState.set_world_seed(int(data.get("world_seed", 0)))
	GameState.requested_map_size_chunks = data.get("map_size_chunks", Vector2i.ZERO) as Vector2i
	var site := SiteData.new()
	site.site_seed = int(data.get("site_seed", 0))
	site.grid_pos = Vector2i.ZERO
	site.biome = int(data.get("biome", 0))
	GameState.set_selected_site(site)
	GameState.set_game_speed(float(data.get("game_speed", 1.0)))
	_pending_load = data
	_current_tree().change_scene_to_file(COLONY_SCENE_PATH)
	return true


## ColonySite pulls (and clears) the pending snapshot during _ready.
func consume_pending_load() -> Dictionary:
	var d: Dictionary = _pending_load
	_pending_load = {}
	return d


func _slot_path(slot: int) -> String:
	return "user://save_%d.sav" % slot


func _save_entry(path: String, slot: int) -> Dictionary:
	var modified: int = 0
	var size: int = 0
	if FileAccess.file_exists(path):
		modified = FileAccess.get_modified_time(path)
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f != null:
			size = f.get_length()
			f.close()
	return {"path": path, "slot": slot, "modified_unix": modified, "size_bytes": size}


func _write(data: Dictionary, path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: could not open %s for writing" % path)
		return false
	f.store_var(data, false)
	f.close()
	return true


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v: Variant = f.get_var(false)
	f.close()
	return v if v is Dictionary else {}


func _current_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _current_scene() -> Node:
	var tree: SceneTree = _current_tree()
	return tree.current_scene if tree != null else null
