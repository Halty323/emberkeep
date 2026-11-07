shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Inky glazed water, with a real mirrored room at grazing angles. No screen
// refraction, vertex texture fetches, white additive pool, or per-tile mesh.
// One union mask preserves the existing hazard footprint and soft shoreline.
uniform sampler2D mask : filter_linear, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D reflection : source_color, filter_linear, repeat_disable;
uniform vec2 grid_origin;
uniform vec2 grid_size;
uniform float tile = .8;
uniform float frozen = 0.0;
uniform float reflect_strength = 0.0;
uniform vec4 ripples[8];
uniform float clock = 0.0;
varying vec2 world_xz;
void vertex() { world_xz = (MODEL_MATRIX*vec4(VERTEX,1)).xz; }
uniform bool body_mesh = false;
float raw(vec2 xz) { return texture(mask,(xz-grid_origin)/(tile*grid_size)).r; }
float cover(vec2 xz) { return smoothstep(.38,.92,raw(xz)); }
void fragment() {
    float r = tile*.42;
    // Five taps round the one-texel-a-tile mask into a puddle's shoreline.
    float c = raw(world_xz)*.36+(raw(world_xz+vec2(r,r))+raw(world_xz+vec2(-r,r))+raw(world_xz+vec2(r,-r))+raw(world_xz+vec2(-r,-r)))*.16;
    c += (texture(detail,world_xz*.33).b-.5)*.16+(texture(detail,world_xz*3.1).r-.5)*.025;
    float shape = smoothstep(.4,.53,c);
    // A soft wet stain and shadow just outside the shore.
    float wet = smoothstep(.22,.42,c)*(1.0-shape);
    if (shape<.01 && wet<.01) discard;
    vec2 drift = texture(detail,world_xz*.4+vec2(TIME*.012,-TIME*.009)).rg-.5;
    vec2 g = vec2(cos(world_xz.x*2.6+TIME*.85),cos(world_xz.y*2.2-TIME*.72))*.025+drift*.045;
    for (int i=0;i<8;i++) {
        vec4 r = ripples[i];
        float age = clock-r.z;
        if (r.w<=0.0 || age<0.0 || age>1.8) continue;
        vec2 d = world_xz-r.xy;
        float distance_to_center = length(d);
        float k = distance_to_center-age*1.7;
        float envelope = exp(-k*k*12.0)*(1.0-age/1.8)*r.w;
        g += d/max(.01,distance_to_center)*sin(k*20.0)*envelope*.17;
    }
    g *= 1.0-frozen;
    // The pool's body: its surface rounds down to the shore like a meniscus,
    // so the edge catches light as a bead instead of a flat cut.
    float e = tile*.4;
    g += vec2(cover(world_xz+vec2(e,0))-cover(world_xz-vec2(e,0)), cover(world_xz+vec2(0,e))-cover(world_xz-vec2(0,e)))*.55;
    NORMAL = normalize((VIEW_MATRIX*vec4(-g.x,1.0,-g.y,0)).xyz);
    float fresnel = pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),4.0);
    float depth = smoothstep(.55,.95,c);
    vec3 body = mix(vec3(.037,.105,.14),vec3(.015,.046,.075),depth);
    float lip = smoothstep(.42,.53,c)*(1.0-smoothstep(.53,.65,c));
    body += vec3(.035,.075,.09)*lip;
    // Light dancing on the bottom: two drifting caustic layers, deeper in.
    float ca = texture(detail,world_xz*1.15+vec2(TIME*.05,TIME*.03)+g*2.0).r;
    float cb = texture(detail,world_xz*1.7-vec2(TIME*.04,-TIME*.06)).g;
    float caustic = smoothstep(.62,.9,min(ca,cb)*1.25)*smoothstep(.5,.85,c)*(1.0-frozen);
    body += vec3(.09,.17,.19)*caustic;
    // A pale bright line of foam right at the shoreline.
    body += vec3(.16,.22,.24)*smoothstep(.4,.47,c)*(1.0-smoothstep(.47,.56,c))*(1.0-frozen*.5);
    float crack = smoothstep(.91,.98,1.0-abs(texture(detail,world_xz*.6).a*2.0-1.0));
    body = mix(body,vec3(.20,.31,.39)+crack*.08,frozen*.78);
    float sheen = reflect_strength*(.12+.68*fresnel)*(1.0-frozen*.3);
    vec2 mirror_uv = clamp(vec2(1.0-SCREEN_UV.x,SCREEN_UV.y)+g*.006,vec2(.002),vec2(.998));
    vec3 mirrored = texture(reflection,mirror_uv).rgb;
    ALBEDO = body*(1.0-sheen);
    EMISSION = mirrored*sheen;
    ROUGHNESS = mix(.12,.32,frozen);
    SPECULAR = .6;
    ALBEDO = mix(ALBEDO, vec3(0.0), wet);
    EMISSION *= shape;
    ALPHA = max(shape*.95, wet*.3);
}
