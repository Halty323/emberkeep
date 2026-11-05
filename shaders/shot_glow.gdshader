shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// The rune circle round a spell: a camera-facing sigil of two rings, runes
// between them and spokes inside, turning as it flies, in a soft halo. The
// node's X scale sizes it and its Y scale (relative to X) is its
// brightness, so spells of one colour share one material.
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);
// The spell's look (Forge.FORMS): 0 orb (the rune sigil), 1 shard (a
// turning diamond), 2 needle (a four-point star), 3 comet (a wide flaring
// corona), 4 mote (a soft spark), 5 disc (a bright ring).
uniform int style = 0;
varying float fade;
varying float turn;

void vertex() {
    float size = length(MODEL_MATRIX[0].xyz);
    fade = length(MODEL_MATRIX[1].xyz) / max(size, 0.0001);
    vec3 at = MODEL_MATRIX[3].xyz;
    turn = TIME * 2.6 + dot(at, vec3(1.3, 0.7, 2.1));
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
    VERTEX *= size;
}

void fragment() {
    vec2 c = (UV - 0.5) * 2.0;
    float d = length(c);
    float a = atan(c.y, c.x) + turn;
    if (style > 0) {
        float centre = exp(-d * d * 22.0);
        float halo = exp(-d * 3.4) * (1.0 - smoothstep(0.75, 1.0, d));
        float shape = 0.0;
        if (style == 1) {
            vec2 r = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * c;
            float diamond = abs(r.x) * 0.75 + abs(r.y) * 1.25;
            shape = smoothstep(0.05, 0.0, abs(diamond - 0.55)) + smoothstep(0.035, 0.0, abs(diamond - 0.36)) * 0.6;
        } else if (style == 2) {
            float spikes = pow(max(0.0, 1.0 - abs(c.x) * 14.0), 2.0) * (1.0 - smoothstep(0.0, 0.9, abs(c.y)))
                + pow(max(0.0, 1.0 - abs(c.y) * 14.0), 2.0) * (1.0 - smoothstep(0.0, 0.9, abs(c.x)));
            shape = spikes * 1.2;
            halo *= 0.45;
        } else if (style == 3) {
            float flare = 0.75 + 0.25 * sin(a * 7.0 + TIME * 11.0);
            halo = exp(-d * 2.2) * flare * (1.0 - smoothstep(0.85, 1.0, d)) * 1.25;
        } else if (style == 4) {
            halo *= 0.7;
        } else {
            shape = smoothstep(0.04, 0.0, abs(d - 0.5)) * 1.1 + smoothstep(0.05, 0.0, abs(sin(a * 4.0))) * step(d, 0.48) * step(0.3, d) * 0.3;
        }
        ALBEDO = tint.rgb * (shape * 0.75 + halo * 0.4 + centre * 0.5) * fade;
    } else {
        float outer = smoothstep(0.022, 0.0, abs(d - 0.62));
        float inner = smoothstep(0.018, 0.0, abs(d - 0.5));
        float rune_cell = fract(a / 6.2832 * 20.0);
        float runes = smoothstep(0.08, 0.0, abs(rune_cell - 0.5)) * step(0.52, d) * step(d, 0.6) * 0.6;
        runes += step(0.5, fract(a / 6.2832 * 5.0)) * smoothstep(0.012, 0.0, abs(d - 0.56)) * 0.5;
        float spokes = smoothstep(0.04, 0.0, abs(sin(a * 3.0))) * step(d, 0.48) * step(0.16, d) * 0.35;
        float halo = exp(-d * 3.2) * (1.0 - smoothstep(0.75, 1.0, d));
        float centre = exp(-d * d * 18.0);
        float sigil = (outer + inner * 0.8 + runes + spokes);
        ALBEDO = tint.rgb * (sigil * 0.7 + halo * 0.32 + centre * 0.45) * fade;
    }
}
