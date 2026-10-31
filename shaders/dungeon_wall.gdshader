shader_type spatial;
render_mode diffuse_lambert;
uniform sampler2D paint : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D relief_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color;
uniform float tile_scale = .5;
uniform float relief_strength = .55;
varying vec3 world;
varying vec3 world_normal;
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec3 n = normalize(world_normal);
    vec2 uv = world.xy;
    vec3 tangent = vec3(1,0,0);
    vec3 up = vec3(0,1,0);
    if (abs(n.x) > .5) { uv = world.zy; tangent = vec3(0,0,1); }
    if (abs(n.y) > .5) { uv = world.xz; up = vec3(0,0,1); }
    vec3 paint_color = texture(paint, uv * tile_scale).rgb;
    vec3 bump = texture(relief_map, uv * tile_scale).rgb * 2.0 - 1.0;
    vec3 shaped = normalize(n + (tangent * bump.x + up * bump.y) * relief_strength);
    NORMAL = normalize((VIEW_MATRIX * vec4(shaped,0.0)).xyz);
    // Painted occlusion, as in period lightmapped environments. Real lamps
    // still supply every warm highlight and can be extinguished correctly.
    float foot = mix(.66,1.0,smoothstep(0.0,.7,world.y));
    ALBEDO = tint * paint_color * 1.5 * foot;
    ROUGHNESS = .87;
    SPECULAR = .25;
}
