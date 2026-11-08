shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// One kind of floor residue over a whole room, drawn from a mask with one
// texel per residue tile. Linear filtering and a threshold merge neighbouring
// tiles into one smooth, evenly coloured patch, so nothing overlaps; a little
// noise frays the edge so no patch is a perfect round. Each kind has its own
// surface: glossy wax, flickering fire, fuzzy moss, glinting glass, oily ink.
// (Water and ice have water.gdshader.) Every patch has a body: its normals
// bend over the mask's own slope, so it domes up from a rounded bead at the
// edge, catches the lanterns as a glossy liquid would, and sits in a soft
// contact shadow just outside its rim.
uniform sampler2D mask : filter_linear, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.86, 0.78, 0.6, 0.85);
uniform float glow = 0.0;
uniform float flicker = 0.0;
uniform float roughness_value = 0.6;
// 0 wax, 1 ice, 2 fire, 3 moss, 4 glass, 5 water, 6 ink (ResidueField.KINDS).
uniform int kind = 0;
uniform bool first_person = false;
uniform vec2 grid_origin;
uniform vec2 grid_size;
uniform float tile = 0.8;
// First person the patch is a real raised body (ResidueField.build_body):
// its own normals light it; flat planes bend theirs from the mask instead.
uniform bool body_mesh = false;
varying vec2 world_xz;

void vertex() {
    world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float raw(vec2 xz) {
    return texture(mask, (xz - grid_origin) / (tile * grid_size)).r;
}

// The mask read through five taps: one texel a tile would draw squares and
// diamonds; this rounds them into puddles.
float soft(vec2 xz) {
    float r = tile * 0.42;
    return raw(xz) * 0.36 + (raw(xz + vec2(r, r)) + raw(xz + vec2(-r, r)) + raw(xz + vec2(r, -r)) + raw(xz + vec2(-r, -r))) * 0.16;
}

float cover(vec2 xz) {
    return smoothstep(0.38, 0.92, raw(xz));
}

void fragment() {
    float coverage = soft(world_xz);
    vec4 n = texture(detail, world_xz * 0.6);
    // A fine, two-scale fray: broad lobes and a crisp wavering shoreline.
    float fray = (texture(detail, world_xz * 0.33).b - 0.5) * 0.22 + (texture(detail, world_xz * 3.1).r - 0.5) * 0.03;
    float shape = smoothstep(0.4, 0.5, coverage + fray);
    // Just outside the rim: the patch's soft contact shadow on the stone.
    float contact = smoothstep(0.24, 0.42, coverage + fray) * (1.0 - shape);
    if (shape < 0.01 && contact < 0.01) {
        discard;
    }
    // How the patch swells: wax and ink bead high, moss and fire sit low.
    float bulge = kind == 0 ? 1.1 : (kind == 6 ? 0.95 : (kind == 5 || kind == 1 ? 0.7 : (kind == 4 ? 0.5 : 0.45)));
    float bumps = kind == 3 ? 0.55 : (kind == 4 ? 0.4 : 0.12);
    float e = tile * 0.4;
    vec2 slope = vec2(cover(world_xz + vec2(e, 0.0)) - cover(world_xz - vec2(e, 0.0)),
        cover(world_xz + vec2(0.0, e)) - cover(world_xz - vec2(0.0, e))) * bulge;
    vec2 grain = (texture(detail, world_xz * 2.1).rg - 0.5) + (texture(detail, world_xz * 6.3).gb - 0.5) * 0.5;
    if (body_mesh) {
        // Real geometry: its own normal, with fine surface grain over it.
        NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(-grain.x * bumps, 0.0, -grain.y * bumps, 0.0)).xyz);
    } else {
        vec3 up = normalize(vec3(-slope.x - grain.x * bumps, 1.0, -slope.y - grain.y * bumps));
        NORMAL = normalize((VIEW_MATRIX * vec4(up, 0.0)).xyz);
    }
    // Thick in the middle, a bright bead where the dome turns at the edge.
    float body = smoothstep(0.5, 0.95, coverage);
    float bead = smoothstep(0.42, 0.52, coverage) * (1.0 - smoothstep(0.55, 0.72, coverage));
    vec3 color = tint.rgb;
    vec3 light = vec3(0.0);
    float rough = roughness_value;
    float opacity = tint.a;
    float rim = 1.0 - smoothstep(0.5, 0.62, coverage);
    if (kind == 0) {
        // Wax: swirled cream, poured thick: a glossy raised lip, deeper and
        // warmer toward the middle where it pooled.
        color *= 0.9 + 0.2 * n.r;
        color = mix(color, color * vec3(0.82, 0.7, 0.5), body * 0.55);
        color = mix(color, vec3(1.0, 0.96, 0.86), bead * 0.45);
        color *= 0.78;
        rough = mix(0.12, 0.26, n.g);
        opacity = mix(0.82, 0.97, body);
    } else if (kind == 2) {
        // Fire: two drifting layers of flame, white-hot where they meet.
        float a = texture(detail, world_xz * 0.9 + vec2(0.0, -TIME * 0.9)).r;
        float b = texture(detail, world_xz * 1.6 + vec2(TIME * 0.35, -TIME * 1.3)).g;
        float flame = smoothstep(0.35, 0.95, a * 0.6 + b * 0.6);
        color = mix(vec3(0.55, 0.12, 0.03), mix(tint.rgb, vec3(1.0, 0.92, 0.6), flame), 0.4 + 0.6 * flame);
        light = color * glow * (0.5 + flame) * (1.0 - flicker * 0.25 + flicker * 0.25 * sin(TIME * 9.0 + n.g * 8.0));
        if (first_person) {
            // A scorched ember bed belongs on a stone dungeon floor. Dark
            // crust dominates, with slow hot fissures and a cooled bank;
            // the damage footprint still comes from the exact same mask.
            vec2 warp = texture(detail,world_xz*.19).rb-vec2(.5);
            vec4 crust = texture(detail,world_xz*.78+warp*.65);
            vec4 grain = texture(detail,world_xz*3.7+warp);
            // Ridged fracture noise is warped by broad stone variation.
            // Avoid cellular-distance contours, which form perfect glowing
            // rings and make a natural ember bed look like a neon pattern.
            float fissure = smoothstep(.38,.68,crust.a)*smoothstep(.3,.68,grain.r);
            float bank = smoothstep(.46,.69,coverage);
            float pulse = .76+.08*sin(TIME*1.45+crust.r*13.0);
            float heat = fissure*bank*pulse;
            vec3 basalt = mix(vec3(.065,.046,.032),vec3(.16,.115,.073),crust.b*.65+grain.b*.35);
            vec3 hot = mix(vec3(.56,.075,.012),vec3(.92,.28,.045),grain.g*.45);
            color = mix(basalt,hot,heat*.28);
            light = hot*heat*.66;
            opacity = mix(.48,.8,heat);
            rough = .93;
        }
    } else if (kind == 3) {
        // Moss: soft and uneven, darker in its hollows.
        color *= 0.7 + 0.5 * texture(detail, world_xz * 2.4).r;
        color = mix(color, color * vec3(1.2, 1.25, 0.9), smoothstep(0.6, 0.9, n.g) * 0.4);
        // Thicker cushions in the middle, thin threads at the edge.
        color *= 0.8 + 0.35 * body;
        opacity = mix(0.75, 0.97, body);
    } else if (kind == 4) {
        // Glass: pale shards that catch the light.
        float facet = step(0.7, texture(detail, world_xz * 2.2).g);
        color = mix(color, vec3(1.0), facet * 0.4);
        light = vec3(0.7, 0.85, 1.0) * facet * glow * (0.6 + 0.4 * sin(TIME * 2.0 + n.r * 12.0));
    } else if (kind == 6) {
        // Ink: deep and glossy, an oily sheen that shifts as you watch.
        float film = texture(detail, world_xz * 0.8 + vec2(TIME * 0.05, 0.0)).g;
        vec3 sheen = 0.5 + 0.5 * cos(6.2831 * (film + vec3(0.0, 0.33, 0.67)) + TIME * 0.4);
        color = mix(color, sheen * 0.35, 0.25 * smoothstep(0.4, 0.8, film));
        color *= 1.0 - 0.35 * body;
        color += vec3(0.25, 0.2, 0.35) * bead * 0.4;
        rough = 0.08;
    } else if (kind == 5 || kind == 1) {
        // Water or ice on devices without the mirrored glaze: dark with
        // depth, a pale meniscus at the shore, glossy.
        color = mix(tint.rgb, tint.rgb * 0.45, body);
        color += vec3(0.25, 0.35, 0.4) * bead * 0.5;
        light = tint.rgb * glow;
        rough = kind == 1 ? 0.25 : 0.06;
    } else {
        light = tint.rgb * glow;
    }
    // Outside the rim only the contact shadow shows.
    color = mix(color, vec3(0.0), contact);
    ALBEDO = color;
    EMISSION = light * shape;
    ROUGHNESS = rough;
    SPECULAR = 0.6;
    ALPHA = max(opacity * shape, contact * 0.32);
}
