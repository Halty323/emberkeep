shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
void fragment() {
    float heart = 1.0 - smoothstep(.06,.67,length(UV - vec2(.5)));
    float breath = .96 + sin(TIME * 3.2) * .025 + sin(TIME * 7.1) * .015;
    ALBEDO = vec3(.32,.15,.035);
    EMISSION = mix(vec3(.85,.21,.025),vec3(1.0,.68,.23),heart) * breath * 1.3;
    ROUGHNESS = .65;
}
