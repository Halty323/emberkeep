class_name FloorLight
## How much light reaches each floor of the tower. A run starts at the
## bottom, a captive with nothing but their own little light, and every floor
## climbed is brighter: more ambient and daylight, more lanterns still
## burning, warmer glass. Profile 0 is the title room; 1-3 are the bottom,
## middle and top of the tower, which every floor blends between by height.
## Foes carry only a small readability floor where it is darkest; real room
## lights supply their shape and colour instead of a bright self-lit body.
## The outline of every open doorway glows, brightest where it is darkest,
## so every way out shows.
##
## The brightest floor stays within the contrast the presentation suite holds
## (ambient under .36, directional key under .45), so shadows keep their shape.
const PROFILES := {
	0: {"ambient": .12, "ambient_color": Color("9aaec2"), "key": .22, "key_color": Color("99b4cf"),
		"background": Color("111d26"), "fog_color": Color("142330"), "fog_density": .002,
		"lamp": .6, "lamp_color": Color("ffbc71"), "shadow": 1.5, "glow": 1.0, "lit": 1.0, "vignette": .48,
		"foe_body": 0.0, "foe_glow": .09, "doorway": .75},
	# The bottom of the tower: a cold slit of moonlight, half the lanterns long dead.
	1: {"ambient": .055, "ambient_color": Color("7b8ca6"), "key": .08, "key_color": Color("86a0c8"),
		"background": Color("070b10"), "fog_color": Color("0a1118"), "fog_density": .006,
		"lamp": .42, "lamp_color": Color("ff9a52"), "shadow": 1.0, "glow": .65, "lit": .5, "vignette": .64,
		"foe_body": .08, "foe_glow": .12, "doorway": 1.0},
	# Halfway up: about as lit as every floor used to be.
	2: {"ambient": .12, "ambient_color": Color("9aaec2"), "key": .22, "key_color": Color("99b4cf"),
		"background": Color("111d26"), "fog_color": Color("142330"), "fog_density": .002,
		"lamp": .6, "lamp_color": Color("ffbc71"), "shadow": 1.5, "glow": 1.0, "lit": 1.0, "vignette": .48,
		"foe_body": 0.0, "foe_glow": .09, "doorway": .75},
	# The top: warm daylight through high windows, every lantern lit.
	3: {"ambient": .22, "ambient_color": Color("c7b9a2"), "key": .4, "key_color": Color("ffdcae"),
		"background": Color("1b2834"), "fog_color": Color("2a3946"), "fog_density": .0025,
		"lamp": .78, "lamp_color": Color("ffcd8c"), "shadow": 1.8, "glow": 1.25, "lit": 1.0, "vignette": .34,
		"foe_body": 0.0, "foe_glow": .09, "doorway": .6},
}

static func profile(floor_number: int) -> Dictionary:
	return PROFILES[clampi(floor_number, 0, 3)]

## The light of the floor being played.
static func current() -> Dictionary:
	return for_floor(Run.height(), Run.theme(), Run.twist_id())

## Brightness follows the height climbed, whatever the climb's length: the
## bottom is the cellar's dark, halfway is the halls, the top is the hearth.
## A theme then tints the colours, and a guttering floor loses half its
## lanterns.
static func for_floor(height: float, theme: Dictionary, twist := "") -> Dictionary:
	var upper = height > .5
	var low: Dictionary = PROFILES[2 if upper else 1]
	var high: Dictionary = PROFILES[3 if upper else 2]
	var t = clampf((height - .5) * 2.0 if upper else height * 2.0, 0.0, 1.0)
	var result := {}
	for key in low:
		# The bottom, middle and top are exactly the old floors' light.
		result[key] = low[key] if t <= 0.0 else (high[key] if t >= 1.0 else lerp(low[key], high[key], t))
	var tint: Dictionary = theme.get("light", {})
	for key in tint:
		result[key] = Color(tint[key])
	if twist == "dim":
		result.lit *= .5
		result.ambient *= .75
		result.foe_glow = maxf(result.foe_glow, .12)
	return result

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
