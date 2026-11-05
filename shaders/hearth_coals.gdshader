shader_type spatial;
render_mode cull_back;
// Ash-dark fuel with narrow glowing seams, instead of a solid red disc.
varying vec3 coal_at;
void vertex() { coal_at = VERTEX; }
vec2 hash22(vec2 p) {
    return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);
}
void fragment() {
    vec2 p=coal_at.xz*15.0;
    vec2 tile=floor(p);
    vec2 f=fract(p);
    float nearest=8.0;
    float next_nearest=8.0;
    float coal=0.0;
    // A fixed nine neighbours make irregular lumps and narrow seams.
    // This little opaque surface has no transparent overlap or extra draws.
    for (int y=-1; y<=1; y++) {
        for (int x=-1; x<=1; x++) {
            vec2 cell=vec2(float(x),float(y));
            vec2 seed=hash22(tile+cell);
            vec2 at=cell+.18+seed*.64-f;
            float d=dot(at,at);
            if (d<nearest) {
                next_nearest=nearest;
                nearest=d;
                coal=seed.x;
            } else { next_nearest=min(next_nearest,d); }
        }
    }
    float seam=next_nearest-nearest;
    float heat=(1.0-smoothstep(.025,.13,seam))*(.3+.7*coal);
    heat*=.68+.14*sin(TIME*1.8+coal*17.0);
    ALBEDO=mix(vec3(.035,.025,.023),vec3(.11,.075,.055),coal);
    ROUGHNESS=.96;
    EMISSION=vec3(1.0,.24,.035)*heat*.95;
}
