shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Standing water (and ice) over a whole room, shaped by the residue mask.
// The sheet is finely divided and its vertices roll with slow swells; rings
// spread from where shots land and feet wade, and a light rain pocks the
// cistern. The floor shows through, bent by the waves; the room is mirrored
// in it (WaterMirror) and lanterns glint on it. Ice is the same water,
// frozen still: cracked, frosted at its rim, a fainter mirror.
uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec2 grid_origin;
uniform vec2 grid_size;
uniform float tile = 0.8;
uniform sampler2D reflection : filter_linear, repeat_disable;
uniform float reflect_strength = 0.0;
uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec4 deep : source_color = vec4(0.06, 0.16, 0.2, 1.0);
uniform vec4 shallow : source_color = vec4(0.55, 0.78, 0.82, 1.0);
uniform float frozen = 0.0;
uniform float wave_height = 0.012;
// x, z, start (clock), strength.
uniform vec4 ripples[8];
uniform float clock = 0.0;
varying vec2 world_xz;

float coverage(vec2 xz) {
    return texture(mask, (xz - grid_origin) / (tile * grid_size)).r;
}

// Slope of the water: swells, a slow drifting texture and spreading rings.
vec2 slope(vec2 xz) {
    vec2 g = vec2(cos(xz.x * 3.1 + TIME * 1.7), cos(xz.y * 2.7 - TIME * 1.3)) * 0.05;
    g += (texture(detail, xz * 0.55 + vec2(TIME * 0.04, TIME * 0.03)).rg - 0.5) * 0.12;
    for (int i = 0; i < 8; i++) {
        vec4 r = ripples[i];
        if (r.w <= 0.0) continue;
        float age = clock - r.z;
        if (age < 0.0 || age > 1.8) continue;
        vec2 d = xz - r.xy;
        float dist = length(d);
        float k = dist - age * 1.7;
        float env = exp(-k * k * 12.0) * (1.0 - age / 1.8) * r.w;
        if (dist > 0.001) g += d / dist * sin(k * 20.0) * env * 0.8;
    }
    return g * (1.0 - frozen);
}

void vertex() {
    world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
    float wet = smoothstep(0.45, 0.7, textureLod(mask, (world_xz - grid_origin) / (tile * grid_size), 0.0).r);
    VERTEX.y += wave_height * wet * (1.0 - frozen) * (sin(world_xz.x * 3.1 + TIME * 1.7) + sin(world_xz.y * 2.7 - TIME * 1.3)) * 0.5;
}

void fragment() {
    float c = coverage(world_xz);
    float shape = smoothstep(0.4, 0.5, c);
    if (shape < 0.01) {
        discard;
    }
    vec2 g = slope(world_xz);
    vec3 n = normalize(vec3(-g.x, 1.0, -g.y));
    NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
    vec2 bend = g * 0.012;
    float depth = smoothstep(0.5, 0.95, c);
    vec3 under = texture(screen, SCREEN_UV + bend).rgb;
    vec3 body = mix(under * shallow.rgb, deep.rgb, depth * 0.5);
    vec3 mirrored = texture(reflection, vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y) + bend * 1.6).rgb;
    float sheen = reflect_strength * (0.5 + 0.3 * depth) * (1.0 - frozen * 0.5);
    vec3 color = mix(body, mirrored, sheen);
    // A bright lip where the water meets the stone.
    float lip = smoothstep(0.42, 0.5, c) * (1.0 - smoothstep(0.5, 0.62, c));
    color += vec3(0.45, 0.55, 0.58) * lip * 0.22 * (1.0 - frozen);
    if (frozen > 0.0) {
        float vein = 1.0 - abs(texture(detail, world_xz * 0.6).a * 2.0 - 1.0);
        float crack = smoothstep(0.9, 0.97, vein);
        float rime = (1.0 - smoothstep(0.5, 0.75, c)) + texture(detail, world_xz * 1.7).b * 0.25;
        color = mix(color, vec3(0.86, 0.93, 1.0), clamp(crack * 0.7 + rime * 0.55, 0.0, 1.0));
    }
    // The light comes from the water itself; real lights add their glints.
    ALBEDO = vec3(0.02);
    EMISSION = color;
    ROUGHNESS = mix(0.05, 0.2, frozen);
    SPECULAR = 0.65;
    ALPHA = shape * mix(0.93, 0.88, frozen);
}
