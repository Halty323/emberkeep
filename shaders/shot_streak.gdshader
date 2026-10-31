shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;
// The light a shot leaves behind it: a ribbon from the shot back along its
// flight, turned to face the camera, bright at the head and gone at the tail.
// The node's basis carries it: X is the flight times the ribbon's length,
// Y's length its brightness, Z's length its width.
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);
varying float along;
varying float fade;

void vertex() {
    vec3 centre = MODEL_MATRIX[3].xyz;
    vec3 reach = MODEL_MATRIX[0].xyz;
    float tail = length(reach);
    vec3 dir = reach / max(tail, 0.0001);
    fade = length(MODEL_MATRIX[1].xyz);
    float width = length(MODEL_MATRIX[2].xyz);
    vec3 side = normalize(cross(dir, normalize(CAMERA_POSITION_WORLD - centre)) + vec3(0.0, 0.00001, 0.0));
    along = UV.x;
    VERTEX = centre - dir * along * tail + side * (UV.y - 0.5) * width * (1.0 - along * 0.7);
}

void fragment() {
    float across = 1.0 - abs(UV.y - 0.5) * 2.0;
    ALBEDO = tint.rgb * pow(1.0 - along, 1.7) * smoothstep(0.0, 0.7, across) * fade * 0.85;
}
