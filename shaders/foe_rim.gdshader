shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
// Drawn over a foe's body: a rim of its own colour so it stands out from
// the floor behind it, and a white flash for a moment when it is struck.
instance uniform vec4 rim_tint : source_color = vec4(1.0, 0.8, 0.6, 1.0);
instance uniform float flash = 0.0;

void fragment() {
    float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
    ALBEDO = rim_tint.rgb * rim * 0.55 + vec3(1.0, 0.97, 0.9) * flash * 0.85;
}
