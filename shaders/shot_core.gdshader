shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
// A spell's heart: a small orb of its own colour with light swirling round
// it and a bright spark inside, rather than a white-hot slug. Spells of one
// colour share this material; a spell fades by shrinking. Its position
// staggers the swirl so neighbouring spells never pulse together.
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);
varying vec3 seed;

void vertex() {
    seed = MODEL_MATRIX[3].xyz;
}

void fragment() {
    float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
    float rim = pow(1.0 - facing, 1.6);
    // Bands of light running round the orb, turning over time.
    vec3 n = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
    float swirl = sin(atan(n.z, n.x) * 3.0 + n.y * 6.0 - TIME * 9.0 + dot(seed, vec3(3.1, 1.7, 2.3)));
    float bands = smoothstep(0.35, 1.0, swirl) * (0.4 + 0.6 * rim);
    float spark = pow(facing, 6.0);
    vec3 colour = tint.rgb * (0.32 + rim * 0.75 + bands * 0.55) + vec3(1.0, 0.97, 0.92) * spark * 0.35;
    ALBEDO = colour;
}
