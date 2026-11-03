shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// The open spellbook's writing, laid just above both pages: rows of glyphs
// in the weapon's colour, and on the right page a turning circle of power.
// U covers both pages (0-0.5 left, 0.5-1 right). The writing flares when a
// spell is cast.
uniform vec4 ink : source_color = vec4(1.0, 0.83, 0.58, 1.0);
uniform float flare = 0.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    bool right = UV.x > 0.5;
    vec2 p = vec2(fract(UV.x * 2.0), UV.y);
    float margin = step(0.12, p.x) * step(p.x, 0.88) * step(0.08, p.y) * step(p.y, 0.92);
    float row = floor(p.y * 15.0);
    float within = fract(p.y * 15.0);
    float column = floor(p.x * 14.0);
    float cell = fract(p.x * 14.0);
    float seed = hash(vec2(column, row + (right ? 31.0 : 0.0)));
    // Each glyph: a short stem and a hooked bar, some cells left blank.
    float stem = smoothstep(0.08, 0.0, abs(cell - 0.35 - 0.25 * seed)) * step(0.3, within) * step(within, 0.78);
    float bar = smoothstep(0.1, 0.0, abs(within - 0.36 - 0.3 * hash(vec2(row, column)))) * step(0.18, cell) * step(cell, 0.82);
    float glyph = max(stem, bar) * step(0.3, seed) * margin;
    float circle = 0.0;
    if (right) {
        vec2 c = (p - vec2(0.5, 0.4)) * vec2(1.0, 1.38);
        float r = length(c);
        float a = atan(c.y, c.x);
        circle = smoothstep(0.011, 0.0, abs(r - 0.3)) + smoothstep(0.009, 0.0, abs(r - 0.235));
        // Rune ticks between the rings, slowly turning.
        float ticks = step(0.62, fract(a / 6.2832 * 18.0 + TIME * 0.06));
        circle += ticks * step(0.245, r) * step(r, 0.29) * 0.8;
        // A star inside.
        float star = abs(sin(a * 2.5 + TIME * 0.2));
        circle += smoothstep(0.012, 0.0, abs(r - 0.17 * (0.55 + 0.45 * star))) * step(r, 0.2);
        glyph *= step(0.33, r);
    }
    float pulse = 0.6 + 0.12 * sin(TIME * 1.7) + flare * 1.6;
    ALBEDO = ink.rgb * (glyph * 0.5 + circle * 0.85) * pulse;
}
