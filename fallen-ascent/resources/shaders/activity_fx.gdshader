shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float time_seconds = 0.0;

varying vec4 fx_custom;
varying vec4 fx_color;

void vertex() {
	fx_custom = INSTANCE_CUSTOM;
	fx_color = COLOR;
}

void fragment() {
	vec2 warped_uv = UV;
	vec2 p = warped_uv * 2.0 - vec2(1.0);
	float d = length(p);
	float kind = fx_custom.r * 10.0;
	float progress = clamp(fx_custom.g, 0.0, 1.0);
	float intensity = clamp(fx_custom.b, 0.0, 1.0);
	float seed = fx_custom.a * 31.0;
	float pulse = 0.5 + 0.5 * sin(time_seconds * (5.0 + kind) + seed);
	float alpha = 0.0;
	vec3 color = fx_color.rgb;

	if (kind < 1.5) {
		float bite = fract((p.x * 3.0 + p.y * 5.0) + seed + time_seconds * 0.9);
		float crack_a = abs(p.x * 0.65 + sin(p.y * 9.0 + seed) * 0.08);
		float crack_b = abs(p.y * 0.48 + cos(p.x * 7.0 + seed) * 0.07);
		float chip = step(0.88, bite) * smoothstep(0.85, 0.12, d);
		alpha = (smoothstep(0.08, 0.0, crack_a) + smoothstep(0.06, 0.0, crack_b) * 0.55 + chip * 0.28)
			* (0.25 + progress * 0.75);
		color = mix(vec3(1.0, 0.42, 0.18), vec3(1.0, 0.78, 0.36), pulse);
	} else if (kind < 2.5) {
		float ring = abs(d - mix(0.18, 0.74, progress));
		float sparks = step(0.975, fract(sin(dot(floor(UV * 10.0 + seed), vec2(12.9898, 78.233))) * 43758.5453));
		float heat = smoothstep(0.95, 0.0, d) * smoothstep(0.0, 0.25, progress) * 0.18;
		alpha = smoothstep(0.08, 0.0, ring) * 0.55 + sparks * pulse * 0.35 + heat;
		color = mix(vec3(1.0, 0.55, 0.18), vec3(1.0, 0.88, 0.42), pulse);
	} else if (kind < 3.5) {
		float ring = abs(d - (0.28 + pulse * 0.34));
		float core = smoothstep(0.32, 0.0, d) * 0.16;
		alpha = (smoothstep(0.08, 0.0, ring) * 0.62 + core) * intensity;
		color = mix(vec3(0.28, 0.72, 1.0), vec3(0.75, 1.0, 1.0), pulse);
	} else if (kind < 4.5) {
		float scan = smoothstep(0.08, 0.0, abs(fract(UV.y * 5.0 - time_seconds * 1.8 + seed) - 0.5));
		float vertical = smoothstep(0.035, 0.0, abs(fract(UV.x * 4.0 + seed) - 0.5)) * 0.28;
		alpha = (scan + vertical) * smoothstep(1.1, 0.15, d) * 0.42;
		color = mix(vec3(0.35, 0.95, 0.68), vec3(0.78, 1.0, 0.86), pulse);
	} else if (kind < 5.5) {
		float shimmer = abs(sin((p.x + p.y) * 8.0 + time_seconds * 2.0 + seed));
		float lattice = smoothstep(0.04, 0.0, abs(fract((p.x - p.y) * 3.5 + seed) - 0.5));
		alpha = (smoothstep(0.8, 1.0, shimmer) * 0.28 + lattice * 0.18) * smoothstep(1.0, 0.2, d);
		color = mix(vec3(0.58, 0.52, 1.0), vec3(0.92, 0.82, 1.0), pulse);
	} else if (kind > 8.5) {
		vec2 drift = vec2(sin(time_seconds * 0.17 + seed), cos(time_seconds * 0.13 + seed * 1.7)) * 0.18;
		vec2 q = fract(UV * vec2(3.0, 2.0) + drift + seed) - vec2(0.5);
		float mote = smoothstep(0.055, 0.0, length(q));
		float fade = 0.35 + 0.65 * sin(time_seconds * 0.7 + seed * 4.0);
		alpha = mote * fade * 0.10 * intensity * fx_color.a;
		color = fx_color.rgb;
	} else {
		float swirl = sin(atan(p.y, p.x) * 3.0 + time_seconds * 1.4 + seed);
		float throb = smoothstep(0.85, 0.0, d) * (0.20 + pulse * 0.14 + swirl * 0.04);
		alpha = throb * intensity;
	}

	COLOR = vec4(color, alpha);
}
