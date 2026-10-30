class_name Forge
extends RefCounted
## Weapons made fresh for every seed. A forged weapon is a firing pattern, an
## element and two or three traits, balanced against one damage budget and
## named and coloured from its parts. Its id says how it was made,
## "forged:<version>:<seed>:<slot>:<tier>", so a save, a shop or the menu
## only ever stores the id and the weapon is rebuilt identically anywhere.
## Tier 1 is the dark store's: a bigger budget and one more trait.
## Changing the tables below changes old ids' weapons: bump VERSION instead
## and keep the old tables for it.
const VERSION := 1
const PREFIX := "forged:"
const STARTERS := 4
# Damage per second a weapon may deal to one foe, before its traits' costs.
# Each trait and element pays part of its value from that budget.
const BUDGET := 34.0
const COST_SHARE := .6
const DARK_BUDGET := 1.35
# [count, spread, cooldown range, speed range, share of shots that land,
#  extra: burst, twin, spin, radial, and base effects].
const PATTERNS := {
	"bolt": {"count": 1, "spread": .03, "cooldown": [.22, .3], "speed": [14.0, 18.0], "lands": 1.0},
	"burst": {"count": 1, "spread": .05, "cooldown": [.5, .62], "speed": [15.0, 18.0], "lands": 1.0, "burst": 3},
	"fan": {"count": 5, "spread": .7, "cooldown": [.55, .7], "speed": [12.0, 14.0], "lands": .6, "extra_count": 2},
	"twin": {"count": 2, "spread": 0.0, "cooldown": [.28, .36], "speed": [15.0, 18.0], "lands": .9, "twin": .32},
	"ring": {"count": 8, "spread": TAU, "cooldown": [.6, .72], "speed": [12.0, 14.0], "lands": .3, "radial": 1, "extra_count": 2},
	"spiral": {"count": 2, "spread": TAU, "cooldown": [.11, .15], "speed": [11.0, 13.0], "lands": .45, "radial": 1, "spin": 2.4},
	"lance": {"count": 1, "spread": .01, "cooldown": [.3, .4], "speed": [24.0, 28.0], "lands": 1.0, "effects": {"pierce": 1, "size": -.2}},
	"lob": {"count": 1, "spread": .02, "cooldown": [.7, .9], "speed": [8.0, 10.0], "lands": 1.0, "effects": {"explosion": 1.4, "size": .5}},
	"boomerang": {"count": 1, "spread": .01, "cooldown": [.48, .58], "speed": [12.0, 14.0], "lands": 1.0, "effects": {"returning": 1, "pierce": 2, "size": .3}}}
const NOUNS := {"bolt": ["Wick", "Taper", "Glimmer", "Spark"], "burst": ["Flicker", "Sputter", "Candelabra", "Triple Wick"],
	"fan": ["Hearthfan", "Brazier", "Scatterlamp", "Spray"], "twin": ["Twin Tapers", "Sister Flames", "Paired Wicks", "Two Candles"],
	"ring": ["Sunwheel", "Halo", "Corona", "Lantern Ring"], "spiral": ["Pinwheel", "Whirl", "Spindle", "Catherine Wheel"],
	"lance": ["Lance", "Needle", "Ray", "Beam"], "lob": ["Mortar", "Censer", "Firepot", "Lamp Bomb"],
	"boomerang": ["Homecomer", "Moth", "Swallow", "Wanderer"]}
const PATTERN_WORDS := {"bolt": "steady single shots", "burst": "shots in bursts of three", "fan": "a wide spray of shots",
	"twin": "paired shots side by side", "ring": "a full ring of shots", "spiral": "a turning spiral of shots", "lance": "fast piercing rays",
	"lob": "slow bursting globes", "boomerang": "returning shots"}
# [effects, colours, adjectives, damage cost, what it does].
const ELEMENTS := {
	"ember": [{"burn": .7}, ["ffb070", "ff9a5a", "ffc47a", "f58a4a"], ["Smouldering", "Cinder", "Hearth", "Scorching"], .95, "that set foes burning"],
	"frost": [{"chill": 1.1}, ["a2e2e3", "9fcff0", "c0e8f5", "8fd0e8"], ["Rime", "Winter", "Frostbitten", "Pale"], .95, "that chill foes and freeze wax and water"],
	"storm": [{"chain": 1}, ["b5b0f7", "c4b8ff", "a8a0f0", "d0c8ff"], ["Thunder", "Storm", "Crackling", "Static"], .8, "that leap to nearby foes and run through water"],
	"venom": [{"poison": .8}, ["9fdb8a", "b0e090", "8ac878", "c0e8a0"], ["Moss", "Bitter", "Fen", "Verdant"], .92, "that poison foes"],
	"radiance": [{"homing": 1.8}, ["ffe5b5", "fff0c8", "ffd890", "f8e0a8"], ["Dawn", "Gilded", "Radiant", "Hallowed"], .9, "that seek out foes"],
	"glass": [{"split": 1}, ["b4e8ed", "c8f0f5", "a8e0e8", "d8f5f8"], ["Glass", "Prism", "Crystal", "Mirrored"], .85, "that split when they strike"],
	"wax": [{"knockback": .6}, ["e7d2a8", "f0dcb0", "d8c098", "e8d8b8"], ["Waxen", "Tallow", "Dripping", "Molten"], 1.0, "that leave wax where they fly"],
	"tide": [{"knockback": 1.2}, ["8fd0d8", "a0d8e0", "7fc0c8", "b0e0e8"], ["Tidal", "Drowned", "Brine", "Rain"], 1.0, "that push foes back and leave water behind"]}
# Elements that lay a trail of residue as they fly.
const TRAILS := {"wax": "wax", "tide": "water", "frost": "ice"}
# [effects, damage cost, phrase, patterns it does not suit].
const TRAITS := {
	"piercing": [{"pierce": 1}, .85, "pierce through", ["lance", "boomerang"]],
	"ricochet": [{"bounce": 2}, .85, "ricochet off walls", ["boomerang"]],
	"seeking": [{"homing": 1.6}, .85, "curve toward foes", []],
	"waving": [{"wave": 1}, .95, "weave as they fly", ["ring", "spiral"]],
	"splitting": [{"split": 1}, .8, "split on impact", []],
	"volatile": [{"explosion": 1.1}, .75, "burst on impact", ["lob"]],
	"chaining": [{"chain": 1}, .85, "arc to the next foe", []],
	"accelerating": [{"accel": 1}, .95, "gather speed", ["lob"]],
	"lingering": [{"linger": 1}, .9, "hang in the air as mines", ["boomerang", "lance"]],
	"growing": [{"grow": 1}, .9, "swell as they travel", []],
	"forking": [{"fork": 1}, .85, "fork apart at the end of their flight", ["boomerang"]],
	"kindled": [{"kindled": 1}, .9, "grow fiercer with the kindle", []],
	"keen": [{"crit": .12, "crit_damage": .5}, .9, "strike critically more often", []],
	"heavy": [{"knockback": 1.5, "size": .3}, .95, "hit heavily", []]}
const DARK_WORDS := ["Black", "Hollow", "Starving", "Grave", "Hungering"]
static var cache: Dictionary = {}

static func id_for(seed_value: int, slot: int, tier := 0) -> String:
	return "%s%d:%d:%d:%d" % [PREFIX, VERSION, seed_value, slot, tier]

static func is_forged(id: String) -> bool:
	return id.begins_with(PREFIX)

## Any weapon id: forged, or one of the catalog's (the Paint Sprayer, and the
## classic weapons older saves still hold). Empty when unknown.
static func lookup(id: String) -> Dictionary:
	if not is_forged(id): return Content.weapon_by_id.get(id, {})
	if cache.has(id): return cache[id]
	var parts = id.trim_prefix(PREFIX).split(":")
	if parts.size() != 4 or int(parts[0]) != VERSION or not parts[1].is_valid_int() or not parts[2].is_valid_int() or not parts[3].is_valid_int():
		return {}
	var weapon = make(int(parts[1]), int(parts[2]), int(parts[3]))
	cache[id] = weapon
	return weapon

static func known(id: String) -> bool:
	return not lookup(id).is_empty()

## A seed's starting choices: no two share a pattern or an element.
static func starters(seed_value: int) -> Array:
	return range(STARTERS).map(func(slot): return lookup(id_for(seed_value, slot)))

static func pick(gen: RandomNumberGenerator, values: Array):
	return values[gen.randi_range(0, values.size() - 1)]

static func make(seed_value: int, slot: int, tier: int) -> Dictionary:
	var gen = RandomNumberGenerator.new()
	gen.seed = Content.stable_hash("forge:%d:%d:%d:%d" % [VERSION, seed_value, slot, tier])
	# Starters of one seed walk through shuffled patterns and elements, so
	# the four choices always differ from each other.
	var order = RandomNumberGenerator.new()
	order.seed = Content.stable_hash("forge-order:%d:%d" % [VERSION, seed_value])
	var patterns: Array = PATTERNS.keys()
	var elements: Array = ELEMENTS.keys()
	shuffle(patterns, order)
	shuffle(elements, order)
	var pattern_id: String = patterns[slot % patterns.size()] if tier == 0 else pick(gen, PATTERNS.keys())
	var element_id: String = elements[slot % elements.size()] if tier == 0 else pick(gen, ELEMENTS.keys())
	var pattern: Dictionary = PATTERNS[pattern_id]
	var element: Array = ELEMENTS[element_id]
	var effects: Dictionary = pattern.get("effects", {}).duplicate()
	if pattern.has("radial"): effects.radial = 1.0
	add_effects(effects, element[0])
	var cost: float = softened(element[3])
	var phrases: Array = []
	var chosen: Array = []
	var pool: Array = TRAITS.keys().filter(func(id): return pattern_id not in TRAITS[id][3])
	for i in 2 + tier:
		if pool.is_empty(): break
		var trait_id: String = pick(gen, pool)
		pool.erase(trait_id)
		# A second homing or chain source would only double the element's.
		if (trait_id == "seeking" and element_id == "radiance") or (trait_id == "chaining" and element_id == "storm") or (trait_id == "splitting" and element_id == "glass"):
			trait_id = pick(gen, pool) if not pool.is_empty() else ""
			if trait_id == "": break
			pool.erase(trait_id)
		chosen.append(trait_id)
		add_effects(effects, TRAITS[trait_id][0])
		cost *= softened(TRAITS[trait_id][1])
		phrases.append(TRAITS[trait_id][2])
	var count: int = int(pattern.count) + (gen.randi_range(0, int(pattern.get("extra_count", 0))))
	var cooldown = snappedf(gen.randf_range(pattern.cooldown[0], pattern.cooldown[1]), .01)
	var burst: int = int(pattern.get("burst", 1))
	var budget = BUDGET * (DARK_BUDGET if tier > 0 else 1.0)
	# Seeking shots from a spread or a ring find their foes far more often.
	var lands: float = pattern.lands
	if float(effects.get("homing", 0)) > 0: lands += (1.0 - lands) * .6
	var damage = snappedf(maxf(1.0, budget * cooldown / (count * burst * lands) * cost), .1)
	var colors: Array = element[1]
	var color = Color(pick(gen, colors))
	color.h = fposmod(color.h + gen.randf_range(-.03, .03), 1.0)
	var adjective: String = pick(gen, element[2])
	var noun: String = pick(gen, NOUNS[pattern_id])
	var title = "%s %s" % [adjective, noun]
	if tier > 0: title = "%s %s" % [pick(gen, DARK_WORDS), title]
	var weapon := {"id": id_for(seed_value, slot, tier), "name": title, "color": "#" + color.to_html(false),
		"damage": damage, "cooldown": cooldown, "speed": snappedf(gen.randf_range(pattern.speed[0], pattern.speed[1]), .1),
		"count": count, "spread": float(pattern.spread), "effects": effects, "pattern": pattern_id, "element": element_id,
		"traits": chosen, "forged": true, "tier": tier}
	if burst > 1:
		weapon.burst = burst
		weapon.burst_gap = .07
	if pattern.has("twin"): weapon.twin = pattern.twin
	if pattern.has("spin"): weapon.spin = pattern.spin
	if TRAILS.has(element_id): weapon.trail = TRAILS[element_id]
	weapon.description = describe(pattern_id, element[4], phrases)
	return weapon

static func describe(pattern_id: String, element_phrase: String, phrases: Array) -> String:
	var line = "Fires %s %s" % [PATTERN_WORDS[pattern_id], element_phrase]
	if phrases.is_empty(): return line + "."
	if phrases.size() == 1: return "%s. They %s." % [line, phrases[0]]
	return "%s. They %s and %s." % [line, ", ".join(phrases.slice(0, phrases.size() - 1)), phrases.back()]

static func softened(cost: float) -> float:
	return 1.0 - (1.0 - cost) * COST_SHARE

static func add_effects(into: Dictionary, effects: Dictionary) -> void:
	for key in effects:
		into[key] = float(into.get(key, 0)) + float(effects[key])

static func shuffle(values: Array, gen: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j = gen.randi_range(0, i)
		var held = values[i]
		values[i] = values[j]
		values[j] = held
