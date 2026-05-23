extends Node2D
##
## Root of the Colony scene. Wires the chunk manager, camera, job board,
## pathfinder, stockpiles, workers, and HUD together based on the SiteData
## chosen on the world map.
##

const ITEM_SCRIPT: Script = preload("res://scripts/colony/Item.gd")

@onready var chunk_manager: ChunkManager = $ChunkManager
@onready var camera: CameraController = $Camera
@onready var job_board: JobBoard = $JobBoard
@onready var pathfinder: Pathfinder = $Pathfinder
@onready var stockpile_manager: StockpileManager = $StockpileManager
@onready var items_root: Node2D = $Items
@onready var workers_root: Node2D = $Workers
@onready var designator: Designator = $Designator
@onready var debug_label: Label = $HUD/DebugLabel
@onready var mode_label: Label = $HUD/ModeLabel


func _ready() -> void:
	var site: SiteData = GameState.selected_site as SiteData
	# Fallback for running ColonySite.tscn directly from the editor.
	if site == null:
		site = SiteData.new()
		site.site_seed = 1234567
	chunk_manager.setup(site.site_seed)

	EventBus.camera_moved.connect(_on_camera_moved)
	EventBus.game_speed_changed.connect(_on_speed_changed)
	job_board.job_added.connect(_on_jobs_changed)
	job_board.job_completed.connect(_on_jobs_changed)
	job_board.job_cancelled.connect(_on_jobs_changed)
	stockpile_manager.stockpile_changed.connect(_refresh_debug)
	designator.mode_changed.connect(_on_mode_changed)

	# Workers need terrain to be queryable, so spawn after the first chunk batch.
	call_deferred("_spawn_initial_workers")
	_refresh_debug()
	_refresh_mode_label()


func _spawn_initial_workers() -> void:
	WorkerSpawner.spawn(
		WorkerSpawner.INITIAL_WORKERS,
		Vector2i.ZERO,
		chunk_manager,
		job_board,
		pathfinder,
		stockpile_manager,
		items_root,
		workers_root,
		self,
	)
	_refresh_debug()


## Called by Workers after they finish a mine: spawn one piece of scrap on
## the now-floor tile, then offer it to the stockpile system.
func spawn_item_at(grid: Vector2i) -> void:
	var item: Item = ITEM_SCRIPT.new() as Item
	items_root.add_child(item)
	item.setup(grid, Item.Kind.SCRAP)
	stockpile_manager.on_item_spawned(item)
	_refresh_debug()


func _on_camera_moved(_world_pos: Vector2, _zoom: Vector2) -> void:
	_refresh_debug()


func _on_speed_changed(_speed: float) -> void:
	_refresh_debug()


func _on_jobs_changed(_job: Job) -> void:
	_refresh_debug()


func _on_mode_changed(_mode: int) -> void:
	_refresh_mode_label()


func _refresh_debug() -> void:
	if debug_label == null:
		return
	var cam_chunk := Vector2i(
		int(floor(camera.position.x / (Chunk.SIZE * Chunk.TILE_PIXELS))),
		int(floor(camera.position.y / (Chunk.SIZE * Chunk.TILE_PIXELS))),
	)
	var workers: int = workers_root.get_child_count() if workers_root != null else 0
	var loose_items: int = items_root.get_child_count() if items_root != null else 0
	var stored: int = stockpile_manager.total_stored() if stockpile_manager != null else 0
	debug_label.text = "chunks:%d cam_chunk:%s speed:%.1fx | workers:%d jobs:%d loose:%d scrap:%d" % [
		chunk_manager.loaded_count(),
		cam_chunk,
		GameState.game_speed,
		workers,
		job_board.pending_count() if job_board != null else 0,
		loose_items,
		stored,
	]


func _refresh_mode_label() -> void:
	if mode_label == null or designator == null:
		return
	mode_label.text = "mode: %s   [M] mine   [B] stockpile   [Esc] cancel" % designator.mode_label()
