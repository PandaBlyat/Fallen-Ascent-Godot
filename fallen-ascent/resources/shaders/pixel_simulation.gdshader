shader_type canvas_item;

// Text Mask sampler with a safe uninitialized default (hint_default_black)
uniform sampler2D text_mask : hint_default_black, filter_nearest;

uniform float formation : hint_range(0.0, 1.0) = 0.0;
uniform float decay : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform bool flip_v = true; // Set default to true to correct ViewportTexture inversion

uniform float aspect_ratio = 0.5625; // Passed from CPU to prevent NaN/division-by-zero
uniform float pixel_grid_width = 384.0;
uniform float wind_strength = 0.6;
uniform float decay_gravity = 2.2;
uniform float glitch_intensity = 0.4;
uniform float bg_dimness = 0.15;
uniform bool enable_scanlines = true;
uniform bool enable_curvature = true;

uniform vec4 base_color : source_color = vec4(0.82, 0.88, 0.90, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.38, 0.08, 1.0);
uniform vec4 ash_color : source_color = vec4(0.18, 0.19, 0.22, 1.0);
uniform vec4 conduit_color : source_color = vec4(0.0, 0.72, 0.53, 1.0);

// Pseudo-random noise generator
float hash2d(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

// 2D Noise for organic coordinate deformation
float noise(vec2 co) {
    vec2 i = floor(co);
    vec2 f = fract(co);
    float a = hash2d(i);
    float b = hash2d(i + vec2(1.0, 0.0));
    float c = hash2d(i + vec2(0.0, 1.0));
    float d = hash2d(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Simulates physical glass curvature of a retro screen CRT
vec2 curve_uv(vec2 uv) {
    vec2 centered = uv - 0.5;
    float dist = dot(centered, centered);
    centered *= 1.0 + dist * 0.14; 
    return centered + 0.5;
}

// Procedurally generates background columns & power conduits for the ancient megastructure
float megastructure(vec2 uv, float t) {
    float pillar_id = floor(uv.x * 6.0);
    float pillar_noise = hash2d(vec2(pillar_id, 34.12));
    float pillar = step(0.6, hash2d(vec2(pillar_id, 12.5)));
    
    float vert_fade = smoothstep(0.0, 0.7, uv.y) * smoothstep(1.0, 0.3, uv.y);
    float conduit_pos = fract(uv.x * 6.0) - 0.5;
    float conduit = step(abs(conduit_pos) - 0.03 * pillar_noise, 0.015) * pillar;
    
    // Slow electrical hum pulsing down the vertical power lines
    float pulse = step(0.95, sin(-t * 2.0 + uv.y * 15.0 + pillar_noise * 100.0) * 0.5 + 0.5);
    
    return conduit * (0.1 + pulse * 0.45) * vert_fade;
}

// Slowly rising embers inside the massive machine pits
float embers(vec2 uv, float t) {
    vec2 ember_uv = uv;
    ember_uv.y -= t * 0.04;
    ember_uv.x += sin(t * 1.5 + uv.y * 8.0) * 0.015;
    
    vec2 grid = floor(ember_uv * 80.0);
    float noise_val = hash2d(grid);
    
    float intensity = step(0.992, noise_val);
    float blink = sin(t * 3.0 + noise_val * 100.0) * 0.5 + 0.5;
    
    return intensity * blink;
}

// Generates flowing internal circuitry overlays when letters are fully active
float circuits(vec2 uv, float t) {
    float grid_lines = step(0.95, sin(uv.x * 120.0 + t * 0.4)) + step(0.95, sin(uv.y * 60.0 - t * 0.2));
    return clamp(grid_lines, 0.0, 1.0) * 0.15;
}

void fragment() {
    bool is_bezel = false;
    vec2 cur_uv = UV;
    
    if (enable_curvature) {
        cur_uv = curve_uv(UV);
        // Mark as bezel if curved coordinates drift out of screen bounds
        if (cur_uv.x < 0.0 || cur_uv.x > 1.0 || cur_uv.y < 0.0 || cur_uv.y > 1.0) {
            is_bezel = true;
        }
    }

    if (is_bezel) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        float pixel_size_x = pixel_grid_width;
        float pixel_size_y = pixel_grid_width * aspect_ratio;
        vec2 pixel_grid = vec2(pixel_size_x, pixel_size_y);
        vec2 grid_uv = floor(cur_uv * pixel_grid) / pixel_grid;

        // Background compilation
        float struct_val = megastructure(grid_uv, time);
        float ember_val = embers(grid_uv, time);

        vec4 raw_bg = mix(vec4(0.02, 0.03, 0.04, 1.0), vec4(0.005, 0.008, 0.012, 1.0), grid_uv.y);
        vec4 bg_color = raw_bg + vec4(conduit_color.rgb * struct_val, 1.0) * 0.45;
        bg_color += vec4(glow_color.rgb * ember_val, 1.0) * 0.35;
        
        // Dim only the RGB colors. Keep background 100% opaque to block out engine clear colors.
        bg_color.rgb *= bg_dimness;
        bg_color.a = 1.0;

        float p_hash = hash2d(grid_uv * 137.0);

        // Dynamic horizontal signal glitches
        float glitch_cycle = sin(time * 0.8) * cos(time * 1.7);
        float active_glitch = step(0.82, glitch_cycle) * hash2d(vec2(floor(time * 15.0))) * glitch_intensity;
        float glitch_offset_x = (hash2d(vec2(floor(grid_uv.y * 32.0), floor(time * 12.0))) - 0.5) * 0.06 * active_glitch;

        // Assembly offsets (Rise/Formation)
        float delay = p_hash * 0.35;
        float t_rise = clamp((formation - delay) / (1.0 - delay), 0.0, 1.0);
        float disp_y = (1.0 - t_rise) * (0.6 + 0.4 * p_hash);
        float disp_x = sin(time * 12.0 + grid_uv.y * 30.0 + p_hash * 6.28) * 0.02 * (1.0 - t_rise) * wind_strength;

        // Disintegration offsets (Meltdown/Decay)
        float decay_delay = p_hash * 0.35;
        float decay_val_pixel = clamp((decay - decay_delay) / (1.0 - decay_delay), 0.0, 1.0);
        float fall_dist = decay_val_pixel * decay_val_pixel * decay_gravity;
        float drift_x = (sin(time * 10.0 + grid_uv.y * 22.0) * 0.15 - 0.2) * decay_val_pixel * wind_strength;

        // Combine offset vectors
        vec2 read_uv = grid_uv;
        read_uv.y += disp_y;
        read_uv.x += disp_x;
        read_uv.y += fall_dist;
        read_uv.x += drift_x;
        read_uv.x += glitch_offset_x;

        if (flip_v) {
            read_uv.y = 1.0 - read_uv.y;
        }

        // Mask sampling with chromatic aberration splitting
        float text_mask_r = 0.0;
        float text_mask_g = 0.0;
        float text_mask_b = 0.0;

        if (read_uv.x >= 0.0 && read_uv.x <= 1.0 && read_uv.y >= 0.0 && read_uv.y <= 1.0) {
            float ab_offset = 0.005 * active_glitch * (1.0 + decay * 2.0);
            vec4 mask_r = texture(text_mask, clamp(read_uv - vec2(ab_offset, 0.0), vec2(0.0), vec2(1.0)));
            vec4 mask_g = texture(text_mask, clamp(read_uv, vec2(0.0), vec2(1.0)));
            vec4 mask_b = texture(text_mask, clamp(read_uv + vec2(ab_offset, 0.0), vec2(0.0), vec2(1.0)));
            
            text_mask_r = mask_r.a;
            text_mask_g = mask_g.a;
            text_mask_b = mask_b.a;
        }

        // Color processing states
        vec4 final_color = base_color;

        if (t_rise > 0.0 && t_rise < 1.0) {
            // High-energy electrical sizzle cooling to steel-bone white
            float sizzle = step(0.65, hash2d(grid_uv * 180.0 + time * 10.0));
            float cooling_factor = clamp(t_rise * 1.5, 0.0, 1.0);
            final_color = mix(vec4(glow_color.rgb + sizzle * 0.3, glow_color.a), base_color, cooling_factor);
        } else if (formation >= 1.0 && decay == 0.0) {
            // Standard holding: circuit pulses flowing through letters
            float circ = circuits(grid_uv, time);
            final_color.rgb += vec3(circ) * glow_color.rgb;
            
            // Crystalline shimmer
            float shimmer = (noise(grid_uv * 120.0 + vec2(time * 1.2)) - 0.5) * 0.08;
            final_color.rgb += vec3(shimmer);
        }

        // Thermal decay phase color changes
        if (decay > 0.0) {
            if (decay_val_pixel < 0.25) {
                float f = decay_val_pixel / 0.25;
                final_color = mix(base_color, glow_color * 1.3, f);
            } else if (decay_val_pixel < 0.60) {
                float f = (decay_val_pixel - 0.25) / 0.35;
                final_color = mix(glow_color * 1.3, ash_color, f);
            } else {
                float f = (decay_val_pixel - 0.60) / 0.40;
                final_color = mix(ash_color, vec4(ash_color.rgb, 0.0), f);
            }
        }

        // Recombine channels
        vec4 final_text_color = vec4(0.0);
        final_text_color.r = text_mask_r * final_color.r;
        final_text_color.g = text_mask_g * final_color.g;
        final_text_color.b = text_mask_b * final_color.b;
        final_text_color.a = max(max(text_mask_r, text_mask_g), text_mask_b) * final_color.a;

        // Mix text over deep industrial structure background
        COLOR = mix(bg_color, final_text_color, final_text_color.a);

        // Micro scanline overlays
        if (enable_scanlines) {
            float scanline = sin(cur_uv.y * pixel_grid.y * 3.14159) * 0.08;
            COLOR.rgb -= vec3(scanline);
        }
    }
}