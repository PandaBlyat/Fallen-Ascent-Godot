extends Control
class_name PixelSimulationBackground

signal title_formed
signal title_decay_started
signal title_decay_finished
signal state_changed(new_state: State)
signal terminal_glitched(intensity: float)

enum State { RISING, HOLDING, DECAYING, PAUSED }

@export_category("Assets")
@export var pixel_shader: Shader 

@export_category("Title Configuration")
@export var title_text: String = "Fallen Ascent"
@export var title_font: Font 
@export var font_size: int = 72

@export_category("Timing (Seconds)")
@export var rise_duration: float = 3.5
@export var hold_duration: float = 5.0
@export var decay_duration: float = 4.0
@export var pause_duration: float = 2.0

@export_category("Aesthetics")
@export var base_color: Color = Color(0.82, 0.92, 0.95, 1.0)       # Cyan terminal metal
@export var glow_color: Color = Color(1.0, 0.38, 0.08, 1.0)       # Thermal decay orange
@export var ash_color: Color = Color(0.18, 0.19, 0.22, 1.0)        # Cooling graphite/ash
@export var conduit_color: Color = Color(0.0, 0.72, 0.53, 1.0)     # Machine bus line green
@export var pixel_grid_width: float = 384.0

@export_category("Simulation Settings")
@export_range(0.0, 2.0) var wind_strength: float = 0.6
@export_range(0.0, 5.0) var decay_gravity: float = 2.2
@export_range(0.0, 1.0) var glitch_intensity: float = 0.5
@export_range(0.0, 1.0) var background_dimness: float = 0.25      
@export var enable_scanlines: bool = true
@export var enable_curvature: bool = true                         
@export var flip_v: bool = false # Easily toggle vertical mirroring inside the Inspector!

var _viewport: SubViewport
var _center_container: CenterContainer
var _label: Label
var _color_rect: ColorRect
var _shader_material: ShaderMaterial

var _current_state: State = State.RISING
var _state_timer: float = 0.0
var _time_elapsed: float = 0.0
var _last_glitch_state: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_setup_color_rect()
	_setup_viewport()
	
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	
	# Wait for sizing arrays to populate before material generation
	await get_tree().process_frame
	
	_setup_shader()

func _setup_color_rect() -> void:
	_color_rect = ColorRect.new()
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_color_rect)
	# Set anchors AFTER the node enters the scene tree so they evaluate parent bounds properly
	_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.canvas_item_default_texture_filter = SubViewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	var screen_size = get_viewport_rect().size
	_viewport.size = Vector2i(screen_size)
	
	add_child(_viewport)
	
	_center_container = CenterContainer.new()
	_viewport.add_child(_center_container)
	# Set anchors AFTER adding the container to its viewport parent
	_center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	_label = Label.new()
	_label.text = title_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.font_color = Color.WHITE
	settings.outline_size = 4
	settings.outline_color = Color.WHITE
	
	if title_font != null:
		settings.font = title_font
		
	_label.label_settings = settings
	_center_container.add_child(_label)

func _setup_shader() -> void:
	var shader_resource: Shader = pixel_shader
	
	if shader_resource == null:
		var fallback_path = "res://pixel_simulation.gdshader"
		if ResourceLoader.exists(fallback_path):
			shader_resource = load(fallback_path)
			
	if shader_resource == null:
		shader_resource = Shader.new()
		shader_resource.code = _get_hardcoded_shader_code()
		push_warning("PixelSimulationBackground: External shader was not found. Using high-fidelity embedded fallback.")
		
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader_resource
	
	_color_rect.material = _shader_material
	_update_shader_parameters()

func _update_shader_parameters() -> void:
	if _shader_material == null:
		return
	_shader_material.set_shader_parameter("text_mask", _viewport.get_texture())
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
	_shader_material.set_shader_parameter("flip_v", flip_v)
	
	# Send stable aspect ratio metrics immediately
	var screen_size = get_viewport_rect().size
	var aspect: float = float(screen_size.y) / float(screen_size.x) if screen_size.x > 0 else 0.5625
	_shader_material.set_shader_parameter("aspect_ratio", aspect)

func _process(delta: float) -> void:
	_time_elapsed += delta
	_state_timer += delta
	
	var formation_val: float = 0.0
	var decay_val: float = 0.0
	
	match _current_state:
		State.RISING:
			formation_val = clampf(_state_timer / rise_duration, 0.0, 1.0)
			decay_val = 0.0
			if _state_timer >= rise_duration:
				_change_state(State.HOLDING)
				title_formed.emit()
				
		State.HOLDING:
			formation_val = 1.0
			decay_val = 0.0
			if _state_timer >= hold_duration:
				_change_state(State.DECAYING)
				title_decay_started.emit()
				
		State.DECAYING:
			formation_val = 1.0
			decay_val = clampf(_state_timer / decay_duration, 0.0, 1.0)
			if _state_timer >= decay_duration:
				_change_state(State.PAUSED)
				title_decay_finished.emit()
				
		State.PAUSED:
			formation_val = 0.0
			decay_val = 1.0
			if _state_timer >= pause_duration:
				_change_state(State.RISING)

	_process_glitch_signals()

	if _shader_material != null:
		_shader_material.set_shader_parameter("formation", formation_val)
		_shader_material.set_shader_parameter("decay", decay_val)
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
			terminal_glitched.emit(randf_range(0.4, 1.0))

func _on_viewport_size_changed() -> void:
	var screen_size = get_viewport_rect().size
	
	# Explicitly drive sizes to match actual window dimensions
	size = screen_size
	if _color_rect:
		_color_rect.size = screen_size
	if _viewport:
		_viewport.size = Vector2i(screen_size)
	if _center_container:
		_center_container.size = screen_size
		_center_container.custom_minimum_size = screen_size
		
	if _shader_material:
		var aspect: float = float(screen_size.y) / float(screen_size.x) if screen_size.x > 0 else 0.5625
		_shader_material.set_shader_parameter("aspect_ratio", aspect)

func _get_hardcoded_shader_code() -> String:
	return """shader_type canvas_item;
uniform sampler2D text_mask : hint_default_black, filter_nearest;
uniform float formation = 0.0;
uniform float decay = 0.0;
uniform float time = 0.0;
uniform bool flip_v = false;
uniform float aspect_ratio = 0.5625;
uniform float pixel_grid_width = 384.0;
uniform float wind_strength = 0.6;
uniform float decay_gravity = 2.2;
uniform float glitch_intensity = 0.5;
uniform float bg_dimness = 0.18;
uniform bool enable_scanlines = true;
uniform bool enable_curvature = true;
uniform vec4 base_color : source_color = vec4(0.82, 0.92, 0.95, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.38, 0.08, 1.0);
uniform vec4 ash_color : source_color = vec4(0.18, 0.19, 0.22, 1.0);
uniform vec4 conduit_color : source_color = vec4(0.0, 0.72, 0.53, 1.0);

float hash2d(vec2 co) { return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 co) {
	vec2 i = floor(co); vec2 f = fract(co);
	float a = hash2d(i), b = hash2d(i + vec2(1.0, 0.0)), c = hash2d(i + vec2(0.0, 1.0)), d = hash2d(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}
vec2 curve_uv(vec2 uv) {
	vec2 centered = uv - 0.5;
	float dist = dot(centered, centered);
	centered *= 1.0 + dist * 0.15; 
	return centered + 0.5;
}
void megastructure(vec2 uv, float t, out vec3 base_struct, out vec3 glow_struct) {
	base_struct = vec3(0.0); glow_struct = vec3(0.0);
	float t3 = t * 0.015, t2 = t * 0.04, t1 = t * 0.08;
	vec2 uv3 = uv + vec2(t3, 0.0);
	float p3_col = floor(uv3.x * 6.0), p3_hash = hash2d(vec2(p3_col, 42.12)), is_p3 = step(0.4, p3_hash);
	float p3_edge = smoothstep(0.01, 0.05, fract(uv3.x * 6.0)) * smoothstep(0.99, 0.95, fract(uv3.x * 6.0));
	float p3_mask = is_p3 * p3_edge;
	base_struct += vec3(0.12) * p3_mask * (1.0 - uv3.y * 0.5);
	float p3_grid_x = floor(uv3.x * 60.0), p3_grid_y = floor(uv3.y * 30.0), light_hash = hash2d(vec2(p3_grid_x, p3_grid_y));
	glow_struct += step(0.96, light_hash) * step(0.5, sin(t * 3.0 + light_hash * 50.0)) * vec3(0.1, 0.15, 0.25) * p3_mask;
	vec2 uv2 = uv + vec2(t2, 0.0);
	float p2_col = floor(uv2.x * 12.0), p2_hash = hash2d(vec2(p2_col, 87.54)), is_p2 = step(0.6, p2_hash);
	float p2_edge = smoothstep(0.03, 0.1, fract(uv2.x * 12.0)) * smoothstep(0.97, 0.9, fract(uv2.x * 12.0)), p2_mask = is_p2 * p2_edge;
	base_struct = mix(base_struct, vec3(0.3) * p2_mask * (1.0 - uv2.y * 0.3), p2_mask);
	base_struct += vec3(step(0.96, sin(fract(uv2.x * 12.0) * 3.14159)) * 0.06 * p2_mask);
	float cable_col = floor(uv2.x * 4.0), cable_x = fract(uv2.x * 4.0), sag = 0.4 + 0.3 * hash2d(vec2(cable_col, 19.82));
	float cable_y = uv2.y - (0.15 + sag * (cable_x - 0.5) * (cable_x - 0.5) * 4.0), cable_mask = step(abs(cable_y), 0.005) * step(0.02, cable_x) * step(cable_x, 0.98);
	base_struct = mix(base_struct, vec3(0.1), cable_mask * (1.0 - p2_mask));
	vec2 fan1_center = vec2(0.12, 0.3), fan1_diff = (uv - fan1_center); fan1_diff.x /= aspect_ratio;
	float fan1_dist = length(fan1_diff), fan1_mask = step(0.38, abs(sin(3.0 * (atan(fan1_diff.y, fan1_diff.x) + t * 1.5)))) * step(fan1_dist, 0.1) * step(0.015, fan1_dist);
	base_struct = mix(base_struct, vec3(0.12), fan1_mask * (1.0 - p2_mask)); glow_struct += smoothstep(0.12, 0.0, fan1_dist) * vec3(0.15, 0.08, 0.04) * (1.0 - p2_mask * 0.8);
	vec2 fan2_center = vec2(0.88, 0.55), fan2_diff = (uv - fan2_center); fan2_diff.x /= aspect_ratio;
	float fan2_dist = length(fan2_diff), fan2_mask = step(0.38, abs(sin(4.0 * (atan(fan2_diff.y, fan2_diff.x) - t * 1.1)))) * step(fan2_dist, 0.08) * step(0.012, fan2_dist);
	base_struct = mix(base_struct, vec3(0.12), fan2_mask * (1.0 - p2_mask)); glow_struct += smoothstep(0.1, 0.0, fan2_dist) * vec3(0.04, 0.12, 0.15) * (1.0 - p2_mask * 0.8);
	float beacon_y = 0.2 + 0.6 * hash2d(vec2(p2_col, 54.3)); vec2 beacon_pos = vec2((p2_col + 0.5) / 12.0 - t2, beacon_y), beacon_diff = uv - beacon_pos; beacon_diff.x /= aspect_ratio;
	glow_struct += vec3(1.0, 0.25, 0.05) * smoothstep(0.04, 0.0, length(beacon_diff)) * step(0.5, sin(t * 3.5 + hash2d(vec2(p2_col)) * 10.0)) * is_p2 * p2_mask * 1.5;
	vec2 uv1 = uv + vec2(t1, 0.0);
	float p1_col = floor(uv1.x * 18.0), p1_hash = hash2d(vec2(p1_col, 133.7)), is_p1 = step(0.8, p1_hash);
	float p1_edge = smoothstep(0.04, 0.12, fract(uv1.x * 18.0)) * smoothstep(0.96, 0.88, fract(uv1.x * 18.0)), p1_mask = is_p1 * p1_edge;
	base_struct = mix(base_struct, vec3(0.5) * p1_mask * (1.0 - uv1.y * 0.2), p1_mask);
	float conduit_pos = fract(uv1.x * 18.0) - 0.5, conduit_line = step(abs(conduit_pos), 0.035) * p1_mask;
	glow_struct += conduit_line * conduit_color.rgb * 0.18 + smoothstep(0.9, 0.99, fract(uv1.y * 1.5 + t * ((p1_hash * 0.7 + 0.3) * -1.8) + p1_hash)) * conduit_line * conduit_color.rgb * 1.4;
	float is_server = step(0.45, hash2d(vec2(p1_col, 22.4))) * p1_mask, code_col = floor(uv1.x * 140.0), code_row = floor(uv1.y * 70.0);
	float code_trail = smoothstep(0.25, 0.0, fract(uv1.y - fract(t * (4.0 + hash2d(vec2(code_col, 88.1)) * 4.0) * 0.06 + hash2d(vec2(code_col, 14.2))))) * step(0.05, fract(uv1.y - fract(t * (4.0 + hash2d(vec2(code_col, 88.1)) * 4.0) * 0.06 + hash2d(vec2(code_col, 14.2)))));
	glow_struct += step(0.5, hash2d(vec2(code_col, code_row + floor(t * 12.0)))) * code_trail * is_server * conduit_color.rgb * 1.2;
}
float steam_haze(vec2 uv, float t) {
	return (noise(uv * 3.5 + vec2(t * 0.06, -t * 0.18)) * 0.6 + noise(uv * 7.0 + vec2(-t * 0.09, -t * 0.25)) * 0.4) * 0.12;
}
float circuits(vec2 uv, float t) {
	vec2 cell = floor(uv * 40.0), f = fract(uv * 40.0); float rand = hash2d(cell), wire = 0.0;
	if (rand < 0.4) { wire = step(0.42, f.y) * step(f.y, 0.48); }
	else if (rand < 0.8) { wire = step(0.42, f.x) * step(f.x, 0.48); }
	else { wire = step(abs(f.x - f.y), 0.06); }
	return (wire * 0.1 + wire * step(0.9, sin(t * 4.0 + rand * 6.28)) * 0.4);
}
void fragment() {
	bool is_bezel = false; vec2 cur_uv = UV;
	if (enable_curvature) {
		cur_uv = curve_uv(UV);
		if (cur_uv.x < 0.0 || cur_uv.x > 1.0 || cur_uv.y < 0.0 || cur_uv.y > 1.0) is_bezel = true;
	}
	if (is_bezel) { COLOR = vec4(0.0, 0.0, 0.0, 1.0); } else {
		vec2 pixel_grid = vec2(pixel_grid_width, pixel_grid_width * aspect_ratio);
		float haze = steam_haze(cur_uv, time);
		vec2 grid_uv = floor((cur_uv + vec2(haze * 0.035, 0.0)) * pixel_grid) / pixel_grid;
		vec3 base_struct = vec3(0.0), glow_struct = vec3(0.0); megastructure(grid_uv, time, base_struct, glow_struct);
		vec4 bg_color = mix(vec4(0.008, 0.01, 0.012, 1.0), vec4(0.002, 0.003, 0.004, 1.0), grid_uv.y) + vec4(base_struct * bg_dimness, 0.0);
		bg_color.rgb += glow_struct + conduit_color.rgb * haze * 0.25 + glow_color.rgb * haze * 0.12 * sin(time * 0.5 + grid_uv.y); bg_color.a = 1.0;
		float p_hash = hash2d(grid_uv * 137.0), glitch_cycle = sin(time * 0.8) * cos(time * 1.7), active_glitch = step(0.85, glitch_cycle) * hash2d(vec2(floor(time * 18.0))) * glitch_intensity;
		float glitch_offset_x = (hash2d(vec2(floor(grid_uv.y * 48.0), floor(time * 15.0))) - 0.5) * 0.08 * active_glitch;
		float glitch_offset_y = (hash2d(vec2(floor(grid_uv.x * 24.0), floor(time * 24.0))) - 0.5) * 0.04 * active_glitch;
		float slice_offset = (hash2d(vec2(floor(grid_uv.y * 64.0), 32.1)) - 0.5) * 0.18 * decay;
		float t_rise = clamp((formation - p_hash * 0.35) / (1.0 - p_hash * 0.35), 0.0, 1.0);
		float disp_y = (1.0 - t_rise) * (0.6 + 0.4 * p_hash), disp_x = sin(time * 14.0 + grid_uv.y * 40.0 + p_hash * 6.28) * 0.02 * (1.0 - t_rise) * wind_strength;
		float decay_val_pixel = clamp((decay - p_hash * 0.35) / (1.0 - p_hash * 0.35), 0.0, 1.0);
		float fall_dist = pow(decay_val_pixel, 2.5) * decay_gravity * (1.0 + noise(grid_uv * 15.0) * 0.3), drift_x = (sin(time * 8.0 + grid_uv.y * 22.0) * 0.25 - 0.15) * decay_val_pixel * wind_strength;
		vec2 read_uv = grid_uv + vec2(disp_x + slice_offset + drift_x + glitch_offset_x, disp_y + fall_dist + glitch_offset_y);
		if (flip_v) read_uv.y = 1.0 - read_uv.y;
		float text_mask_r = 0.0, text_mask_g = 0.0, text_mask_b = 0.0;
		if (read_uv.x >= 0.0 && read_uv.x <= 1.0 && read_uv.y >= 0.0 && read_uv.y <= 1.0) {
			float ab_offset = 0.006 * active_glitch * (1.0 + decay * 2.5);
			vec4 mask_r = texture(text_mask, clamp(read_uv - vec2(ab_offset, 0.0), vec2(0.0), vec2(1.0)));
			vec4 mask_g = texture(text_mask, clamp(read_uv, vec2(0.0), vec2(1.0)));
			vec4 mask_b = texture(text_mask, clamp(read_uv + vec2(ab_offset, 0.0), vec2(0.0), vec2(1.0)));
			text_mask_r = max(mask_r.a, max(mask_r.r, max(mask_r.g, mask_r.b)));
			text_mask_g = max(mask_g.a, max(mask_g.r, max(mask_g.g, mask_g.b)));
			text_mask_b = max(mask_b.a, max(mask_b.r, max(mask_b.g, mask_b.b)));
		}
		vec4 final_color = base_color;
		if (t_rise > 0.0 && t_rise < 1.0) {
			float sweep_line = smoothstep(0.05, 0.0, abs(grid_uv.y - (1.0 - t_rise)));
			final_color = mix(vec4(glow_color.rgb + step(0.6, hash2d(grid_uv * 180.0 + time * 12.0)) * 0.4, glow_color.a), base_color, clamp(t_rise * 1.5, 0.0, 1.0));
			final_color.rgb += vec3(sweep_line * 1.5) * base_color.rgb;
		} else if (formation >= 1.0 && decay == 0.0) {
			final_color.rgb += vec3(circuits(grid_uv, time)) * conduit_color.rgb * 1.5;
			final_color.rgb += vec3((noise(grid_uv * 120.0 + vec2(time * 2.5)) - 0.5) * 0.08);
			final_color.rgb *= (1.0 - (hash2d(vec2(floor(time * 24.0))) * 0.05));
		}
		if (decay > 0.0) {
			if (decay_val_pixel < 0.25) { final_color = mix(base_color, glow_color * 1.5, decay_val_pixel / 0.25); }
			else if (decay_val_pixel < 0.65) { final_color = mix(glow_color * 1.5, ash_color, (decay_val_pixel - 0.25) / 0.40); }
			else { final_color = mix(ash_color, vec4(ash_color.rgb, 0.0), (decay_val_pixel - 0.65) / 0.35); }
		}
		vec4 final_text_color = vec4(0.0);
		final_text_color.r = text_mask_r * final_color.r; final_text_color.g = text_mask_g * final_color.g; final_text_color.b = text_mask_b * final_color.b;
		final_text_color.a = max(max(text_mask_r, text_mask_g), text_mask_b) * final_color.a;
		COLOR = mix(bg_color, final_text_color, final_text_color.a);
		if (enable_scanlines) { COLOR.rgb -= vec3(sin(cur_uv.y * pixel_grid.y * 3.14159) * 0.15 + sin(cur_uv.y * 10.0 - time * 2.0) * 0.03); }
		COLOR.rgb *= mix(0.4, 1.0, smoothstep(0.8, 0.45, length(cur_uv - 0.5)));
		COLOR.rgb *= (0.85 + 0.15 * sin(cur_uv.x * pixel_grid_width * 3.14159 * 3.0));
	}
}"""
