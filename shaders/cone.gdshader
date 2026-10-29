shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// A cone of lantern light on the floor, along the plane's local +Z, fading
// with distance and toward its edges, clipped to the room like every halo.
uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.38, 0.34);
uniform float half_angle = 0.49;
global uniform sampler2D room_footprint : filter_nearest, repeat_disable;
global uniform vec2 room_grid_origin;
global uniform vec2 room_grid_cells;
const vec2 CELL = vec2(18.0, 14.0);
const float EDGE_FADE = 0.15;
varying vec2 world_xz;

float occupied(ivec2 cell) {
    if (cell.x < 0 || cell.y < 0 || cell.x >= int(room_grid_cells.x) || cell.y >= int(room_grid_cells.y)) {
        return 0.0;
    }
    return texelFetch(room_footprint, cell, 0).r;
}

void vertex() {
    world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    vec2 p = (UV - vec2(0.5)) * 2.0;
    float dist = length(p);
    float angle = atan(abs(p.x), p.y);
    if (dist > 1.0 || p.y <= 0.0 || angle > half_angle) {
        discard;
    }
    float fade = (1.0 - dist) * (1.0 - smoothstep(half_angle * 0.65, half_angle, angle));
    vec2 grid = (world_xz - room_grid_origin) / CELL;
    ivec2 cell = ivec2(floor(grid));
    vec2 local = (grid - vec2(cell)) * CELL;
    float floor_edge = occupied(cell);
    if (occupied(cell + ivec2(-1, 0)) < 0.5) floor_edge *= smoothstep(0.0, EDGE_FADE, local.x);
    if (occupied(cell + ivec2(1, 0)) < 0.5) floor_edge *= smoothstep(0.0, EDGE_FADE, CELL.x - local.x);
    if (occupied(cell + ivec2(0, -1)) < 0.5) floor_edge *= smoothstep(0.0, EDGE_FADE, local.y);
    if (occupied(cell + ivec2(0, 1)) < 0.5) floor_edge *= smoothstep(0.0, EDGE_FADE, CELL.y - local.y);
    float intensity = fade * tint.a * floor_edge;
    if (intensity < 0.001) {
        discard;
    }
    ALBEDO = tint.rgb * intensity;
    ALPHA = 1.0;
}
