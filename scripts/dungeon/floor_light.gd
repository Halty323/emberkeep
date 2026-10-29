class_name FloorLight
## How much light reaches each floor of the tower. A run starts in the cellar,
## a captive with nothing but their own little light, and every floor climbed
## is brighter: more ambient and daylight, more lanterns still burning,
## warmer glass. Floor 0 is the title room. Purely visual: no gameplay reads it.
## Foes carry a faint glow of their own where it is darkest, to stay readable,
## and open doorways spill light from beyond onto the floor, strongest where it
## is darkest, so every way out shows.
##
## The brightest floor stays within the contrast the presentation suite holds
## (ambient under .36, directional key under .45), so shadows keep their shape.
const PROFILES := {
	0: {"ambient": .12, "ambient_color": Color("9aaec2"), "key": .22, "key_color": Color("99b4cf"),
		"background": Color("111d26"), "fog_color": Color("142330"), "fog_density": .002,
		"lamp": .6, "lamp_color": Color("ffbc71"), "shadow": 1.5, "glow": 1.0, "lit": 1.0, "vignette": .48,
		"foe_body": 0.0, "foe_glow": .09, "doorway": .24},
	# The Waking Cellar: a cold slit of moonlight, half the lanterns long dead.
	1: {"ambient": .055, "ambient_color": Color("7b8ca6"), "key": .08, "key_color": Color("86a0c8"),
		"background": Color("070b10"), "fog_color": Color("0a1118"), "fog_density": .006,
		"lamp": .42, "lamp_color": Color("ff9a52"), "shadow": 1.0, "glow": .65, "lit": .5, "vignette": .64,
		"foe_body": .38, "foe_glow": .42, "doorway": .5},
	# The Mosslit Halls: about as lit as every floor used to be.
	2: {"ambient": .12, "ambient_color": Color("9aaec2"), "key": .22, "key_color": Color("99b4cf"),
		"background": Color("111d26"), "fog_color": Color("142330"), "fog_density": .002,
		"lamp": .6, "lamp_color": Color("ffbc71"), "shadow": 1.5, "glow": 1.0, "lit": 1.0, "vignette": .48,
		"foe_body": 0.0, "foe_glow": .09, "doorway": .3},
	# The Last Hearth: warm daylight through high windows, every lantern lit.
	3: {"ambient": .22, "ambient_color": Color("c7b9a2"), "key": .4, "key_color": Color("ffdcae"),
		"background": Color("1b2834"), "fog_color": Color("2a3946"), "fog_density": .0025,
		"lamp": .78, "lamp_color": Color("ffcd8c"), "shadow": 1.8, "glow": 1.25, "lit": 1.0, "vignette": .34,
		"foe_body": 0.0, "foe_glow": .09, "doorway": .24},
}

static func profile(floor_number: int) -> Dictionary:
	return PROFILES[clampi(floor_number, 0, 3)]

## Floor-wide light: the environment, the directional key and the vignette.
static func apply(light: Dictionary, environment: Environment, key_light: DirectionalLight3D, vignette: ShaderMaterial) -> void:
	environment.background_color = light.background
	environment.ambient_light_color = light.ambient_color
	environment.ambient_light_energy = light.ambient
	environment.fog_light_color = light.fog_color
	environment.fog_density = light.fog_density
	key_light.light_color = light.key_color
	key_light.light_energy = light.key
	if vignette: vignette.set_shader_parameter("strength", light.vignette)

## Which of a room's lanterns still burn: at least one, chosen from the room
## seed on its own stream so neither decor nor gameplay randomness shifts.
static func lit_lanterns(count: int, light: Dictionary, room_seed: int) -> Array:
	var order: Array = range(count)
	if light.lit >= 1.0 or count == 0: return order
	var rng = RandomNumberGenerator.new()
	rng.seed = Content.stable_hash("lanterns:%d" % room_seed)
	for i in range(count - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var held = order[i]
		order[i] = order[j]
		order[j] = held
	var keep = order.slice(0, maxi(1, roundi(count * light.lit)))
	keep.sort()
	return keep
