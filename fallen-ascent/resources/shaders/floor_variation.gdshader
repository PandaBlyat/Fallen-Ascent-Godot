shader_type canvas_item;

// Per-tile variation for the base floor TileMapLayer. The same atlas cell is
// sampled across the whole map, so we recolor it deterministically per tile
// coordinate to break up the obvious repetition.
//
// Designed to stay pixel-art friendly:
//  * All hashed values are *quantized* so the eye reads "different stamp"
//    instead of a smooth gradient.
//  * Wear / grime / cracks are hashed at pixel-grid resolution so dithering
//    stays crisp at any zoom level.
//  * Multi-tile "patch" hashes group nearby tiles into shared brightness
//    bands, so the floor reads as having larger regions of wear/cleanliness
//    instead of one-tile noise.

uniform float tile_size : hint_range(8.0, 64.0) = 32.0;
uniform float brightness_min : hint_range(0.4, 1.0) = 0.78;
uniform float brightness_max : hint_range(1.0, 1.6) = 1.12;
uniform float hue_jitter : hint_range(0.0, 0.10) = 0.030;
uniform float wear_strength : hint_range(0.0, 1.0) = 0.42;
uniform float wear_threshold : hint_range(0.0, 1.0) = 0.62;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.30;
uniform float grime_threshold : hint_range(0.0, 1.0) = 0.78;
uniform float crack_chance : hint_range(0.0, 1.0) = 0.08;
uniform float edge_shade : hint_range(0.0, 0.5) = 0.16;
uniform int brightness_steps : hint_range(2, 16) = 5;
uniform int tint_steps : hint_range(2, 12) = 5;
uniform float patch_scale : hint_range(1.0, 12.0) = 5.0;

varying vec2 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 78.233);
	return fract(p.x * p.y);
}

float hash_pixel(vec2 p) {
	vec2 q = floor(p);
	return fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453);
}

float quantize(float v, int steps) {
	float s = float(max(steps, 2));
	return floor(clamp(v, 0.0, 0.9999) * s) / (s - 1.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (base.a < 0.01) {
		COLOR = base;
	} else {
		vec2 tile_xy = floor(world_pos / tile_size);
		vec2 patch_xy = floor(tile_xy / patch_scale);

		float h_bright = hash21(tile_xy + vec2(11.7, 3.1));
		float h_tint = hash21(tile_xy + vec2(0.3, 91.4));
		float h_wear_seed = hash21(tile_xy + vec2(57.0, 22.0));
		float h_grime_seed = hash21(tile_xy + vec2(82.4, 13.6));
		float h_crack_seed = hash21(tile_xy + vec2(118.9, 47.3));
		// Patch-level hashes bias whole regions toward darker / dirtier looks
		// so wear groups instead of being uniform white noise.
		float h_patch_bright = hash21(patch_xy + vec2(7.2, 19.1));
		float h_patch_grime = hash21(patch_xy + vec2(31.5, 88.7));

		// Per-tile brightness pulled toward the patch's brightness band, with
		// quantized steps so neighbouring tiles snap onto a small palette.
		float bright_mix = mix(h_bright, h_patch_bright, 0.55);
		float bright_t = quantize(bright_mix, brightness_steps);
		float brightness = mix(brightness_min, brightness_max, bright_t);

		// Warm/cool tint, quantized so the swing is felt as palette shifts.
		float tint_t = quantize(h_tint, tint_steps) * 2.0 - 1.0;
		vec3 tint_dir = vec3(0.06, 0.0, -0.06);
		vec3 tint = tint_dir * tint_t * hue_jitter * 4.0;

		vec3 color = base.rgb * brightness + tint;

		// Tile-edge darkening: read each pixel's distance to the closest tile
		// border and subtly shade it. Makes individual tiles legible without
		// drawing explicit grout in art.
		vec2 in_tile = fract(world_pos / tile_size);
		vec2 to_edge = min(in_tile, 1.0 - in_tile);
		float edge_d = min(to_edge.x, to_edge.y) * tile_size;
		// Soft 1.5 px wide shadow on the inside of each tile edge.
		float edge_t = 1.0 - clamp(edge_d / 1.5, 0.0, 1.0);
		color *= 1.0 - edge_t * edge_shade;

		// Sparse pixel-grid wear flecks on a fraction of tiles. Patch grime
		// pushes some regions over the threshold so dirty zones look dirty.
		float wear_seed = max(h_wear_seed, h_patch_grime * 0.35);
		if (wear_seed > wear_threshold) {
			vec2 pixel = floor(world_pos);
			float wear_noise = hash_pixel(pixel + vec2(h_wear_seed * 91.0, h_wear_seed * 17.0));
			float wear_amount = step(0.78, wear_noise) * wear_strength;
			color *= 1.0 - wear_amount * 0.55;
		}

		// Layer a second, coarser grime stipple — bigger blotches that read as
		// dust patches rather than chipped paint.
		if (h_grime_seed > grime_threshold) {
			vec2 coarse = floor(world_pos * 0.5);
			float grime_noise = hash_pixel(coarse + vec2(h_grime_seed * 51.0, h_grime_seed * 23.0));
			float grime_amount = step(0.70, grime_noise) * grime_strength;
			color *= 1.0 - grime_amount * 0.40;
		}

		// Occasional 1px chip: a deterministic dark pixel inside the tile.
		// `crack_chance` is the fraction of tiles eligible. Stays a single
		// pixel so it never looks "smudged" at high zoom.
		if (h_crack_seed > 1.0 - crack_chance) {
			vec2 chip_pixel = floor(vec2(
				mod(h_crack_seed * 17.0, tile_size - 2.0) + 1.0,
				mod(h_crack_seed * 23.0, tile_size - 2.0) + 1.0
			));
			vec2 local_pixel = floor(in_tile * tile_size);
			if (distance(local_pixel, chip_pixel) < 0.8) {
				color *= 0.55;
			}
		}

		COLOR = vec4(color, base.a);
	}
}
