shader_type canvas_item;
render_mode unshaded;

uniform vec2 panel_size = vec2(300.0, 130.0);
uniform vec2 panel_origin = vec2(0.0);
uniform vec4 base_color : source_color = vec4(0.26, 0.26, 0.23, 1.0);
uniform vec4 accent_color : source_color = vec4(0.63, 0.55, 0.38, 1.0);
uniform bool compact_surface = false;
uniform vec4 lamp_data[4]; // logical screen x, y, radius, real light energy
uniform vec4 lamp_colors[4] : source_color;
uniform vec3 key_direction = vec3(-0.45, -0.6, 0.8);
uniform vec4 key_color : source_color = vec4(0.16, 0.19, 0.22, 1.0);
uniform float ambient_energy = 0.65;

float rounded_box(vec2 point, vec2 half_size, float radius) {
	vec2 q = abs(point) - half_size + vec2(radius);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
}

float grain(vec2 point) {
	return fract(sin(dot(floor(point), vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * panel_size;
	vec2 centered = p - panel_size * 0.5;
	float radius = compact_surface ? 7.0 : 9.0;
	float sdf = rounded_box(centered, panel_size * 0.5 - vec2(0.8), radius);
	float coverage = 1.0 - smoothstep(-0.75, 0.5, sdf);
	if (coverage < 0.001) {
		discard;
	}
	float edge = -sdf;
	vec2 q = abs(centered) - panel_size * 0.5 + vec2(radius + 0.8);
	vec2 outward = q.x > q.y ? vec2(sign(centered.x), 0.0) : vec2(0.0, sign(centered.y));
	if (min(q.x, q.y) > 0.0) {
		outward = normalize(max(q, vec2(0.001)) * sign(centered));
	}
	float bevel = 1.0 - smoothstep(1.0, 5.5, edge);
	float inset = smoothstep(7.0, 8.5, edge) * (1.0 - smoothstep(9.5, 11.5, edge));
	vec3 normal = normalize(vec3(outward * (bevel * 1.15 - inset * 0.65), 1.0));
	float rim = 1.0 - smoothstep(5.0, 8.0, edge);
	float hairline = smoothstep(10.0, 10.6, edge) * (1.0 - smoothstep(11.1, 11.9, edge));
	vec3 stone = base_color.rgb;
	stone *= 0.97 + grain(p * 0.75) * 0.055;
	stone *= 1.03 - UV.y * 0.065;
	stone = mix(stone, mix(stone * 1.15, accent_color.rgb, 0.31), rim);
	stone = mix(stone, stone * 0.52, hairline * 0.65);
	// The bottom face is a thick stone lip; the top bevel catches the key light.
	float bottom_lip = (1.0 - smoothstep(1.0, 4.5, panel_size.y - p.y)) * 0.30;
	stone *= 1.0 - bottom_lip;
	// Small brass pins make larger panels feel assembled, not flat rectangles.
	if (!compact_surface && panel_size.x > 140.0 && panel_size.y > 85.0) {
		vec2 stud_offset = abs(centered) - (panel_size * 0.5 - vec2(16.0));
		float stud_d = length(stud_offset);
		float stud = 1.0 - smoothstep(2.4, 3.3, stud_d);
		vec3 stud_normal = normalize(vec3(stud_offset * vec2(sign(centered.x), sign(centered.y)) * 0.45, 1.0));
		normal = normalize(mix(normal, stud_normal, stud));
		stone = mix(stone, accent_color.rgb * (0.72 + stud * 0.20), stud);
		float recess = smoothstep(3.2, 3.6, stud_d) * (1.0 - smoothstep(3.9, 4.4, stud_d));
		stone *= 1.0 - recess * 0.4;
	}
	vec3 illumination = vec3(max(0.55, ambient_energy));
	illumination += key_color.rgb * max(dot(normal, normalize(key_direction)), 0.0);
	vec2 screen_point = panel_origin + p;
	for (int index = 0; index < 4; index++) {
		vec2 delta = lamp_data[index].xy - screen_point;
		float reach = max(lamp_data[index].z, 1.0);
		float attenuation = max(0.0, 1.0 - length(delta) / reach);
		vec3 light_direction = normalize(vec3(delta / reach, 0.38));
		float diffuse = max(dot(normal, light_direction), 0.0);
		illumination += lamp_colors[index].rgb * lamp_data[index].w * attenuation * attenuation * diffuse * 1.7;
	}
	// A restrained response keeps lantern pools soft and never washes out text.
	vec3 lit_stone = stone * min(illumination, vec3(1.8));
	COLOR = vec4(lit_stone, base_color.a * coverage) * COLOR;
}
