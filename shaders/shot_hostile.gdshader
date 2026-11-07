shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// A foe's spell wears a dark, notched rim facing the eye: every spell of the
// party is pure light, so a dark-ringed ember always reads as danger.
uniform vec4 tint : source_color = vec4(1.0, 0.24, 0.39, 1.0);

void vertex() {
    float s = length(MODEL_MATRIX[0].xyz);
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
    MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
    vec2 p = UV - 0.5;
    float d = length(p) * 2.0;
    float turn = atan(p.y, p.x) * 4.0 + TIME * 5.0;
    float notch = 0.06 * step(0.0, sin(turn));
    float band = smoothstep(0.58, 0.64, d) * (1.0 - smoothstep(0.86 + notch, 0.92 + notch, d));
    float edge = smoothstep(0.5, 0.56, d) * (1.0 - smoothstep(0.6, 0.66, d));
    ALBEDO = mix(vec3(0.07, 0.0, 0.03), tint.rgb, edge);
    ALPHA = max(band * 0.9, edge);
}
