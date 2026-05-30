shader_type canvas_item;

uniform sampler2D text_mask : hint_default_black, filter_nearest;
uniform sampler2D wallpaper_texture : hint_default_black, filter_nearest;

uniform float bg_formation : hint_range(0.0, 1.0) = 0.0;
uniform float bg_decay : hint_range(0.0, 1.0) = 0.0;
uniform float title_formation : hint_range(0.0, 1.0) = 0.0;
uniform float title_decay : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform bool flip_v = true;

uniform float aspect_ratio = 0.5625;
uniform float pixel_grid_width = 384.0;
uniform float wind_strength = 0.6;
uniform float decay_gravity = 2.2;
uniform float glitch_intensity = 0.4;
uniform float bg_dimness = 0.15;
uniform bool enable_scanlines = true;
uniform bool enable_curvature = true;

uniform float phosphor_intensity : hint_range(0.0, 1.0) = 0.06;
uniform float glass_reflection : hint_range(0.0, 1.0) = 0.06;
uniform float edge_burn_width : hint_range(0.05, 0.3) = 0.12;

uniform vec4 base_color : source_color = vec4(0.82, 0.88, 0.90, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.38, 0.08, 1.0);
uniform vec4 ash_color : source_color = vec4(0.18, 0.19, 0.22, 1.0);
uniform vec4 conduit_color : source_color = vec4(0.0, 0.72, 0.53, 1.0);

uniform vec2 screen_shake = vec2(0.0);
uniform float sync_roll = 0.0;
uniform float hum_bar_speed = 0.75;
uniform float hum_bar_intensity = 0.02;

// ─── Hash & Noise ───────────────────────────────────────────────
float hash2d(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 hash4(vec2 p) {
	vec4 q = fract(vec4(p.xyxy + vec2(11.123, 22.345).xyxy) * vec4(1031.278, 9753.125, 8312.436, 5132.895));
	q += dot(q, q.wzxy + 33.33);
	return fract((q.xxyz + q.yzzw) * q.zywx);
}

float noise(vec2 co) {
	vec2 i = floor(co);
	vec2 f = fract(co);
	float a = hash2d(i), b = hash2d(i + vec2(1.0, 0.0));
	float c = hash2d(i + vec2(0.0, 1.0)), d = hash2d(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0; a *= 0.5;
	}
	return v;
}

float bayer4x4(vec2 p) {
	ivec2 ip = ivec2(mod(p, 4.0));
	int val = (ip.x ^ ip.y) * 4 + ip.y;
	return float(val) / 16.0;
}

// ─── CRT Curvature ──────────────────────────────────────────────
vec2 curve_uv(vec2 uv) {
	vec2 centered = uv - 0.5;
	float dist = dot(centered, centered);
	centered *= 1.0 + dist * 0.06;
	return centered + 0.5;
}

// ─── Procedural Megastructure Elements ──────────────────────────

// Horizontal structural beams at various depths.
float megastructure_beams(vec2 uv, float t, float depth) {
	float beam_density = 12.0 * depth;
	vec2 grid = floor(uv * vec2(beam_density, beam_density * 0.4));
	vec2 f = fract(uv * vec2(beam_density, beam_density * 0.4));
	float h = hash2d(grid);
	float beam = 0.0;
	// Horizontal beam.
	if (h > 0.55) {
		beam += step(0.88, f.y) * step(f.y, 0.94);
	}
	// Vertical support column.
	if (h > 0.7) {
		beam += step(0.42, f.x) * step(f.x, 0.48) * step(0.0, f.y);
	}
	// Cross-brace diagonal.
	if (h > 0.85) {
		float diag = abs(f.x - f.y);
		beam += step(diag, 0.04) * step(0.0, f.x) * step(f.x, 1.0);
	}
	// Blinking indicator lights on beams.
	float blink = step(0.96, h) * step(0.5, sin(t * (2.0 + h * 4.0)));
	return beam * 0.6 + blink * 0.4;
}

// Pipe network — thin lines running horizontally and vertically with junction nodes.
float pipe_network(vec2 uv, float t, float density) {
	vec2 grid = floor(uv * density);
	vec2 f = fract(uv * density);
	float h = hash2d(grid);
	float pipe = 0.0;
	// Horizontal pipe.
	if (h > 0.4) {
		float pipe_y = 0.3 + h * 0.4;
		pipe += step(abs(f.y - pipe_y), 0.015);
	}
	// Vertical pipe.
	if (h > 0.6) {
		float pipe_x = 0.2 + fract(h * 7.13) * 0.6;
		pipe += step(abs(f.x - pipe_x), 0.015);
	}
	// Junction node (small square at intersection).
	if (h > 0.8) {
		pipe += step(max(abs(f.x - 0.5), abs(f.y - 0.5)), 0.04);
	}
	// Flowing coolant pulse along pipes.
	float pulse = sin(uv.x * density * 2.0 - t * 3.0) * 0.5 + 0.5;
	return pipe * (0.4 + 0.6 * pulse);
}

// Falling debris/ash particles drifting down through the megastructure.
float falling_particles(vec2 uv, float t, float density, float speed) {
	float particles = 0.0;
	for (int layer = 0; layer < 3; layer++) {
		float layer_speed = speed * (0.5 + float(layer) * 0.3);
		float layer_scale = density * (1.0 + float(layer) * 0.5);
		vec2 p_uv = uv;
		p_uv.y -= t * layer_speed;
		p_uv.x += sin(t * 0.7 + float(layer) * 2.1) * 0.015;
		vec2 grid = floor(p_uv * layer_scale);
		vec2 f = fract(p_uv * layer_scale);
		float h = hash2d(grid + float(layer) * 100.0);
		// Sparse particle dots.
		if (h > 0.985) {
			float dist = length(f - vec2(h, fract(h * 3.7)));
			particles += step(dist, 0.12) * (sin(t * 5.0 + h * 50.0) * 0.3 + 0.7);
		}
	}
	return particles;
}

// Deep ambient glow sources — large soft pulsing lights in the background.
float ambient_glow(vec2 uv, float t) {
	float glow = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 glow_pos = vec2(
			hash2d(vec2(float(i) * 17.3, 42.0)) * 0.8 + 0.1,
			hash2d(vec2(float(i) * 31.7, 88.0)) * 0.8 + 0.1
		);
		float pulse = sin(t * (0.3 + float(i) * 0.15) + float(i) * 1.7) * 0.3 + 0.7;
		float dist = length((uv - glow_pos) * vec2(1.0, aspect_ratio));
		glow += pulse * exp(-dist * dist * 18.0) * 0.15;
	}
	return glow;
}

// Spire-like vertical structures reaching upward from the bottom.
float megastructure_spires(vec2 uv, float t) {
	float spires = 0.0;
	for (int i = 0; i < 6; i++) {
		float spire_x = hash2d(vec2(float(i) * 23.7, 11.0)) * 0.9 + 0.05;
		float spire_w = 0.008 + hash2d(vec2(float(i) * 7.3, 55.0)) * 0.012;
		float spire_h = 0.3 + hash2d(vec2(float(i) * 41.1, 99.0)) * 0.5;
		float dx = abs(uv.x - spire_x);
		if (dx < spire_w && uv.y > (1.0 - spire_h)) {
			spires += 0.3;
			// Antenna light at top.
			if (uv.y < (1.0 - spire_h + 0.02)) {
				spires += step(0.5, sin(t * 2.0 + float(i) * 1.3)) * 0.7;
			}
		}
	}
	return spires;
}

// Embers — rising thermal particles.
float embers(vec2 uv, float t) {
	vec2 ember_uv = uv;
	ember_uv.y -= t * 0.06;
	ember_uv.x += sin(t * 1.8 + uv.y * 12.0) * 0.02;
	vec2 grid = floor(ember_uv * 96.0);
	float noise_val = hash2d(grid);
	float intensity = step(0.994, noise_val);
	float blink = sin(t * 4.0 + noise_val * 100.0) * 0.5 + 0.5;
	return intensity * blink;
}

// Circuit tracks.
float circuits(vec2 uv, float t) {
	vec2 grid = floor(uv * 48.0);
	vec2 ipart = fract(uv * 48.0);
	float h = hash2d(grid);
	float line = 0.0;
	if (h > 0.5) {
		line = step(0.92, ipart.x) * step(0.15, hash2d(grid + vec2(1.0, 0.0)));
	} else {
		line = step(0.92, ipart.y) * step(0.15, hash2d(grid + vec2(0.0, 1.0)));
	}
	float pulses = step(0.92, sin(t * 3.0 + h * 20.0));
	return line * (0.2 + 0.8 * pulses);
}

// ─── Main Fragment ──────────────────────────────────────────────
void fragment() {
	bool is_bezel = false;
	vec2 cur_uv = UV;

	if (enable_curvature) {
		cur_uv = curve_uv(UV);
		if (cur_uv.x < 0.0 || cur_uv.x > 1.0 || cur_uv.y < 0.0 || cur_uv.y > 1.0) {
			is_bezel = true;
		}
	}

	if (is_bezel) {
		COLOR = vec4(0.012, 0.012, 0.015, 1.0);
	} else {
		cur_uv += screen_shake;
		cur_uv.y = fract(cur_uv.y + sync_roll);

		float pixel_size_x = pixel_grid_width;
		float pixel_size_y = pixel_grid_width * aspect_ratio;
		vec2 pixel_grid = vec2(pixel_size_x, pixel_size_y);
		vec2 grid_uv = floor(cur_uv * pixel_grid) / pixel_grid;

		// Sync Cycle & horizontal line tearing.
		float glitch_cycle = sin(time * 0.8) * cos(time * 1.7);
		float active_glitch = step(0.82, glitch_cycle) * hash2d(vec2(floor(time * 15.0))) * glitch_intensity;

		float jitter_rand = hash2d(vec2(floor(grid_uv.y * 64.0), floor(time * 24.0)));
		float glitch_offset_x = (jitter_rand - 0.5) * 0.08 * active_glitch;
		if (jitter_rand > 0.85) {
			glitch_offset_x += (hash2d(vec2(floor(time * 30.0))) - 0.5) * 0.05 * active_glitch;
		}

		vec2 glitch_block_grid = floor(grid_uv * 12.0);
		if (hash2d(glitch_block_grid + floor(time * 8.0)) < 0.08 * active_glitch) {
			grid_uv.x += (hash2d(glitch_block_grid) - 0.5) * 0.15;
			grid_uv.y += (hash2d(glitch_block_grid + vec2(1.0)) - 0.5) * 0.15;
		}

		float hum_bar = sin(grid_uv.y * 8.0 - time * hum_bar_speed) * sin(grid_uv.y * 3.0 + time * hum_bar_speed * 0.5);
		grid_uv.x += hum_bar * hum_bar_intensity * active_glitch;

		float dither = bayer4x4(grid_uv * pixel_grid);

		float conduit_luma = dot(conduit_color.rgb, vec3(0.299, 0.587, 0.114));
		vec4 desat_green = vec4(mix(conduit_color.rgb, vec3(conduit_luma), 0.5), 1.0);

		// ═══════════════════════════════════════════════════════════
		// 1. BACKGROUND — Multi-Layer Megastructure Simulation
		// ═══════════════════════════════════════════════════════════
		float bg_p_hash = hash2d(grid_uv * 157.0);

		float bg_form_wave = bg_formation * (1.0 + edge_burn_width * 2.0) - edge_burn_width;
		float bg_form_threshold = grid_uv.y + grid_uv.x * 0.2 + (bg_p_hash - 0.5) * 0.08;
		float bg_t_rise = clamp((bg_form_wave - bg_form_threshold) / edge_burn_width, 0.0, 1.0);
		float bg_visible_rise = step(dither, bg_t_rise);

		float bg_form_disp_y = (1.0 - bg_t_rise) * 0.35;
		float bg_form_drift_x = sin(time * 12.0 + grid_uv.y * 32.0) * 0.08 * (1.0 - bg_t_rise) * wind_strength;

		float bg_decay_wave = bg_decay * (1.0 + edge_burn_width * 2.0) - edge_burn_width;
		float bg_decay_threshold = grid_uv.y + grid_uv.x * 0.15 + (bg_p_hash - 0.5) * 0.1;
		float bg_decay_age = clamp((bg_decay_wave - bg_decay_threshold) / edge_burn_width, 0.0, 1.0);
		float bg_visible_decay = step(bg_decay_age, dither);

		float bg_fall_dist = bg_decay_age * bg_decay_age * decay_gravity * 0.35;
		float bg_decay_drift_x = (sin(time * 9.0 + grid_uv.y * 18.0) * 0.18 - (0.4 + wind_strength * 0.3)) * bg_decay_age * wind_strength;

		// Read background UV coordinates.
		vec2 read_uv_bg = grid_uv;
		read_uv_bg.y -= bg_form_disp_y;
		read_uv_bg.x -= bg_form_drift_x;
		read_uv_bg.y -= bg_fall_dist;
		read_uv_bg.x -= bg_decay_drift_x;
		read_uv_bg.x += glitch_offset_x;

		// Sample wallpaper.
		float wp_mask = 0.0;
		if (read_uv_bg.x >= 0.0 && read_uv_bg.x <= 1.0 && read_uv_bg.y >= 0.0 && read_uv_bg.y <= 1.0) {
			float wp_ab = 0.005 * active_glitch * (1.0 + bg_decay * 2.0);
			vec4 wp_r = texture(wallpaper_texture, clamp(read_uv_bg - vec2(wp_ab, 0.0), vec2(0.0), vec2(1.0)));
			vec4 wp_g = texture(wallpaper_texture, clamp(read_uv_bg, vec2(0.0), vec2(1.0)));
			vec4 wp_b = texture(wallpaper_texture, clamp(read_uv_bg + vec2(wp_ab, 0.0), vec2(0.0), vec2(1.0)));
			wp_mask = max(wp_r.r, max(wp_g.g, wp_b.b));
		}

		// ── Layered Background Composition ──
		// Deep background: very dark with ambient glow.
		vec4 raw_bg = mix(vec4(0.008, 0.010, 0.014, 1.0), vec4(0.002, 0.003, 0.006, 1.0), grid_uv.y);

		// Layer 1: Distant megastructure beams (slow parallax).
		vec2 far_uv = grid_uv * vec2(1.0, 0.6) + vec2(time * 0.003, time * -0.005);
		float far_beams = megastructure_beams(far_uv, time * 0.4, 1.0);
		raw_bg.rgb += conduit_color.rgb * far_beams * 0.04;

		// Layer 2: Mid-ground pipe network (medium parallax).
		vec2 mid_uv = grid_uv * vec2(1.2, 0.8) + vec2(time * 0.008, time * -0.012);
		float pipes = pipe_network(mid_uv, time * 0.6, 20.0);
		raw_bg.rgb += conduit_color.rgb * pipes * 0.06;

		// Layer 3: Spires reaching from bottom.
		float spires = megastructure_spires(grid_uv, time);
		raw_bg.rgb += conduit_color.rgb * spires * 0.08;

		// Layer 4: Ambient deep glow sources.
		float glow = ambient_glow(grid_uv, time);
		raw_bg.rgb += conduit_color.rgb * glow;

		// Layer 5: Falling debris particles.
		float debris = falling_particles(grid_uv, time, 40.0, 0.03);
		raw_bg.rgb += desat_green.rgb * debris * 0.25;

		// Layer 6: Rising embers.
		float ember_val = embers(grid_uv, time);
		raw_bg.rgb += desat_green.rgb * ember_val * 0.18;

		// Layer 7: Wallpaper blend.
		vec4 wp_color = conduit_color;
		if (bg_t_rise > 0.0 && bg_t_rise < 1.0) {
			float edge_glow_factor = sin(bg_t_rise * 3.14159);
			float sizzle = step(0.40, hash2d(grid_uv * 200.0 + time * 20.0));
			vec4 green_glow = mix(desat_green, vec4(0.65, 0.85, 0.75, 1.0), sizzle * 0.5);
			wp_color = mix(conduit_color, green_glow * 2.0, edge_glow_factor);
		} else if (bg_formation >= 1.0 && bg_decay == 0.0) {
			float circ = circuits(grid_uv, time * 0.5);
			wp_color.rgb += vec3(circ) * base_color.rgb * 0.6;
			// Organic noise shimmer.
			float shimmer = fbm(grid_uv * 60.0 + vec2(time * 0.5)) * 0.08;
			wp_color.rgb += vec3(shimmer);
		}

		// Decay color transitions.
		float wp_alpha_mult = bg_visible_rise * bg_visible_decay;
		if (bg_decay > 0.0 && bg_decay_age > 0.0) {
			if (bg_decay_age < 0.25) {
				float sizzle = step(0.35, hash2d(grid_uv * 180.0 + time * 25.0));
				float f = bg_decay_age / 0.25;
				wp_color = mix(conduit_color, vec4(desat_green.rgb * 2.5 + sizzle * 0.5, 1.0), f);
			} else if (bg_decay_age < 0.70) {
				float f = (bg_decay_age - 0.25) / 0.45;
				wp_color = mix(desat_green * 1.8, ash_color, f);
			} else {
				float f = (bg_decay_age - 0.70) / 0.30;
				wp_color = mix(ash_color, vec4(ash_color.rgb, 0.0), f);
			}
		}

		vec4 bg_color = raw_bg;
		bg_color.rgb *= bg_dimness;
		bg_color.a = 1.0;

		vec4 final_wp = vec4(wp_color.rgb, wp_mask * wp_color.a * wp_alpha_mult);
		bg_color = mix(bg_color, final_wp, final_wp.a);

		// ═══════════════════════════════════════════════════════════
		// 2. TITLE TEXT SIMULATION
		// ═══════════════════════════════════════════════════════════
		float p_hash = hash2d(grid_uv * 137.0);

		float title_form_wave = title_formation * (1.0 + edge_burn_width * 2.0) - edge_burn_width;
		float title_form_threshold = grid_uv.y + grid_uv.x * 0.15 + (p_hash - 0.5) * 0.08;
		float t_rise = clamp((title_form_wave - title_form_threshold) / edge_burn_width, 0.0, 1.0);
		float title_visible_rise = step(dither, t_rise);

		float title_form_disp_y = (1.0 - t_rise) * 0.35;
		float title_form_drift_x = sin(time * 14.0 + grid_uv.y * 36.0) * 0.06 * (1.0 - t_rise) * wind_strength;

		float title_decay_wave = title_decay * (1.0 + edge_burn_width * 2.0) - edge_burn_width;
		float title_decay_threshold = grid_uv.y + grid_uv.x * 0.15 + (p_hash - 0.5) * 0.08;
		float decay_val_pixel = clamp((title_decay_wave - title_decay_threshold) / edge_burn_width, 0.0, 1.0);
		float title_visible_decay = step(decay_val_pixel, dither);

		float title_fall_dist = decay_val_pixel * decay_val_pixel * decay_gravity * 0.35;
		float title_decay_drift_x = (sin(time * 11.0 + grid_uv.y * 22.0) * 0.18 - (0.45 + wind_strength * 0.35)) * decay_val_pixel * wind_strength;

		vec2 read_uv = grid_uv;
		read_uv.y -= title_form_disp_y;
		read_uv.x -= title_form_drift_x;
		read_uv.y -= title_fall_dist;
		read_uv.x -= title_decay_drift_x;
		read_uv.x += glitch_offset_x;

		vec2 read_uv_text = read_uv;
		if (flip_v) {
			read_uv_text.y = 1.0 - read_uv_text.y;
		}

		// Chromatic Aberration.
		float ab_intensity = 0.007 * active_glitch * (1.0 + title_decay * 2.0);
		vec2 ab_dir = vec2(ab_intensity, 0.0);

		float text_mask_r = 0.0;
		float text_mask_g = 0.0;
		float text_mask_b = 0.0;

		if (read_uv.x >= 0.0 && read_uv.x <= 1.0 && read_uv.y >= 0.0 && read_uv.y <= 1.0) {
			vec4 mask_r = texture(text_mask, clamp(read_uv_text - ab_dir, vec2(0.0), vec2(1.0)));
			vec4 mask_g = texture(text_mask, clamp(read_uv_text, vec2(0.0), vec2(1.0)));
			vec4 mask_b = texture(text_mask, clamp(read_uv_text + ab_dir, vec2(0.0), vec2(1.0)));
			text_mask_r = mask_r.a;
			text_mask_g = mask_g.a;
			text_mask_b = mask_b.a;
		}

		vec4 final_color = base_color;

		if (t_rise > 0.0 && t_rise < 1.0) {
			float edge_glow_factor = sin(t_rise * 3.14159);
			float sizzle = step(0.40, hash2d(grid_uv * 200.0 + time * 20.0));
			vec4 green_glow = mix(desat_green, vec4(0.65, 0.85, 0.75, 1.0), sizzle * 0.5);
			final_color = mix(base_color, green_glow * 2.0, edge_glow_factor);
		} else if (title_formation >= 1.0 && title_decay == 0.0) {
			float circ = circuits(grid_uv, time * 1.2);
			final_color.rgb += vec3(circ) * desat_green.rgb * 1.2;
			float shimmer = fbm(grid_uv * 80.0 + vec2(time * 0.8)) * 0.10;
			final_color.rgb += vec3(shimmer);
			// Raster scan sweep.
			float raster_sweep = sin(grid_uv.y * 10.0 - time * 3.0) * 0.5 + 0.5;
			final_color.rgb = mix(final_color.rgb, final_color.rgb * 1.35, raster_sweep * 0.3);
		}

		float text_alpha_mult = title_visible_rise * title_visible_decay;
		if (title_decay > 0.0 && decay_val_pixel > 0.0) {
			if (decay_val_pixel < 0.25) {
				float sizzle = step(0.35, hash2d(grid_uv * 180.0 + time * 25.0));
				float f = decay_val_pixel / 0.25;
				final_color = mix(base_color, vec4(desat_green.rgb * 2.5 + sizzle * 0.5, 1.0), f);
			} else if (decay_val_pixel < 0.70) {
				float f = (decay_val_pixel - 0.25) / 0.45;
				final_color = mix(desat_green * 1.8, ash_color, f);
			} else {
				float f = (decay_val_pixel - 0.70) / 0.30;
				final_color = mix(ash_color, vec4(ash_color.rgb, 0.0), f);
			}
		}

		// 8-TAP Radial Halation / Blur glow.
		float glow_mask = 0.0;
		if (title_formation > 0.0) {
			float glow_offset_1 = 0.003;
			float glow_offset_2 = 0.006;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(-glow_offset_1, -glow_offset_1), vec2(0.0), vec2(1.0))).a;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(glow_offset_1, -glow_offset_1), vec2(0.0), vec2(1.0))).a;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(-glow_offset_1, glow_offset_1), vec2(0.0), vec2(1.0))).a;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(glow_offset_1, glow_offset_1), vec2(0.0), vec2(1.0))).a;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(-glow_offset_2, 0.0), vec2(0.0), vec2(1.0))).a * 0.5;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(glow_offset_2, 0.0), vec2(0.0), vec2(1.0))).a * 0.5;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(0.0, -glow_offset_2), vec2(0.0), vec2(1.0))).a * 0.5;
			glow_mask += texture(text_mask, clamp(read_uv_text + vec2(0.0, glow_offset_2), vec2(0.0), vec2(1.0))).a * 0.5;
			glow_mask = (glow_mask / 6.0) * 1.1;
		}

		vec4 glow_layer = vec4(desat_green.rgb * 1.3, glow_mask * text_alpha_mult);
		vec4 text_layer = vec4(
			text_mask_r * final_color.r,
			text_mask_g * final_color.g,
			text_mask_b * final_color.b,
			max(max(text_mask_r, text_mask_g), text_mask_b) * final_color.a * text_alpha_mult
		);

		vec4 final_text_color = mix(glow_layer, text_layer, text_layer.a);
		final_text_color.a = max(glow_layer.a, text_layer.a);

		COLOR = mix(bg_color, final_text_color, final_text_color.a);

		// ═══════════════════════════════════════════════════════════
		// 3. CRT POST-PROCESSING
		// ═══════════════════════════════════════════════════════════
		vec2 edge_dist = min(cur_uv, 1.0 - cur_uv);
		COLOR.rgb *= smoothstep(0.0, 0.03, min(edge_dist.x, edge_dist.y));

		// Glass reflection sweep.
		float reflection_sweep = sin(cur_uv.x * 1.8 - cur_uv.y * 0.6 + time * 0.5) * 0.5 + 0.5;
		reflection_sweep = pow(reflection_sweep, 10.0) * glass_reflection;
		COLOR.rgb += vec3(reflection_sweep * 0.08);

		// Scanlines.
		if (enable_scanlines) {
			float scanline_val = sin(cur_uv.y * pixel_grid.y * 3.14159);
			float scanline = mix(0.06, 0.0, abs(scanline_val)) * 0.4;
			COLOR.rgb -= vec3(scanline);
			COLOR.rgb *= (0.99 + 0.01 * sin(time * 60.0));
		}

		// Phosphor RGB subpixel mask.
		float subpixel = mod(cur_uv.x * pixel_grid.x * 3.0, 3.0);
		vec3 rgb_mask = vec3(1.0);
		if (subpixel < 1.0) {
			rgb_mask = vec3(1.0 + phosphor_intensity, 1.0 - phosphor_intensity, 1.0 - phosphor_intensity);
		} else if (subpixel < 2.0) {
			rgb_mask = vec3(1.0 - phosphor_intensity, 1.0 + phosphor_intensity, 1.0 - phosphor_intensity);
		} else {
			rgb_mask = vec3(1.0 - phosphor_intensity, 1.0 - phosphor_intensity, 1.0 + phosphor_intensity);
		}
		COLOR.rgb *= rgb_mask;

		// Vignette.
		float vignette = smoothstep(0.85, 0.35, length(cur_uv - 0.5));
		COLOR.rgb *= mix(0.7, 1.0, vignette);

		// Glitch static.
		if (active_glitch > 0.4) {
			float static_noise = hash2d(grid_uv * 313.0 + vec2(time));
			if (static_noise > 0.98) {
				COLOR.rgb += vec3(0.5 * active_glitch);
			}
		}
	}
}
