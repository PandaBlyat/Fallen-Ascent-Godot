shader_type canvas_item;

// Wind Physics
uniform float wind_speed : hint_range(0.1, 5.0) = 1.15;
uniform float wind_amplitude : hint_range(0.1, 5.0) = 0.9;
uniform float max_sway_uv : hint_range(0.0, 0.1) = 0.02;
uniform float animation_fps : hint_range(0.0, 30.0) = 0.0; // 0.0 means smooth, set to 10.0-12.0 for retro style

// Walker Interactions
uniform vec2 walker_positions[8];
uniform int walker_count : hint_range(0, 8) = 0;
uniform float interaction_radius : hint_range(5.0, 100.0) = 24.0;
uniform float interaction_strength : hint_range(0.5, 5.0) = 1.8;
uniform float vertical_compression : hint_range(0.0, 1.0) = 0.40; // How much the grass squashes down when stepped on

// Aesthetics
uniform float saturation : hint_range(0.0, 1.0) = 0.55;
uniform vec3 mood_tint : source_color = vec3(0.78, 0.86, 0.72);
uniform float wind_shadow_intensity : hint_range(0.0, 0.2) = 0.06; // Dark/light waves passing over

// Atlas Layout
uniform float atlas_rows = 10.0;
uniform float atlas_cols = 16.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Optional frame-rate limiting for retro look
	float t = TIME;
	if (animation_fps > 0.0) {
		t = floor(TIME * animation_fps) / animation_fps;
	}

	// Base vertical interpolation within the specific atlas cell
	float v_in_cell = fract(UV.y * atlas_rows);
	float blade_height = 1.0 - v_in_cell;
	
	// Anchors lower region of the texture to avoid detached roots
	float sway_weight = blade_height * blade_height;

	// 1. Layered wind calculations to simulate gusts
	float wind_primary = sin(t * wind_speed + world_pos.x * 0.06);
	float wind_secondary = sin(t * wind_speed * 2.1 + world_pos.x * 0.15) * 0.3;
	float sway = (wind_primary + wind_secondary) * wind_amplitude;

	// 2. Walker calculation with wind suppression
	float total_push = 0.0;
	float wind_suppression = 1.0;

	for (int i = 0; i < 8; i++) {
		if (i >= walker_count) {
			break;
		}
		float dist = distance(world_pos, walker_positions[i]);
		if (dist < interaction_radius) {
			float push_t = 1.0 - (dist / interaction_radius);
			float push_force = push_t * push_t * interaction_strength;
			
			float push_dir = sign(world_pos.x - walker_positions[i].x);
			if (push_dir == 0.0) push_dir = 1.0;
			
			total_push += push_dir * push_force;
			wind_suppression = min(wind_suppression, 1.0 - push_t);
		}
	}

	// Combine wind with walker displacement
	sway = (sway * wind_suppression) + total_push;

	float sway_uv = sway * sway_weight * max_sway_uv;

	// 3. Vertical Compression (Grass squashes downward when bent/stepped on)
	float bend_amount = abs(sway) * sway_weight;
	float squash_offset = bend_amount * vertical_compression * (0.05 / atlas_rows);

	// 4. Texel Snapping (Ensures pixel-perfect horizontal translation)
	float texel_size_x = TEXTURE_PIXEL_SIZE.x;
	float sway_pixels = round(sway_uv / texel_size_x);
	float snapped_sway_uv = sway_pixels * texel_size_x;

	vec2 sample_uv = vec2(UV.x - snapped_sway_uv, UV.y + squash_offset);

	// Protect cell boundaries in atlas from bleeding (Horizontal and Vertical)
	float cell_left = floor(UV.x * atlas_cols) / atlas_cols;
	float cell_right = cell_left + 1.0 / atlas_cols;
	float cell_top = floor(UV.y * atlas_rows) / atlas_rows;
	float cell_bottom = cell_top + 1.0 / atlas_rows;
	
	float half_texel_x = TEXTURE_PIXEL_SIZE.x * 0.5;
	float half_texel_y = TEXTURE_PIXEL_SIZE.y * 0.5;
	
	sample_uv.x = clamp(sample_uv.x, cell_left + half_texel_x, cell_right - half_texel_x);
	sample_uv.y = clamp(sample_uv.y, cell_top + half_texel_y, cell_bottom - half_texel_y);

	vec4 tex = texture(TEXTURE, sample_uv) * COLOR;

	// Color adjustment / Color Grading
	float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 desat = mix(vec3(luma), tex.rgb, saturation);
	
	// Dynamic wind gusts / cloud shadows passing through
	float cloud_shadow = sin(t * wind_speed * 0.5 + world_pos.x * 0.01 + world_pos.y * 0.015);
	vec3 adjusted_mood_tint = mood_tint + (cloud_shadow * wind_shadow_intensity);

	vec3 tinted = desat * adjusted_mood_tint;
	vec3 final_color = mix(desat, tinted, 0.85);

	COLOR = vec4(final_color, tex.a);
}