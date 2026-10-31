shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;
// One eye-level surface, with a maximum-density union rather than stacked
// transparency. Fixed uniform indices also suit GLES mobile drivers.
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
global uniform sampler2D room_footprint : filter_nearest, repeat_disable;
global uniform vec2 room_grid_origin;
global uniform vec2 room_grid_cells;
varying vec2 world_xz;
uniform vec4 cloud_fields[4];
uniform vec4 cloud_tints[4] : source_color;
uniform vec2 sheet_size = vec2(1.0);
uniform float clock = 0.0;
void vertex() {
    world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
float density(vec2 point, vec4 field) {
    float d = length((point - field.xy) / max(field.z, 0.001));
    return (1.0 - smoothstep(0.15, 1.06, d)) * step(0.001, field.z) * clamp(field.w, 0.0, 1.0);
}
void fragment() {
    vec2 point = (UV - vec2(0.5)) * sheet_size;
    point.y *= 1.3;
    vec2 grain = texture(detail, point * 0.32 + vec2(clock * 0.025, -clock * 0.018)).rb;
    point += (grain - vec2(0.5)) * 0.18;
    float a = density(point, cloud_fields[0]);
    float b = density(point, cloud_fields[1]);
    float c = density(point, cloud_fields[2]);
    float d = density(point, cloud_fields[3]);
    float alpha = max(max(a * cloud_tints[0].a, b * cloud_tints[1].a), max(c * cloud_tints[2].a, d * cloud_tints[3].a));
    vec2 grid = (world_xz - room_grid_origin) / vec2(18.0, 14.0);
    ivec2 cell = ivec2(floor(grid));
    if (cell.x < 0 || cell.y < 0 || cell.x >= int(room_grid_cells.x) || cell.y >= int(room_grid_cells.y)) discard;
    if (texelFetch(room_footprint, cell, 0).r < 0.5 || alpha < 0.002) discard;
    ALBEDO = (cloud_tints[0].rgb * a + cloud_tints[1].rgb * b + cloud_tints[2].rgb * c + cloud_tints[3].rgb * d) / max(a + b + c + d, 0.001);
    ROUGHNESS = 1.0;
    ALPHA = alpha;
}
