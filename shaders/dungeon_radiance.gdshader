shader_type sky;
// Deliberately broad painted radiance. A narrow pale high window, a cool
// vault and a low amber bounce make roughness/relief legible without turning
// every wall into a mirror or inventing extra dynamic lights.
uniform vec3 vault : source_color = vec3(.55,.68,.82);
uniform vec3 hearth : source_color = vec3(1.0,.86,.67);
void sky() {
    vec3 d = normalize(EYEDIR);
    float upper = smoothstep(-.3,.65,d.y);
    vec3 body = mix(hearth*.10,vault*.20,upper);
    float window = pow(max(0.0,dot(d,normalize(vec3(-.45,.55,-.7)))),34.0);
    float warm = pow(max(0.0,dot(d,normalize(vec3(.65,-.12,.6)))),8.0);
    COLOR = body + vault*window*.65 + hearth*warm*.20;
}
