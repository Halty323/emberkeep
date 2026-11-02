shader_type spatial;
render_mode unshaded, blend_mix, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled;
// Bounded horizon occlusion: nearby reconstructed surfaces above the tangent
// plane shade contacts; distant depth discontinuities never become dark halos.
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform int sample_count = 8;
uniform float radius = .85;
uniform float intensity = .75;
const vec2 KERNEL[12] = vec2[12](
    vec2(.25,.0),vec2(-.18,.2),vec2(-.03,-.34),vec2(.38,.32),
    vec2(-.52,-.07),vec2(.33,-.55),vec2(-.27,.62),vec2(-.62,-.55),
    vec2(.8,.08),vec2(.3,.85),vec2(-.87,.32),vec2(.64,-.75));
void vertex() { POSITION=vec4(VERTEX.xy,1.0,1.0); }
vec3 view_position(vec2 uv,mat4 inverse_projection) {
    float depth=texture(scene_depth,uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc=vec3(uv*2.0-1.0,depth*2.0-1.0);
#else
    vec3 ndc=vec3(uv*2.0-1.0,depth);
#endif
    vec4 p=inverse_projection*vec4(ndc,1.0);
    return p.xyz/max(abs(p.w),.000001)*sign(p.w);
}
void fragment() {
    vec2 uv=SCREEN_UV;
    vec3 p=view_position(uv,INV_PROJECTION_MATRIX);
    vec3 raw_normal=cross(dFdx(p),dFdy(p));
    vec3 normal=raw_normal/max(length(raw_normal),.000001);
    if (dot(normal,-p)<0.0) normal=-normal;
    float occlusion=0.0;
    // Stable interleaved sampling replaces visible ring/band contours.
    float angle=6.2831853*fract(52.9829189*fract(dot(floor(FRAGCOORD.xy),vec2(.06711056,.00583715))));
    mat2 rotation=mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)));
    if (-p.z>.08 && -p.z<80.0) {
        vec2 projection=vec2(PROJECTION_MATRIX[0][0],PROJECTION_MATRIX[1][1]);
        vec2 spread=min(vec2(.075),radius*projection/(2.0*max(.15,-p.z)));
        for (int i=0;i<12;i++) {
            if (i>=sample_count) break;
            vec2 sample_uv=uv+(rotation*KERNEL[i])*spread;
            if (any(lessThan(sample_uv,vec2(.002))) || any(greaterThan(sample_uv,vec2(.998)))) continue;
            vec3 delta=view_position(sample_uv,INV_PROJECTION_MATRIX)-p;
            float distance_to_sample=length(delta);
            float horizon=max(0.0,dot(normal,delta/max(.001,distance_to_sample))-.12);
            float proximity=1.0-smoothstep(radius*.12,radius,distance_to_sample);
            // A few centimetres of bias prevent a flat surface shading itself.
            float contact=smoothstep(.025,.09,distance_to_sample);
            occlusion+=horizon*proximity*contact;
        }
        occlusion=clamp(occlusion/float(sample_count)*3.4*intensity,0.0,.52);
    }
    // Reconstruct the average of each 2x2 fragment quad with derivatives.
    // A depth/normal edge guard prevents smoothing across a foreground edge.
    vec2 parity=mod(floor(FRAGCOORD.xy),vec2(2.0));
    float horizontal=occlusion+dFdx(occlusion)*(.5-parity.x);
    float filtered=horizontal+dFdy(horizontal)*(.5-parity.y);
    float depth_edge=max(abs(dFdx(p.z)),abs(dFdy(p.z)));
    float normal_edge=max(length(dFdx(normal)),length(dFdy(normal)));
    float can_filter=step(depth_edge,max(.025,-p.z*.015))*step(normal_edge,.25);
    occlusion=mix(occlusion,clamp(filtered,0.0,.52),can_filter);
    // Blend only a contact-darkening amount. Sampling/re-emitting scene
    // color here would apply Compatibility's material tonemapper twice.
    // Transparent flames render later, and Canvas HUD remains untouched.
    ALBEDO=vec3(0.0);
    ALPHA=occlusion;
}
