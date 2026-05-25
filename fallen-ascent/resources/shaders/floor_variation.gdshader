shader_type canvas_item;

// Per-tile variation for the base floor TileMapLayer. The same atlas cell is
// sampled across the whole map, so we recolor it deterministically per tile
// coordinate to break up the obvious repetition.
//
// Designed to stay pixel-art friendly:
//  * Variation values are *quantized* to a small palette of steps so the eye
//    reads it as "different stamp" instead of a smooth gradient.
//  * The "wear" overlay is hashed at pixel-grid resolution, not screen-space,
//    so dithering stays crisp at any zoom level.

uniform float tile_size : hint_range(8.0, 64.0) = 32.0;
uniform float brightness_min : hint_range(0.5, 1.0) = 0.86;
uniform float brightness_max : hint_range(1.0, 1.5) = 1.06;
uniform float hue_jitter : hint_range(0.0, 0.08) = 0.022;
uniform float wear_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wear_threshold : hint_range(0.0, 1.0) = 0.78;
uniform int brightness_steps : hint_range(2, 16) = 6;

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
	return floor(v * s) / (s - 1.0);
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

		float h_bright = hash21(tile_xy + vec2(11.7, 3.1));
		float h_tint = hash21(tile_xy + vec2(0.3, 91.4));
		float h_wear_seed = hash21(tile_xy + vec2(57.0, 22.0));

		float bright_t = quantize(h_bright, brightness_steps);
		float brightness = mix(brightness_min, brightness_max, bright_t);

		// Small warm/cool axis so neighbouring tiles drift apart without the
		// floor ever losing material identity.
		float tint_t = (h_tint - 0.5) * 2.0;
		vec3 tint_dir = vec3(0.06, 0.0, -0.06);
		vec3 tint = tint_dir * tint_t * hue_jitter * 4.0;

		vec3 color = base.rgb * brightness + tint;

		// Sparse pixel-grid wear flecks on a fraction of tiles.
		if (h_wear_seed > wear_threshold) {
			vec2 pixel = floor(world_pos);
			float wear_noise = hash_pixel(pixel + vec2(h_wear_seed * 91.0, h_wear_seed * 17.0));
			float wear_amount = step(0.78, wear_noise) * wear_strength;
			color *= (1.0 - wear_amount * 0.55);
		}

		COLOR = vec4(color, base.a);
	}
}
