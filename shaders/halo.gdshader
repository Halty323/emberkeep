shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.15, 0.25);
uniform float softness = 2.6;
// One texel per room cell, shared by every halo, glow and floor mark. Rooms
// are built at the origin, so world XZ is room space.
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
    float d = length(UV - vec2(0.5)) * 2.0;
    float glow = pow(max(0.0, 1.0 - d), softness);
    vec2 grid = (world_xz - room_grid_origin) / CELL;
    ivec2 cell = ivec2(floor(grid));
    vec2 local = (grid - vec2(cell)) * CELL;
    // Clip to the actual footprint: an L's missing quadrant gets nothing, and
    // light fades only toward exposed edges, never across open seams.
    float floor_edge = occupied(cell);
    if (occupied(cell + ivec2(-1, 0)) < 0.5) floor_edge *= smoothstep(0.0, EDGE_FADE, local.x);
    if (occupied(cell + ivec2(1, 0)) < 0.5) floor_edge *= smoothstep(0.0, EDGE_FADE, CELL.x - local.x);
    if (occupied(cell + ivec2(0, -1)) < 0.5) floor_edge *= smoothstep(0.0, EDGE_FADE, local.y);
    if (occupied(cell + ivec2(0, 1)) < 0.5) floor_edge *= smoothstep(0.0, EDGE_FADE, CELL.y - local.y);
    float intensity = glow * tint.a * floor_edge;
    if (intensity < 0.001) {
        discard;
    }
    // GLES3 shadow passes can leave additive blending at GL_ONE. Encode the
    // falloff in RGB too, so the quad edges always contribute zero light.
    ALBEDO = tint.rgb * intensity;
    ALPHA = 1.0;
}
