shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Temporary floor marks such as paint splashes. Clipped to the room's real
// footprint with the same cached per-cell mask as the halos.
uniform vec4 tint : source_color = vec4(0.8, 0.2, 0.2, 0.5);
uniform float seed = 0.0;
global uniform sampler2D room_footprint : filter_nearest, repeat_disable;
global uniform vec2 room_grid_origin;
global uniform vec2 room_grid_cells;
const vec2 CELL = vec2(18.0, 14.0);
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
    vec2 p = UV * 2.0 - 1.0;
    float angle = atan(p.y, p.x);
    // A few lobes give each splash an irregular, painted edge.
    float edge = 0.62 + 0.18 * sin(angle * 5.0 + seed * 6.28) + 0.1 * sin(angle * 9.0 + seed * 3.1);
    float coverage = 1.0 - smoothstep(edge - 0.08, edge, length(p));
    vec2 grid = (world_xz - room_grid_origin) / CELL;
    float inside = occupied(ivec2(floor(grid)));
    float alpha = coverage * tint.a * inside;
    if (alpha < 0.01) {
        discard;
    }
    ALBEDO = tint.rgb;
    ALPHA = alpha;
}
