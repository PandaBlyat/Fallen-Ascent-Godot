shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D visibility_mask : filter_nearest, repeat_disable;
uniform sampler2D light_mask : filter_nearest, repeat_disable;
uniform vec2 mask_origin_grid = vec2(0.0, 0.0);
uniform vec2 mask_size_grid = vec2(1.0, 1.0);
uniform float tile_pixels = 32.0;
uniform float unlit_alpha = 0.46;
uniform float lit_alpha = 0.020;
uniform float time_seconds = 0.0;
uniform vec4 darkness_tint = vec4(0.010, 0.014, 0.018, 1.0);

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 grid_pos = world_pos / tile_pixels;
	vec2 uv = (grid_pos - mask_origin_grid) / max(mask_size_grid, vec2(1.0));
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}

	vec4 visibility = texture(visibility_mask, uv);
	if (visibility.r < 0.5) {
		discard;
	}
	float sight_power = clamp(visibility.g, 0.0, 1.0);

	vec4 light_sample = texture(light_mask, uv);
	float light_power = clamp(light_sample.a, 0.0, 1.0);
	float grain = fract(sin(dot(floor(grid_pos * 1.7), vec2(12.9898, 78.233))) * 43758.5453);
	float slow_wave = sin(time_seconds * 0.85 + grain * 6.2831) * 0.5 + 0.5;
	float flicker = 0.955 + 0.032 * sin(time_seconds * 4.2 + light_sample.r * 17.0 + light_sample.g * 11.0) + 0.010 * slow_wave;
	light_power = clamp(light_power * flicker, 0.0, 1.0);

	float sight_edge = smoothstep(0.05, 1.0, sight_power);
	float light_soft = smoothstep(0.01, 0.92, light_power);
	float alpha = mix(unlit_alpha, lit_alpha, light_soft);
	alpha += (1.0 - sight_edge) * 0.22;
	alpha = clamp(alpha, 0.0, 0.90);

	vec3 warm_floor = vec3(0.035, 0.028, 0.020);
	vec3 light_tint = clamp(light_sample.rgb * (0.62 + 0.24 * light_soft) + warm_floor * (1.0 - light_soft), 0.0, 1.0);
	vec3 tint = mix(darkness_tint.rgb, light_tint, light_soft * 0.52);
	tint *= mix(0.72, 1.0, sight_edge);
	COLOR = vec4(tint, alpha);
}
