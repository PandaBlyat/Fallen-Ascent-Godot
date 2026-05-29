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

// Custom styling parameters (optimized default values for softened CRT simulation)
uniform float phosphor_intensity : hint_range(0.0, 1.0) = 0.06;    // Softened subpixel RGB mask separation
uniform float glass_reflection : hint_range(0.0, 1.0) = 0.06;      // Softened ambient reflection overlay
uniform float edge_burn_width : hint_range(0.05, 0.3) = 0.12;      // Glowing boundary thickness

uniform vec4 base_color : source_color = vec4(0.82, 0.88, 0.90, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.38, 0.08, 1.0);
uniform vec4 ash_color : source_color = vec4(0.18, 0.19, 0.22, 1.0);
uniform vec4 conduit_color : source_color = vec4(0.0, 0.72, 0.53, 1.0);

// Analog video feed simulation uniforms
uniform vec2 screen_shake = vec2(0.0);                             // Internally shifts signal behind the bezel
uniform float sync_roll = 0.0;                                     // Simulated V-Hold desynchronization vertical wrap
uniform float hum_bar_speed = 0.75;                                // Travel velocity of power hum lines
uniform float hum_bar_intensity = 0.02;                            // Wave deviation strength of the hum bar

// 2D pseudo-random hash generator
float hash2d(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

// Organic 2D Value Noise
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

// 4x4 Bayer dither generator
float bayer4x4(vec2 p) {
    ivec2 ip = ivec2(mod(p, 4.0));
    int val = (ip.x ^ ip.y) * 4 + ip.y;
    return float(val) / 16.0;
}

// Simulates outward screen curvature distortions (bezel mapping) - Softened bend
vec2 curve_uv(vec2 uv) {
    vec2 centered = uv - 0.5;
    float dist = dot(centered, centered);
    centered *= 1.0 + dist * 0.06; 
    return centered + 0.5;
}

// Spawns micro-sized thermal rising soot particles
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

// Generates pulsing circuit tracks running through background elements
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
        // Apply analog sync warp & vertical roll internally behind glass boundaries
        cur_uv += screen_shake;
        cur_uv.y = fract(cur_uv.y + sync_roll);

        float pixel_size_x = pixel_grid_width;
        float pixel_size_y = pixel_grid_width * aspect_ratio;
        vec2 pixel_grid = vec2(pixel_size_x, pixel_size_y);
        vec2 grid_uv = floor(cur_uv * pixel_grid) / pixel_grid;

        // Sync Cycle & horizontal line tearing variables
        float glitch_cycle = sin(time * 0.8) * cos(time * 1.7);
        float active_glitch = step(0.82, glitch_cycle) * hash2d(vec2(floor(time * 15.0))) * glitch_intensity;
        
        float jitter_rand = hash2d(vec2(floor(grid_uv.y * 64.0), floor(time * 24.0)));
        float glitch_offset_x = (jitter_rand - 0.5) * 0.08 * active_glitch;
        if (jitter_rand > 0.85) {
            glitch_offset_x += (hash2d(vec2(floor(time * 30.0))) - 0.5) * 0.05 * active_glitch;
        }
        
        // Digital chunk block corruption simulation
        vec2 glitch_block_grid = floor(grid_uv * 12.0);
        if (hash2d(glitch_block_grid + floor(time * 8.0)) < 0.08 * active_glitch) {
            grid_uv.x += (hash2d(glitch_block_grid) - 0.5) * 0.15;
            grid_uv.y += (hash2d(glitch_block_grid + vec2(1.0)) - 0.5) * 0.15;
        }

        // Apply rolling hum bar wave distortion horizontally
        float hum_bar = sin(grid_uv.y * 8.0 - time * hum_bar_speed) * sin(grid_uv.y * 3.0 + time * hum_bar_speed * 0.5);
        grid_uv.x += hum_bar * hum_bar_intensity * active_glitch;

        // Generate ordered dither comparison metric
        float dither = bayer4x4(grid_uv * pixel_grid);

        // Dynamically calculate desaturated green matching background (conduit_color) luma
        float conduit_luma = dot(conduit_color.rgb, vec3(0.299, 0.587, 0.114));
        vec4 desat_green = vec4(mix(conduit_color.rgb, vec3(conduit_luma), 0.5), 1.0);

        // --- 1. BACKGROUND WALLPAPER SIMULATION ---
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

        // Read background UV coordinates
        vec2 read_uv_bg = grid_uv;
        read_uv_bg.y -= bg_form_disp_y;
        read_uv_bg.x -= bg_form_drift_x;
        read_uv_bg.y -= bg_fall_dist;
        read_uv_bg.x -= bg_decay_drift_x;
        read_uv_bg.x += glitch_offset_x;

        // Sampling wallpaper textures
        float wp_mask = 0.0;
        if (read_uv_bg.x >= 0.0 && read_uv_bg.x <= 1.0 && read_uv_bg.y >= 0.0 && read_uv_bg.y <= 1.0) {
            float wp_ab = 0.005 * active_glitch * (1.0 + bg_decay * 2.0);
            vec4 wp_r = texture(wallpaper_texture, clamp(read_uv_bg - vec2(wp_ab, 0.0), vec2(0.0), vec2(1.0)));
            vec4 wp_g = texture(wallpaper_texture, clamp(read_uv_bg, vec2(0.0), vec2(1.0)));
            vec4 wp_b = texture(wallpaper_texture, clamp(read_uv_bg + vec2(wp_ab, 0.0), vec2(0.0), vec2(1.0)));
            wp_mask = max(wp_r.r, max(wp_g.g, wp_b.b));
        }

        vec4 wp_color = conduit_color;

        // Render desaturated green boundary edge during rise
        if (bg_t_rise > 0.0 && bg_t_rise < 1.0) {
            float edge_glow_factor = sin(bg_t_rise * 3.14159);
            float sizzle = step(0.40, hash2d(grid_uv * 200.0 + time * 20.0));
            vec4 green_glow = mix(desat_green, vec4(0.65, 0.85, 0.75, 1.0), sizzle * 0.5);
            wp_color = mix(conduit_color, green_glow * 2.0, edge_glow_factor);
        } else if (bg_formation >= 1.0 && bg_decay == 0.0) {
            float circ = circuits(grid_uv, time * 0.5);
            wp_color.rgb += vec3(circ) * base_color.rgb * 0.6;
            float shimmer = (noise(grid_uv * 100.0 + vec2(time * 1.0)) - 0.5) * 0.08;
            wp_color.rgb += vec3(shimmer);
        }

        // Interpolate decay sequences using desaturated green instead of fire colors
        float wp_alpha_mult = bg_visible_rise * bg_visible_decay;
        if (bg_decay > 0.0) {
            if (bg_decay_age > 0.0) {
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
        }

        vec4 raw_bg = mix(vec4(0.01, 0.012, 0.015, 1.0), vec4(0.002, 0.003, 0.005, 1.0), grid_uv.y);
        float ember_val = embers(grid_uv, time);
        
        // Embers colored in desaturated green
        vec4 bg_color = raw_bg + vec4(desat_green.rgb * ember_val, 1.0) * 0.22;
        bg_color.rgb *= bg_dimness;
        bg_color.a = 1.0;

        vec4 final_wp = vec4(wp_color.rgb, wp_mask * wp_color.a * wp_alpha_mult);
        bg_color = mix(bg_color, final_wp, final_wp.a);


        // --- 2. TITLE TEXT SIMULATION ---
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

        // Chromatic Aberration Vectors
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
            // Dynamic green circuit overlays inside letters
            final_color.rgb += vec3(circ) * desat_green.rgb * 1.2;
            float shimmer = (noise(grid_uv * 140.0 + vec2(time * 1.5)) - 0.5) * 0.12;
            final_color.rgb += vec3(shimmer);

            float raster_sweep = sin(grid_uv.y * 10.0 - time * 3.0) * 0.5 + 0.5;
            final_color.rgb = mix(final_color.rgb, final_color.rgb * 1.35, raster_sweep * 0.3);
        }

        float text_alpha_mult = title_visible_rise * title_visible_decay;
        if (title_decay > 0.0) {
            if (decay_val_pixel > 0.0) {
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
        }

        // --- 8-TAP CONCENTRIC RADIAL HALATION / BLUR ---
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

        // Glowing layer desaturated green
        vec4 glow_layer = vec4(desat_green.rgb * 1.3, glow_mask * text_alpha_mult);
        vec4 text_layer = vec4(
            text_mask_r * final_color.r,
            text_mask_g * final_color.g,
            text_mask_b * final_color.b,
            max(max(text_mask_r, text_mask_g), text_mask_b) * final_color.a * text_alpha_mult
        );

        // Blend glow layer under solid text layer
        vec4 final_text_color = mix(glow_layer, text_layer, text_layer.a);
        final_text_color.a = max(glow_layer.a, text_layer.a);

        COLOR = mix(bg_color, final_text_color, final_text_color.a);

        // --- RETRO CRT SIMULATION OVERLAYS - REDUCED/SOFTENED ---
        vec2 edge_dist = min(cur_uv, 1.0 - cur_uv);
        COLOR.rgb *= smoothstep(0.0, 0.03, min(edge_dist.x, edge_dist.y));
        
        float reflection_sweep = sin(cur_uv.x * 1.8 - cur_uv.y * 0.6 + time * 0.5) * 0.5 + 0.5;
        reflection_sweep = pow(reflection_sweep, 10.0) * glass_reflection;
        COLOR.rgb += vec3(reflection_sweep * 0.08); // Reduced glint intensity

        if (enable_scanlines) {
            float scanline_val = sin(cur_uv.y * pixel_grid.y * 3.14159);
            float scanline = mix(0.06, 0.0, abs(scanline_val)) * 0.4; // Softened scanline subtraction depth
            COLOR.rgb -= vec3(scanline);
            COLOR.rgb *= (0.99 + 0.01 * sin(time * 60.0)); // Softened brightness flicker
        }

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

        float vignette = smoothstep(0.85, 0.35, length(cur_uv - 0.5));
        COLOR.rgb *= mix(0.7, 1.0, vignette); // Softened vignette corner dark spots

        if (active_glitch > 0.4) {
            float static_noise = hash2d(grid_uv * 313.0 + vec2(time));
            if (static_noise > 0.98) {
                COLOR.rgb += vec3(0.5 * active_glitch);
            }
        }
    }
}