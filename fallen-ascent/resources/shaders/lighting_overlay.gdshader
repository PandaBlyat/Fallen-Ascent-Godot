shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D visibility_mask : filter_linear, repeat_disable;
uniform sampler2D light_mask : filter_linear, repeat_disable;

uniform vec2 mask_origin_grid = vec2(0.0, 0.0);
uniform vec2 mask_size_grid = vec2(1.0, 1.0);
uniform float tile_pixels = 32.0;
uniform float unlit_alpha = 0.46;
uniform float lit_alpha = 0.020;
uniform vec4 darkness_tint = vec4(0.010, 0.014, 0.018, 1.0);

// Pixel-art lighting controls
uniform float pixel_size = 4.0;
// New uniform to control the scale of the dither pattern independently
uniform float dither_pixel_size = 1.0; 
uniform float dither_strength : hint_range(0.0, 1.0) = 0.55;
uniform int light_bands = 3; 
uniform bool use_screen_space_dither = true;

// Camera and Window scaling values
uniform float screen_scale_factor = 1.0; 
uniform float camera_zoom = 1.0;
uniform vec2 camera_position = vec2(0.0);

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// 8x8 Ordered Bayer Matrix
float get_bayer_threshold(vec2 pos) {
	// Scale the dither pattern using the independent dither_pixel_size
	float effective_pixel_size = max(1.0, dither_pixel_size * camera_zoom * screen_scale_factor);
	
	ivec2 p = ivec2(floor(pos / effective_pixel_size));
	int x = p.x % 8;
	if (x < 0) x += 8;
	int y = p.y % 8;
	if (y < 0) y += 8;
	int index = y * 8 + x;

	const float bayer[64] = float[64](
		 0.0,  48.0,  12.0,  60.0,   3.0,  51.0,  15.0,  63.0,
		32.0,  16.0,  44.0,  28.0,  35.0,  19.0,  47.0,  31.0,
		 8.0,  56.0,   4.0,  52.0,  11.0,  59.0,   7.0,  55.0,
		40.0,  24.0,  36.0,  20.0,  43.0,  27.0,  39.0,  23.0,
		 2.0,  50.0,  14.0,  62.0,   1.0,  49.0,  13.0,  61.0,
		34.0,  18.0,  46.0,  30.0,  33.0,  17.0,  45.0,  29.0,
		10.0,  58.0,   6.0,  54.0,   9.0,  57.0,   5.0,  53.0,
		42.0,  26.0,  38.0,  22.0,  41.0,  25.0,  37.0,  21.0
	);
	return bayer[index] / 64.0;
}

void fragment() {
	// Snap coordinates to game-world virtual pixels
	vec2 snapped_world = floor(world_pos / pixel_size) * pixel_size;
	vec2 grid_pos = snapped_world / tile_pixels;

	vec2 uv = (grid_pos - mask_origin_grid) / max(mask_size_grid, vec2(1.0));
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}

	vec4 visibility = texture(visibility_mask, uv);
	if (visibility.r < 0.1) {
		discard;
	}
	float sight_power = clamp(visibility.g, 0.0, 1.0);

	vec4 light_sample = texture(light_mask, uv);
	float light_power = clamp(light_sample.a, 0.0, 1.0);

	// Light Flicker
	float grain = fract(sin(dot(floor(grid_pos * 1.7), vec2(12.9898, 78.233))) * 43758.5453);
	float slow_wave = sin(TIME * 0.85 + grain * 6.2831) * 0.5 + 0.5;
	float flicker = 0.96 + 0.028 * sin(TIME * 4.2 + light_sample.r * 17.0 + light_sample.g * 11.0)
	              + 0.010 * slow_wave;
	light_power = clamp(light_power * flicker, 0.0, 1.0);

	// Determine dither position
	vec2 dither_coord;
	if (use_screen_space_dither) {
		vec2 raw_offset = camera_position * camera_zoom * screen_scale_factor;
		dither_coord = FRAGCOORD.xy + raw_offset;
	} else {
		dither_coord = world_pos;
	}

	float dither = get_bayer_threshold(dither_coord);

	// Sight dithered edge
	float sight_threshold = mix(0.5, dither, dither_strength);
	float sight_edge = step(sight_threshold, sight_power);

	// Smooth band transitions
	float light_soft;
	if (light_bands > 1) {
		float raw_band = light_power * float(light_bands - 1);
		float band_floor = floor(raw_band);
		float band_fraction = fract(raw_band);
		
		float band_threshold = mix(0.5, dither, dither_strength);
		float transition = step(band_threshold, band_fraction);
		
		light_soft = (band_floor + transition) / float(light_bands - 1);
	} else {
		light_soft = clamp(light_power + (dither - 0.5) * dither_strength, 0.0, 1.0);
	}

	float alpha = mix(unlit_alpha, lit_alpha, light_soft);
	alpha += (1.0 - sight_edge) * 0.25;
	alpha = clamp(alpha, 0.0, 0.92);

	// Color Grading
	vec3 warm_floor = vec3(0.040, 0.030, 0.018);
	vec3 light_tint = clamp(
		light_sample.rgb * (0.60 + 0.26 * light_soft) + warm_floor * (1.0 - light_soft),
		0.0, 1.0
	);
	vec3 tint = mix(darkness_tint.rgb, light_tint, light_soft * 0.50);
	tint *= mix(0.65, 1.0, sight_edge);

	COLOR = vec4(tint, alpha);
}