shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D visibility_mask : filter_nearest, repeat_disable;
uniform sampler2D light_mask : filter_nearest, repeat_disable;
uniform vec2 mask_origin_grid = vec2(0.0, 0.0);
uniform vec2 mask_size_grid = vec2(1.0, 1.0);
uniform float tile_pixels = 32.0;
uniform float unlit_alpha = 0.46;
uniform float lit_alpha = 0.020;
uniform float time_seconds = 0.0;
uniform vec4 darkness_tint = vec4(0.010, 0.014, 0.018, 1.0);

// Pixel-art lighting controls
// Dither block size in world pixels — 4 gives a chunky 4x4 pixel dither grid.
uniform float pixel_size = 4.0;
// How strong the dithering at light-zone transitions is (0 = none, 1 = full).
uniform float dither_strength : hint_range(0.0, 1.0) = 0.55;
// Hard light bands (2 = binary lit/unlit, 3-4 = stepped zones like old RPGs).
uniform int light_bands = 3;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Standard 4x4 ordered Bayer matrix, quantized to the virtual pixel grid.
float get_bayer_threshold(vec2 pos) {
	ivec2 p = ivec2(floor(pos / pixel_size));
	int x = p.x % 4;
	if (x < 0) x += 4;
	int y = p.y % 4;
	if (y < 0) y += 4;
	int index = y * 4 + x;

	const float bayer[16] = float[16](
		 0.0,     0.5,     0.125,   0.625,
		 0.75,    0.25,    0.875,   0.375,
		 0.1875,  0.6875,  0.0625,  0.5625,
		 0.9375,  0.4375,  0.8125,  0.3125
	);
	return bayer[index];
}

void fragment() {
	// Snap to virtual pixel grid for blocky pixel-art sampling.
	vec2 snapped_world = floor(world_pos / pixel_size) * pixel_size;
	vec2 grid_pos = snapped_world / tile_pixels;

	vec2 uv = (grid_pos - mask_origin_grid) / max(mask_size_grid, vec2(1.0));
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}

	vec4 visibility = texture(visibility_mask, uv);
	if (visibility.r < 0.5) {
		discard;
	}
	float sight_power = clamp(visibility.g, 0.0, 1.0);

	vec4 light_sample = texture(light_mask, uv);
	float light_power = clamp(light_sample.a, 0.0, 1.0);

	// Subtle per-tile flicker, snapped to the same pixel grid to avoid
	// shimmering at sub-pixel boundaries.
	float grain = fract(sin(dot(floor(grid_pos * 1.7), vec2(12.9898, 78.233))) * 43758.5453);
	float slow_wave = sin(time_seconds * 0.85 + grain * 6.2831) * 0.5 + 0.5;
	float flicker = 0.96 + 0.028 * sin(time_seconds * 4.2 + light_sample.r * 17.0 + light_sample.g * 11.0)
	              + 0.010 * slow_wave;
	light_power = clamp(light_power * flicker, 0.0, 1.0);

	float dither = get_bayer_threshold(snapped_world);

	// Quantise sight into a hard in/out value with a dithered fringe.
	float raw_sight = step(0.08, sight_power);
	float dithered_sight = raw_sight + (dither - 0.5) * dither_strength * 0.6;
	float sight_edge = clamp(floor(dithered_sight * 2.0), 0.0, 1.0);

	// Quantise light into discrete bands with dithered transitions between bands.
	// Higher dither_strength = coarser, more visible pixel-art checkerboard at edges.
	float raw_light = light_power;
	float dithered_light = raw_light + (dither - 0.5) * dither_strength;
	float light_soft;
	if (light_bands > 1) {
		light_soft = clamp(
			floor(dithered_light * float(light_bands) + 0.5) / float(light_bands - 1),
			0.0, 1.0
		);
	} else {
		light_soft = clamp(dithered_light, 0.0, 1.0);
	}

	float alpha = mix(unlit_alpha, lit_alpha, light_soft);
	// Darken cells at the edge of LOS slightly for a crisper boundary.
	alpha += (1.0 - sight_edge) * 0.20;
	alpha = clamp(alpha, 0.0, 0.90);

	// Warm amber tint on lit tiles, cool dark tint on unlit.
	vec3 warm_floor = vec3(0.040, 0.030, 0.018);
	vec3 light_tint = clamp(
		light_sample.rgb * (0.60 + 0.26 * light_soft) + warm_floor * (1.0 - light_soft),
		0.0, 1.0
	);
	vec3 tint = mix(darkness_tint.rgb, light_tint, light_soft * 0.50);
	tint *= mix(0.70, 1.0, sight_edge);

	COLOR = vec4(tint, alpha);
}
