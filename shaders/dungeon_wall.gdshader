shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D paint : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D relief_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm : filter_linear_mipmap, repeat_enable;
uniform vec2 uv_aspect = vec2(1.0);
uniform vec3 tint : source_color;
uniform float tile_scale = .4;
uniform float relief_strength = .72;
uniform float dampness = 0.0;
varying vec3 world;
varying vec3 world_normal;
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec3 n = normalize(world_normal);
    vec3 tangent;
    vec3 bitangent;
    vec2 uv;
    if (abs(n.y) > .65) {
        tangent = vec3(1.0,0.0,0.0);
        bitangent = vec3(0.0,0.0,-sign(n.y));
        uv = vec2(world.x,-world.z*sign(n.y));
    } else if (abs(n.x) > .65) {
        tangent = vec3(0.0,0.0,-sign(n.x));
        bitangent = vec3(0.0,1.0,0.0);
        uv = vec2(-world.z*sign(n.x),world.y);
    } else {
        tangent = vec3(sign(n.z),0.0,0.0);
        bitangent = vec3(0.0,1.0,0.0);
        uv = vec2(world.x*sign(n.z),world.y);
    }
    uv *= tile_scale*uv_aspect;
    vec3 surface = texture(paint,uv).rgb;
    vec3 physical = texture(orm,uv).rgb;
    vec3 bump = texture(relief_map,uv).rgb*2.0-1.0;
    vec3 shaped = normalize(tangent*bump.x*relief_strength + bitangent*bump.y*relief_strength + n*sqrt(max(.04,1.0-dot(bump.xy,bump.xy))));
    NORMAL = normalize((VIEW_MATRIX*vec4(shaped,0.0)).xyz);
    vec3 hue = tint / max(.08,max(tint.r,max(tint.g,tint.b)));
    float damp = dampness * (1.0-smoothstep(.25,2.6,world.y));
    ALBEDO = surface * mix(vec3(.94),hue,.22) * (1.0-damp*.16);
    ROUGHNESS = clamp(physical.g-damp*.36,.2,.97);
    SPECULAR = .48;
    METALLIC = physical.b;
    AO = mix(1.0,physical.r,.7);
    AO_LIGHT_AFFECT = .2;
}
