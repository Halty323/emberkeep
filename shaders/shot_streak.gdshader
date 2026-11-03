shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;
// What a spell leaves behind: two wisps twisting round each other back along
// its flight, flecked with sparkles, thinning to nothing at the tail. The
// node's basis carries it: X is the flight times the trail's length, Y's
// length its brightness, Z's length its width.
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);
varying float along;
varying float fade;
varying float phase;

void vertex() {
    vec3 centre = MODEL_MATRIX[3].xyz;
    vec3 reach = MODEL_MATRIX[0].xyz;
    float tail = length(reach);
    vec3 dir = reach / max(tail, 0.0001);
    fade = length(MODEL_MATRIX[1].xyz);
    float width = length(MODEL_MATRIX[2].xyz) * 1.8;
    vec3 side = normalize(cross(dir, normalize(CAMERA_POSITION_WORLD - centre)) + vec3(0.0, 0.00001, 0.0));
    along = UV.x;
    phase = dot(centre, vec3(0.9, 1.3, 0.7));
    VERTEX = centre - dir * along * tail + side * (UV.y - 0.5) * width * (1.0 - along * 0.55);
}

void fragment() {
    float y = (UV.y - 0.5) * 2.0;
    float twist = along * 14.0 - TIME * 16.0 + phase;
    float a = smoothstep(0.22, 0.0, abs(y - 0.45 * sin(twist) * (1.0 - along)));
    float b = smoothstep(0.22, 0.0, abs(y + 0.45 * sin(twist) * (1.0 - along)));
    float sparkle = step(0.93, fract(sin(floor(along * 40.0) * 12.9898 + floor(TIME * 12.0) + phase) * 43758.5453)) * smoothstep(0.5, 0.0, abs(y));
    float strength = pow(1.0 - along, 1.4);
    ALBEDO = tint.rgb * ((a + b) * 0.6 + sparkle * 0.9) * strength * fade;
}
