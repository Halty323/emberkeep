shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Period-style fire card with flowing silhouettes, viewed behind real logs
// and an iron grate. No screen/depth reads or particle/light allocations.
uniform bool billboard = false;
void vertex() {
    if (billboard) {
        mat4 facing = mat4(vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz),0.0),
                           vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz),0.0),
                           vec4(INV_VIEW_MATRIX[2].xyz * length(MODEL_MATRIX[2].xyz),0.0),MODEL_MATRIX[3]);
        MODELVIEW_MATRIX = VIEW_MATRIX * facing;
    }
}
float tongue(vec2 p, float centre, float height, float width, float phase) {
    float y = p.y / height;
    float curl = sin(y * 8.0 - TIME * 3.5 + phase) * .055 * y;
    curl += sin(y * 15.0 - TIME * 5.1 + phase) * .018 * y;
    return 1.0 - abs(p.x - centre + curl) / max(.02, width * (1.0 - y * .85)) - y;
}
void fragment() {
    vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);
    float a = tongue(p,-.43,.82+sin(TIME*2.0)*.06,.35,.7);
    float b = tongue(p,.0,.98+sin(TIME*2.3+.8)*.045,.39,2.1);
    float c = tongue(p,.43,.76+sin(TIME*2.6+1.9)*.055,.34,4.0);
    float density = max(a,max(b,c));
    float alpha = smoothstep(.0,.14,density) * smoothstep(.0,.06,p.y);
    vec3 rim = vec3(.95,.19,.018);
    vec3 heart = vec3(1.0,.73,.24);
    ALBEDO = mix(rim,heart,smoothstep(.03,.75,density));
    EMISSION = ALBEDO * 1.6;
    ALPHA = alpha;
}
