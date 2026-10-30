shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// The soft light around a shot: a camera-facing disc, a tight hot centre in
// a wide falloff. The node's X scale sizes it and its Y scale (relative to
// X) is its brightness, so shots of one colour share one material.
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);
varying float fade;

void vertex() {
    float size = length(MODEL_MATRIX[0].xyz);
    fade = length(MODEL_MATRIX[1].xyz) / max(size, 0.0001);
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
    VERTEX *= size;
}

void fragment() {
    float d = length(UV - 0.5) * 2.0;
    float centre = exp(-d * d * 10.0);
    float halo = exp(-d * 3.4) * (1.0 - smoothstep(0.8, 1.0, d));
    ALBEDO = tint.rgb * (centre * 0.95 + halo * 0.42) * fade;
}
