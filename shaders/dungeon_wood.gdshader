shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 tint : source_color;
uniform sampler2D paint : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D relief_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm : filter_linear_mipmap, repeat_enable;
uniform vec2 uv_aspect = vec2(1.0);
uniform bool local_space = false;
varying vec3 position;
varying vec3 surface_normal;
varying mat3 normal_to_view;
void vertex() {
    position = local_space ? VERTEX : (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    surface_normal = local_space ? NORMAL : normalize(MODEL_NORMAL_MATRIX*NORMAL);
    normal_to_view = local_space ? MODELVIEW_NORMAL_MATRIX : mat3(VIEW_MATRIX);
}
void fragment() {
    vec3 n = normalize(surface_normal);
    vec3 t;
    vec3 b;
    vec2 uv;
    if (abs(n.y) > .65) {
        t=vec3(1,0,0); b=vec3(0,0,-sign(n.y)); uv=vec2(position.x,-position.z*sign(n.y));
    } else if (abs(n.x) > .65) {
        t=vec3(0,0,-sign(n.x)); b=vec3(0,1,0); uv=vec2(-position.z*sign(n.x),position.y);
    } else {
        t=vec3(sign(n.z),0,0); b=vec3(0,1,0); uv=vec2(position.x*sign(n.z),position.y);
    }
    uv *= vec2(.45,.55)*uv_aspect;
    vec3 color = texture(paint,uv).rgb;
    vec3 physical = texture(orm,uv).rgb;
    vec3 bump = texture(relief_map,uv).rgb*2.0-1.0;
    vec3 shaped = normalize(t*bump.x*.45+b*bump.y*.45+n*sqrt(max(.04,1.0-dot(bump.xy,bump.xy))));
    NORMAL = normalize(normal_to_view*shaped);
    vec3 hue = tint/max(.08,max(tint.r,max(tint.g,tint.b)));
    ALBEDO = color*mix(vec3(1),hue,.24);
    ROUGHNESS = clamp(physical.g,.38,.95);
    SPECULAR = .42;
    AO = mix(1.0,physical.r,.55);
    AO_LIGHT_AFFECT = .15;
}
