shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.15, 0.25);
uniform float softness = 2.6;
// Room footprint mask: one (x0, z0, x1, z1) rectangle per floor cell. Sides
// shared with a neighbouring cell are pre-extended, so seams stay seamless.
uniform vec4 room_cells[4];
varying vec2 world_xz;

void vertex() {
    world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float cell_mask(vec4 r, vec2 p) {
    vec2 low = smoothstep(r.xy, r.xy + vec2(0.15), p);
    vec2 high = 1.0 - smoothstep(r.zw - vec2(0.15), r.zw, p);
    return low.x * low.y * high.x * high.y;
}

void fragment() {
    float d = length(UV - vec2(0.5)) * 2.0;
    float glow = pow(max(0.0, 1.0 - d), softness);
    float floor_mask = 0.0;
    for (int i = 0; i < 4; i++) {
        floor_mask = max(floor_mask, cell_mask(room_cells[i], world_xz));
    }
    float intensity = glow * tint.a * floor_mask;
    if (intensity < 0.001) {
        discard;
    }
    // GLES3 shadow passes can leave additive blending at GL_ONE. Encode the
    // falloff in RGB too, so the quad edges always contribute zero light.
    ALBEDO = tint.rgb * intensity;
    ALPHA = 1.0;
}
