class_name CameraController
extends Camera2D
##
## Pan (WASD/arrows, MMB drag, edge-scroll) + zoom (mouse wheel, centered on
## cursor). Emits EventBus.camera_moved only when position/zoom changed beyond
## an epsilon — never once-per-frame.
##

@export var pan_speed: float = 600.0           ## pixels/second at zoom 1.0
@export var edge_margin: int = 12              ## pixels from window edge
@export var edge_scroll_enabled: bool = true
@export var zoom_min: float = 0.5
@export var zoom_max: float = 4.0
@export var zoom_step: float = 1.1             ## multiplicative per wheel tick

const _MOVE_EPSILON: float = 1.0               ## px before we re-emit camera_moved
const _ZOOM_EPSILON: float = 0.001

var _dragging: bool = false
var _last_emitted_pos: Vector2 = Vector2.INF
var _last_emitted_zoom: Vector2 = Vector2.ZERO
var _last_real_usec: int = 0
var _has_world_bounds: bool = false
var _world_bounds: Rect2 = Rect2()
var _follow_target: Node2D = null


func _ready() -> void:
	# Pan/zoom must keep working while the sim is paused (Engine.time_scale=0),
	# so we ignore the per-frame delta and use real wall-clock time instead.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_real_usec = Time.get_ticks_usec()
	make_current()
	_apply_camera_settings()
	SettingsManager.settings_changed.connect(_apply_camera_settings)
	# Defer so ColonySite._ready (which sets up ChunkManager) runs first.
	_emit_if_changed.call_deferred(true)


func _apply_camera_settings() -> void:
	pan_speed = SettingsManager.camera_pan_speed
	edge_scroll_enabled = SettingsManager.edge_panning_enabled


func _process(_delta: float) -> void:
	# Wall-clock delta (independent of Engine.time_scale).
	var now: int = Time.get_ticks_usec()
	# Cap real_dt to 0.1s to prevent extreme positional jumps during engine lag spikes.
	var real_dt: float = minf((now - _last_real_usec) / 1_000_000.0, 0.1)
	_last_real_usec = now

	var dir: Vector2 = Vector2(
		Input.get_axis("cam_left", "cam_right"),
		Input.get_axis("cam_up", "cam_down"),
	)
	if edge_scroll_enabled:
		dir += _edge_scroll_dir()
	if dir != Vector2.ZERO:
		clear_follow()
		# Divide by zoom so we move the same SCREEN distance regardless of zoom.
		position += dir.normalized() * pan_speed * real_dt / zoom.x
		_clamp_to_world()
		_emit_if_changed()
	elif _follow_target != null:
		if is_instance_valid(_follow_target):
			position = _follow_target.global_position
			_clamp_to_world()
			_emit_if_changed()
		else:
			clear_follow()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		clear_follow()
		position -= event.relative / zoom.x
		_clamp_to_world()
		_emit_if_changed()


func set_world_bounds(bounds: Rect2) -> void:
	_world_bounds = bounds
	_has_world_bounds = true
	_clamp_to_world()
	_emit_if_changed(true)


func center_on(world_pos: Vector2) -> void:
	position = world_pos
	_clamp_to_world()
	_emit_if_changed(true)


func follow_node(node: Node2D) -> void:
	_follow_target = node
	if _follow_target != null and is_instance_valid(_follow_target):
		center_on(_follow_target.global_position)


func clear_follow() -> void:
	_follow_target = null


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			clear_follow()
		_dragging = event.pressed
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		clear_follow()
		_zoom_at(get_global_mouse_position(), zoom_step, true)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		clear_follow()
		_zoom_at(get_global_mouse_position(), 1.0 / zoom_step, false)


func _zoom_at(world_target: Vector2, factor: float, zoom_in: bool = true) -> void:
	var old_z: float = zoom.x
	var new_z: float = clampf(old_z * factor, zoom_min, zoom_max)
	if is_equal_approx(new_z, old_z):
		return

	zoom = Vector2(new_z, new_z)
	# Mathematical offset to ensure the target world point remains stationary under the cursor.
	# This bypasses potential engine frame delays when calling get_global_mouse_position() mid-frame.
	position += (world_target - position) * (1.0 - old_z / new_z)
	_clamp_to_world()
	_emit_if_changed()
	if zoom_in:
		AudioManager.play_zoom_in()
	else:
		AudioManager.play_zoom_out()


func _edge_scroll_dir() -> Vector2:
	# Ignore edge scrolling if hovering over interactive UI panels or elements.
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return Vector2.ZERO

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var m: Vector2 = get_viewport().get_mouse_position()
	var d := Vector2.ZERO
	if m.x < edge_margin:           d.x -= 1.0
	elif m.x > vp.x - edge_margin:  d.x += 1.0
	if m.y < edge_margin:           d.y -= 1.0
	elif m.y > vp.y - edge_margin:  d.y += 1.0
	return d


func _emit_if_changed(force: bool = false) -> void:
	if not force:
		if position.distance_to(_last_emitted_pos) < _MOVE_EPSILON \
		and absf(zoom.x - _last_emitted_zoom.x) < _ZOOM_EPSILON:
			return
	_last_emitted_pos = position
	_last_emitted_zoom = zoom
	EventBus.camera_moved.emit(position, zoom)


func _clamp_to_world() -> void:
	if not _has_world_bounds:
		return
	var view_size: Vector2 = get_viewport().get_visible_rect().size / zoom.x
	var half: Vector2 = view_size * 0.5
	var min_pos: Vector2 = _world_bounds.position + half
	var max_pos: Vector2 = _world_bounds.position + _world_bounds.size - half
	if min_pos.x > max_pos.x:
		position.x = _world_bounds.get_center().x
	else:
		position.x = clampf(position.x, min_pos.x, max_pos.x)
	if min_pos.y > max_pos.y:
		position.y = _world_bounds.get_center().y
	else:
		position.y = clampf(position.y, min_pos.y, max_pos.y)
