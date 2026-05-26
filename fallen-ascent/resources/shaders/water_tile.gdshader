shader_type canvas_item;
render_mode unshaded;

// Shared procedural-water/acid shader used by both fluid families in
// `resources/tiles/water_atlas.png`. The atlas row currently being sampled
// determines which palette and ripple style we use:
//   UV.y < 1/6           -> deep water     (impassable)
//   UV.y in 1/6..2/6     -> shallow water  (slower walking)
//   UV.y in 2/6..3/6     -> puddle water   (slightly slower walking)
//   UV.y in 3/6..4/6     -> deep acid      (impassable, caustic)
//   UV.y in 4/6..5/6     -> shallow acid   (slow + damage)
//   UV.y > 5/6           -> acid puddle    (slight damage)
//
// The TileMapLayer feeds normalized UVs across the entire atlas, so we can
// recover the depth band without per-tile uniforms. Keeping it one shader
// per chunk means we still get a single batched draw call for all fluids.

uniform float dirty_strength = 0.55;
uniform float flow_speed = 0.10;

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

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
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
	vec2 p = world_pos / 32.0;
	float t = TIME * flow_speed;
	float wave = noise(p * 1.7 + vec2(t * 2.1, -t * 0.7));
	float ripple = noise(p * 7.0 + vec2(-t * 8.0, t * 3.0));
	float grit = noise(p * 17.0);

	// Atlas row → depth band. UV.y is in [0,1] across the whole atlas, 6 rows.
	// Bias by half a row so floating-point precision near a row boundary
	// (UV.y = N/6) can never tip a fragment into the next band: row N spans
	// [N/6, (N+1)/6) → we want depth_band == N for every fragment in it.
	float depth_band = clamp(floor(UV.y * 6.0 + 0.0001), 0.0, 5.0);

	vec3 low_color;
	vec3 high_color;
	vec3 sheen_color = oil_sheen;
	float ripple_gain;
	float oil_gain;
	float alpha;
	if (depth_band < 0.5) {
		low_color = deep_low;
		high_color = deep_high;
		ripple_gain = 0.10;
		oil_gain = 0.06;
		alpha = 1.0;
	} else if (depth_band < 1.5) {
		low_color = shallow_low;
		high_color = shallow_high;
		ripple_gain = 0.35;
		oil_gain = 0.18;
		alpha = 0.92;
	} else if (depth_band < 2.5) {
		low_color = puddle_low;
		high_color = puddle_high;
		ripple_gain = 0.55;
		oil_gain = 0.10;
		alpha = 0.85;
	} else if (depth_band < 3.5) {
		low_color = acid_deep_low;
		high_color = acid_deep_high;
		sheen_color = acid_sheen;
		ripple_gain = 0.18;
		oil_gain = 0.22;
		alpha = 1.0;
	} else if (depth_band < 4.5) {
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

	vec3 color = mix(low_color, high_color, wave * 0.7 + ripple * ripple_gain);
	float oil = smoothstep(0.78, 0.96, noise(p * 3.1 + vec2(t * 4.0, t * 1.6)));
	color = mix(color, sheen_color, oil * oil_gain);
	if (depth_band >= 3.0) {
		float pulse = 0.72 + 0.28 * sin(TIME * 2.4 + wave * 5.0);
		float acid_glow = (0.18 + oil * 0.35 + ripple * 0.12) * pulse * acid_glow_gain;
		color += sheen_color * acid_glow;
	}
	color *= 0.78 + grit * dirty_strength * 0.22;

	// Soft scum/foam edge along each tile boundary so seams between
	// neighboring water cells read as a continuous body.
	vec2 tile_uv = fract(world_pos / 32.0);
	float edge = min(min(tile_uv.x, 1.0 - tile_uv.x), min(tile_uv.y, 1.0 - tile_uv.y));
	float scum = smoothstep(0.0, 0.16, edge);
	color = mix(low_color * 0.65, color, scum);

	COLOR = vec4(color, alpha);
}
