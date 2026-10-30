shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
// A shot's white-hot heart, tinted toward its colour at the rim. Bright
// enough to bloom. Shots of one colour share this material; a shot fades by
// shrinking.
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);

void fragment() {
    float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
    vec3 hot = mix(vec3(1.0, 0.97, 0.9), tint.rgb, 0.3 + 0.6 * rim);
    ALBEDO = hot * (1.15 + rim * 0.6);
}
