shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Rising ribbons, feathered edges and a pale hot heart. World-space phase
// keeps neighbouring fires from moving in lockstep. No screen/depth reads.
uniform bool billboard = false;
uniform vec4 flame_tint : source_color = vec4(1.0);
uniform float colorize = 0.0;
varying float phase;
void vertex() {
    phase = dot(MODEL_MATRIX[3].xyz, vec3(5.37, 8.13, 3.71));
    if (billboard) {
        // Fire stays upright when looking down into a brazier. A full
        // camera-facing card used to lay the flame across its bowl.
        vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
        vec3 up = vec3(0.0, 1.0, 0.0);
        mat4 facing = mat4(vec4(right * length(MODEL_MATRIX[0].xyz),0.0),
                           vec4(up * length(MODEL_MATRIX[1].xyz),0.0),
                           vec4(cross(right, up) * length(MODEL_MATRIX[2].xyz),0.0),MODEL_MATRIX[3]);
        MODELVIEW_MATRIX = VIEW_MATRIX * facing;
    }
}
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise2(vec2 p) {
    vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
float flow_noise(vec2 p) {
    return noise2(p)*.60 + noise2(p*2.03+vec2(13.1,7.9))*.28
           + noise2(p*4.07+vec2(3.7,19.2))*.12;
}
void fragment() {
    vec2 p=vec2(UV.x*2.0-1.0,1.0-UV.y);
    float t=TIME*1.65+phase;
    float rise=flow_noise(vec2(p.x*2.8+phase,p.y*5.5-t*2.2));
    float curl=sin(p.y*7.5-t*2.0)*.13*p.y+(rise-.5)*.40*p.y;
    float width=pow(max(0.0,1.0-p.y),.72)*(.51+.24*rise);
    float edge=width-abs(p.x+curl);
    float filaments=noise2(vec2(p.x*9.0+rise*2.0,p.y*3.0-t*3.0));
    float density=edge+(filaments-.5)*(.05+p.y*.22);
    float alpha=smoothstep(-.035,.12,density);
    alpha*=smoothstep(0.0,.065,p.y)*(1.0-smoothstep(.78,1.0,p.y));
    float core=smoothstep(.03,.38,edge)*(1.0-smoothstep(.2,.85,p.y));
    float ribbon=smoothstep(.4,.85,filaments)*(1.0-core)*.18;
    vec3 fire=mix(vec3(1.0,.24,.035),vec3(1.0,.69,.16),smoothstep(-.01,.24,density)+ribbon);
    fire=mix(fire,vec3(1.0,.94,.70),core);
    fire=mix(fire,flame_tint.rgb*mix(.42,1.12,core),colorize);
    ALBEDO=fire;
    EMISSION=fire*.85;
    ALPHA=alpha*.94;
}
