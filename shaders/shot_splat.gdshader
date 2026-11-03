shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// The light a spell throws on the floor beneath it, with the faint ring of
// its sigil; it fades by shrinking.
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);

void fragment() {
    float d = length(UV - 0.5) * 2.0;
    float pool = pow(max(0.0, 1.0 - d), 2.4) * 0.2;
    float ring = smoothstep(0.04, 0.0, abs(d - 0.55)) * 0.08;
    ALBEDO = tint.rgb * (pool + ring);
}
