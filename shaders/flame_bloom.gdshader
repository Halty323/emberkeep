shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// A soft bloom of light round a flame, drawn in the world as one small
// camera-facing card: the glow a bright flame leaves on the eye, for devices
// that cannot run the full-screen bloom pass. It is pulled a little toward
// the eye so a wall close behind the flame does not cut it.
uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.26, 1.0);
uniform float strength = 0.5;

void vertex() {
    float s = length(MODEL_MATRIX[0].xyz);
    vec3 center = MODEL_MATRIX[3].xyz;
    vec3 toward = normalize(CAMERA_POSITION_WORLD - center);
    mat4 facing = mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, vec4(center + toward * 0.22, 1.0));
    MODELVIEW_MATRIX = VIEW_MATRIX * facing;
    MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
    float d = length(UV - 0.5) * 2.0;
    float core = pow(max(0.0, 1.0 - d), 2.6);
    float halo = pow(max(0.0, 1.0 - d), 1.2) * 0.25;
    float flicker = 0.92 + 0.08 * sin(TIME * 9.0 + NODE_POSITION_WORLD.x * 7.0 + NODE_POSITION_WORLD.z * 5.0);
    ALBEDO = tint.rgb * (core + halo) * strength * flicker;
}
