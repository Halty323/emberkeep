shader_type spatial;
render_mode cull_back, shadows_disabled;
// A room cell's floor as one finely divided sheet of natural ground, with no
// tile grid anywhere. The vertex stage swells and dips the surface and sinks
// its seams and cracks, so the relief is real geometry; the fragment stage
// paints it from the floor theme's palette in drifting patches and adds the
// theme's own finish: wet rock, frost and glints, glowing cracks, moss, brass.
// Laid out in world space, so neighbouring cells meet without a seam.
uniform vec3 palette_a : source_color = vec3(0.29, 0.26, 0.24);
uniform vec3 palette_b : source_color = vec3(0.27, 0.25, 0.23);
uniform vec3 palette_c : source_color = vec3(0.30, 0.27, 0.24);
uniform vec3 palette_d : source_color = vec3(0.25, 0.24, 0.22);
uniform vec3 palette_e : source_color = vec3(0.31, 0.28, 0.24);
uniform vec3 grout_color : source_color = vec3(0.09, 0.09, 0.09);
// 0: worn slabs of every size and shape; 1: rough rock; 2: packed earth.
uniform int pattern = 0;
// The typical slab across, in world units.
uniform float stone_size = 2.4;
uniform float grout_width = 0.035;
// How far the ground swells and its seams sink (world units); 0 lays it flat.
uniform float relief = 0.035;
uniform float roughness_value = 0.82;
uniform float wetness = 0.0;
uniform float frost = 0.0;
uniform float embers = 0.0;
uniform vec3 ember_color : source_color = vec3(1.0, 0.42, 0.12);
uniform float moss = 0.0;
uniform vec3 moss_color : source_color = vec3(0.24, 0.36, 0.18);
uniform float brass = 0.0;
uniform float cracks = 0.5;
uniform float sparkle = 0.0;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
varying vec3 world;

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash2(vec2 p) {
    return vec2(hash(p), hash(p + 17.31));
}

// Irregular cells: which one a point lies in and how far it is from the
// cell's edge, in cell units. Strong jitter keeps any lattice from showing.
vec3 cells(vec2 q, out vec2 id) {
    vec2 base = floor(q);
    vec2 f = fract(q);
    float best = 9.0;
    float second = 9.0;
    id = base;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 n = vec2(float(x), float(y));
            vec2 point = n + 0.05 + 0.9 * hash2(base + n) - f;
            float d = dot(point, point);
            if (d < best) {
                second = best;
                best = d;
                id = base + n;
            } else if (d < second) {
                second = d;
            }
        }
    }
    return vec3(sqrt(best), sqrt(second), (sqrt(second) - sqrt(best)) * 0.5);
}

// Low, rolling unevenness common to every kind of ground.
float swell(vec2 p, float lod) {
    return textureLod(detail, p * 0.11, lod).r * 0.8 + textureLod(detail, p * 0.43, lod).b * 0.35;
}

// Height of the ground at a point.
float surface(vec2 p) {
    float h = swell(p, 0.0) - 0.6;
    if (pattern == 0) {
        vec2 id;
        vec3 c = cells(p / stone_size, id);
        float seam = 1.0 - smoothstep(0.0, grout_width * 2.4 / stone_size, c.z);
        h += hash(id) * 0.5 - 1.5 * seam;
    } else if (pattern == 1) {
        float ridge = 1.0 - abs(textureLod(detail, p * 0.19, 0.0).a * 2.0 - 1.0);
        h -= 1.2 * smoothstep(0.86, 0.97, ridge) * cracks;
    } else {
        vec2 id;
        vec3 c = cells(p * 2.6, id);
        float pebble = step(0.62, hash(id)) * (1.0 - smoothstep(0.18, 0.32, c.x));
        h += 0.9 * pebble;
    }
    return relief * h;
}

void vertex() {
    vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    if (relief > 0.0) {
        float e = 0.07;
        float h = surface(w.xz);
        VERTEX.y += h;
        float hx = surface(w.xz + vec2(e, 0.0));
        float hz = surface(w.xz + vec2(0.0, e));
        NORMAL = normalize(vec3(h - hx, e, h - hz));
    }
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 p = world.xz;
    vec4 broad = texture(detail, p * 0.07);
    vec4 fine = texture(detail, p * 0.37);
    vec4 grain = texture(detail, p * 2.1);
    // The palette drifts across the floor in patches, never by tile.
    vec3 color = mix(mix(palette_a, palette_b, broad.r), mix(palette_c, palette_d, broad.g), smoothstep(0.3, 0.7, broad.b));
    color = mix(color, palette_e, smoothstep(0.55, 0.9, fine.g) * 0.6);
    color *= 0.8 + 0.4 * fine.r;
    color *= 0.88 + 0.24 * grain.g;
    float seam = 0.0;
    float rim = 0.0;
    float crack = 0.0;
    float rough = roughness_value;
    if (pattern == 0) {
        vec2 id;
        vec3 c = cells(p / stone_size, id);
        float edge = c.z * stone_size;
        float width = grout_width * (0.7 + 0.8 * grain.b);
        seam = 1.0 - smoothstep(width, width + 0.025, edge);
        rim = 1.0 - smoothstep(0.0, 0.22, edge);
        color *= 0.86 + 0.28 * hash(id);
        color *= 1.0 - rim * 0.14;
    } else if (pattern == 2) {
        vec2 id;
        vec3 c = cells(p * 2.6, id);
        float pebble = step(0.62, hash(id)) * (1.0 - smoothstep(0.2, 0.3, c.x));
        color = mix(color, mix(palette_e, vec3(0.42, 0.4, 0.37), 0.4) * (0.8 + 0.4 * hash(id + 1.3)), pebble);
        rough = mix(rough, 0.6, pebble);
        // Scuffs and darker trodden patches.
        color *= 1.0 - smoothstep(0.55, 0.85, broad.a) * 0.25;
    }
    // Cracks wander across everything, deepest in rough rock.
    float vein = 1.0 - abs(texture(detail, p * 0.19).a * 2.0 - 1.0);
    crack = (pattern == 1 ? smoothstep(0.935, 0.985, vein) : smoothstep(0.9, 0.975, vein) * 0.55) * cracks;
    color = mix(color, grout_color, seam * 0.85);
    color *= 1.0 - crack * 0.6;
    rough = mix(rough, 0.96, seam);
    float metal = 0.0;
    vec3 glow = vec3(0.0);
    float patch = smoothstep(0.5, 0.8, fine.g + broad.r * 0.3);
    float growth = moss * clamp(seam + patch * 0.7 + crack * 0.5, 0.0, 1.0);
    float rime = frost * clamp(seam * 0.9 + smoothstep(0.45, 0.9, fine.b) * 0.6 + rim * 0.25, 0.0, 1.0);
    color = mix(color, moss_color * (0.7 + 0.6 * grain.r), growth);
    color = mix(color, vec3(0.78, 0.86, 0.94), rime);
    float damp = wetness * smoothstep(0.35, 0.7, broad.a + 0.3 * seam);
    color *= 1.0 - damp * 0.45;
    rough = mix(rough, 0.12, damp);
    rough = mix(rough, 0.35, rime);
    // Brass set into the floor: scattered studs and discs, no lines.
    if (brass > 0.0) {
        vec2 id;
        vec3 c = cells(p * 0.9, id);
        float disc = step(0.72, hash(id + 5.1)) * (1.0 - smoothstep(0.1, 0.13, c.x)) * brass;
        float ring = step(0.72, hash(id + 5.1)) * (1.0 - smoothstep(0.012, 0.03, abs(c.x - 0.16))) * brass;
        float inlay = max(disc, ring);
        color = mix(color, vec3(0.8, 0.62, 0.3) * (0.85 + 0.3 * grain.r), inlay);
        metal = max(metal, inlay);
        rough = mix(rough, 0.3, inlay);
    }
    if (embers > 0.0) {
        // Only some cracks still hold fire, in patches that come and go.
        float live = smoothstep(0.45, 0.75, broad.g);
        float heat = clamp(crack * 1.3 + seam * smoothstep(0.8, 0.95, fine.r), 0.0, 1.0) * live;
        float breath = 0.55 + 0.45 * sin(TIME * 1.7 + broad.r * 9.0 + fine.g * 4.0);
        glow += ember_color * heat * embers * breath * 1.2;
        color = mix(color, vec3(0.05, 0.03, 0.02), heat * 0.6);
    }
    if (sparkle > 0.0) {
        vec2 cell = floor(p * 30.0);
        float twinkle = sin(TIME * 2.4 + hash(cell + 4.0) * 40.0);
        glow += vec3(0.85, 0.93, 1.0) * step(0.9965, hash(cell)) * smoothstep(0.2, 1.0, twinkle) * sparkle * 1.6;
    }
    // Per-pixel bevel and grain from the surface's own slope.
    float h = (1.0 - seam) * 0.012 - crack * 0.01 + grain.r * 0.005 - rim * 0.006;
    vec3 surf = vec3(world.x, world.y + h, world.z);
    vec3 n = normalize(cross(dFdy(surf), dFdx(surf)));
    if (n.y < 0.0) n = -n;
    NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(n, 0.0)).xyz, 0.6));
    ALBEDO = color;
    ROUGHNESS = rough;
    METALLIC = metal;
    SPECULAR = 0.35 + damp * 0.4;
    EMISSION = glow;
}
