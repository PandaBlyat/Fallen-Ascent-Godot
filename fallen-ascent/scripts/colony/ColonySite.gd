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
@onready var items_root: Node2D = $Items
@onready var workers_root: Node2D = $Workers
@onready var neutrals_root: Node2D = $Neutrals
@onready var hostiles_root: Node2D = $Hostiles
@onready var designator: Designator = $Designator
@onready var fog_of_war: FogOfWar = $FogOfWar
@onready var room_manager: RoomManager = $RoomManager

var _site_seed: int = 0


func _ready() -> void:
	var site: SiteData = GameState.selected_site as SiteData
	# Fallback for running ColonySite.tscn directly from the editor.
	if site == null:
		site = SiteData.new()
		site.site_seed = 1234567
	_site_seed = site.site_seed
	chunk_manager.setup(site.site_seed)
	camera.set_world_bounds(chunk_manager.map_world_rect())

	EventBus.camera_moved.connect(_on_camera_moved)
	EventBus.game_speed_changed.connect(_on_speed_changed)

	# Workers need terrain to be queryable, so spawn after the first chunk batch.
	call_deferred("_spawn_initial_workers")


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
		fog_of_war,
		structure_manager,
		room_manager,
	)
	_spawn_neutral_bots(INITIAL_NEUTRALS)


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
		bot.setup(chunk_manager, pathfinder, hostiles_root, fog_of_war)
		bot.position = Chunk.grid_to_pixel_center(cell)
		neutrals_root.add_child(bot)
		spawned += 1


## Called by Workers after they finish a mine: spawn one piece of scrap on
## the now-floor tile, then offer it to the stockpile system.
func spawn_item_at(grid: Vector2i, kind: int = Item.Kind.SCRAP) -> void:
	var item: Item = ITEM_SCRIPT.new() as Item
	items_root.add_child(item)
	item.setup(grid, kind, 1)
	stockpile_manager.on_item_spawned(item)


func can_place_blueprint(blueprint_id: int, anchor: Vector2i) -> bool:
	return structure_manager != null and structure_manager.can_place_blueprint(blueprint_id, anchor)


func build_structure(blueprint_id: int, anchor: Vector2i) -> void:
	if structure_manager == null:
		return
	structure_manager.build_structure(blueprint_id, anchor)


func _on_camera_moved(_world_pos: Vector2, _zoom: Vector2) -> void:
	pass


func _on_speed_changed(_speed: float) -> void:
	pass
