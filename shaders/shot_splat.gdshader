shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// The pool of light a shot throws on the floor beneath it; it fades by
// shrinking.
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);

void fragment() {
    float d = length(UV - 0.5) * 2.0;
    ALBEDO = tint.rgb * pow(max(0.0, 1.0 - d), 2.4) * 0.22;
}
