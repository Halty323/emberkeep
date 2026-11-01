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
void fragment() {
    float c = texture(mask,(world_xz-grid_origin)/(tile*grid_size)).r;
    float shape = smoothstep(.4,.53,c);
    if (shape<.01) discard;
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
    NORMAL = normalize((VIEW_MATRIX*vec4(-g.x,1.0,-g.y,0)).xyz);
    float fresnel = pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),4.0);
    float depth = smoothstep(.55,.95,c);
    vec3 body = mix(vec3(.037,.105,.14),vec3(.015,.046,.075),depth);
    float lip = smoothstep(.42,.53,c)*(1.0-smoothstep(.53,.65,c));
    body += vec3(.035,.075,.09)*lip;
    float crack = smoothstep(.91,.98,1.0-abs(texture(detail,world_xz*.6).a*2.0-1.0));
    body = mix(body,vec3(.20,.31,.39)+crack*.08,frozen*.78);
    float sheen = reflect_strength*(.12+.68*fresnel)*(1.0-frozen*.3);
    vec2 mirror_uv = clamp(vec2(1.0-SCREEN_UV.x,SCREEN_UV.y)+g*.006,vec2(.002),vec2(.998));
    vec3 mirrored = texture(reflection,mirror_uv).rgb;
    ALBEDO = body*(1.0-sheen);
    EMISSION = mirrored*sheen;
    ROUGHNESS = mix(.12,.32,frozen);
    SPECULAR = .6;
    ALPHA = shape*.95;
}
