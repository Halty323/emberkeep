shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Soft turbulent fire card, viewed behind real logs
// and an iron grate. No screen/depth reads or particle/light allocations.
uniform bool billboard = false;
void vertex() {
    if (billboard) {
        mat4 facing = mat4(vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz),0.0),
                           vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz),0.0),
                           vec4(INV_VIEW_MATRIX[2].xyz * length(MODEL_MATRIX[2].xyz),0.0),MODEL_MATRIX[3]);
        MODELVIEW_MATRIX = VIEW_MATRIX * facing;
    }
}
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise2(vec2 p) {
    vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
    vec2 p=vec2(UV.x*2.0-1.0,1.0-UV.y);
    vec2 flow=vec2(p.x*3.4,p.y*4.3-TIME*1.8);
    float turbulence=noise2(flow)*.65+noise2(flow*2.1+TIME*.3)*.35;
    float bend=sin(p.y*5.0-TIME*2.1)*p.y*.1;
    float width=mix(.8,.06,pow(p.y,.72));
    float body=1.0-abs(p.x+bend)/max(.05,width);
    float density=body-p.y*.25+(turbulence-.5)*p.y*.85;
    float alpha=smoothstep(.0,.24,density)*smoothstep(.0,.06,p.y)*(1.0-smoothstep(.72,1.0,p.y));
    float core=smoothstep(.12,.95,density)*(1.0-p.y*.6);
    vec3 fire=mix(vec3(.82,.12,.012),vec3(1.0,.69,.19),core);
    fire=mix(fire,vec3(1.0,.92,.64),core*core*.45);
    ALBEDO=fire;
    EMISSION=fire*1.7;
    ALPHA=alpha;
}
