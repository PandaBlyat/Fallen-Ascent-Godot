shader_type canvas_item;
render_mode unshaded;

uniform float dirty_strength = 0.75;
uniform float flow_speed = 0.08;
uniform vec4 deep_mud = vec4(0.12, 0.075, 0.038, 1.0);
uniform vec4 shallow_mud = vec4(0.30, 0.19, 0.095, 1.0);
uniform vec4 oil_sheen = vec4(0.55, 0.48, 0.22, 1.0);

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
	float sludge = noise(p * 1.7 + vec2(t * 2.1, -t * 0.7));
	float ripples = noise(p * 7.0 + vec2(-t * 8.0, t * 3.0));
	float grit = noise(p * 17.0);
	float oil = smoothstep(0.78, 0.96, noise(p * 3.1 + vec2(t * 4.0, t * 1.6)));

	vec3 color = mix(deep_mud.rgb, shallow_mud.rgb, sludge * 0.72 + ripples * 0.18);
	color = mix(color, oil_sheen.rgb, oil * 0.22);
	color *= 0.72 + grit * dirty_strength * 0.26;

	vec2 tile_uv = fract(world_pos / 32.0);
	float edge = min(min(tile_uv.x, 1.0 - tile_uv.x), min(tile_uv.y, 1.0 - tile_uv.y));
	float scum = smoothstep(0.0, 0.16, edge);
	color = mix(vec3(0.20, 0.13, 0.065), color, scum);

	COLOR = vec4(color, 1.0);
}
