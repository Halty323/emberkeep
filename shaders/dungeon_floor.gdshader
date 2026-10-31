shader_type spatial;
render_mode diffuse_lambert;
uniform sampler2D paint : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D relief_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec3 palette_a : source_color;
uniform vec3 palette_b : source_color;
uniform vec3 palette_c : source_color;
uniform vec3 palette_d : source_color;
uniform vec3 palette_e : source_color;
uniform vec3 moss_color : source_color;
uniform vec3 ember_color : source_color;
uniform float tile_scale = .25;
uniform float wetness = 0.0;
uniform float moss = 0.0;
uniform float frost = 0.0;
uniform float brass = 0.0;
uniform float embers = 0.0;
varying vec2 world_xz;
void vertex() { world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; }
void fragment() {
    vec2 p = world_xz * tile_scale;
    vec4 tile = texture(paint, p);
    vec4 patches = texture(detail, world_xz * .065);
    vec3 palette = mix(mix(palette_a, palette_b, tile.b), mix(palette_c, palette_d, patches.r), patches.b * .65);
    palette = mix(palette, palette_e, patches.g * .3);
    vec3 color = palette * (tile.r * 1.35 + .1);
    float growth = moss * smoothstep(.42, .8, patches.g + tile.g * .25);
    color = mix(color, moss_color * (.55 + tile.r * .7), growth);
    color = mix(color, vec3(.65,.74,.8), frost * patches.b * .65);
    float damp = wetness * smoothstep(.3,.8, patches.a);
    ALBEDO = color * (1.0 - damp * .22);
    NORMAL_MAP = texture(relief_map, p).rgb;
    NORMAL_MAP_DEPTH = .27;
    ROUGHNESS = mix(tile.a, .39, damp);
    SPECULAR = .35;
    METALLIC = brass * smoothstep(.92,1.0,tile.b) * .4;
    EMISSION = ember_color * tile.g * embers * (.18 + patches.r * .22);
}
