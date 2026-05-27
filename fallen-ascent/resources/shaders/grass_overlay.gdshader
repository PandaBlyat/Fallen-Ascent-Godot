shader_type canvas_item;

// Wind Physics
uniform float wind_speed : hint_range(0.1, 5.0) = 1.15;
uniform float wind_amplitude : hint_range(0.1, 5.0) = 0.9;
uniform float max_sway_uv : hint_range(0.0, 0.1) = 0.02;

// Walker Interactions
uniform vec2 walker_positions[8];
uniform int walker_count : hint_range(0, 8) = 0;
uniform float interaction_radius : hint_range(5.0, 100.0) = 24.0;
uniform float interaction_strength : hint_range(0.5, 5.0) = 1.8;

// Aesthetics
uniform float saturation : hint_range(0.0, 1.0) = 0.55;
uniform vec3 mood_tint : source_color = vec3(0.78, 0.86, 0.72);

// Atlas Layout
uniform float atlas_rows = 10.0;
uniform float atlas_cols = 16.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Base vertical interpolation within the specific atlas cell
	float v_in_cell = fract(UV.y * atlas_rows);
	float blade_height = 1.0 - v_in_cell;
	
	// Anchors lower region of the texture to avoid detached roots
	float sway_weight = blade_height * blade_height;

	// 1. Layered wind calculations to simulate gusts
	float wind_primary = sin(TIME * wind_speed + world_pos.x * 0.06);
	float wind_secondary = sin(TIME * wind_speed * 2.1 + world_pos.x * 0.15) * 0.3;
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
			// Calculate smooth quadratic push curve
			float push_t = 1.0 - (dist / interaction_radius);
			float push_force = push_t * push_t * interaction_strength;
			
			// Decide push direction based on orientation to walker
			float push_dir = sign(world_pos.x - walker_positions[i].x);
			if (push_dir == 0.0) push_dir = 1.0; // Avoid division by zero
			
			total_push += push_dir * push_force;
			
			// Suppress regular wind oscillation relative to the push depth
			wind_suppression = min(wind_suppression, 1.0 - push_t);
		}
	}

	// Combine wind (which may be suppressed) with walker displacement
	sway = (sway * wind_suppression) + total_push;

	float sway_uv = sway * sway_weight * max_sway_uv;

	// 3. Texel Snapping (Ensures pixel-perfect horizontal translation)
	float texel_size_x = TEXTURE_PIXEL_SIZE.x;
	float sway_pixels = round(sway_uv / texel_size_x);
	float snapped_sway_uv = sway_pixels * texel_size_x;

	vec2 sample_uv = vec2(UV.x - snapped_sway_uv, UV.y);

	// Protect cell boundaries in atlas from bleeding
	float cell_left = floor(UV.x * atlas_cols) / atlas_cols;
	float cell_right = cell_left + 1.0 / atlas_cols;
	float half_texel = TEXTURE_PIXEL_SIZE.x * 0.5;
	sample_uv.x = clamp(sample_uv.x, cell_left + half_texel, cell_right - half_texel);

	vec4 tex = texture(TEXTURE, sample_uv) * COLOR;

	// Color adjustment / Color Grading
	float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 desat = mix(vec3(luma), tex.rgb, saturation);
	
	// Multiply mood tint while protecting highlights from getting overly washed out
	vec3 tinted = desat * mood_tint;
	vec3 final_color = mix(desat, tinted, 0.85);

	COLOR = vec4(final_color, tex.a);
}