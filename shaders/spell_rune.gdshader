shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Where something is about to rise from the floor: a ring with runes turning
// inside it and a glow filling it as the moment comes. A flat plane; its X
// and Z scale size it and its Y scale (which a plane does not show) is how
// close the moment is, so runes of one colour share one material.
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);
varying float charge;
varying float turn;

void vertex() {
    charge = clamp(length(MODEL_MATRIX[1].xyz), 0.0, 1.0);
    turn = TIME * 1.8 + dot(MODEL_MATRIX[3].xyz, vec3(1.3, 0.0, 2.1));
}

void fragment() {
    vec2 c = (UV - 0.5) * 2.0;
    float d = length(c);
    float a = atan(c.y, c.x) + turn;
    float ring = smoothstep(0.05, 0.0, abs(d - 0.92));
    float inner = smoothstep(0.03, 0.0, abs(d - 0.74)) * 0.7;
    float runes = step(0.55, fract(a / 6.2832 * 9.0)) * step(0.76, d) * step(d, 0.9) * 0.45;
    float fill = (1.0 - smoothstep(0.0, 0.95, d)) * charge * charge * 0.55;
    ALBEDO = tint.rgb * ((ring + inner + runes) * (0.35 + 0.65 * charge) + fill) * step(d, 1.0);
}
