// A short, finite height refinement for ORIGINAL authored ORMH relief.
// No raymarch, screen/depth copy, vertex sampling, or extra geometry. The
// caller supplies world-sized offsets, faded out before distant mip levels.
vec2 carved_uv(sampler2D height_map, vec2 uv, vec2 slide) {
    float h = texture(height_map, uv).a;
    vec2 first = uv - slide * (1.0-h);
    float next_h = texture(height_map, first).a;
    return uv - slide * (1.0-(h+next_h)*.5);
}
