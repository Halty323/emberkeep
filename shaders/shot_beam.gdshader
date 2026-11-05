shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;
// A ray's or a lightning bolt's stretch of light: a camera-facing ribbon from
// one point to the next, a white-hot line in a halo of its colour with light
// running along it. The node's basis carries it: X is the stretch itself
// (centred on the node), Y's length its brightness, Z's length its width,
// so beams of one colour share one material.
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);
varying float fade;
varying float reach;
varying float seed;

void vertex() {
    vec3 centre = MODEL_MATRIX[3].xyz;
    vec3 span = MODEL_MATRIX[0].xyz;
    reach = length(span);
    vec3 dir = span / max(reach, 0.0001);
    fade = length(MODEL_MATRIX[1].xyz);
    float width = length(MODEL_MATRIX[2].xyz);
    vec3 side = normalize(cross(dir, normalize(CAMERA_POSITION_WORLD - centre)) + vec3(0.0, 0.00001, 0.0));
    seed = dot(centre, vec3(1.7, 2.3, 0.9));
    VERTEX = centre + span * (UV.x - 0.5) + side * (UV.y - 0.5) * width;
}

void fragment() {
    float y = abs(UV.y - 0.5) * 2.0;
    float line = smoothstep(0.32, 0.0, y);
    float halo = exp(-y * 3.4) * 0.55;
    float run = 0.72 + 0.28 * sin(UV.x * reach * 5.0 - TIME * 34.0 + seed);
    vec3 hot = mix(tint.rgb, vec3(1.0, 0.98, 0.94), 0.65);
    ALBEDO = (tint.rgb * halo + hot * line) * run * fade;
}
