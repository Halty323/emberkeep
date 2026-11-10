shader_type spatial;
// Low fog made of puffs: soft cloud sprites that always face the camera,
// drifting and turning slowly over the floor under each one. A Perlin noise
// field slides across the room beneath them: its broad banks roll through,
// thickening the puffs they cover and thinning those they leave, and its fine
// detail warps each puff's edges so they churn. A puff thins out where it
// meets the stones (no hard line) and close to the camera (you walk through
// it), and is lighter on top than below. It takes the light of whatever
// lantern, candle or spell is near without facing it, as light scatters in
// fog, so it glows around fixtures and sinks into the dark between.
// Everything per puff comes from its transform: the floor height is its
// origin's y, its size its scale, and the rest a hash of where it stands.
// The fog stays put however you look: puffs turn to face you but stay
// mostly upright (they never lie down into a sheet over the floor when you
// look down), and their noise is read in the puff's own frame on the world,
// not the turning quad, so turning your head never reshuffles the fog.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, skip_vertex_transform;

uniform sampler2D puff_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D flow_map : filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(.74, .79, .84, 1.0);
uniform float strength = .4;
uniform float scatter = .9;
uniform float squash = .62;
// How the noise field moves: its broad banks, and the finer churn.
uniform vec2 drift = vec2(.032, .019);
uniform float bank_scale = .045;
uniform float churn_scale = .17;
uniform float warp = .11;

varying vec3 world;
varying float ground_y;
varying float shade;
varying vec2 cell;
varying vec2 local;
varying vec2 pattern;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	float a = hash(origin.xz);
	float b = hash(origin.zx + vec2(17.31, 5.17));
	ground_y = origin.y;
	vec3 center = origin + vec3(
		sin(TIME * .07 + a * 6.2832) * .4,
		mix(.2, .48, b) + sin(TIME * .23 + a * 9.0) * .04,
		cos(TIME * .055 + b * 6.2832) * .4);
	float spin = a * 6.2832 + TIME * (b - .5) * .09;
	vec2 corner = mat2(vec2(cos(spin), sin(spin)), vec2(-sin(spin), cos(spin))) * VERTEX.xy;
	shade = clamp(VERTEX.y + .5, 0.0, 1.0);
	// Face the eye around the vertical, leaning back toward it at most 40°.
	vec3 to_eye = CAMERA_POSITION_WORLD - center;
	vec3 toward = normalize(vec3(to_eye.x, 0.0, to_eye.z) + vec3(1e-4, 0.0, 0.0));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), toward));
	float lean = clamp(atan(max(0.0, to_eye.y), length(to_eye.xz)), 0.0, 0.7);
	vec3 up = normalize(vec3(0.0, cos(lean), 0.0) - toward * sin(lean));
	world = center + (right * corner.x + up * corner.y * squash) * size;
	// Where this bit of the puff lies on the world, whatever way it faces.
	pattern = center.xz + corner * size;
	// One of four puff shapes in the 2x2 sheet.
	cell = vec2(step(.5, b), step(.5, fract(a * 7.0))) * .5;
	local = UV;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 flow = TIME * drift;
	// Broad banks rolling through the room.
	float bank = texture(flow_map, pattern * bank_scale + flow).r;
	// Finer churn, moving faster and the other way, rising a little with height.
	vec2 fine = pattern * churn_scale - flow * 2.4 + vec2(0.0, world.y * .35);
	float churn = texture(flow_map, fine).r;
	float churn_b = texture(flow_map, fine.yx + vec2(.31, .67)).r;
	vec2 bent = clamp(local + (vec2(churn, churn_b) - .5) * warp * 2.0, 0.0, 1.0);
	float density = texture(puff_map, cell + bent * .5).r;
	density *= mix(.15, 1.4, smoothstep(.32, .72, bank)) * (.7 + churn * .6);
	float ground = smoothstep(ground_y - .02, ground_y + .38, world.y);
	// Thins only right at the eye, so no hole opens round you as you walk.
	float near = smoothstep(.3, 1.2, distance(world, CAMERA_POSITION_WORLD));
	ALBEDO = tint.rgb * mix(.7, 1.06, shade);
	ALPHA = clamp(density * strength * ground * near, 0.0, 1.0);
}

void light() {
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * scatter / PI;
}
