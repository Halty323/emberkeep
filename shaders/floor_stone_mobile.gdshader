shader_type spatial;
render_mode cull_back, shadows_disabled, diffuse_lambert;
// PowerVR/GLES fallback. Two baked-noise samples retain the floor palette,
// worn patches, moss, frost and embers. No vertex texture fetches, Voronoi
// searches, derivatives, screen textures or per-pixel animation. Ordinary
// dungeon lights still illuminate the surface, as with the regular floor.
uniform vec3 palette_a : source_color = vec3(0.29, 0.26, 0.24);
uniform vec3 palette_b : source_color = vec3(0.27, 0.25, 0.23);
uniform vec3 palette_c : source_color = vec3(0.30, 0.27, 0.24);
uniform vec3 palette_d : source_color = vec3(0.25, 0.24, 0.22);
uniform vec3 palette_e : source_color = vec3(0.31, 0.28, 0.24);
uniform vec3 grout_color : source_color = vec3(0.09, 0.09, 0.09);
uniform int pattern = 0;
uniform float stone_size = 2.4;
uniform float roughness_value = 0.82;
uniform float wetness = 0.0;
uniform float frost = 0.0;
uniform float embers = 0.0;
uniform vec3 ember_color : source_color = vec3(1.0, 0.42, 0.12);
uniform float moss = 0.0;
uniform vec3 moss_color : source_color = vec3(0.24, 0.36, 0.18);
uniform float brass = 0.0;
uniform float cracks = 0.5;
uniform float sparkle = 0.0;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
varying vec2 world_xz;

void vertex() {
    world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    vec4 broad = texture(detail, world_xz * 0.07);
    vec4 fine = texture(detail, world_xz * (0.89 / max(stone_size, 0.1)));
    vec3 color = mix(mix(palette_a, palette_b, broad.r), mix(palette_c, palette_d, broad.g), smoothstep(0.3, 0.7, broad.b));
    color = mix(color, palette_e, smoothstep(0.55, 0.9, fine.g) * 0.6);
    color *= (0.8 + 0.4 * fine.r) * (0.88 + 0.24 * fine.b);

    // The cellular and ridged channels are generated once on the CPU, not
    // searched for every pixel and every light illuminating this sheet.
    float seam = (1.0 - smoothstep(0.08, 0.17, fine.g)) * (pattern == 0 ? 1.0 : 0.0);
    float vein = 1.0 - abs(fine.a * 2.0 - 1.0);
    float crack = smoothstep(0.9, 0.975, vein) * cracks * (pattern == 1 ? 1.0 : 0.55);
    color = mix(color, grout_color, seam * 0.65);
    color *= 1.0 - crack * 0.45;
    color *= pattern == 2 ? 0.88 + 0.24 * fine.g : 1.0;

    float growth = moss * clamp(seam + smoothstep(0.5, 0.8, fine.g + broad.r * 0.3) * 0.7 + crack * 0.5, 0.0, 1.0);
    float rime = frost * clamp(seam * 0.9 + smoothstep(0.45, 0.9, fine.b) * 0.6, 0.0, 1.0);
    color = mix(color, moss_color * (0.7 + 0.6 * fine.r), growth);
    color = mix(color, vec3(0.78, 0.86, 0.94), rime);
    float damp = wetness * smoothstep(0.35, 0.7, broad.a + seam * 0.3);
    color *= 1.0 - damp * 0.45;
    float inlay = brass * smoothstep(0.92, 0.98, fine.g);
    color = mix(color, vec3(0.8, 0.62, 0.3), inlay);
    float heat = clamp(crack + seam * smoothstep(0.8, 0.95, fine.r), 0.0, 1.0) * smoothstep(0.45, 0.75, broad.g) * embers;
    ALBEDO = color;
    ROUGHNESS = mix(mix(roughness_value, 0.96, seam), 0.22, damp);
    METALLIC = inlay;
    SPECULAR = 0.35;
    EMISSION = ember_color * heat * 0.65 + vec3(0.85, 0.93, 1.0) * smoothstep(0.98, 1.0, fine.b) * sparkle * 0.2;
}
