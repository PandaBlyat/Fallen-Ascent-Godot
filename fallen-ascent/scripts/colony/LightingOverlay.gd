extends Node2D
##
## Fullscreen colony darkness pass. FogOfWar owns LOS/discovery masks;
## this node only applies mood lighting over currently visible cells.
##

const LIGHTING_SHADER: Shader = preload("res://resources/shaders/lighting_overlay.gdshader")
const LIGHTING_Z_INDEX: int = 850

@export var camera_path: NodePath
@export var chunk_manager_path: NodePath
@export var fog_of_war_path: NodePath

var _camera: Camera2D
var _chunk_manager: ChunkManager
var _fog: FogOfWar
var _material: ShaderMaterial
var _shader_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = LIGHTING_Z_INDEX
	_camera = get_node(camera_path) as Camera2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_fog = get_node(fog_of_war_path) as FogOfWar
	_material = ShaderMaterial.new()
	_material.shader = LIGHTING_SHADER
	material = _material
	EventBus.camera_moved.connect(_on_camera_moved)
	EventBus.visibility_changed.connect(_on_visibility_changed)
	EventBus.structure_built.connect(_on_structure_built)
	_refresh_shader_inputs()


func _process(delta: float) -> void:
	if _material == null:
		return
	_shader_time += delta
	_material.set_shader_parameter("time_seconds", _shader_time)
	queue_redraw()


func _draw() -> void:
	if _camera == null or _chunk_manager == null or _fog == null:
		return
	if _fog.visibility_mask_texture() == null or _fog.light_mask_texture() == null:
		return
	var bounds: Rect2i = _visible_grid_bounds()
	var map_bounds: Rect2i = _chunk_manager.map_grid_bounds()
	var lo := Vector2i(
		maxi(bounds.position.x, map_bounds.position.x),
		maxi(bounds.position.y, map_bounds.position.y),
	)
	var hi := Vector2i(
		mini(bounds.position.x + bounds.size.x, map_bounds.position.x + map_bounds.size.x),
		mini(bounds.position.y + bounds.size.y, map_bounds.position.y + map_bounds.size.y),
	)
	if hi.x <= lo.x or hi.y <= lo.y:
		return
	var rect := Rect2(
		Vector2(lo * Chunk.TILE_PIXELS),
		Vector2((hi - lo) * Chunk.TILE_PIXELS),
	)
	draw_rect(rect, Color.WHITE)


func _on_camera_moved(_world_pos: Vector2, _zoom: Vector2) -> void:
	queue_redraw()


func _on_visibility_changed(_bounds: Rect2i) -> void:
	_refresh_shader_inputs()
	queue_redraw()


func _on_structure_built(_manager: Node) -> void:
	_refresh_shader_inputs()
	queue_redraw()


func _refresh_shader_inputs() -> void:
	if _material == null or _fog == null:
		return
	_material.set_shader_parameter("visibility_mask", _fog.visibility_mask_texture())
	_material.set_shader_parameter("light_mask", _fog.light_mask_texture())
	_material.set_shader_parameter("mask_origin_grid", Vector2(_fog.visibility_mask_origin()))
	_material.set_shader_parameter("mask_size_grid", Vector2(_fog.visibility_mask_size()))
	_material.set_shader_parameter("tile_pixels", float(Chunk.TILE_PIXELS))


func _visible_grid_bounds() -> Rect2i:
	var viewport_size: Vector2 = get_viewport_rect().size
	var zoom: Vector2 = _camera.zoom
	var world_size := Vector2(viewport_size.x / zoom.x, viewport_size.y / zoom.y)
	var top_left: Vector2 = _camera.global_position - world_size * 0.5
	var bottom_right: Vector2 = _camera.global_position + world_size * 0.5
	var lo := Vector2i(
		int(floor(top_left.x / Chunk.TILE_PIXELS)) - 2,
		int(floor(top_left.y / Chunk.TILE_PIXELS)) - 2,
	)
	var hi := Vector2i(
		int(ceil(bottom_right.x / Chunk.TILE_PIXELS)) + 2,
		int(ceil(bottom_right.y / Chunk.TILE_PIXELS)) + 2,
	)
	return Rect2i(lo, hi - lo)
