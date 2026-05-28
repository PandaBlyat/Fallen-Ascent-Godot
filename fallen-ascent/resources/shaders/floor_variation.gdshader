shader_type canvas_item;

// --- Basic Settings ---
uniform float tile_size : hint_range(8.0, 64.0) = 32.0;
uniform float pixel_size = 1.0; // Snaps dither patterns to your game's virtual pixels

// --- Dynamic Ambient Lighting ---
// Represents the direction pointing TOWARD the light source.
// Vector (-1.0, -1.0) means light comes from the top-left.
uniform vec2 light_direction = vec2(-1.0, -1.0);

// --- Variations & Damage ---
uniform float brightness_min : hint_range(0.4, 1.0) = 0.82;
uniform float brightness_max : hint_range(1.0, 1.6) = 1.10;
uniform float hue_jitter : hint_range(0.0, 0.10) = 0.025;
uniform float wear_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wear_threshold : hint_range(0.0, 1.0) = 0.65;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.40;
uniform float grime_threshold : hint_range(0.0, 1.0) = 0.70;
uniform float crack_chance : hint_range(0.0, 1.0) = 0.10;

// --- Bevel Highlights/Shadows ---
uniform float bevel_highlight : hint_range(0.0, 0.5) = 0.12;
uniform float bevel_shadow : hint_range(0.0, 0.5) = 0.18;

// --- Quantization & Patch Blend ---
uniform int brightness_steps : hint_range(2, 16) = 4;
uniform int tint_steps : hint_range(2, 12) = 4;
uniform float patch_scale : hint_range(1.0, 12.0) = 6.0;
uniform bool organic_patches = false; // Turn on to blend variations seamlessly

// --- Active Glowing Conduits (Megastructure Aesthetic) ---
uniform float conduit_chance : hint_range(0.0, 0.2) = 0.00;
uniform vec4 conduit_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float conduit_pulse_speed : hint_range(0.1, 10.0) = 2.0;

// --- Rusty Metallic Plating ---
uniform float rust_chance : hint_range(0.0, 1.0) = 0.15;
uniform float rust_strength : hint_range(0.0, 1.0) = 0.50;
uniform vec4 rust_color : source_color = vec4(0.45, 0.22, 0.12, 1.0);

// --- Industrial Hazard Stripes ---
uniform float hazard_chance : hint_range(0.0, 0.2) = 0.01;
uniform vec4 hazard_yellow : source_color = vec4(0.80, 0.60, 0.05, 1.0);
uniform vec4 hazard_dark : source_color = vec4(0.12, 0.12, 0.12, 1.0);

// --- Ventilation Grates ---
uniform float grate_chance : hint_range(0.0, 0.2) = 0.03;

// --- Floor Breaches (Void holes) ---
uniform float breach_chance : hint_range(0.0, 0.2) = 0.005;

// --- Coolant / Sludge Leaks ---
uniform float fluid_chance : hint_range(0.0, 0.2) = 0.0;
uniform vec4 fluid_color : source_color = vec4(0.0, 0.9, 0.2, 1.0);
uniform float fluid_flow_speed : hint_range(0.1, 5.0) = 1.5;

// --- Server LED Grid Panels ---
uniform float server_chance : hint_range(0.0, 0.2) = 0.005;

// --- Multi-Panel Subdivisions ---
uniform float split_chance : hint_range(0.0, 1.0) = 0.30;

varying vec2 world_pos;

// Ordered 4x4 Bayer Dithering Matrix
const float bayer[16] = float[](
	0.0000, 0.5000, 0.1250, 0.6250,
	0.7500, 0.2500, 0.8750, 0.3750,
	0.1875, 0.6875, 0.0625, 0.5625,
	0.9375, 0.4375, 0.8125, 0.3125
);

// High-performance 2D to 4D hash
vec4 hash4(vec2 p) {
	vec4 p4 = fract(vec4(p.xyxy + vec2(11.123, 22.345).xyxy) * vec4(1031.2785, 9753.1245, 8312.4356, 5132.8953));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

// High-performance 2D to 2D hash
vec2 hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx + vec3(11.123, 22.345, 33.567)) * vec3(443.897, 441.423, 437.195));
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Fast pixel hash avoiding sin()
float hash_pixel_fast(vec2 p) {
	vec2 q = floor(p) + vec2(17.31, 23.97);
	vec2 fract_part = fract(q * vec2(0.1031, 0.1136));
	fract_part += dot(fract_part, fract_part.yx + 19.19);
	return fract(fract_part.x * fract_part.y);
}

// Standard pseudo-random hash retained for noise generation
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 78.233);
	return fract(p.x * p.y);
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

float get_bayer_threshold(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	return bayer[x + y * 4];
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (base.a < 0.01) {
		COLOR = base;
	} else {
		// Calculate current coordinate relative to the grid, snapped to virtual pixels
		vec2 snapped_world = floor(world_pos / pixel_size) * pixel_size;
		vec2 pixel_pos = floor(snapped_world);
		vec2 tile_xy = floor(snapped_world / tile_size);
		vec2 patch_xy = floor(tile_xy / patch_scale);

		// 1. Consolidated Hash: Generates multiple seeds simultaneously
		vec4 tile_h = hash4(tile_xy);
		float h_bright = tile_h.x;
		float h_tint = tile_h.y;
		float h_wear_seed = tile_h.z;
		float h_grime_seed = tile_h.w;

		// Uncorrelated seeds derived cheaply from existing channels
		float h_crack_seed = fract(tile_h.x * 12.9898 + tile_h.y * 78.233);
		float h_conduit_seed = fract(tile_h.z * 45.1234 + tile_h.w * 91.4321);
		float h_rust_seed = fract(tile_h.y * 73.1843 + tile_h.w * 19.8273);
		float h_hazard_seed = fract(tile_h.x * 37.512 + tile_h.z * 83.194);
		float h_grate_seed = fract(tile_h.y * 61.234 + tile_h.z * 12.845);
		float h_breach_seed = fract(tile_h.x * 53.789 + tile_h.w * 27.654);
		float h_fluid_seed = fract(tile_h.z * 93.412 + tile_h.y * 41.678);
		float h_server_seed = fract(tile_h.w * 82.134 + tile_h.x * 19.345);
		float h_split_seed = fract(tile_h.w * 34.567 + tile_h.z * 67.891);

		vec2 patch_h = hash2(patch_xy);
		float h_patch_bright = patch_h.x;
		float h_patch_grime = patch_h.y;

		// 2. Conditional Noise
		float patch_bright_val;
		float patch_grime_val;
		if (organic_patches) {
			float patch_noise = noise(snapped_world / (tile_size * patch_scale));
			patch_bright_val = patch_noise;
			patch_grime_val = patch_noise;
		} else {
			patch_bright_val = h_patch_bright;
			patch_grime_val = h_patch_grime;
		}

		// Quantized brightness with patch influence
		float bright_mix = mix(h_bright, patch_bright_val, 0.5);
		float bright_t = quantize(bright_mix, brightness_steps);
		float brightness = mix(brightness_min, brightness_max, bright_t);

		// Tinting (Palette shift)
		float tint_t = quantize(h_tint, tint_steps) * 2.0 - 1.0;
		vec3 tint_dir = vec3(0.04, 0.01, -0.05); // Shifting toward warm/cool
		vec3 tint = tint_dir * tint_t * hue_jitter * 4.0;

		vec3 color = base.rgb * brightness + tint;

		vec2 local_pixel = mod(pixel_pos, tile_size);

		// Check tile layout status
		bool is_server = h_server_seed < server_chance;
		bool is_grate = (!is_server) && (h_grate_seed < grate_chance);
		bool is_hazard = (!is_server) && (!is_grate) && (h_hazard_seed < hazard_chance);
		bool is_normal = (!is_server) && (!is_grate) && (!is_hazard);
		bool apply_split = is_normal && (h_split_seed < split_chance);

		// 3. Base Color & Layout Calculations
		if (is_server) {
			// Server LED Casing (3x3 modular indicator components)
			vec2 grid_pos = floor((local_pixel / tile_size) * 3.0);
			vec2 local_light = mod(local_pixel, tile_size / 3.0);

			if (local_light.x > pixel_size && local_light.y > pixel_size &&
			    local_light.x < (tile_size / 3.0) - pixel_size && local_light.y < (tile_size / 3.0) - pixel_size) {

				float light_seed = hash21(tile_xy + grid_pos);
				float active_pulse = sin(TIME * (3.0 + light_seed * 4.0) + light_seed * 10.0);

				if (active_pulse > 0.3) {
					vec3 led_color = (light_seed < 0.5) ? vec3(0.9, 0.45, 0.0) : vec3(0.0, 0.8, 0.25); // Amber or Cyan LED
					color = led_color;
				} else {
					color = vec3(0.12, 0.12, 0.15); // Unlit LED
				}
			} else {
				color = vec3(0.2, 0.22, 0.25); // Component casing metal
			}
		} else if (is_grate) {
			// Ventilation Grates (replaces texture with hollow slats)
			float grate_y = mod(local_pixel.y, pixel_size * 4.0);
			if (grate_y < pixel_size) {
				color = vec3(0.08, 0.08, 0.1); // Empty slat darkness
			} else {
				color = mix(color, vec3(0.3, 0.32, 0.35), 0.5); // Slat metal
				if (grate_y < pixel_size * 2.0) {
					color += vec3(bevel_highlight * 0.6); // Mini-bevel
				}
			}
		} else if (is_hazard) {
			// Hazard warning stripes
			float stripe = mod(floor((local_pixel.x + local_pixel.y) / pixel_size), 8.0);
			vec3 stripe_color = (stripe < 4.0) ? hazard_yellow.rgb : hazard_dark.rgb;
			color = mix(color, stripe_color, 0.85);
		} else if (apply_split) {
			// Subdivided Panels (Draws partition grooves on the base plate)
			float half_tile = floor(tile_size * 0.5);
			bool is_split_x = abs(local_pixel.x - half_tile) < pixel_size * 0.5;
			bool is_split_y = abs(local_pixel.y - half_tile) < pixel_size * 0.5;
			if (is_split_x || is_split_y) {
				color *= 1.0 - bevel_shadow;
			}
		}

		// 4. Dynamic Bevel Lighting (Unifies edge bevels and modular split bevels)
		float left_edge = step(local_pixel.x, pixel_size - 0.1);
		float top_edge = step(local_pixel.y, pixel_size - 0.1);
		float right_edge = step(tile_size - pixel_size - 0.1, local_pixel.x);
		float bottom_edge = step(tile_size - pixel_size - 0.1, local_pixel.y);

		if (apply_split) {
			float half_tile = floor(tile_size * 0.5);
			left_edge = max(left_edge, step(abs(local_pixel.x - half_tile), 0.1));
			right_edge = max(right_edge, step(abs(local_pixel.x - (half_tile + pixel_size)), 0.1));
			top_edge = max(top_edge, step(abs(local_pixel.y - half_tile), 0.1));
			bottom_edge = max(bottom_edge, step(abs(local_pixel.y - (half_tile + pixel_size)), 0.1));
		}

		vec2 edge_normal = vec2(right_edge - left_edge, bottom_edge - top_edge);
		float edge_len = length(edge_normal);

		if (edge_len > 0.1) {
			vec2 normal_dir = edge_normal / edge_len; // Safe normalize
			float light_align = dot(normal_dir, normalize(light_direction));

			float bevel_factor = mix(bevel_shadow * light_align, bevel_highlight * light_align, step(0.0, light_align));
			color += vec3(bevel_factor);
		}

		// 5. Dithered Grime & Rusty Plates
		float dither_val = get_bayer_threshold(pixel_pos / pixel_size);
		float grime_influence = max(h_grime_seed, patch_grime_val * 0.4);

		if (grime_influence > grime_threshold) {
			vec2 coarse_pixel = floor(pixel_pos / (pixel_size * 2.0));
			float grime_noise = hash_pixel_fast(coarse_pixel + vec2(h_grime_seed * 13.0, h_grime_seed * 37.0));

			if (grime_noise * grime_strength > dither_val * 0.5) {
				if (h_rust_seed < rust_chance) {
					color = mix(color, rust_color.rgb, rust_strength * 0.8);
				} else {
					color *= 1.0 - (grime_strength * 0.4);
				}
			}
		}

		// 6. Crisp Pixel Wear
		float wear_influence = max(h_wear_seed, patch_grime_val * 0.3);
		if (wear_influence > wear_threshold) {
			float wear_noise = hash_pixel_fast(pixel_pos / pixel_size + vec2(h_wear_seed * 81.0, h_wear_seed * 27.0));
			if (wear_noise * wear_strength > dither_val * 0.7) {
				color *= 1.0 - (wear_strength * 0.5);
			}
		}

		// 7. Active Unstable Power Conduits
		if (h_conduit_seed < conduit_chance) {
			float center_x = floor(tile_size / (pixel_size * 2.0)) * pixel_size;
			float center_y = floor(tile_size / (pixel_size * 2.0)) * pixel_size;

			bool horizontal = (local_pixel.x <= center_x) && (abs(local_pixel.y - center_y) < pixel_size * 0.5);
			bool vertical = (local_pixel.y >= center_y) && (abs(local_pixel.x - center_x) < pixel_size * 0.5);

			if (horizontal || vertical) {
				float pulse = 0.75 + 0.25 * sin(TIME * conduit_pulse_speed + h_conduit_seed * 100.0);

				float flicker = fract(sin(TIME * 15.0 + h_conduit_seed * 45.2));
				if (flicker < 0.12) {
					pulse *= 0.15; // Connection brownout
				} else if (flicker > 0.96) {
					pulse *= 1.6;  // Power surge
				}

				color = mix(color, conduit_color.rgb, pulse);
			}
		}

		// 8. Coolant Leaks / Sludge Streams (Fluid trails over tiles)
		if (h_fluid_seed < fluid_chance) {
			float wave = sin(local_pixel.y * 0.25 + TIME * fluid_flow_speed) * pixel_size * 1.5;
			float stream_x = (tile_size * 0.5) + wave;

			float dist_to_stream = abs(local_pixel.x - stream_x);
			if (dist_to_stream < pixel_size * 2.5) {
				float flow_pattern = fract(sin(local_pixel.y * 0.5 - TIME * (fluid_flow_speed * 0.8)) + h_fluid_seed);
				vec3 final_fluid = mix(fluid_color.rgb * 0.8, fluid_color.rgb * 1.3, flow_pattern);
				color = mix(color, final_fluid, 0.85);
			}
		}

		// 9. Structured Cracks
		if (h_crack_seed > 1.0 - crack_chance) {
			vec2 crack_origin = floor(vec2(
				mod(h_crack_seed * 17.1, tile_size - (pixel_size * 4.0)) + (pixel_size * 2.0),
				mod(h_crack_seed * 23.3, tile_size - (pixel_size * 4.0)) + (pixel_size * 2.0)
			));

			vec2 relative_pos = floor((local_pixel - crack_origin) / pixel_size);

			bool is_crack_pixel = false;
			if (relative_pos.y == 0.0) {
				is_crack_pixel = (relative_pos.x == 0.0 || relative_pos.x == 1.0);
			} else if (relative_pos.y == 1.0) {
				is_crack_pixel = (relative_pos.x == 1.0);
			}

			if (is_crack_pixel) {
				color *= 0.45; // Dark shadow inside crack
			}

			// Highlight edge below the crack to give it depth
			bool is_crack_highlight = false;
			if (relative_pos.y == 1.0) {
				is_crack_highlight = (relative_pos.x == 0.0);
			} else if (relative_pos.y == 2.0) {
				is_crack_highlight = (relative_pos.x == 1.0 || relative_pos.x == 2.0);
			}

			if (is_crack_highlight && !is_crack_pixel) {
				color += vec3(bevel_highlight * 0.8);
			}
		}

		// 10. Floor Breaches / Corroded Holes (Cuts literal transparency through the floor)
		float base_alpha = base.a;
		if (h_breach_seed < breach_chance) {
			// Center offset using 2D hashes
			vec2 center = vec2(tile_size * 0.5) + (hash2(tile_xy + vec2(44.1, 88.2)) - 0.5) * (tile_size * 0.3);
			float dist = distance(local_pixel, center);

			float jag = hash_pixel_fast(local_pixel) * (pixel_size * 2.0);
			float hole_radius = (tile_size * 0.22) + jag;

			if (dist < hole_radius) {
				base_alpha = 0.0; // Fully transparent hole
			} else if (dist < hole_radius + (pixel_size * 1.5)) {
				color = mix(color, rust_color.rgb * 0.5, 0.8); // Scorched rim
			}
		}

		COLOR = vec4(clamp(color, 0.0, 1.0), base_alpha);
	}
}