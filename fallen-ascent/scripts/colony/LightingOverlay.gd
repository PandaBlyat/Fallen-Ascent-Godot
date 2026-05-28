extends Node2D
##
## Fullscreen colony darkness pass. FogOfWar owns LOS/discovery masks;
## this node only applies mood lighting over currently visible cells.
##
## Light-mask changes are smoothed by blending from a saved copy of the
## previous mask (prev_light_mask) to the new one over TRANSITION_SECONDS,
## eliminating the jarring instant jump whenever lights are added/removed
## or chunks stream in.
##

const LIGHTING_SHADER: Shader = preload("res://resources/shaders/lighting_overlay.gdshader")
const LIGHTING_Z_INDEX: int = 850
const TRANSITION_SECONDS: float = 0.35

@export var camera_path: NodePath
@export var chunk_manager_path: NodePath
@export var fog_of_war_path: NodePath
@export var dither_pixel_size: float = 1.0 # Set to 1.0 or 2.0 for higher detail

var _camera: Camera2D
var _chunk_manager: ChunkManager
var _fog: FogOfWar
var _material: ShaderMaterial

## Saved copy of the light mask from the previous refresh, used as the
## "from" texture when animating a transition.
var _prev_light_image: Image = null
var _prev_light_texture: ImageTexture = null
var _light_transition_tween: Tween = null


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
	if SettingsManager != null:
		SettingsManager.settings_changed.connect(_on_settings_changed)

	_refresh_shader_inputs()


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


func _on_camera_moved(world_pos: Vector2, zoom: Vector2) -> void:
	if _material != null:
		_material.set_shader_parameter("camera_zoom", zoom.x)
		_material.set_shader_parameter("camera_position", world_pos)
	queue_redraw()


func _on_visibility_changed(_bounds: Rect2i) -> void:
	_begin_light_transition()
	queue_redraw()


func _on_structure_built(_manager: Node) -> void:
	_begin_light_transition()
	queue_redraw()


func _on_settings_changed() -> void:
	_apply_darkness_settings()
	queue_redraw()


## Capture the current light mask as prev, update shader inputs with the new
## mask, then animate transition_t from 0 → 1.
func _begin_light_transition() -> void:
	_capture_current_as_prev()
	_refresh_shader_inputs()
	_material.set_shader_parameter("transition_t", 0.0)
	if _light_transition_tween != null:
		_light_transition_tween.kill()
	_light_transition_tween = create_tween()
	_light_transition_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_light_transition_tween.tween_method(
		func(t: float) -> void:
			if _material != null:
				_material.set_shader_parameter("transition_t", t)
			queue_redraw(),
		0.0, 1.0, TRANSITION_SECONDS
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


## Saves the fog's current light image into _prev_light_texture so the shader
## can blend FROM it during the upcoming transition.
func _capture_current_as_prev() -> void:
	if _fog == null or _material == null:
		return
	var fog_tex: ImageTexture = _fog.light_mask_texture() as ImageTexture
	if fog_tex == null:
		return
	# Use the saved image from the last refresh as "previous" — this is one
	# update behind the current fog state, which is exactly what we want.
	if _prev_light_image == null:
		# First call: prev = current (no visible change, transition_t will snap to 1)
		var img: Image = fog_tex.get_image()
		if img == null:
			return
		_prev_light_image = img.duplicate() as Image
	if _prev_light_texture == null \
			or _prev_light_texture.get_width() != _prev_light_image.get_width() \
			or _prev_light_texture.get_height() != _prev_light_image.get_height():
		_prev_light_texture = ImageTexture.create_from_image(_prev_light_image)
	else:
		_prev_light_texture.update(_prev_light_image)
	_material.set_shader_parameter("prev_light_mask", _prev_light_texture)


## Save the fog's current light image so the next transition can use it as prev.
func _save_light_snapshot() -> void:
	if _fog == null:
		return
	var fog_tex: ImageTexture = _fog.light_mask_texture() as ImageTexture
	if fog_tex == null:
		return
	var img: Image = fog_tex.get_image()
	if img == null:
		return
	if _prev_light_image == null \
			or _prev_light_image.get_width() != img.get_width() \
			or _prev_light_image.get_height() != img.get_height():
		_prev_light_image = img.duplicate() as Image
	else:
		_prev_light_image.copy_from(img)


func _refresh_shader_inputs() -> void:
	if _material == null or _fog == null:
		return
	_material.set_shader_parameter("visibility_mask", _fog.visibility_mask_texture())
	_material.set_shader_parameter("light_mask", _fog.light_mask_texture())
	_material.set_shader_parameter("mask_origin_grid", Vector2(_fog.visibility_mask_origin()))
	_material.set_shader_parameter("mask_size_grid", Vector2(_fog.visibility_mask_size()))
	_material.set_shader_parameter("tile_pixels", float(Chunk.TILE_PIXELS))
	_material.set_shader_parameter("dither_pixel_size", dither_pixel_size)

	if _camera != null:
		_material.set_shader_parameter("camera_zoom", _camera.zoom.x)
		_material.set_shader_parameter("camera_position", _camera.global_position)

	var scale_factor: float = float(get_viewport().size.x) / get_viewport_rect().size.x
	_material.set_shader_parameter("screen_scale_factor", scale_factor)

	# Ensure prev_light_mask is always bound (use light_mask as fallback on first call).
	if _prev_light_texture == null:
		_material.set_shader_parameter("prev_light_mask", _fog.light_mask_texture())
		_material.set_shader_parameter("transition_t", 1.0)

	_apply_darkness_settings()
	# Save snapshot so the next transition can use this frame as "previous".
	_save_light_snapshot()


func _apply_darkness_settings() -> void:
	if _material == null:
		return
	var darkness: float = clampf(SettingsManager.overall_darkness if SettingsManager != null else 1.0, 0.0, 2.0)
	_material.set_shader_parameter("unlit_alpha", clampf(0.46 * darkness, 0.0, 0.90))
	_material.set_shader_parameter("lit_alpha", clampf(0.020 * darkness, 0.0, 0.25))


func _visible_grid_bounds() -> Rect2i:
	var viewport_size: Vector2 = get_viewport_rect().size
	var zoom: Vector2 = _camera.zoom
	var world_size := viewport_size / zoom
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
