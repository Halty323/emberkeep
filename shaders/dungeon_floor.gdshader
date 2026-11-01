shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D paint : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D relief_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm : filter_linear_mipmap, repeat_enable;
uniform vec2 uv_aspect = vec2(1.0);
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec3 palette_a : source_color;
uniform vec3 palette_b : source_color;
uniform vec3 palette_c : source_color;
uniform vec3 palette_d : source_color;
uniform vec3 palette_e : source_color;
uniform vec3 moss_color : source_color;
uniform vec3 ember_color : source_color;
uniform float tile_scale = .34;
uniform float relief_strength = .65;
uniform float relief_depth = 0.0;
uniform float earth = 0.0;
uniform float wetness = 0.0;
uniform float moss = 0.0;
uniform float frost = 0.0;
uniform float brass = 0.0;
uniform float embers = 0.0;
varying vec2 world_xz;
varying float world_y;
#include "res://shaders/carved_relief.gdshaderinc"
void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    world_xz = world.xz;
    world_y = world.y;
}
void fragment() {
    vec2 p = vec2(world_xz.x,-world_xz.y)*tile_scale*uv_aspect;
    if (relief_depth > 0.0) {
        vec3 to_eye = INV_VIEW_MATRIX[3].xyz - vec3(world_xz.x,world_y,world_xz.y);
        float fade = 1.0-smoothstep(6.0,16.0,length(to_eye));
        vec2 slide = clamp(vec2(to_eye.x,-to_eye.z)/max(abs(to_eye.y),.65),vec2(-3.0),vec2(3.0));
        p = carved_uv(orm,p,slide*tile_scale*uv_aspect*relief_depth*fade);
    }
    vec3 base = texture(paint,p).rgb;
    vec3 physical = texture(orm,p).rgb;
    vec4 patches = texture(detail,world_xz*.055);
    vec3 tint = mix(mix(palette_a,palette_b,patches.r),mix(palette_c,palette_d,patches.g),patches.b);
    tint = mix(tint,palette_e,patches.a*.2);
    tint /= max(.08,max(tint.r,max(tint.g,tint.b)));
    vec3 color = base * mix(vec3(.98),tint,.17);
    color = mix(color,color*vec3(.83,.85,.94),earth*.3);
    float growth = moss*smoothstep(.43,.83,patches.g+(1.0-physical.r)*.25);
    color = mix(color,moss_color*(.5+base.r),growth*.7);
    color = mix(color,vec3(.45,.55,.63),frost*patches.b*.38);
    float damp = wetness*smoothstep(.22,.72,patches.a);
    ALBEDO = color*(1.0-damp*.16);
    vec3 bump = texture(relief_map,p).rgb*2.0-1.0;
    // Matching world-space tangent frame on every merged ground sheet.
    NORMAL = normalize((VIEW_MATRIX*vec4(bump.x*relief_strength,sqrt(max(.04,1.0-dot(bump.xy,bump.xy))),-bump.y*relief_strength,0.0)).xyz);
    ROUGHNESS = clamp(mix(physical.g,.24,damp),.22,.95);
    SPECULAR = .5;
    AO = mix(1.0,physical.r,.75);
    AO_LIGHT_AFFECT = .15;
    METALLIC = max(physical.b,brass*smoothstep(.97,1.0,patches.b)*.28);
    EMISSION = ember_color*embers*smoothstep(.69,.95,1.0-physical.r)*(.05+patches.r*.08);
}
