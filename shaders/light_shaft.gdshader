shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Light falling down the stairwell from the floor above: strongest high up,
// gone by the top of the stair, soft at the silhouette.
uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.62, 0.42);
uniform float strength = 1.0;

void fragment() {
    float height = 1.0 - UV.y;
    float rise = smoothstep(0.0, 0.75, height);
    float facing = pow(abs(dot(NORMAL, VIEW)), 1.6);
    // Additive output encoded in RGB, as the halos do (see halo.gdshader).
    ALBEDO = tint.rgb * tint.a * strength * rise * facing;
    ALPHA = 1.0;
}
