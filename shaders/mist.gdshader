shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;
// A single lit mist sheet for the room. The strongest cloud determines
// opacity rather than adding stacked transparent spheres. No screen copy,
// depth texture, extra render target, light or shadow map is required.
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec4 cloud_fields[4]; // room x/z, radius, simulation lifetime fade
uniform vec4 cloud_tints[4] : source_color;
uniform vec2 sheet_origin;
uniform float clock = 0.0;
global uniform sampler2D room_footprint : filter_nearest, repeat_disable;
global uniform vec2 room_grid_origin;
global uniform vec2 room_grid_cells;
const vec2 CELL = vec2(18.0, 14.0);
varying vec2 room_xz;
varying vec2 world_xz;

float occupied(ivec2 cell) {
    if (cell.x < 0 || cell.y < 0 || cell.x >= int(room_grid_cells.x) || cell.y >= int(room_grid_cells.y)) return 0.0;
    return texelFetch(room_footprint, cell, 0).r;
}

void vertex() {
    room_xz = VERTEX.xz + sheet_origin;
    world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    vec2 drift = vec2(clock * 0.025, -clock * 0.018);
    vec2 noise = texture(detail, room_xz * 0.32 + drift).rb;
    vec3 color = vec3(0.0);
    float weight = 0.0;
    float opacity = 0.0;
    vec2 gradient = vec2(0.0);
    for (int i = 0; i < 4; i++) {
        vec4 field = cloud_fields[i];
        if (field.z <= 0.0 || field.w <= 0.0) continue;
        vec2 delta = (room_xz - field.xy) / field.z;
        float distance = length(delta);
        float density = (1.0 - smoothstep(0.15, 1.06, distance + (noise.x - 0.5) * 0.18));
        density *= field.w * (0.68 + noise.y * 0.32);
        float alpha = density * cloud_tints[i].a;
        opacity = max(opacity, alpha);
        gradient += delta * density;
        color += cloud_tints[i].rgb * density;
        weight += density;
    }
    if (opacity < 0.002) discard;
    // Match the room's shared footprint, fading at exposed edges only.
    vec2 grid = (world_xz - room_grid_origin) / CELL;
    ivec2 cell = ivec2(floor(grid));
    vec2 local = (grid - vec2(cell)) * CELL;
    float edge = occupied(cell);
    if (occupied(cell + ivec2(-1, 0)) < 0.5) edge *= smoothstep(0.0, 0.15, local.x);
    if (occupied(cell + ivec2(1, 0)) < 0.5) edge *= smoothstep(0.0, 0.15, CELL.x - local.x);
    if (occupied(cell + ivec2(0, -1)) < 0.5) edge *= smoothstep(0.0, 0.15, local.y);
    if (occupied(cell + ivec2(0, 1)) < 0.5) edge *= smoothstep(0.0, 0.15, CELL.y - local.y);
    if (opacity * edge < 0.002) discard;
    ALBEDO = color / max(weight, 0.001);
    vec2 slope = gradient / max(weight, 0.001);
    NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(slope.x * 0.25, 1.0, slope.y * 0.25)), 0.0)).xyz);
    ROUGHNESS = 1.0;
    ALPHA = opacity * edge;
}
