shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// A shockwave on the floor: a soft bright band racing outward with a faint
// wake inside it. A flat plane; its X and Z scale are its reach, and its Y
// scale (which a plane does not show) its brightness, so waves of one colour
// share one material. Drawn by every renderer: it needs no screen copy.
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);
varying float bright;

void vertex() {
    bright = length(MODEL_MATRIX[1].xyz);
}

void fragment() {
    float d = length(UV - 0.5) * 2.0;
    float band = exp(-pow((d - 0.86) / 0.07, 2.0));
    float wake = smoothstep(0.86, 0.2, d) * 0.12 * step(d, 0.86);
    ALBEDO = tint.rgb * (band + wake) * bright * step(d, 1.0);
}
