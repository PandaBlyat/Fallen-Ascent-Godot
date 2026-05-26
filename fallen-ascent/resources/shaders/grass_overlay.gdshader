shader_type canvas_item;

uniform float wind_speed = 1.15;
uniform float wind_amplitude = 0.9;
uniform vec2 walker_positions[8];
uniform int walker_count = 0;
// Lower than 1.0 = less saturated grass. The placeholder atlas reads as
// neon green at full saturation, which clashes with the muted floor; pulling
// this down gives the grass a more mossy, lived-in look.
uniform float saturation : hint_range(0.0, 1.0) = 0.55;
// Tints the grass slightly cooler/dustier so it sits between the warm floor
// and the dark walls. Subtle on purpose — too much and it looks dead.
uniform vec3 mood_tint : source_color = vec3(0.78, 0.86, 0.72);
// Atlas geometry: rows of 32x32 cells stacked vertically. We need the row
// count so we can recover the per-cell V coordinate from the atlas UV.
uniform float atlas_rows = 10.0;
uniform float atlas_cols = 16.0;
// Max horizontal offset (in source-texture UV units) at the very tip of the
// blade. Larger = more visible sway. Tuned for the 32 px placeholder.
uniform float max_sway_uv = 0.02;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// `fract(UV.y * rows)` is 0 at the top of a cell and ~1 at the bottom,
	// giving us a per-blade vertical coordinate. Stems live at the bottom
	// of the cell (don't move); leaves live at the top (sway most).
	float v_in_cell = fract(UV.y * atlas_rows);
	float blade_height = 1.0 - v_in_cell;
	// Quadratic ramp keeps the lower third nearly anchored so we don't smear
	// the dirt under the blades.
	float sway_weight = blade_height * blade_height;

	float sway = sin(TIME * wind_speed + world_pos.x * 0.055) * wind_amplitude;
	for (int i = 0; i < 8; i++) {
		if (i >= walker_count) {
			break;
		}
		float dist = distance(world_pos, walker_positions[i]);
		float push = smoothstep(30.0, 0.0, dist) * 2.2;
		sway += sign(world_pos.x - walker_positions[i].x) * push;
	}

	float sway_uv = sway * sway_weight * max_sway_uv;
	// Sampling at UV.x - sway_uv visually shifts pixels in the +sway_uv
	// direction (sampled origin moves opposite the displayed shift).
	vec2 sample_uv = vec2(UV.x - sway_uv, UV.y);

	// Keep the sample inside this atlas cell — sampling across neighbors
	// would bleed in a completely different grass variant.
	float cell_left = floor(UV.x * atlas_cols) / atlas_cols;
	float cell_right = cell_left + 1.0 / atlas_cols;
	float half_texel = TEXTURE_PIXEL_SIZE.x * 0.5;
	sample_uv.x = clamp(sample_uv.x, cell_left + half_texel, cell_right - half_texel);

	vec4 tex = texture(TEXTURE, sample_uv) * COLOR;
	// Desaturate by mixing toward luminance. Keeps the alpha (blades vs
	// transparent) untouched so the silhouette stays crisp.
	float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 desat = mix(vec3(luma), tex.rgb, saturation);
	desat *= mood_tint;
	COLOR = vec4(desat, tex.a);
}
