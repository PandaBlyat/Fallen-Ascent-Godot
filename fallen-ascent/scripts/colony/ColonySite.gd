extends Node2D
##
## Root of the Colony scene. Wires the chunk manager, camera, job board,
## pathfinder, stockpiles, workers, and HUD together based on the SiteData
## chosen on the world map.
##

const ITEM_SCRIPT: Script = preload("res://scripts/colony/Item.gd")
const NEUTRAL_BOT_SCRIPT: Script = preload("res://scripts/colony/NeutralBot.gd")
const ALERT_SYSTEM_SCRIPT: Script = preload("res://scripts/ui/AlertSystem.gd")
const INITIAL_NEUTRALS: int = 30
## How often (seconds) to check if a hostile has entered any worker's FOV.
const HOSTILE_FOV_CHECK_SEC: float = 1.5

@onready var chunk_manager: ChunkManager = $ChunkManager
@onready var camera: CameraController = $Camera
@onready var job_board: JobBoard = $JobBoard
@onready var pathfinder: Pathfinder = $Pathfinder
@onready var stockpile_manager: StockpileManager = $StockpileManager
@onready var structure_manager: StructureManager = $StructureManager
@onready var static_prop_manager: Node = $StaticPropManager
@onready var items_root: Node2D = $Items
@onready var workers_root: Node2D = $Workers
@onready var neutrals_root: Node2D = $Neutrals
@onready var hostiles_root: Node2D = $Hostiles
@onready var designator: Designator = $Designator
@onready var fog_of_war: FogOfWar = $FogOfWar
@onready var room_manager: RoomManager = $RoomManager

const HOSTILE_BOT_SCRIPT: Script = preload("res://scripts/colony/HostileBot.gd")
const WORKER_SCRIPT: Script = preload("res://scripts/colony/Worker.gd")

var _site_seed: int = 0
var _loading_overlay: Control = null
var _loading_bar: ProgressBar = null
var _loading_label: Label = null
var _spawned_initial_workers: bool = false
var _alert_system: Node = null
## Tracks which hostile nodes have already triggered a "spotted" alert.
var _spotted_hostiles: Dictionary = {}
## Snapshot to restore instead of fresh-spawning, set when the colony scene is
## entered via SaveManager.begin_load. Empty for a brand-new game.
var _pending_load: Dictionary = {}
## Wall-clock msec of the last autosave; 0 until the first interval elapses.
var _last_autosave_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pending_load = SaveManager.consume_pending_load()
	var site: SiteData = GameState.selected_site as SiteData
	# Fallback for running ColonySite.tscn directly from the editor.
	if site == null:
		site = SiteData.new()
		site.site_seed = 1234567
	_site_seed = site.site_seed
	if GameState.requested_map_size_chunks.x > 0 and GameState.requested_map_size_chunks.y > 0:
		chunk_manager.map_size_chunks = GameState.requested_map_size_chunks
	chunk_manager.setup(site.site_seed)
	structure_manager.setup(site.site_seed)
	static_prop_manager.setup(site.site_seed)
	camera.set_world_bounds(chunk_manager.map_world_rect())

	EventBus.camera_moved.connect(_on_camera_moved)
	EventBus.game_speed_changed.connect(_on_speed_changed)
	EventBus.colony_load_progress.connect(_on_colony_load_progress)

	_alert_system = ALERT_SYSTEM_SCRIPT.new() as Node
	_alert_system.name = "AlertSystem"
	$HUD.add_child(_alert_system)
	if _alert_system.has_method("set_camera"):
		_alert_system.call("set_camera", camera)

	if chunk_manager.preload_entire_map:
		_show_loading_overlay()
	else:
		# Workers need terrain to be queryable, so spawn after the first chunk batch.
		call_deferred("_spawn_initial_workers")


func _spawn_initial_workers() -> void:
	if _spawned_initial_workers:
		return
	_spawned_initial_workers = true
	if static_prop_manager != null and static_prop_manager.has_method("generate_now_at"):
		static_prop_manager.call("generate_now_at", Vector2i.ZERO)
	if not _pending_load.is_empty():
		_restore_from_save(_pending_load)
		_pending_load = {}
		return
	var spawn_cells: Array[Vector2i] = WorkerSpawner.spawn(
		WorkerSpawner.INITIAL_WORKERS,
		Vector2i.ZERO,
		chunk_manager,
		job_board,
		pathfinder,
		stockpile_manager,
		items_root,
		workers_root,
		self,
		fog_of_war,
		structure_manager,
		room_manager,
	)
	# Seed an outlet inside the actual spawn room. Using a spawn cell as the
	# BFS origin (instead of Vector2i.ZERO) guarantees the placed outlet sits
	# in the same connected region as the workers. If the BFS-based placement
	# fails (no eligible floor in the room flood), fall back to converting the
	# spawn cell itself so workers never end up stranded without charge.
	var outlet_seed: Vector2i = spawn_cells[0] if not spawn_cells.is_empty() else Vector2i.ZERO
	var placed_outlet: Vector2i = Pathfinder.UNREACHABLE
	if chunk_manager.has_method("ensure_spawn_outlet"):
		placed_outlet = chunk_manager.ensure_spawn_outlet(spawn_cells, outlet_seed)
	if placed_outlet == Pathfinder.UNREACHABLE:
		for spawn_cell in spawn_cells:
			placed_outlet = chunk_manager.ensure_outlet_near(spawn_cell)
			if placed_outlet != Pathfinder.UNREACHABLE:
				break
	if placed_outlet == Pathfinder.UNREACHABLE:
		placed_outlet = chunk_manager.force_outlet_on_spawn(spawn_cells, outlet_seed)
	_spawn_neutral_bots(INITIAL_NEUTRALS)
	# Notify alert system of the initial outlet count.
	EventBus.outlet_count_changed.emit(chunk_manager.outlet_count())


func _show_loading_overlay() -> void:
	Engine.time_scale = 0.0
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
	designator.set_process_unhandled_input(false)
	$SelectionController.set_process_unhandled_input(false)

	var overlay := Control.new()
	overlay.name = "LoadingOverlay"
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 200
	overlay.modulate = Color.WHITE
	_loading_overlay = overlay
	$HUD.add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.03, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -180.0
	box.offset_right = 180.0
	box.offset_top = -34.0
	box.offset_bottom = 34.0
	box.add_theme_constant_override("separation", 10)
	overlay.add_child(box)

	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.92, 0.96, 0.97, 1.0))
	label.text = "loading colony 0 / 0"
	_loading_label = label
	box.add_child(label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(360, 18)
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	_loading_bar = bar
	box.add_child(bar)


func _hide_loading_overlay() -> void:
	if static_prop_manager != null and static_prop_manager.has_method("generate_all_pending_now"):
		if _loading_label != null:
			_loading_label.text = "loading props"
		static_prop_manager.call("generate_all_pending_now")
	if _loading_overlay != null and is_instance_valid(_loading_overlay):
		_loading_overlay.queue_free()
	_loading_overlay = null
	_loading_bar = null
	_loading_label = null
	Engine.time_scale = GameState.game_speed
	camera.set_process(true)
	camera.set_process_unhandled_input(true)
	designator.set_process_unhandled_input(true)
	$SelectionController.set_process_unhandled_input(true)
	_spawn_initial_workers()


func _on_colony_load_progress(loaded: int, total: int) -> void:
	if _loading_overlay == null:
		return
	var safe_total: int = maxi(total, 1)
	if _loading_bar != null:
		_loading_bar.max_value = safe_total
		_loading_bar.value = clampi(loaded, 0, safe_total)
	if _loading_label != null:
		_loading_label.text = "loading colony %d / %d" % [loaded, total]
	if total > 0 and loaded >= total:
		_hide_loading_overlay()


func _spawn_neutral_bots(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_site_seed, "neutral_bots"])
	var bounds: Rect2i = chunk_manager.map_grid_bounds()
	var spawned: int = 0
	var attempts: int = 0
	while spawned < count and attempts < count * 160:
		attempts += 1
		var cell := Vector2i(
			rng.randi_range(bounds.position.x, bounds.position.x + bounds.size.x - 1),
			rng.randi_range(bounds.position.y, bounds.position.y + bounds.size.y - 1),
		)
		if not chunk_manager.is_walkable(cell):
			continue
		var bot := NEUTRAL_BOT_SCRIPT.new() as NeutralBot
		bot.name = "Neutral_%02d" % (spawned + 1)
		bot.setup(chunk_manager, pathfinder, fog_of_war)
		bot.position = Chunk.grid_to_pixel_center(cell)
		neutrals_root.add_child(bot)
		spawned += 1


## ---- Save / load ------------------------------------------------------------

## Build a full plain-data snapshot of the colony. Called by SaveManager.
func capture_save() -> Dictionary:
	var site: SiteData = GameState.selected_site as SiteData
	return {
		"world_seed": GameState.world_seed,
		"site_seed": _site_seed,
		"biome": int(site.biome) if site != null else 0,
		"map_size_chunks": chunk_manager.map_size_chunks,
		"game_speed": GameState.game_speed,
		"camera_pos": camera.position,
		"camera_zoom": camera.zoom,
		"chunks": chunk_manager.capture_save(),
		"stockpiles": stockpile_manager.capture_save(),
		"structures": structure_manager.capture_save(),
		"static_props": static_prop_manager.call("capture_save") if static_prop_manager.has_method("capture_save") else {},
		"rooms": room_manager.capture_save(),
		"fog": fog_of_war.capture_save(),
		"tech": TechManager.capture_save(),
		"jobs": job_board.capture_save(),
		"workers": _capture_workers(),
		"items": _capture_loose_items(),
		"neutrals": _capture_bots(neutrals_root),
		"hostiles": _capture_bots(hostiles_root),
	}


## Rebuild the colony from a snapshot. Ordering matters: tiles first (so terrain
## queries are correct), then stockpiles (storage-bin structures register into
## them), structures, world objects, then live agents, then fog + designations.
func _restore_from_save(data: Dictionary) -> void:
	if static_prop_manager != null and static_prop_manager.has_method("generate_all_pending_now"):
		static_prop_manager.call("generate_all_pending_now")
	chunk_manager.restore_save(data.get("chunks", {}) as Dictionary)
	if static_prop_manager != null and static_prop_manager.has_method("restore_save"):
		static_prop_manager.call("restore_save", data.get("static_props", {}) as Dictionary)
	stockpile_manager.restore_save(data.get("stockpiles", {}) as Dictionary)
	structure_manager.restore_save(data.get("structures", {}) as Dictionary)
	_restore_loose_items(data.get("items", []) as Array)
	room_manager.restore_save(data.get("rooms", {}) as Dictionary)
	TechManager.restore_save(data.get("tech", {}) as Dictionary)
	_restore_workers(data.get("workers", []) as Array)
	_restore_bots(neutrals_root, data.get("neutrals", []) as Array, NEUTRAL_BOT_SCRIPT, "Neutral")
	_restore_bots(hostiles_root, data.get("hostiles", []) as Array, HOSTILE_BOT_SCRIPT, "Hostile")
	fog_of_war.restore_save(data.get("fog", {}) as Dictionary)
	job_board.restore_save(data.get("jobs", {}) as Dictionary)
	camera.zoom = data.get("camera_zoom", camera.zoom) as Vector2
	camera.position = data.get("camera_pos", camera.position) as Vector2
	EventBus.camera_moved.emit(camera.position, camera.zoom)
	EventBus.outlet_count_changed.emit(chunk_manager.outlet_count())
	stockpile_manager.stockpile_changed.emit()


func _capture_workers() -> Array:
	var out: Array = []
	for child in workers_root.get_children():
		var w := child as Worker
		if w != null and is_instance_valid(w):
			out.append(w.capture_save())
	return out


func _restore_workers(arr: Array) -> void:
	for raw in arr:
		var d: Dictionary = raw
		var w := WORKER_SCRIPT.new() as Worker
		w.name = str(d.get("name", "bot"))
		w.setup(
			job_board, pathfinder, chunk_manager, stockpile_manager,
			items_root, self, fog_of_war, structure_manager, room_manager,
		)
		w.position = d.get("pos", Vector2.ZERO) as Vector2
		workers_root.add_child(w)
		w.restore_save(d)
		var carried: Dictionary = d.get("carried", {}) as Dictionary
		if not carried.is_empty():
			spawn_item_at(w.current_grid(), int(carried["kind"]), int(carried["count"]))


func _capture_loose_items() -> Array:
	var out: Array = []
	for child in items_root.get_children():
		var it := child as Item
		if it != null and is_instance_valid(it):
			out.append([it.grid, int(it.kind), int(it.count)])
	return out


func _restore_loose_items(arr: Array) -> void:
	for raw in arr:
		var e: Array = raw
		spawn_item_at(e[0] as Vector2i, int(e[1]), int(e[2]))


func _capture_bots(root: Node2D) -> Array:
	var out: Array = []
	if root == null:
		return out
	for child in root.get_children():
		if not is_instance_valid(child) or not (child is Node2D):
			continue
		if child.has_method("is_alive") and not bool(child.call("is_alive")):
			continue
		var hp: float = 0.0
		if child.has_method("combat_stats"):
			var st: Object = child.call("combat_stats")
			if st != null:
				hp = float(st.get("hp"))
		out.append([(child as Node2D).position, hp])
	return out


func _restore_bots(root: Node2D, arr: Array, script: Script, prefix: String) -> void:
	if root == null:
		return
	var i: int = 0
	for raw in arr:
		var e: Array = raw
		var bot: Node2D = script.new() as Node2D
		bot.name = "%s_%03d" % [prefix, i]
		if bot.has_method("setup"):
			bot.call("setup", chunk_manager, pathfinder, fog_of_war)
		bot.position = e[0] as Vector2
		root.add_child(bot)
		if bot.has_method("combat_stats"):
			var st: Object = bot.call("combat_stats")
			if st != null:
				st.set("hp", float(e[1]))
		i += 1


func _maybe_autosave(now_msec: int) -> void:
	var interval: int = SettingsManager.autosave_interval
	if interval <= 0:
		return
	if _last_autosave_msec == 0:
		_last_autosave_msec = now_msec
		return
	if now_msec - _last_autosave_msec >= interval * 1000:
		_last_autosave_msec = now_msec
		SaveManager.save_current_game()


## Called by Workers after they finish a mine: spawn one piece of scrap on
## the now-floor tile, then offer it to the stockpile system.
func spawn_item_at(grid: Vector2i, kind: int = Item.Kind.SCRAP, count: int = 1) -> void:
	var item: Item = ITEM_SCRIPT.new() as Item
	items_root.add_child(item)
	item.setup(grid, kind, count)
	stockpile_manager.on_item_spawned(item)


func has_mineable_static_prop(grid: Vector2i) -> bool:
	if structure_manager != null \
			and structure_manager.has_method("has_scrappable_structure") \
			and bool(structure_manager.call("has_scrappable_structure", grid)):
		return true
	return static_prop_manager != null \
		and static_prop_manager.has_method("has_mineable_prop") \
		and bool(static_prop_manager.call("has_mineable_prop", grid))


func static_prop_mine_stand_for(grid: Vector2i, from: Vector2i, pathfinder: Pathfinder) -> Vector2i:
	if structure_manager != null \
			and structure_manager.has_method("has_scrappable_structure") \
			and bool(structure_manager.call("has_scrappable_structure", grid)):
		return structure_manager.call("scrap_stand_for", grid, from, pathfinder) as Vector2i
	if static_prop_manager == null:
		return Pathfinder.UNREACHABLE
	return static_prop_manager.call("mine_stand_for", grid, from, pathfinder) as Vector2i


func mine_static_prop_at(grid: Vector2i) -> Dictionary:
	if structure_manager != null \
			and structure_manager.has_method("has_scrappable_structure") \
			and bool(structure_manager.call("has_scrappable_structure", grid)):
		return structure_manager.call("scrap_structure_at", grid) as Dictionary
	if static_prop_manager == null:
		return {}
	return static_prop_manager.call("mine_prop_at", grid) as Dictionary


func can_place_blueprint(blueprint_id: int, anchor: Vector2i, rotation: int = 0) -> bool:
	return structure_manager != null and structure_manager.can_place_blueprint(blueprint_id, anchor, rotation)


func build_structure(blueprint_id: int, anchor: Vector2i, rotation: int = 0) -> void:
	if structure_manager == null:
		return
	structure_manager.build_structure(blueprint_id, anchor, rotation)


func cancel_build_with_refund(anchor: Vector2i) -> bool:
	if job_board == null:
		return false
	var job: BuildJob = job_board.cancel_build_at(anchor)
	if job == null:
		return false
	var refund: Dictionary = job.refund_items()
	for kind in refund.keys():
		var amount: int = int(refund[kind])
		if amount <= 0:
			continue
		spawn_item_at(_refund_spawn_cell(job.anchor), int(kind), amount)
	return true


func _refund_spawn_cell(anchor: Vector2i) -> Vector2i:
	if chunk_manager.is_walkable(anchor):
		return anchor
	const OFFSETS: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	for off in OFFSETS:
		var candidate: Vector2i = anchor + off
		if chunk_manager.is_walkable(candidate):
			return candidate
	return anchor


## Wall-clock timer for hostile FOV check — runs even when paused.
var _hostile_fov_real_msec: int = 0


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _hostile_fov_real_msec >= int(HOSTILE_FOV_CHECK_SEC * 1000.0):
		_hostile_fov_real_msec = now
		_check_hostile_fov()
	_maybe_autosave(now)


func _check_hostile_fov() -> void:
	if workers_root == null or hostiles_root == null:
		return
	var workers: Array = workers_root.get_children()
	var all_hostiles: Array = hostiles_root.get_children()
	if neutrals_root != null:
		all_hostiles.append_array(neutrals_root.get_children())
	for hostile in all_hostiles:
		if not is_instance_valid(hostile):
			continue
		if hostile.has_method("is_alive") and not bool(hostile.call("is_alive")):
			continue
		if not (hostile is Node2D):
			continue
		var h_grid: Vector2i = Vector2i(
			int(floor((hostile as Node2D).global_position.x / Chunk.TILE_PIXELS)),
			int(floor((hostile as Node2D).global_position.y / Chunk.TILE_PIXELS)),
		)
		for worker_node in workers:
			var worker := worker_node as Worker
			if worker == null or not is_instance_valid(worker) or worker.is_downed():
				continue
			var sight: int = worker.sight_radius()
			var w_grid: Vector2i = worker.current_grid()
			var dist: int = maxi(absi(h_grid.x - w_grid.x), absi(h_grid.y - w_grid.y))
			if dist <= sight:
				if not _spotted_hostiles.has(hostile):
					_spotted_hostiles[hostile] = true
					EventBus.hostile_spotted.emit(hostile, worker)
				break
	# Clean up dead hostiles from the spotted set.
	var to_remove: Array = []
	for hostile in _spotted_hostiles.keys():
		if not is_instance_valid(hostile):
			to_remove.append(hostile)
		elif hostile.has_method("is_alive") and not bool(hostile.call("is_alive")):
			to_remove.append(hostile)
	for h in to_remove:
		_spotted_hostiles.erase(h)


func _on_camera_moved(_world_pos: Vector2, _zoom: Vector2) -> void:
	pass


func _on_speed_changed(_speed: float) -> void:
	pass
