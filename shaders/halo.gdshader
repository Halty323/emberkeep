shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.15, 0.25);
uniform float softness = 2.6;
void fragment() {
    float d = length(UV - vec2(0.5)) * 2.0;
    float glow = pow(max(0.0, 1.0 - d), softness);
    ALBEDO = tint.rgb;
    ALPHA = glow * tint.a;
}
