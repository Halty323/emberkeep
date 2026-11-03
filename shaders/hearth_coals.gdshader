shader_type spatial;
render_mode cull_back;
// Ash-dark fuel with narrow glowing seams, instead of a solid red disc.
varying vec3 coal_at;
void vertex() { coal_at = VERTEX; }
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
    vec2 p=coal_at.xz*31.0;
    vec2 tile=floor(p);
    vec2 f=fract(p);
    float rough=hash21(tile);
    float seam=min(min(f.x,1.0-f.x),min(f.y,1.0-f.y));
    float heat=(1.0-smoothstep(.015,.10,seam))*step(.35,rough);
    heat*=.65+.20*sin(TIME*1.8+rough*17.0);
    ALBEDO=mix(vec3(.035,.025,.023),vec3(.11,.075,.055),rough);
    ROUGHNESS=.96;
    EMISSION=vec3(1.0,.22,.025)*heat*1.25;
}
