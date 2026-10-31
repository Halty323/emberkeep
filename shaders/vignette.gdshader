shader_type canvas_item;
render_mode unshaded;
uniform float hurt = 0.0;
// Edge darkness; deeper on the dark lower floors of the tower.
uniform float strength = 0.48;
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float edge = smoothstep(0.35, 1.6, length(p));
    COLOR = vec4(mix(vec3(0.015, 0.023, 0.033), vec3(0.55, 0.06, 0.04), hurt), edge * (strength + hurt * 0.45));
}
