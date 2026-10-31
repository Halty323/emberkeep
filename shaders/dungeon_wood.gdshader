shader_type spatial;
render_mode diffuse_lambert;
uniform vec3 tint : source_color;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform bool local_space = false;
varying vec3 world;
void vertex() { world = local_space ? VERTEX : (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec2 uv = vec2(world.x + world.z, world.y);
    vec4 grain = texture(detail, uv * vec2(.12,2.8));
    float streak = (grain.r - .5) * .05;
    ALBEDO = tint * (.76 + grain.b * .36 + streak);
    ROUGHNESS = .73 + grain.g * .15;
    SPECULAR = .3;
}
