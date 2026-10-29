shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// One kind of floor residue over a whole room, drawn from a mask with one
// texel per residue tile. Linear filtering and a threshold merge neighbouring
// tiles into one smooth, evenly coloured patch, so nothing overlaps.
uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(0.86, 0.78, 0.6, 0.85);
uniform float glow = 0.0;
uniform float flicker = 0.0;
uniform float roughness_value = 0.6;
uniform vec2 grid_origin;
uniform vec2 grid_size;
uniform float tile = 0.8;
varying vec2 world_xz;

void vertex() {
    world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    float coverage = texture(mask, (world_xz - grid_origin) / (tile * grid_size)).r;
    float shape = smoothstep(0.4, 0.5, coverage);
    if (shape < 0.01) {
        discard;
    }
    // Fire shimmers as a whole; every other kind stays one even colour.
    float wave = 1.0 - flicker * (0.15 + 0.15 * sin(TIME * 8.0));
    ALBEDO = tint.rgb * wave;
    EMISSION = tint.rgb * glow * wave;
    ROUGHNESS = roughness_value;
    ALPHA = tint.a * shape;
}
