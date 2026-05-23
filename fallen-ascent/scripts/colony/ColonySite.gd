extends Node2D
##
## Root of the Colony scene. Wires the camera, chunk manager, HUD, and a
## small debug label together based on the SiteData chosen on the world map.
##

@onready var chunk_manager: ChunkManager = $ChunkManager
@onready var camera: CameraController = $Camera
@onready var debug_label: Label = $HUD/DebugLabel


func _ready() -> void:
	var site: SiteData = GameState.selected_site as SiteData
	# Fallback for running ColonySite.tscn directly from the editor.
	if site == null:
		site = SiteData.new()
		site.site_seed = 1234567
	chunk_manager.setup(site.site_seed)

	EventBus.camera_moved.connect(_on_camera_moved)
	EventBus.game_speed_changed.connect(_on_speed_changed)
	_refresh_debug()


func _on_camera_moved(_world_pos: Vector2, _zoom: Vector2) -> void:
	_refresh_debug()


func _on_speed_changed(_speed: float) -> void:
	_refresh_debug()


func _refresh_debug() -> void:
	if debug_label == null:
		return
	var cam_chunk := Vector2i(
		int(floor(camera.position.x / (Chunk.SIZE * Chunk.TILE_PIXELS))),
		int(floor(camera.position.y / (Chunk.SIZE * Chunk.TILE_PIXELS))),
	)
	debug_label.text = "chunks: %d | cam_chunk: %s | speed: %.1fx" % [
		chunk_manager.loaded_count(),
		cam_chunk,
		GameState.game_speed,
	]
