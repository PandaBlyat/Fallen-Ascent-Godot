extends Control
class_name PixelSimulationBackground

signal title_formed
signal title_decay_started
signal title_decay_finished
signal state_changed(new_state: State)
signal terminal_glitched(intensity: float)

enum State { BG_RISING, TITLE_RISING, HOLDING, TITLE_DECAYING, BG_DECAYING, PAUSED }

@export_category("Assets")
@export var pixel_shader: Shader 

@export_category("Title Configuration")
@export var title_text: String = "Fallen Ascent":
	set(val):
		title_text = val
		if _label:
			_label.text = title_text
@export var title_font: Font 
@export var font_size: int = 108:
	set(val):
		font_size = val
		if _label and _label.label_settings:
			_label.label_settings.font_size = font_size

@export_category("Subtitle Configuration")
@export var subtitle_text: String = "SYSTEM REBOOT // STAGE_01":
	set(val):
		subtitle_text = val
		if _subtitle_label:
			_subtitle_label.text = subtitle_text
@export var subtitle_font: Font
@export var subtitle_font_size: int = 32:
	set(val):
		subtitle_font_size = val
		if _subtitle_label and _subtitle_label.label_settings:
			_subtitle_label.label_settings.font_size = subtitle_font_size
@export var subtitle_visible: bool = true:
	set(val):
		subtitle_visible = val
		if _subtitle_label:
			_subtitle_label.visible = subtitle_visible

@export_category("Layout Positioning")
@export_range(0.1, 0.9) var title_vertical_position: float = 0.35:
	set(val):
		title_vertical_position = val
		_update_text_container_layout()

@export_category("Timing (Seconds)")
@export var bg_rise_duration: float = 4.0
@export var title_rise_duration: float = 3.0
@export var hold_duration: float = 14.0
@export var title_decay_duration: float = 3.0
@export var bg_decay_duration: float = 2.0
@export var pause_duration: float = 2.0

@export_category("Aesthetics")
@export var base_color: Color = Color(0.82, 0.92, 0.95, 1.0)       # Cyan terminal metal
@export var glow_color: Color = Color(1.0, 0.38, 0.08, 1.0)       # Thermal decay orange
@export var ash_color: Color = Color(0.18, 0.19, 0.22, 1.0)        # Cooling graphite/ash
@export var conduit_color: Color = Color(0.0, 0.72, 0.53, 1.0)     # Machine bus line green
@export var pixel_grid_width: float = 1024.0                       # Raised to 512 for pixel-art readability

@export_category("Simulation Settings")
@export_range(0.0, 2.0) var wind_strength: float = 0.4
@export_range(0.0, 5.0) var decay_gravity: float = 0.6
@export_range(0.0, 1.0) var glitch_intensity: float = 0.4
@export_range(0.0, 1.0) var background_dimness: float = 0.25      
@export var enable_scanlines: bool = true
@export var enable_curvature: bool = true                         
@export var flip_v: bool = false

@export_category("CRT & Lens Customization")
@export_range(0.0, 1.0) var phosphor_intensity: float = 0.07      # RGB phosphor triad bleed strength
@export_range(0.0, 1.0) var glass_reflection: float = 0.06        # Dynamic sweep glare intensity
@export_range(0.05, 0.3) var edge_burn_width: float = 0.06        # Sweep glow boundary thickness
@export_range(0.0, 0.5) var curvature_intensity: float = 0.04     # CRT screen bending bulge intensity (lowered from 0.14)

@export_category("CRT Analog Glitch Settings")
@export var enable_screen_shake: bool = true
@export_range(0.0, 0.1) var max_shake_offset: float = 0.015       # Relative shift multiplier inside screen space UVs
@export var shake_decay: float = 4.5                              # Dampening speed
@export_range(0.0, 2.0) var max_vhold_roll_speed: float = 0.2     # Speed of screen roll during sync failure

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _text_container: VBoxContainer
var _label: Label
var _subtitle_label: Label
var _color_rect: ColorRect
var _shader_material: ShaderMaterial

var _current_state: State = State.BG_RISING
var _state_timer: float = 0.0
var _time_elapsed: float = 0.0
var _last_glitch_state: bool = false
var _selected_wallpaper: Texture2D

# Analog simulation parameters
var _shake_intensity: float = 0.0
var _shake_vector: Vector2 = Vector2.ZERO
var _current_sync_roll: float = 0.0
var _roll_velocity: float = 0.0

var _has_simulated_ui: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_load_random_wallpaper()
	_setup_color_rect()
	_setup_viewport()
	
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	
	await get_tree().process_frame
	
	_setup_shader()

func _load_random_wallpaper() -> void:
	var wp_index: int = randi_range(1, 7)
	var wp_path: String = "res://resources/wallpapers/wallpaper" + str(wp_index) + ".png"
	
	if ResourceLoader.exists(wp_path):
		_selected_wallpaper = load(wp_path) as Texture2D
		if _shader_material:
			_shader_material.set_shader_parameter("wallpaper_texture", _selected_wallpaper)
	else:
		push_error("PixelSimulationBackground: Wallpaper file not found at: " + wp_path)

func _setup_color_rect() -> void:
	_color_rect = ColorRect.new()
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_color_rect)
	_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

func _setup_viewport() -> void:
	_viewport_container = SubViewportContainer.new()
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Set opacity to a tiny fraction above 0.0 so Godot's UI collision engine remains 
	# active, but rendering remains completely invisible to the player.
	_viewport_container.modulate.a = 0.001
	add_child(_viewport_container)
	
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.canvas_item_default_texture_filter = SubViewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	var screen_size = get_viewport_rect().size
	_viewport.size = Vector2i(screen_size)
	
	_viewport_container.add_child(_viewport)
	
	# Layout Container
	_text_container = VBoxContainer.new()
	_viewport.add_child(_text_container)
	_text_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_update_text_container_layout()
	
	# Primary Title Setup
	_label = Label.new()
	_label.text = title_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	var title_settings := LabelSettings.new()
	title_settings.font_size = font_size
	title_settings.font_color = Color.WHITE
	title_settings.outline_size = 12 # Increased for solid pixel presence
	title_settings.outline_color = Color.WHITE
	
	if title_font != null:
		title_settings.font = title_font
		
	_label.label_settings = title_settings
	_text_container.add_child(_label)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	_text_container.add_child(spacer)
	
	# Subtitle Setup
	_subtitle_label = Label.new()
	_subtitle_label.text = subtitle_text
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_label.visible = subtitle_visible
	
	var sub_settings := LabelSettings.new()
	sub_settings.font_size = subtitle_font_size
	sub_settings.font_color = Color.WHITE
	sub_settings.outline_size = 6 # Increased for solid pixel presence
	sub_settings.outline_color = Color.WHITE
	
	if subtitle_font != null:
		sub_settings.font = subtitle_font
	elif title_font != null:
		sub_settings.font = title_font
		
	_subtitle_label.label_settings = sub_settings
	_text_container.add_child(_subtitle_label)

func _update_text_container_layout() -> void:
	if not _text_container:
		return
		
	var vertical_half_span: float = 0.45 if _has_simulated_ui else 0.25
	var top_anchor = clampf(title_vertical_position - vertical_half_span, 0.0, 1.0 - (vertical_half_span * 2.0))
	var bottom_anchor = clampf(title_vertical_position + vertical_half_span, vertical_half_span * 2.0, 1.0)
	
	_text_container.anchor_left = 0.0
	_text_container.anchor_right = 1.0
	_text_container.anchor_top = top_anchor
	_text_container.anchor_bottom = bottom_anchor
	
	_text_container.offset_left = 0
	_text_container.offset_right = 0
	_text_container.offset_top = 0
	_text_container.offset_bottom = 0

func _setup_shader() -> void:
	var shader_resource: Shader = pixel_shader
	
	if shader_resource == null:
		var fallback_path = "res://pixel_simulation.gdshader"
		if ResourceLoader.exists(fallback_path):
			shader_resource = load(fallback_path)
			
	if shader_resource == null:
		shader_resource = Shader.new()
		shader_resource.code = _get_hardcoded_shader_code()
		push_warning("PixelSimulationBackground: External shader not found. Using updated fallback.")
		
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader_resource
	
	_color_rect.material = _shader_material
	_update_shader_parameters()

func _update_shader_parameters() -> void:
	if _shader_material == null:
		return
	_shader_material.set_shader_parameter("text_mask", _viewport.get_texture())
	if _selected_wallpaper != null:
		_shader_material.set_shader_parameter("wallpaper_texture", _selected_wallpaper)
	_shader_material.set_shader_parameter("base_color", base_color)
	_shader_material.set_shader_parameter("glow_color", glow_color)
	_shader_material.set_shader_parameter("ash_color", ash_color)
	_shader_material.set_shader_parameter("conduit_color", conduit_color)
	_shader_material.set_shader_parameter("pixel_grid_width", pixel_grid_width)
	_shader_material.set_shader_parameter("wind_strength", wind_strength)
	_shader_material.set_shader_parameter("decay_gravity", decay_gravity)
	_shader_material.set_shader_parameter("glitch_intensity", glitch_intensity)
	_shader_material.set_shader_parameter("bg_dimness", background_dimness)
	_shader_material.set_shader_parameter("enable_scanlines", enable_scanlines)
	_shader_material.set_shader_parameter("enable_curvature", enable_curvature)
	_shader_material.set_shader_parameter("curvature_intensity", curvature_intensity)
	_shader_material.set_shader_parameter("flip_v", flip_v)
	
	_shader_material.set_shader_parameter("phosphor_intensity", phosphor_intensity)
	_shader_material.set_shader_parameter("glass_reflection", glass_reflection)
	_shader_material.set_shader_parameter("edge_burn_width", edge_burn_width)
	
	var screen_size = get_viewport_rect().size
	var aspect: float = float(screen_size.y) / float(screen_size.x) if screen_size.x > 0 else 0.5625
	_shader_material.set_shader_parameter("aspect_ratio", aspect)

func _process(delta: float) -> void:
	_time_elapsed += delta
	_state_timer += delta
	
	var bg_formation_val: float = 0.0
	var title_formation_val: float = 0.0
	var bg_decay_val: float = 0.0
	var title_decay_val: float = 0.0
	
	match _current_state:
		State.BG_RISING:
			bg_formation_val = clampf(_state_timer / bg_rise_duration, 0.0, 1.0)
			title_formation_val = 0.0
			bg_decay_val = 0.0
			title_decay_val = 0.0
			if _state_timer >= bg_rise_duration:
				_change_state(State.TITLE_RISING)
				
		State.TITLE_RISING:
			bg_formation_val = 1.0
			title_formation_val = clampf(_state_timer / title_rise_duration, 0.0, 1.0)
			bg_decay_val = 0.0
			title_decay_val = 0.0
			if _state_timer >= title_rise_duration:
				_change_state(State.HOLDING)
				title_formed.emit()
				
		State.HOLDING:
			bg_formation_val = 1.0
			title_formation_val = 1.0
			bg_decay_val = 0.0
			title_decay_val = 0.0
			if _state_timer >= hold_duration:
				_change_state(State.TITLE_DECAYING)
				title_decay_started.emit()
				
		State.TITLE_DECAYING:
			bg_formation_val = 1.0
			title_formation_val = 1.0
			bg_decay_val = 0.0
			title_decay_val = clampf(_state_timer / title_decay_duration, 0.0, 1.0)
			if _state_timer >= title_decay_duration:
				_change_state(State.BG_DECAYING)
				title_decay_finished.emit()
				
		State.BG_DECAYING:
			bg_formation_val = 1.0
			title_formation_val = 0.0
			bg_decay_val = clampf(_state_timer / bg_decay_duration, 0.0, 1.0)
			title_decay_val = 1.0
			if _state_timer >= bg_decay_duration:
				_change_state(State.PAUSED)
				
		State.PAUSED:
			bg_formation_val = 0.0
			title_formation_val = 0.0
			bg_decay_val = 1.0
			title_decay_val = 1.0
			if _state_timer >= pause_duration:
				_load_random_wallpaper()
				_change_state(State.BG_RISING)

	_process_glitch_signals()
	_process_analog_sync_simulation(delta)

	if _shader_material != null:
		_shader_material.set_shader_parameter("bg_formation", bg_formation_val)
		_shader_material.set_shader_parameter("title_formation", title_formation_val)
		_shader_material.set_shader_parameter("bg_decay", bg_decay_val)
		_shader_material.set_shader_parameter("title_decay", title_decay_val)
		_shader_material.set_shader_parameter("time", _time_elapsed)

func _change_state(new_state: State) -> void:
	_current_state = new_state
	_state_timer = 0.0
	state_changed.emit(_current_state)

func _process_glitch_signals() -> void:
	if _current_state == State.PAUSED:
		return
		
	var glitch_cycle = sin(_time_elapsed * 0.8) * cos(_time_elapsed * 1.7)
	var is_glitching = glitch_cycle > 0.85
	
	if is_glitching != _last_glitch_state:
		_last_glitch_state = is_glitching
		if is_glitching:
			var intensity: float = randf_range(0.45, 1.0)
			_shake_intensity = intensity
			
			# Induce vertical desynchronization roll on heavy glitch peaks
			if intensity > 0.75:
				_roll_velocity = randf_range(0.5, max_vhold_roll_speed)
				
			terminal_glitched.emit(intensity)

func _process_analog_sync_simulation(delta: float) -> void:
	if enable_screen_shake and _shake_intensity > 0.0:
		_shake_intensity = move_toward(_shake_intensity, 0.0, delta * shake_decay)
		var shake_range = _shake_intensity * max_shake_offset
		_shake_vector = Vector2(
			randf_range(-shake_range, shake_range),
			randf_range(-shake_range, shake_range)
		)
	else:
		_shake_vector = Vector2.ZERO
	
	if _roll_velocity > 0.01:
		_roll_velocity = move_toward(_roll_velocity, 0.0, delta * 1.5)
		_current_sync_roll = fposmod(_current_sync_roll + _roll_velocity * delta, 1.0)
	else:
		_current_sync_roll = move_toward(_current_sync_roll, 0.0, delta * 0.8)
		
	if _shader_material != null:
		_shader_material.set_shader_parameter("screen_shake", _shake_vector)
		_shader_material.set_shader_parameter("sync_roll", _current_sync_roll)

func _on_viewport_size_changed() -> void:
	var screen_size = get_viewport_rect().size
	size = screen_size
	if _color_rect:
		_color_rect.size = screen_size
	if _viewport_container:
		_viewport_container.size = screen_size
	if _viewport:
		_viewport.size = Vector2i(screen_size)
		
	_update_text_container_layout()
		
	if _shader_material:
		var aspect: float = float(screen_size.y) / float(screen_size.x) if screen_size.x > 0 else 0.5625
		_shader_material.set_shader_parameter("aspect_ratio", aspect)

## Integrates a Control container (such as a VBoxContainer of buttons) into the
## simulation viewport. This manages reparenting, layout centering, terminal styling,
## and signals for dynamic additions.
func add_simulated_ui(control: Control) -> void:
	if not is_node_ready():
		await ready
		
	if control == null:
		return
		
	_has_simulated_ui = true
	_update_text_container_layout()
	
	if control.get_parent():
		control.get_parent().remove_child(control)
		
	# Vertical separator between subtitle and interactive buttons
	var menu_spacer := Control.new()
	menu_spacer.custom_minimum_size = Vector2(0, 24)
	_text_container.add_child(menu_spacer)
	
	_text_container.add_child(control)
	
	# Optimize layout configuration for terminal centring
	control.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if control is BoxContainer:
		control.alignment = BoxContainer.ALIGNMENT_CENTER
		# Set comfortable visual spacing between button panels
		control.add_theme_constant_override("separation", 16)
		
	_apply_terminal_styling(control)
	
	if not control.child_entered_tree.is_connected(_on_simulated_ui_child_entered):
		control.child_entered_tree.connect(_on_simulated_ui_child_entered)

func _apply_terminal_styling(node: Node) -> void:
	if node is Button:
		_style_button(node)
	for child in node.get_children():
		_apply_terminal_styling(child)

func _on_simulated_ui_child_entered(node: Node) -> void:
	# Wait one frame to ensure properties such as text are initialized
	await get_tree().process_frame
	if is_instance_valid(node):
		_apply_terminal_styling(node)

func _style_button(btn: Button) -> void:
	if btn == null:
		return
		
	if not btn.has_meta("original_text"):
		btn.set_meta("original_text", btn.text)
		
	# Clear parent themes that interfere with the shader dither rendering
	btn.theme = null
	
	# Enforce a slightly larger vertical size to accommodate the optimized, thicker font bounds
	btn.custom_minimum_size = Vector2(360, 64)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	# Solid white coordinates and clean borders for dithered text_mask sampling
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(1.0, 1.0, 1.0, 0.0) # Transparent content area
	style_normal.border_color = Color(1.0, 1.0, 1.0, 0.35) # Raised outline visibility to define bounds clearly
	style_normal.set_border_width_all(2) # Thicker border retains presence through low-res shader
	style_normal.content_margin_left = 24
	style_normal.content_margin_right = 24
	style_normal.content_margin_top = 10
	style_normal.content_margin_bottom = 10
	style_normal.anti_aliasing = false # Crisp pixelated boundary
	
	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(1.0, 1.0, 1.0, 0.15) # Stronger glowing backdrop on hover
	style_hover.border_color = Color(1.0, 1.0, 1.0, 0.95) # Bright white outline on hover
	style_hover.set_border_width_all(2)
	style_hover.content_margin_left = 24
	style_hover.content_margin_right = 24
	style_hover.content_margin_top = 10
	style_hover.content_margin_bottom = 10
	style_hover.anti_aliasing = false
	
	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(1.0, 1.0, 1.0, 0.3)
	style_pressed.border_color = Color(1.0, 1.0, 1.0, 1.0)
	style_pressed.set_border_width_all(2)
	style_pressed.content_margin_left = 24
	style_pressed.content_margin_right = 24
	style_pressed.content_margin_top = 10
	style_pressed.content_margin_bottom = 10
	style_pressed.anti_aliasing = false
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("focus", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("disabled", style_normal)
	
	# Bold configuration and outline additions to survive nearest-neighbor pixel grids
	btn.add_theme_font_size_override("font_size", 44) # Increased from 40 for superior character clarity
	btn.add_theme_constant_override("outline_size", 6) # Thickened outline prevents broken subpixel stems
	btn.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.95)) # Increased opacity
	
	if subtitle_font != null:
		btn.add_theme_font_override("font", subtitle_font)
	elif title_font != null:
		btn.add_theme_font_override("font", title_font)
		
	# Robust opacity parameters prevent text cores from getting washed out by background dither
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.2))
	
	btn.add_theme_color_override("icon_normal_color", Color(1.0, 1.0, 1.0, 0.95))
	btn.add_theme_color_override("icon_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("icon_focus_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("icon_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("icon_disabled_color", Color(1.0, 1.0, 1.0, 0.2))
	
	if not btn.has_meta("simulation_styled"):
		btn.set_meta("simulation_styled", true)
		btn.mouse_entered.connect(_on_btn_hover.bind(btn))
		btn.mouse_exited.connect(_on_btn_unhover.bind(btn))
		btn.focus_entered.connect(_on_btn_hover.bind(btn))
		btn.focus_exited.connect(_on_btn_unhover.bind(btn))

func _on_btn_hover(btn: Button) -> void:
	if btn == null:
		return
	var original = btn.get_meta("original_text", btn.text)
	btn.text = "[  " + original + "  ]"
	
	# Attempt to play hover audio using whichever naming convention AudioManager implements
	var am = get_node_or_null("/root/AudioManager")
	if am:
		if am.has_method("play_hover"):
			am.call("play_hover")
		elif am.has_method("play_button_hover"):
			am.call("play_button_hover")

func _on_btn_unhover(btn: Button) -> void:
	if btn == null:
		return
	var original = btn.get_meta("original_text", btn.text)
	btn.text = original

func _get_hardcoded_shader_code() -> String:
	return """shader_type canvas_item;
uniform sampler2D text_mask : hint_default_black, filter_nearest;
uniform sampler2D wallpaper_texture : hint_default_black, filter_nearest;
uniform float bg_formation = 0.0;
uniform float bg_decay = 0.0;
uniform float title_formation = 0.0;
uniform float title_decay = 0.0;
uniform float time = 0.0;
uniform bool flip_v = true;
uniform float aspect_ratio = 0.5625;
uniform float pixel_grid_width = 384.0;
uniform float wind_strength = 0.6;
uniform float decay_gravity = 2.2;
uniform float glitch_intensity = 0.5;
uniform float bg_dimness = 0.25;
uniform bool enable_scanlines = true;
uniform bool enable_curvature = true;
uniform float phosphor_intensity = 0.15;
uniform float glass_reflection = 0.12;
uniform float edge_burn_width = 0.12;
uniform float curvature_intensity = 0.04;
uniform vec4 base_color : source_color = vec4(0.82, 0.92, 0.95, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.38, 0.08, 1.0);
uniform vec4 ash_color : source_color = vec4(0.18, 0.19, 0.22, 1.0);
uniform vec4 conduit_color : source_color = vec4(0.0, 0.72, 0.53, 1.0);
uniform vec2 screen_shake = vec2(0.0);
uniform float sync_roll = 0.0;
uniform float hum_bar_speed = 0.75;
uniform float hum_bar_intensity = 0.02;

float hash2d(vec2 co) { return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 co) {
	vec2 i = floor(co); vec2 f = fract(co);
	float a = hash2d(i), b = hash2d(i + vec2(1.0, 0.0)), c = hash2d(i + vec2(0.0, 1.0)), d = hash2d(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}
float bayer4x4(vec2 p) {
	ivec2 ip = ivec2(mod(p, 4.0));
	int val = (ip.x ^ ip.y) * 4 + ip.y;
	return float(val) / 16.0;
}
vec2 curve_uv(vec2 uv) {
	vec2 centered = uv - 0.5;
	float dist = dot(centered, centered);
	centered *= 1.0 + dist * curvature_intensity; 
	return centered + 0.5;
}
float embers(vec2 uv, float t) {
	vec2 ember_uv = uv;
	ember_uv.y -= t * 0.06;
	ember_uv.x += sin(t * 1.8 + uv.y * 12.0) * 0.02;
	vec2 grid = floor(ember_uv * 96.0);
	float noise_val = hash2d(grid);
	return step(0.994, noise_val) * (sin(t * 4.0 + noise_val * 100.0) * 0.5 + 0.5);
}
float circuits(vec2 uv, float t) {
	vec2 grid = floor(uv * 48.0);
	vec2 ipart = fract(uv * 48.0);
	float h = hash2d(grid);
	float line = 0.0;
	if (h > 0.5) {
		line = step(0.92, ipart.x) * step(0.15, hash2d(grid + vec2(1.0, 0.0)));
	} else {
		line = step(0.92, ipart.y) * step(0.15, hash2d(grid + vec2(0.0, 1.0)));
	}
	float pulses = step(0.92, sin(t * 3.0 + h * 20.0));
	return line * (0.2 + 0.8 * pulses);
}
void fragment() {
	bool is_bezel = false; vec2 cur_uv = UV;
	if (enable_curvature) {
		cur_uv = curve_uv(UV);
		if (cur_uv.x < 0.0 || cur_uv.x > 1.0 || cur_uv.y < 0.0 || cur_uv.y > 1.0) is_bezel = true;
	}
	if (is_bezel) { COLOR = vec4(0.012, 0.012, 0.015, 1.0); } else {
		cur_uv += screen_shake;
		cur_uv.y = fract(cur_uv.y + sync_roll);
		vec2 pixel_grid = vec2(pixel_grid_width, pixel_grid_width * aspect_ratio);
		vec2 grid_uv = floor(cur_uv * pixel_grid) / pixel_grid;
		float glitch_cycle = sin(time * 0.8) * cos(time * 1.7), active_glitch = step(0.82, glitch_cycle) * hash2d(vec2(floor(time * 15.0))) * glitch_intensity;
		float jitter_rand = hash2d(vec2(floor(grid_uv.y * 64.0), floor(time * 24.0))), glitch_offset_x = (jitter_rand - 0.5) * 0.08 * active_glitch;
		if (jitter_rand > 0.85) glitch_offset_x += (hash2d(vec2(floor(time * 30.0))) - 0.5) * 0.05 * active_glitch;
		vec2 glitch_block_grid = floor(grid_uv * 12.0);
		if (hash2d(glitch_block_grid + floor(time * 8.0)) < 0.08 * active_glitch) {
			grid_uv.x += (hash2d(glitch_block_grid) - 0.5) * 0.15;
			grid_uv.y += (hash2d(glitch_block_grid + vec2(1.0)) - 0.5) * 0.15;
		}
		float hum_bar = sin(grid_uv.y * 8.0 - time * hum_bar_speed) * sin(grid_uv.y * 3.0 + time * hum_bar_speed * 0.5);
		grid_uv.x += hum_bar * hum_bar_intensity * active_glitch;
		float dither = bayer4x4(grid_uv * pixel_grid);
		float bg_p_hash = hash2d(grid_uv * 157.0);
		float bg_form_wave = bg_formation * (1.0 + edge_burn_width * 2.0) - edge_burn_width;
		float bg_form_threshold = grid_uv.y + grid_uv.x * 0.2 + (bg_p_hash - 0.5) * 0.08;
		float bg_t_rise = clamp((bg_form_wave - bg_form_threshold) / edge_burn_width, 0.0, 1.0);
		float bg_visible_rise = step(dither, bg_t_rise);
		float bg_form_disp_y = (1.0 - bg_t_rise) * 0.35, bg_form_drift_x = sin(time * 12.0 + grid_uv.y * 32.0) * 0.08 * (1.0 - bg_t_rise) * wind_strength;
		float bg_decay_wave = bg_decay * (1.0 + edge_burn_width * 2.0) - edge_burn_width;
		float bg_decay_threshold = grid_uv.y + grid_uv.x * 0.15 + (bg_p_hash - 0.5) * 0.1;
		float bg_decay_age = clamp((bg_decay_wave - bg_decay_threshold) / edge_burn_width, 0.0, 1.0);
		float bg_visible_decay = step(bg_decay_age, dither);
		float bg_fall_dist = bg_decay_age * bg_decay_age * decay_gravity * 0.35, bg_decay_drift_x = (sin(time * 9.0 + grid_uv.y * 18.0) * 0.18 - (0.4 + wind_strength * 0.3)) * bg_decay_age * wind_strength;
		vec2 read_uv_bg = grid_uv;
		read_uv_bg.y -= bg_form_disp_y; read_uv_bg.x -= bg_form_drift_x;
		read_uv_bg.y -= bg_fall_dist; read_uv_bg.x -= bg_decay_drift_x;
		read_uv_bg.x += glitch_offset_x;
		float wp_mask = 0.0;
		if (read_uv_bg.x >= 0.0 && read_uv_bg.x <= 1.0 && read_uv_bg.y >= 0.0 && read_uv_bg.y <= 1.0) {
			float wp_ab = 0.005 * active_glitch * (1.0 + bg_decay * 2.0);
			vec4 wp_r = texture(wallpaper_texture, clamp(read_uv_bg - vec2(wp_ab, 0.0), vec2(0.0), vec2(1.0)));
			vec4 wp_g = texture(wallpaper_texture, clamp(read_uv_bg, vec2(0.0), vec2(1.0)));
			vec4 wp_b = texture(wallpaper_texture, clamp(read_uv_bg + vec2(wp_ab, 0.0), vec2(0.0), vec2(1.0)));
			wp_mask = max(wp_r.r, max(wp_g.g, wp_b.b));
		}
		vec4 wp_color = conduit_color;
		if (bg_t_rise > 0.0 && bg_t_rise < 1.0) {
			float sizzle = step(0.40, hash2d(grid_uv * 200.0 + time * 20.0));
			wp_color = mix(conduit_color, mix(glow_color, vec4(1.0, 0.8, 0.5, 1.0), sizzle * 0.5) * 2.5, sin(bg_t_rise * 3.14159));
		} else if (bg_formation >= 1.0 && bg_decay == 0.0) {
			wp_color.rgb += vec3(circuits(grid_uv, time * 0.5)) * base_color.rgb * 0.6;
			wp_color.rgb += vec3((noise(grid_uv * 100.0 + vec2(time * 1.0)) - 0.5) * 0.08);
		}
		float wp_alpha_mult = bg_visible_rise * bg_visible_decay;
		if (bg_decay > 0.0 && bg_decay_age > 0.0) {
			if (bg_decay_age < 0.25) {
				float sizzle = step(0.35, hash2d(grid_uv * 180.0 + time * 25.0));
				wp_color = mix(conduit_color, vec4(glow_color.rgb * 3.0 + sizzle * 0.8, 1.0), bg_decay_age / 0.25);
			} else if (bg_decay_age < 0.70) {
				wp_color = mix(glow_color * 2.0, ash_color, (bg_decay_age - 0.25) / 0.45);
			} else {
				wp_color = mix(ash_color, vec4(ash_color.rgb, 0.0), (bg_decay_age - 0.70) / 0.30);
			}
		}
		vec4 raw_bg = mix(vec4(0.01, 0.012, 0.015, 1.0), vec4(0.002, 0.003, 0.005, 1.0), grid_uv.y);
		vec4 bg_color = raw_bg + vec4(glow_color.rgb * embers(grid_uv, time), 1.0) * 0.22;
		bg_color.rgb *= bg_dimness; bg_color.a = 1.0;
		vec4 final_wp = vec4(wp_color.rgb, wp_mask * wp_color.a * wp_alpha_mult);
		bg_color = mix(bg_color, final_wp, final_wp.a);
		float p_hash = hash2d(grid_uv * 137.0);
		float title_form_wave = title_formation * (1.0 + edge_burn_width * 2.0) - edge_burn_width;
		float title_form_threshold = grid_uv.y + grid_uv.x * 0.15 + (p_hash - 0.5) * 0.08;
		float t_rise = clamp((title_form_wave - title_form_threshold) / edge_burn_width, 0.0, 1.0);
		float title_visible_rise = step(dither, t_rise);
		float title_form_disp_y = (1.0 - t_rise) * 0.35, title_form_drift_x = sin(time * 14.0 + grid_uv.y * 36.0) * 0.06 * (1.0 - t_rise) * wind_strength;
		float title_decay_wave = title_decay * (1.0 + edge_burn_width * 2.0) - edge_burn_width;
		float title_decay_threshold = grid_uv.y + grid_uv.x * 0.15 + (p_hash - 0.5) * 0.08;
		float decay_val_pixel = clamp((title_decay_wave - title_decay_threshold) / edge_burn_width, 0.0, 1.0);
		float title_visible_decay = step(decay_val_pixel, dither);
		float title_fall_dist = decay_val_pixel * decay_val_pixel * decay_gravity * 0.35, title_decay_drift_x = (sin(time * 11.0 + grid_uv.y * 22.0) * 0.18 - (0.45 + wind_strength * 0.35)) * decay_val_pixel * wind_strength;
		vec2 read_uv = grid_uv;
		read_uv.y -= title_form_disp_y; read_uv.x -= title_form_drift_x;
		read_uv.y -= title_fall_dist; read_uv.x -= title_decay_drift_x;
		read_uv.x += glitch_offset_x;
		vec2 read_uv_text = read_uv; if (flip_v) read_uv_text.y = 1.0 - read_uv_text.y;
		float text_mask_r = 0.0, text_mask_g = 0.0, text_mask_b = 0.0;
		float ab_intensity = 0.007 * active_glitch * (1.0 + title_decay * 2.0);
		vec2 ab_dir = vec2(ab_intensity, 0.0);
		if (read_uv.x >= 0.0 && read_uv.x <= 1.0 && read_uv.y >= 0.0 && read_uv.y <= 1.0) {
			vec4 mask_r = texture(text_mask, clamp(read_uv_text - ab_dir, vec2(0.0), vec2(1.0)));
			vec4 mask_g = texture(text_mask, clamp(read_uv_text, vec2(0.0), vec2(1.0)));
			vec4 mask_b = texture(text_mask, clamp(read_uv_text + ab_dir, vec2(0.0), vec2(1.0)));
			text_mask_r = mask_r.a; text_mask_g = mask_g.a; text_mask_b = mask_b.a;
		}
		vec4 final_color = base_color;
		if (t_rise > 0.0 && t_rise < 1.0) {
			float sizzle = step(0.40, hash2d(grid_uv * 200.0 + time * 20.0));
			final_color = mix(base_color, mix(glow_color, vec4(1.0, 0.8, 0.5, 1.0), sizzle * 0.5) * 2.5, sin(t_rise * 3.14159));
		} else if (title_formation >= 1.0 && title_decay == 0.0) {
			final_color.rgb += vec3(circuits(grid_uv, time * 1.2)) * glow_color.rgb * 1.5;
			final_color.rgb += vec3((noise(grid_uv * 140.0 + vec2(time * 1.5)) - 0.5) * 0.12);
			float raster_sweep = sin(grid_uv.y * 10.0 - time * 3.0) * 0.5 + 0.5;
			final_color.rgb = mix(final_color.rgb, final_color.rgb * 1.35, raster_sweep * 0.3);
		}
		float text_alpha_mult = title_visible_rise * title_visible_decay;
		if (title_decay > 0.0 && decay_val_pixel > 0.0) {
			if (decay_val_pixel < 0.25) {
				float sizzle = step(0.35, hash2d(grid_uv * 180.0 + time * 25.0));
				final_color = mix(base_color, vec4(glow_color.rgb * 3.0 + sizzle * 0.8, 1.0), decay_val_pixel / 0.25);
			} else if (decay_val_pixel < 0.70) {
				final_color = mix(glow_color * 2.0, ash_color, (decay_val_pixel - 0.25) / 0.45);
			} else {
				final_color = mix(ash_color, vec4(ash_color.rgb, 0.0), (decay_val_pixel - 0.70) / 0.30);
			}
		}
		float glow_mask = 0.0;
		if (title_formation > 0.0) {
			float glow_offset_1 = 0.0035; float glow_offset_2 = 0.007;
			// Aspect-ratio correction applied to prevent horizontal stretching in ultra-widescreen modes
			vec2 off1 = vec2(glow_offset_1 * aspect_ratio, glow_offset_1);
			vec2 off2 = vec2(glow_offset_2 * aspect_ratio, glow_offset_2);
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(-off1.x, -off1.y), vec2(0.0), vec2(1.0))).a;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(off1.x, -off1.y), vec2(0.0), vec2(1.0))).a;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(-off1.x, off1.y), vec2(0.0), vec2(1.0))).a;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(off1.x, off1.y), vec2(0.0), vec2(1.0))).a;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(-off2.x, 0.0), vec2(0.0), vec2(1.0))).a * 0.5;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(off2.x, 0.0), vec2(0.0), vec2(1.0))).a * 0.5;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(0.0, -off2.y), vec2(0.0), vec2(1.0))).a * 0.5;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(0.0, off2.y), vec2(0.0), vec2(1.0))).a * 0.5;
			glow_mask = (glow_mask / 6.0) * 1.1;
		}
		vec4 glow_layer = vec4(glow_color.rgb * 1.5, glow_mask * text_alpha_mult);
		vec4 text_layer = vec4(text_mask_r * final_color.r, text_mask_g * final_color.g, text_mask_b * final_color.b, max(max(text_mask_r, text_mask_g), text_mask_b) * final_color.a * text_alpha_mult);
		vec4 final_text_color = mix(glow_layer, text_layer, text_layer.a);
		final_text_color.a = max(glow_layer.a, text_layer.a);
		
		// Injects a localized, dark drop-shadow around the text boundaries and glow to preserve readability over bright backgrounds
		float text_or_glow_alpha = max(max(text_mask_r, text_mask_g), text_mask_b);
		float shadow_factor = max(glow_mask * 1.5, text_or_glow_alpha) * text_alpha_mult;
		bg_color.rgb = mix(bg_color.rgb, bg_color.rgb * 0.12, clamp(shadow_factor, 0.0, 1.0));
		
		COLOR = mix(bg_color, final_text_color, final_text_color.a);
		
		vec2 edge_dist = min(cur_uv, 1.0 - cur_uv);
		COLOR.rgb *= smoothstep(0.0, 0.03, min(edge_dist.x, edge_dist.y));
		float reflection_sweep = sin(cur_uv.x * 1.8 - cur_uv.y * 0.6 + time * 0.5) * 0.5 + 0.5;
		COLOR.rgb += vec3((pow(reflection_sweep, 10.0) * glass_reflection) * 0.18);
		if (enable_scanlines) {
			COLOR.rgb -= vec3(mix(0.12, 0.0, abs(sin(cur_uv.y * pixel_grid.y * 3.14159))) * 0.5);
			COLOR.rgb *= (0.98 + 0.02 * sin(time * 60.0));
		}
		float subpixel = mod(cur_uv.x * pixel_grid.x * 3.0, 3.0);
		vec3 rgb_mask = vec3(1.0);
		if (subpixel < 1.0) rgb_mask = vec3(1.0 + phosphor_intensity, 1.0 - phosphor_intensity, 1.0 - phosphor_intensity);
		else if (subpixel < 2.0) rgb_mask = vec3(1.0 - phosphor_intensity, 1.0 + phosphor_intensity, 1.0 - phosphor_intensity);
		else rgb_mask = vec3(1.0 - phosphor_intensity, 1.0 - phosphor_intensity, 1.0 + phosphor_intensity);
		COLOR.rgb *= rgb_mask;
		COLOR.rgb *= mix(0.5, 1.0, smoothstep(0.85, 0.35, length(cur_uv - 0.5)));
		if (active_glitch > 0.4 && hash2d(grid_uv * 313.0 + vec2(time)) > 0.98) {
			COLOR.rgb += vec3(0.5 * active_glitch);
		}
	}
}"""
