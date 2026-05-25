extends Node2D
##
## Root of the Colony scene. Wires the chunk manager, camera, job board,
## pathfinder, stockpiles, workers, and HUD together based on the SiteData
## chosen on the world map.
##

const ITEM_SCRIPT: Script = preload("res://scripts/colony/Item.gd")
const NEUTRAL_BOT_SCRIPT: Script = preload("res://scripts/colony/NeutralBot.gd")
const INITIAL_NEUTRALS: int = 30

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

var _site_seed: int = 0
var _loading_overlay: Control = null
var _loading_bar: ProgressBar = null
var _loading_label: Label = null
var _spawned_initial_workers: bool = false


func _ready() -> void:
	var site: SiteData = GameState.selected_site as SiteData
	# Fallback for running ColonySite.tscn directly from the editor.
	if site == null:
		site = SiteData.new()
		site.site_seed = 1234567
	_site_seed = site.site_seed
	chunk_manager.setup(site.site_seed)
	static_prop_manager.setup(site.site_seed)
	camera.set_world_bounds(chunk_manager.map_world_rect())

	EventBus.camera_moved.connect(_on_camera_moved)
	EventBus.game_speed_changed.connect(_on_speed_changed)
	EventBus.colony_load_progress.connect(_on_colony_load_progress)

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
	# in the same connected region as the workers.
	var outlet_seed: Vector2i = spawn_cells[0] if not spawn_cells.is_empty() else Vector2i.ZERO
	var placed_outlet: Vector2i = Pathfinder.UNREACHABLE
	for spawn_cell in spawn_cells:
		placed_outlet = chunk_manager.ensure_outlet_near(spawn_cell)
		if placed_outlet != Pathfinder.UNREACHABLE:
			break
	if placed_outlet == Pathfinder.UNREACHABLE:
		chunk_manager.ensure_outlet_near(outlet_seed)
	_spawn_neutral_bots(INITIAL_NEUTRALS)


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


## Called by Workers after they finish a mine: spawn one piece of scrap on
## the now-floor tile, then offer it to the stockpile system.
func spawn_item_at(grid: Vector2i, kind: int = Item.Kind.SCRAP, count: int = 1) -> void:
	var item: Item = ITEM_SCRIPT.new() as Item
	items_root.add_child(item)
	item.setup(grid, kind, count)
	stockpile_manager.on_item_spawned(item)


func has_mineable_static_prop(grid: Vector2i) -> bool:
	return static_prop_manager != null \
		and static_prop_manager.has_method("has_mineable_prop") \
		and bool(static_prop_manager.call("has_mineable_prop", grid))


func static_prop_mine_stand_for(grid: Vector2i, from: Vector2i, pathfinder: Pathfinder) -> Vector2i:
	if static_prop_manager == null:
		return Pathfinder.UNREACHABLE
	return static_prop_manager.call("mine_stand_for", grid, from, pathfinder) as Vector2i


func mine_static_prop_at(grid: Vector2i) -> Dictionary:
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


func _on_camera_moved(_world_pos: Vector2, _zoom: Vector2) -> void:
	pass


func _on_speed_changed(_speed: float) -> void:
	pass
