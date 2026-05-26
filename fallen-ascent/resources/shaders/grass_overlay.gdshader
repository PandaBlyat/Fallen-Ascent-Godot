shader_type canvas_item;

uniform float wind_speed = 1.15;
uniform float wind_amplitude = 0.9;
uniform vec2 walker_positions[8];
uniform int walker_count = 0;
// Lower than 1.0 = less saturated grass. The placeholder atlas reads as
// neon green at full saturation, which clashes with the muted floor; pulling
// this down gives the grass a more mossy, lived-in look.
uniform float saturation : hint_range(0.0, 1.0) = 0.55;
// Tints the grass slightly cooler/dustier so it sits between the warm floor
// and the dark walls. Subtle on purpose — too much and it looks dead.
uniform vec3 mood_tint : source_color = vec3(0.78, 0.86, 0.72);

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float local_y = mod(VERTEX.y, 32.0) / 32.0;
	float blade_mask = smoothstep(0.10, 0.95, 1.0 - local_y);
	float sway_px = sin(TIME * wind_speed + world_pos.x * 0.055) * wind_amplitude * blade_mask;
	for (int i = 0; i < 8; i++) {
		if (i >= walker_count) {
			break;
		}
		float dist = distance(world_pos, walker_positions[i]);
		float push_px = smoothstep(30.0, 0.0, dist) * 2.2 * blade_mask;
		sway_px += sign(world_pos.x - walker_positions[i].x) * push_px;
	}
	VERTEX.x += sway_px;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	// Desaturate by mixing toward luminance. Keeps the alpha (blades vs
	// transparent) untouched so the silhouette stays crisp.
	float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 desat = mix(vec3(luma), tex.rgb, saturation);
	desat *= mood_tint;
	COLOR = vec4(desat, tex.a);
}
