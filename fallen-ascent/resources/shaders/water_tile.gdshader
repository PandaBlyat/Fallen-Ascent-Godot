shader_type canvas_item;
render_mode unshaded;

uniform int depth_band : hint_range(0, 5) = 0;

uniform float dirty_strength = 0.55;
uniform float flow_speed = 0.10;

// Retro pixel-art configuration
uniform float pixel_size = 2.0;       // Matches the virtual pixel size of the game
uniform float animation_fps = 10.0;   // Restricts animation update speed for a retro feel
uniform int color_bands = 4;          // Posterization levels for liquid transitions

uniform vec3 deep_low   = vec3(0.03, 0.06, 0.14);
uniform vec3 deep_high  = vec3(0.07, 0.14, 0.28);
uniform vec3 shallow_low  = vec3(0.10, 0.34, 0.40);
uniform vec3 shallow_high = vec3(0.28, 0.62, 0.66);
uniform vec3 puddle_low   = vec3(0.18, 0.20, 0.18);
uniform vec3 puddle_high  = vec3(0.45, 0.45, 0.38);
uniform vec3 oil_sheen    = vec3(0.55, 0.48, 0.22);

uniform vec3 acid_deep_low      = vec3(0.04, 0.12, 0.04);
uniform vec3 acid_deep_high     = vec3(0.10, 0.30, 0.08);
uniform vec3 acid_shallow_low   = vec3(0.14, 0.38, 0.10);
uniform vec3 acid_shallow_high  = vec3(0.40, 0.72, 0.22);
uniform vec3 acid_puddle_low    = vec3(0.30, 0.52, 0.16);
uniform vec3 acid_puddle_high   = vec3(0.58, 0.86, 0.32);
uniform vec3 acid_sheen         = vec3(0.78, 0.92, 0.34);
uniform float acid_glow_gain = 0.32;

varying vec2 world_pos;

// Slightly streamlined hash multiplier
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Precompute reciprocals to eliminate division in hot paths
	float inv_pixel_size = 1.0 / max(pixel_size, 0.001);
	float inv_fps = 1.0 / max(animation_fps, 0.001);
	float inv_bands_minus_one = 1.0 / max(float(color_bands - 1), 1.0);

	// 1. Snap time to simulate a lower, stepped frame rate
	float stepped_time = floor(TIME * animation_fps) * inv_fps;
	float t = stepped_time * flow_speed;

	// 2. Snap coordinates to virtual pixels for crisp art styling
	vec2 snapped_world = floor(world_pos * inv_pixel_size) * pixel_size;
	vec2 p = snapped_world * 0.03125; // Equivalent to / 32.0 (1.0 / 32.0 = 0.03125)

	// Calculate noise coordinates
	float wave = noise(p * 1.7 + vec2(t * 2.1, -t * 0.7));
	float ripple = noise(p * 7.0 + vec2(-t * 8.0, t * 3.0));
	float grit = noise(p * 17.0);

	int band = clamp(depth_band, 0, 5);

	vec3 low_color;
	vec3 high_color;
	vec3 sheen_color = oil_sheen;
	float ripple_gain;
	float oil_gain;
	float alpha;
	
	// Uniform branching is generally well-handled, but structured simply
	if (band == 0) {
		low_color = deep_low;
		high_color = deep_high;
		ripple_gain = 0.10;
		oil_gain = 0.06;
		alpha = 1.0;
	} else if (band == 1) {
		low_color = shallow_low;
		high_color = shallow_high;
		ripple_gain = 0.35;
		oil_gain = 0.18;
		alpha = 0.92;
	} else if (band == 2) {
		low_color = puddle_low;
		high_color = puddle_high;
		ripple_gain = 0.55;
		oil_gain = 0.10;
		alpha = 0.85;
	} else if (band == 3) {
		low_color = acid_deep_low;
		high_color = acid_deep_high;
		sheen_color = acid_sheen;
		ripple_gain = 0.18;
		oil_gain = 0.22;
		alpha = 1.0;
	} else if (band == 4) {
		low_color = acid_shallow_low;
		high_color = acid_shallow_high;
		sheen_color = acid_sheen;
		ripple_gain = 0.42;
		oil_gain = 0.32;
		alpha = 0.94;
	} else {
		low_color = acid_puddle_low;
		high_color = acid_puddle_high;
		sheen_color = acid_sheen;
		ripple_gain = 0.62;
		oil_gain = 0.28;
		alpha = 0.88;
	}

	// 3. Posterize/Band the gradient mix for a hand-shaded look
	float raw_mix = clamp(wave * 0.7 + ripple * ripple_gain, 0.0, 1.0);
	float posterized_mix = floor(raw_mix * float(color_bands)) * inv_bands_minus_one;
	vec3 color = mix(low_color, high_color, posterized_mix);

	// Calculate oil/sheen
	float oil = smoothstep(0.78, 0.96, noise(p * 3.1 + vec2(t * 4.0, t * 1.6)));
	color = mix(color, sheen_color, oil * oil_gain);

	// 4. Acid-specific glowing and bubbling effects
	if (band >= 3) {
		// Pulsing glow
		float pulse = 0.72 + 0.28 * sin(stepped_time * 2.4 + wave * 5.0);
		float acid_glow = (0.18 + oil * 0.35 + ripple * 0.12) * pulse * acid_glow_gain;
		color += sheen_color * acid_glow;

		// Procedural pixelated bubbles rising upwards
		float bubble_speed = 1.5;
		vec2 bubble_uv = p * 16.0 + vec2(0.0, -stepped_time * bubble_speed);
		float bubble_noise = noise(bubble_uv);
		
		// Use a local time-based offset so bubbles occasionally "pop" and disappear
		float cell_id = hash(floor(bubble_uv));
		float pop_cycle = fract(stepped_time * 0.3 + cell_id);
		
		// Branchless bubble selection using step functions instead of an if-statement
		float is_bubble = step(0.86, bubble_noise) * step(pop_cycle, 0.75);
		color = mix(color, sheen_color, 0.85 * is_bubble);
	}

	// Apply grit/dirt texture to the color map
	color *= 0.78 + grit * dirty_strength * 0.22;

	// 5. Pixelated tile boundary dark seam
	vec2 pixel_tile_uv = fract(snapped_world * 0.03125); // Equivalent to / 32.0
	vec2 edge_dist = min(pixel_tile_uv, 1.0 - pixel_tile_uv) * 32.0;
	float min_dist = min(edge_dist.x, edge_dist.y);

	// Create a sharp, pixel-aligned boundary shadow instead of a smooth blur
	float border_width = max(pixel_size, 2.0);
	float scum = step(border_width, min_dist);
	color = mix(low_color * 0.60, color, scum);

	COLOR = vec4(color, alpha);
}