shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled, fog_disabled;
// A real local 3D density integral, bounded by the fixture's box and opaque
// scene depth. Compatibility/GLES path: no color copy, froxel buffer or MSAA.
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 tint : source_color = vec4(.8,.75,1.0,1.0);
uniform float density = .065;
uniform int steps = 8;
varying vec3 world;
varying flat vec3 center;
varying flat vec3 half_size;
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    center = MODEL_MATRIX[3].xyz;
    half_size = vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz))*.5;
}
float grain(vec3 p) {
    return .78 + .14*sin(p.x*2.1+p.y*.8+TIME*.13)*sin(p.z*1.7-p.y*.6-TIME*.09);
}
void fragment() {
    vec3 eye = INV_VIEW_MATRIX[3].xyz;
    vec3 ray = normalize(world-eye);
    vec3 inv = 1.0/(ray+vec3(.00001));
    vec3 a = (center-half_size-eye)*inv;
    vec3 b = (center+half_size-eye)*inv;
    vec3 near_box = min(a,b);
    vec3 far_box = max(a,b);
    float entry = max(0.0,max(near_box.x,max(near_box.y,near_box.z)));
    float leave = min(far_box.x,min(far_box.y,far_box.z));
    float depth = texture(scene_depth, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(SCREEN_UV,depth)*2.0-1.0;
#else
    vec3 ndc = vec3(SCREEN_UV*2.0-1.0,depth);
#endif
    vec4 opaque = INV_PROJECTION_MATRIX * vec4(ndc,1.0);
    float stop = length(opaque.xyz/max(abs(opaque.w),.000001));
    leave = min(leave,stop);
    if (leave <= entry) discard;
    float stride = (leave-entry)/float(steps);
    float optical = 0.0;
    for (int i=0;i<12;i++) {
        if (i>=steps) break;
        vec3 p = eye+ray*(entry+(float(i)+.5)*stride);
        float down = (center.y+half_size.y-p.y)/(half_size.y*2.0);
        float radius = half_size.x*mix(.12,1.0,clamp(down,0.0,1.0));
        float r = length(p.xz-center.xz)/max(radius,.02);
        float cone = 1.0-smoothstep(.2,1.0,r);
        float ends = smoothstep(.0,.08,down)*(1.0-smoothstep(.8,1.0,down));
        optical += cone*ends*grain(p)*stride*density;
    }
    // Thin pale scattering, never an opaque illuminated white column.
    float scatter = min(.22,1.0-exp(-optical));
    ALBEDO = tint.rgb;
    ALPHA = scatter;
}
