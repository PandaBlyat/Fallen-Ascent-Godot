shader_type canvas_item;
render_mode unshaded, blend_mix; // Changed to blend_mix for clean pixel-art transparency

uniform float time_seconds = 0.0;

varying vec4 fx_custom;
varying vec4 fx_color;

// Helper for local-space dithering
float get_local_bayer(vec2 local_pos) {
	ivec2 p = ivec2(floor(local_pos));
	int x = p.x % 4;
	int y = p.y % 4;
	int index = y * 4 + x;
	const float bayer[16] = float[16](
		 0.0,  8.0,  2.0, 10.0,
		12.0,  4.0, 14.0,  6.0,
		 3.0, 11.0,  1.0,  9.0,
		15.0,  7.0, 13.0,  5.0
	);
	return bayer[index] / 16.0;
}

void vertex() {
	fx_custom = INSTANCE_CUSTOM;
	fx_color = COLOR;
}

void fragment() {
	// 1. Quantize time to match low-FPS animation aesthetic
	float fps = 10.0; 
	float stepped_time = floor(time_seconds * fps) / fps;

	// 2. Snap UV coordinates to virtual resolution (e.g., 32x32 tiles)
	float virtual_res = 32.0;
	vec2 snapped_uv = floor(UV * virtual_res) / virtual_res;
	vec2 p = snapped_uv * 2.0 - vec2(1.0);
	float d = length(p);

	float kind = fx_custom.r * 10.0;
	float progress = clamp(fx_custom.g, 0.0, 1.0);
	float intensity = clamp(fx_custom.b, 0.0, 1.0);
	float seed = fx_custom.a * 31.0;
	
	float pulse = 0.5 + 0.5 * sin(stepped_time * (5.0 + kind) + seed);
	float alpha = 0.0;
	vec3 color = fx_color.rgb;

	// Size of one virtual pixel in UV space
	float px_width = 1.0 / virtual_res;

	if (kind < 1.5) {
		// Stepped cracks / chips
		float bite = fract((p.x * 3.0 + p.y * 5.0) + seed + stepped_time * 0.9);
		float crack_a = abs(p.x * 0.65 + sin(p.y * 9.0 + seed) * 0.08);
		float crack_b = abs(p.y * 0.48 + cos(p.x * 7.0 + seed) * 0.07);
		
		float chip = step(0.88, bite) * step(d, 0.85);
		float is_crack = step(crack_a, px_width) + step(crack_b, px_width) * 0.55;
		
		alpha = (is_crack + chip * 0.28) * (0.25 + progress * 0.75);
		color = mix(vec3(1.0, 0.42, 0.18), vec3(1.0, 0.78, 0.36), step(0.5, pulse));
	} else if (kind < 2.5) {
		// Crisp ring + dithered heat core
		float target_radius = mix(0.18, 0.74, progress);
		float ring = abs(d - target_radius);
		float is_ring = step(ring, px_width);

		float sparks = step(0.975, fract(sin(dot(floor(snapped_uv * 10.0 + seed), vec2(12.9898, 78.233))) * 43758.5453));
		float heat_gradient = step(d, 0.95) * (1.0 - d) * progress * 0.4;
		
		// Dither the soft heat glow
		float bayer_val = get_local_bayer(UV * virtual_res);
		float heat_dithered = step(bayer_val, heat_gradient);

		alpha = is_ring * 0.85 + sparks * step(0.5, pulse) * 0.35 + heat_dithered * 0.3;
		color = mix(vec3(1.0, 0.55, 0.18), vec3(1.0, 0.88, 0.42), step(0.5, pulse));
	} else if (kind < 3.5) {
		// Clean pulsing tech-ring
		float target_radius = 0.28 + pulse * 0.34;
		float ring = abs(d - target_radius);
		float is_ring = step(ring, px_width);
		float core = step(d, 0.32) * 0.25;
		
		alpha = (is_ring * 0.8 + core) * intensity;
		color = mix(vec3(0.28, 0.72, 1.0), vec3(0.75, 1.0, 1.0), step(0.5, pulse));
	} else if (kind < 4.5) {
		// Structured terminal scanner effect
		float scan_y = fract(snapped_uv.y * 3.0 - stepped_time * 1.0 + seed);
		float scan = step(scan_y, px_width * 3.0);
		float vertical = step(abs(fract(snapped_uv.x * 4.0 + seed) - 0.5), px_width) * 0.3;
		
		alpha = (scan + vertical) * step(d, 0.9) * 0.7;
		color = mix(vec3(0.35, 0.95, 0.68), vec3(0.78, 1.0, 0.86), step(0.5, pulse));
	} else if (kind < 5.5) {
		// Dithered shimmering screen/lattice
		float shimmer = abs(sin((p.x + p.y) * 8.0 + stepped_time * 2.0 + seed));
		float lattice = step(abs(fract((p.x - p.y) * 3.5 + seed) - 0.5), px_width) * 0.3;
		
		float bayer_val = get_local_bayer(UV * virtual_res);
		float sh_dither = step(bayer_val, step(0.8, shimmer) * 0.4);

		alpha = (sh_dither + lattice) * step(d, 0.8);
		color = mix(vec3(0.58, 0.52, 1.0), vec3(0.92, 0.82, 1.0), step(0.5, pulse));
	} else if (kind < 7.5) {
		// Build dust - hard-edged pixels with dithered fade
		float puff = step(length(snapped_uv * 2.0 - vec2(1.0)), 0.6);
		float grain = fract(sin(dot(floor(snapped_uv * 6.0 + seed), vec2(12.9898, 78.233))) * 43758.5453);
		
		float drift_t = stepped_time * 0.6 + seed * 6.28;
		float bob = step(0.5, 0.7 + 0.3 * sin(drift_t));
		
		float dust = puff * (0.6 + step(0.5, grain) * 0.4) * bob;
		
		float bayer_val = get_local_bayer(UV * virtual_res);
		float dither_fade = step(bayer_val, intensity * fx_color.a);

		alpha = dust * dither_fade;
		color = fx_color.rgb;
	} else if (kind > 8.5) {
		// Floating screen motes
		vec2 drift = vec2(sin(stepped_time * 0.17 + seed), cos(stepped_time * 0.13 + seed * 1.7)) * 0.18;
		vec2 q = fract(snapped_uv * vec2(3.0, 2.0) + drift + seed) - vec2(0.5);
		float mote = step(length(q), px_width * 1.5);
		
		float fade = step(0.5, 0.35 + 0.65 * sin(stepped_time * 0.7 + seed * 4.0));
		alpha = mote * fade * intensity * fx_color.a;
		color = fx_color.rgb;
	} else {
		// Simple rotating cog / indicator
		float angle = atan(p.y, p.x);
		float swirl = step(0.0, sin(angle * 4.0 + stepped_time * 2.0 + seed));
		float core = step(d, 0.7) * (0.3 + swirl * 0.2);
		
		alpha = core * intensity;
	}

	COLOR = vec4(color, alpha);
}