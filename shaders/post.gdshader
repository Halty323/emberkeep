shader_type canvas_item;
render_mode unshaded;
// The finished frame, re-drawn once: shockwaves bend it outward from blasts
// and slams, hot air shimmers above fire, colour fringes at the edges when
// you are hurt, each floor's grade, the vignette, and a breath of grain.
// Effects detail Low draws only the vignette (vignette.gdshader) instead.
uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength = 0.48;
uniform float hurt = 0.0;
// xy: centre in screen UV; z: radius in screen heights; w: amplitude.
uniform vec4 waves[4];
// xy: centre in screen UV; z: radius in screen heights; w: strength.
uniform vec4 heat[6];
uniform float aberration = 0.0;
uniform float grain = 0.025;
uniform vec3 lift = vec3(0.0);
uniform vec3 gain = vec3(1.0);
uniform float saturation = 1.0;
uniform float aspect = 1.7777778;

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 scale = vec2(aspect, 1.0);
    vec2 bend = vec2(0.0);
    for (int i = 0; i < 4; i++) {
        vec4 w = waves[i];
        if (w.w <= 0.0) continue;
        vec2 d = (uv - w.xy) * scale;
        float dist = length(d);
        float band = (dist - w.z) / 0.04;
        float ring = exp(-band * band);
        if (dist > 0.0001) bend += d / dist * ring * w.w * 0.022 / scale;
    }
    for (int i = 0; i < 6; i++) {
        vec4 h = heat[i];
        if (h.w <= 0.0) continue;
        vec2 d = (uv - h.xy) * scale;
        // Hot air rises: the shimmer reaches higher above a source than below.
        d.y *= d.y < 0.0 ? 0.55 : 1.4;
        float near = 1.0 - smoothstep(0.0, h.z, length(d));
        bend += vec2(sin(uv.y * 140.0 + TIME * 7.0 + float(i) * 2.1), cos(uv.x * 110.0 + TIME * 5.3 + float(i))) * 0.0022 * h.w * near;
    }
    uv += bend;
    vec2 c = uv - 0.5;
    float fringe = (aberration + hurt * 1.4) * dot(c, c) * 0.018;
    vec3 col;
    col.r = texture(screen, uv + c * fringe).r;
    col.g = texture(screen, uv).g;
    col.b = texture(screen, uv - c * fringe).b;
    col = col * gain + lift;
    float l = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(l), col, saturation);
    vec2 p = UV * 2.0 - 1.0;
    float edge = smoothstep(0.35, 1.6, length(p));
    vec3 shade = mix(vec3(0.015, 0.023, 0.033), vec3(0.55, 0.06, 0.04), hurt);
    col = mix(col, shade, clamp(edge * (strength + hurt * 0.45), 0.0, 1.0));
    col += (hash(SCREEN_UV * 1931.7 + fract(TIME) * 61.3) - 0.5) * grain;
    COLOR = vec4(col, 1.0);
}
