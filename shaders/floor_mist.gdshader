shader_type spatial;
// Low mist over the floor: a thin sheet of slow-drifting noise. It takes the
// light of whatever lantern, candle or spell is near without facing it (light
// scatters in mist), so it glows around fixtures and fades into the dark
// between them, and it thins out close to the camera so it never fills the view.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

uniform sampler2D noise_map : repeat_enable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(.74, .79, .84, 1.0);
uniform float strength = .5;
uniform float scale = .065;
uniform vec2 drift = vec2(.012, .007);
uniform vec2 offset = vec2(0.0);
uniform float scatter = .9;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz * scale + offset;
	float broad = texture(noise_map, p + TIME * drift).r;
	float fine = texture(noise_map, p * 2.6 - TIME * drift * 1.9 + vec2(.37, .61)).r;
	float body = smoothstep(.28, .8, broad * .68 + fine * .32);
	float near = smoothstep(.35, 2.2, distance(world, CAMERA_POSITION_WORLD));
	ALBEDO = tint.rgb;
	ALPHA = body * strength * near;
}

void light() {
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * scatter / PI;
}
