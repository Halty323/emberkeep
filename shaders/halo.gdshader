shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.15, 0.25);
uniform float softness = 2.6;
uniform vec2 room_half_size = vec2(9.0, 7.0);
varying vec2 world_xz;

void vertex() {
    world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    float d = length(UV - vec2(0.5)) * 2.0;
    float glow = pow(max(0.0, 1.0 - d), softness);
    vec2 floor_edge = 1.0 - smoothstep(room_half_size - vec2(0.15), room_half_size, abs(world_xz));
    float intensity = glow * tint.a * floor_edge.x * floor_edge.y;
    if (intensity < 0.001) {
        discard;
    }
    // GLES3 shadow passes can leave additive blending at GL_ONE. Encode the
    // falloff in RGB too, so the quad edges always contribute zero light.
    ALBEDO = tint.rgb * intensity;
    ALPHA = 1.0;
}
