shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// One kind of floor residue over a whole room, drawn from a mask with one
// texel per residue tile. Linear filtering and a threshold merge neighbouring
// tiles into one smooth, evenly coloured patch, so nothing overlaps; a little
// noise frays the edge so no patch is a perfect round. Each kind has its own
// surface: glossy wax, flickering fire, fuzzy moss, glinting glass, oily ink.
// (Water and ice have water.gdshader.)
uniform sampler2D mask : filter_linear, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.86, 0.78, 0.6, 0.85);
uniform float glow = 0.0;
uniform float flicker = 0.0;
uniform float roughness_value = 0.6;
// 0 wax, 1 ice, 2 fire, 3 moss, 4 glass, 5 water, 6 ink (ResidueField.KINDS).
uniform int kind = 0;
uniform vec2 grid_origin;
uniform vec2 grid_size;
uniform float tile = 0.8;
varying vec2 world_xz;

void vertex() {
    world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    float coverage = texture(mask, (world_xz - grid_origin) / (tile * grid_size)).r;
    vec4 n = texture(detail, world_xz * 0.6);
    float shape = smoothstep(0.4, 0.5, coverage + (n.b - 0.5) * 0.14);
    if (shape < 0.01) {
        discard;
    }
    vec3 color = tint.rgb;
    vec3 light = vec3(0.0);
    float rough = roughness_value;
    float rim = 1.0 - smoothstep(0.5, 0.62, coverage);
    if (kind == 0) {
        // Wax: swirled cream, a raised lighter lip.
        color *= 0.9 + 0.2 * n.r;
        color = mix(color, vec3(0.98, 0.94, 0.82), rim * 0.35);
    } else if (kind == 2) {
        // Fire: two drifting layers of flame, white-hot where they meet.
        float a = texture(detail, world_xz * 0.9 + vec2(0.0, -TIME * 0.9)).r;
        float b = texture(detail, world_xz * 1.6 + vec2(TIME * 0.35, -TIME * 1.3)).g;
        float flame = smoothstep(0.35, 0.95, a * 0.6 + b * 0.6);
        color = mix(vec3(0.55, 0.12, 0.03), mix(tint.rgb, vec3(1.0, 0.92, 0.6), flame), 0.4 + 0.6 * flame);
        light = color * glow * (0.5 + flame) * (1.0 - flicker * 0.25 + flicker * 0.25 * sin(TIME * 9.0 + n.g * 8.0));
    } else if (kind == 3) {
        // Moss: soft and uneven, darker in its hollows.
        color *= 0.7 + 0.5 * texture(detail, world_xz * 2.4).r;
        color = mix(color, color * vec3(1.2, 1.25, 0.9), smoothstep(0.6, 0.9, n.g) * 0.4);
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
        rough = 0.15;
    } else {
        light = tint.rgb * glow;
    }
    ALBEDO = color;
    EMISSION = light;
    ROUGHNESS = rough;
    ALPHA = tint.a * shape;
}
