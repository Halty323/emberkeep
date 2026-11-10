shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, world_vertex_coords;
// Every foe is gelatin: a translucent, wet-looking body you can see the room
// through, darker and richer where it is thick, pale at its thin edges, with
// sharp highlights from the lanterns, light glowing through from behind,
// small bubbles hanging inside, and a wobble that runs up from its feet and
// shudders when it is struck. No screen copy: it draws on every renderer.
// One material serves every foe; each mesh carries its own colour and state.
instance uniform vec4 jelly_tint : source_color = vec4(0.9, 0.3, 0.35, 1.0);
// Its own faint glow on the dark floors (the floor's foe_body light).
instance uniform float glow = 0.0;
// 1 for a moment when struck (white), and a slower shudder after it.
instance uniform float flash = 0.0;
instance uniform float jiggle = 0.0;
// How high this mesh's origin sits above the foe's feet.
instance uniform float lift = 0.0;
varying vec3 world_at;
varying vec3 origin_at;

float hash3(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
        mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

void vertex() {
    vec3 origin = MODEL_MATRIX[3].xyz;
    // The wobble grows with height above the feet, so the base stays planted
    // and the top sways; where the foe stands staggers it, so a crowd never
    // wobbles in step and walking sets it going.
    float h = max(0.0, lift + VERTEX.y - origin.y);
    float t = TIME * 5.2 + dot(origin.xz - vec2(0.0, lift), vec2(1.3, 1.7));
    float amp = 0.03 + jiggle * 0.13;
    VERTEX.x += sin(t) * amp * h;
    VERTEX.z += cos(t * 0.83) * amp * h;
    VERTEX.y += sin(t * 1.7) * amp * 0.45 * h;
    world_at = VERTEX;
    origin_at = origin;
}

void fragment() {
    vec3 n = normalize(NORMAL);
    vec3 v = normalize(VIEW);
    float facing = clamp(dot(n, v), 0.0, 1.0);
    float edge = pow(1.0 - facing, 2.4);
    // Thick through the middle: deeper and more saturated. Thin at the rim.
    vec3 tint = jelly_tint.rgb;
    vec3 deep = tint * tint * 0.9;
    vec3 thin = mix(tint, vec3(1.0), 0.22);
    vec3 body = mix(thin, deep, pow(facing, 0.8));
    // Bubbles and motes hanging inside, seen a little way in along the view,
    // so they slide against the surface as the foe or the eye moves.
    vec3 view_world = (INV_VIEW_MATRIX * vec4(v, 0.0)).xyz;
    vec3 inside = (world_at - origin_at) - view_world * 0.16;
    float specks = smoothstep(0.80, 0.93, noise3(inside * 11.0 + vec3(0.0, TIME * 0.12, 0.0)));
    float swirl = noise3(inside * 3.2 - vec3(0.0, TIME * 0.2, 0.0));
    body *= 0.86 + 0.28 * swirl;
    // Light comes in at the top and is soaked up on the way down: a mould
    // of gelatin is paler toward its top and deeper at its foot.
    float height = clamp((world_at.y - origin_at.y + lift) * 0.8, 0.0, 1.0);
    body *= mix(0.72, 1.12, height);
    ALBEDO = body;
    // Light held inside the gel: a soft glow of its own colour, strongest at
    // the thin edges, plus the bright points of its bubbles.
    EMISSION = tint * (glow * 0.7 + 0.10 + 0.34 * edge) + mix(tint, vec3(1.0), 0.6) * specks * 0.3 * facing + vec3(1.0, 0.97, 0.9) * flash * 0.9;
    ROUGHNESS = 0.07;
    SPECULAR = 0.75;
    METALLIC = 0.0;
    // See-through in the middle, a little more solid where the surface turns
    // away and reflects.
    ALPHA = clamp(mix(0.74, 0.95, edge) + flash * 0.2, 0.0, 1.0);
}

void light() {
    // Gelatin scatters: light wraps well round the body, and a light behind
    // it shines through toward the eye.
    float wrap = clamp((dot(NORMAL, LIGHT) + 0.55) / 1.55, 0.0, 1.0);
    float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 2.5);
    DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (wrap * 0.9 + through * 1.3) / PI;
    // A wet surface: a small, hard highlight and a broader soft one.
    vec3 half_way = normalize(VIEW + LIGHT);
    float nh = clamp(dot(NORMAL, half_way), 0.0, 1.0);
    float lit = step(0.0, dot(NORMAL, LIGHT));
    SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * lit * (pow(nh, 220.0) * 2.4 + pow(nh, 28.0) * 0.22);
}
