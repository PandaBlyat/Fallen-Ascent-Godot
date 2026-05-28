shader_type canvas_item;

// Per-tile variation for the base floor TileMapLayer.
uniform float tile_size : hint_range(8.0, 64.0) = 32.0;
uniform float pixel_size = 1.0; // Snaps dither patterns to your game's virtual pixels

uniform float brightness_min : hint_range(0.4, 1.0) = 0.82;
uniform float brightness_max : hint_range(1.0, 1.6) = 1.10;
uniform float hue_jitter : hint_range(0.0, 0.10) = 0.025;
uniform float wear_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wear_threshold : hint_range(0.0, 1.0) = 0.65;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.40;
uniform float grime_threshold : hint_range(0.0, 1.0) = 0.70;
uniform float crack_chance : hint_range(0.0, 1.0) = 0.10;

// Highlight and shadow strengths for the 3D tile bevel
uniform float bevel_highlight : hint_range(0.0, 0.5) = 0.12;
uniform float bevel_shadow : hint_range(0.0, 0.5) = 0.18;

uniform int brightness_steps : hint_range(2, 16) = 4;
uniform int tint_steps : hint_range(2, 12) = 4;
uniform float patch_scale : hint_range(1.0, 12.0) = 6.0;
uniform bool organic_patches = false; // Turn on to blend variations seamlessly (great for dirt/grass tiles)

varying vec2 world_pos;

// Standard pseudo-random hash
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 78.233);
	return fract(p.x * p.y);
}

float hash_pixel(vec2 p) {
	vec2 q = floor(p);
	return fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453);
}

// 2D Noise for organic patch mapping
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i + vec2(0.0, 0.0)), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float quantize(float v, int steps) {
	float s = float(max(steps, 2));
	return floor(clamp(v, 0.0, 0.9999) * s) / (s - 1.0);
}

// Ordered 4x4 Bayer Dithering Matrix
float get_bayer_threshold(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int index = x + y * 4;

	float bayer[16] = float[](
		0.0000, 0.5000, 0.1250, 0.6250,
		0.7500, 0.2500, 0.8750, 0.3750,
		0.1875, 0.6875, 0.0625, 0.5625,
		0.9375, 0.4375, 0.8125, 0.3125
	);
	return bayer[index];
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (base.a < 0.01) {
		COLOR = base;
	} else {
		// Calculate current pixel coordinate relative to the grid, snapped to virtual pixels
		vec2 snapped_world = floor(world_pos / pixel_size) * pixel_size;
		vec2 pixel_pos = floor(snapped_world);
		vec2 tile_xy = floor(snapped_world / tile_size);
		vec2 patch_xy = floor(tile_xy / patch_scale);

		// Hashes
		float h_bright = hash21(tile_xy + vec2(11.7, 3.1));
		float h_tint = hash21(tile_xy + vec2(0.3, 91.4));
		float h_wear_seed = hash21(tile_xy + vec2(57.0, 22.0));
		float h_grime_seed = hash21(tile_xy + vec2(82.4, 13.6));
		float h_crack_seed = hash21(tile_xy + vec2(118.9, 47.3));

		float h_patch_bright = hash21(patch_xy + vec2(7.2, 19.1));
		float h_patch_grime = hash21(patch_xy + vec2(31.5, 88.7));

		// Use continuous noise if organic patches are preferred
		float patch_noise = noise(snapped_world / (tile_size * patch_scale));
		float patch_bright_val = organic_patches ? patch_noise : h_patch_bright;
		float patch_grime_val = organic_patches ? patch_noise : h_patch_grime;

		// Quantized brightness with patch influence
		float bright_mix = mix(h_bright, patch_bright_val, 0.5);
		float bright_t = quantize(bright_mix, brightness_steps);
		float brightness = mix(brightness_min, brightness_max, bright_t);

		// Tinting (Palette shift)
		float tint_t = quantize(h_tint, tint_steps) * 2.0 - 1.0;
		vec3 tint_dir = vec3(0.04, 0.01, -0.05); // Shifting toward warm/cool
		vec3 tint = tint_dir * tint_t * hue_jitter * 4.0;

		vec3 color = base.rgb * brightness + tint;

		// 1. Pixel-Perfect Directional Bevel (Top-Left Highlight, Bottom-Right Shadow)
		vec2 local_pixel = mod(pixel_pos, tile_size);

		if (local_pixel.x < pixel_size || local_pixel.y < pixel_size) {
			// Top or left edge: Add a subtle highlight
			color += vec3(bevel_highlight);
		} else if (local_pixel.x >= tile_size - pixel_size || local_pixel.y >= tile_size - pixel_size) {
			// Bottom or right edge: Add a subtle shadow
			color -= vec3(bevel_shadow);
		}

		// 2. Dithered Grime Patches (Uses 4x4 Bayer Matrix instead of smooth noise)
		float dither_val = get_bayer_threshold(pixel_pos / pixel_size);
		float grime_influence = max(h_grime_seed, patch_grime_val * 0.4);

		if (grime_influence > grime_threshold) {
			// Coarser coordinate grid for blockier grime shapes
			vec2 coarse_pixel = floor(pixel_pos / (pixel_size * 2.0));
			float grime_noise = hash_pixel(coarse_pixel + vec2(h_grime_seed * 13.0, h_grime_seed * 37.0));

			if (grime_noise * grime_strength > dither_val * 0.5) {
				color *= 1.0 - (grime_strength * 0.4);
			}
		}

		// 3. Crisp Pixel Wear
		float wear_influence = max(h_wear_seed, patch_grime_val * 0.3);
		if (wear_influence > wear_threshold) {
			float wear_noise = hash_pixel(pixel_pos / pixel_size + vec2(h_wear_seed * 81.0, h_wear_seed * 27.0));
			if (wear_noise * wear_strength > dither_val * 0.7) {
				color *= 1.0 - (wear_strength * 0.5);
			}
		}

		// 4. Structured Cracks (Small L-shaped or diagonal chips instead of single pixels)
		if (h_crack_seed > 1.0 - crack_chance) {
			vec2 crack_origin = floor(vec2(
				mod(h_crack_seed * 17.1, tile_size - (pixel_size * 4.0)) + (pixel_size * 2.0),
				mod(h_crack_seed * 23.3, tile_size - (pixel_size * 4.0)) + (pixel_size * 2.0)
			));

			// Align to the pixel size
			vec2 relative_pos = floor((local_pixel - crack_origin) / pixel_size);

			// Define a small diagonal step crack: (0,0), (1,0), and (1,1)
			bool is_crack_pixel = (relative_pos == vec2(0.0, 0.0)) ||
			                      (relative_pos == vec2(1.0, 0.0)) ||
			                      (relative_pos == vec2(1.0, 1.0));

			if (is_crack_pixel) {
				color *= 0.45; // Dark shadow inside crack
			}

			// Highlight edge below the crack to give it depth
			bool is_crack_highlight = (relative_pos == vec2(0.0, 1.0)) ||
			                          (relative_pos == vec2(1.0, 2.0)) ||
			                          (relative_pos == vec2(2.0, 2.0));

			if (is_crack_highlight && !is_crack_pixel) {
				color += vec3(bevel_highlight * 0.8);
			}
		}

		COLOR = vec4(clamp(color, 0.0, 1.0), base.a);
	}
}