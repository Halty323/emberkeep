class_name Synergies
extends RefCounted
## How things combine. Three kinds of combination, each found once and then
## kept in the journal:
## - Reactions: a foe carries the elements that last touched it (a glint
##   above it shows them). A different element landing on it sets off a
##   reaction (Shatter, Steam, Surge…), consuming the element it carried.
## - Pairings: two relics carried together unlock something neither does.
## - Resonance: relics of the same element as the spellbook in hand grow
##   stronger with it.
## Spells carry their elements, pairing flags and resonance in their stats,
## so a co-op host applies a guest's combinations exactly as the guest's own
## device would. Pure data and lookups: it names no autoload.
const ELEMENT_ORDER := ["ember", "frost", "storm", "venom", "radiance", "glass", "wax", "tide"]
const ELEMENT_COLORS := {"ember": Color("ff9a5a"), "frost": Color("a2e2e3"), "storm": Color("b5b0f7"), "venom": Color("9fdb8a"),
	"radiance": Color("ffe5b5"), "glass": Color("c8f0f5"), "wax": Color("e7d2a8"), "tide": Color("6fc0e0")}
const ELEMENT_NAMES := {"ember": "Ember", "frost": "Frost", "storm": "Storm", "venom": "Venom", "radiance": "Radiance",
	"glass": "Glass", "wax": "Wax", "tide": "Tide"}
# How long an element stays on a foe after it lands.
const MARK_TIME := 4.0
# A foe reacts at most this often (bosses less often).
const REACTION_COOLDOWN := .9
const BOSS_REACTION_COOLDOWN := 2.2
# Later floors push back against what combinations can do.
const TOUGHNESS := [1.0, 1.0, 1.0, 1.1, 1.2, 1.3]
# id: [element, element ("*" for any other), name, colour, what it does, the journal's hint]
const REACTIONS := {
	"shatter": ["frost", "ember", "Shatter", Color("ffd2b8"),
		"Fire meets a chilled foe and cracks it: a heavy burst on the foe that also strikes those beside it.", "Ice remembers the first warm hand."],
	"steam": ["ember", "tide", "Steam", Color("e8eef0"),
		"Water meets a burning foe, or fire a soaked one: scalding steam hurts and slows everything near it.", "What a kettle says when it is angry."],
	"blight": ["ember", "venom", "Blight", Color("c8d65a"),
		"Fire meets poison: both spread to every foe close by, and all of them are scorched.", "Some fevers travel."],
	"overload": ["ember", "storm", "Overload", Color("ffb8f0"),
		"Lightning meets a burning foe, or fire a charged one: it explodes.", "Too much light in one place."],
	"wildfire": ["ember", "wax", "Wildfire", Color("ffb050"),
		"Fire meets a waxed foe: it burns long and hot and pools burning wax beneath it.", "Every candle was waiting for this."],
	"freeze": ["frost", "tide", "Freeze", Color("bff0ff"),
		"Frost meets a soaked foe: it freezes solid, cannot move or strike, and takes half again as much damage.", "Still water, stiller."],
	"brittle": ["frost", "venom", "Brittle", Color("d0f0c8"),
		"Frost meets poison: the foe turns brittle and takes 40% more damage for five seconds.", "Rot is patient; cold is quicker."],
	"set": ["frost", "wax", "Set Fast", Color("f0e8d0"),
		"Frost meets a waxed foe: the wax hardens and holds it in place.", "Wax forgets how to flow."],
	"surge": ["storm", "tide", "Surge", Color("a8d8ff"),
		"Lightning meets a soaked foe: it runs through every soaked foe in the room, and every foe standing in water.", "The water carries the news."],
	"prism": ["glass", "radiance", "Prism", Color("fff4d8"),
		"Radiance meets glass, either way round: six seeking beams burst from the foe.", "Morning through a window."],
	"flare": ["radiance", "*", "Flare", Color("fff0c0"),
		"Radiance meets a foe carrying any other element: it is laid bare and takes 30% more damage for five seconds.", "Light finds what hides inside."],
	"refract": ["glass", "*", "Refract", Color("d8f8ff"),
		"Any element meets a foe carrying glass: it splinters into four shards that carry that element on.", "A prism splits more than light."]}
# id: [relic, relic, name, colour, what it does, hint, flag a spell carries ("" for the player's own)]
const PAIRINGS := {
	"powder_keg": ["chili_oil", "firecracker", "Powder Keg", Color("ff8a4a"),
		"Foes you set burning explode when they fall.", "Fire that waits for a funeral.", "keg"],
	"icicle": ["winter_mint", "splinter", "Icicle", Color("bfe8f5"),
		"Your piercing spells shatter chilled foes as they pass through.", "A cold that goes straight through.", "icicle"],
	"ricochet_arc": ["copper_wire", "skipping_stone", "Ricochet Arc", Color("b5b0f7"),
		"Every ricochet throws lightning at the nearest foe.", "Each wall a little thunder.", "arc"],
	"royal_jelly": ["honeycomb", "bitter_tea", "Royal Jelly", Color("f0d070"),
		"A foe you poisoned heals you half a heart when it falls.", "Sweetness from bitterness.", "jelly"],
	"starfall": ["sunseed", "shattered_star", "Starfall", Color("ffd890"),
		"Every shard your spells split into bursts where it lands.", "A star does not break quietly.", "starfall"],
	"hunters_moon": ["moon_shard", "hunters_mark", "Hunter's Moon", Color("d8d0ff"),
		"Your weaving spells finish off any foe below a quarter of its health (not bosses).", "The tide turns on the wounded.", "moon"],
	"lucky_star": ["lucky_penny", "red_thread", "Lucky Star", Color("ffe08a"),
		"Critical hits leap to a second foe at full strength.", "Luck, tied with a red thread.", "lucky"],
	"northern_lights": ["storm_lantern", "deep_freeze", "Northern Lights", Color("a0f0e0"),
		"Lightning freezes the foes it leaps to.", "A cold sky that crackles.", "northern"],
	"homecoming": ["return_address", "seeking_spark", "Homecoming", Color("ffe5b5"),
		"Returning spells strike twice as hard on the way home.", "Nothing hits harder than coming home.", "homecoming"],
	"crossfire": ["rear_view", "side_candles", "Crossfire", Color("ffc890"),
		"Spells cast behind and beside you curve toward foes and pierce one.", "Eyes in the back of your head.", "crossfire"],
	"mirror_maze": ["mirror_box", "long_match", "Mirror Maze", Color("d8f0ff"),
		"Every ricochet makes a spell 30% stronger.", "Each reflection a little brighter.", "maze"],
	"candlemaker": ["warm_wax", "wide_wick", "Candlemaker", Color("f0dcb0"),
		"Your spells leave wax where they fly, and foes that walk through it are waxed.", "Drip, and drip, and drip.", "candle"],
	"constellation": ["firefly_jar", "tiny_planets", "Constellation", Color("fff3c4"),
		"Your orbiting lights cast little spells at nearby foes.", "Small lights learn to bite.", ""],
	"magpie": ["lodestone", "pocket_change", "Magpie", Color("ffd36b"),
		"Every coin you pick up gives +20% damage for five seconds, up to three times.", "Shiny things are worth fighting for.", ""],
	"bramble_ward": ["thorn_crown", "amber_guard", "Bramble Ward", Color("b0d080"),
		"When your guard takes a blow, a ring of thorns flies out.", "A shield with teeth.", ""],
	"snow_angel": ["snowglobe", "second_wind", "Snow Angel", Color("e0f4ff"),
		"Your dash nova freezes foes solid.", "Fall back into the snow.", ""],
	"frenzy": ["sugar_rush", "hungry_flame", "Frenzy", Color("ff9a8a"),
		"Each kill doubles your casting speed for two seconds.", "Appetite feeds appetite.", ""],
	"last_stand": ["heartstone", "last_light", "Last Stand", Color("ff7a6a"),
		"Below half health your spells pierce, and every kill heals a quarter heart.", "The last ember burns the brightest.", ""],
	"ember_dash": ["cinder_steps", "chili_oil", "Ember Dash", Color("ff8a5a"),
		"Dashing through foes sets them burning and marks them with your spellbook's element.", "Leave a little fire behind.", ""],
	"hearthkeeper": ["eternal_hearth", "dried_rose", "Hearthkeeper", Color("ffc080"),
		"Every room you clear gives you a ward.", "A hearth keeps those who tend it.", ""],
	"glass_cannon": ["glass_sun", "heavy_ember", "Glass Cannon", Color("e0f8ff"),
		"Foes that fall shatter into four glass shards that fly outward.", "Break, and break again.", ""]}
# element: [relics that sing with it, name, what it does, hint]
const RESONANCE := {
	"ember": [["chili_oil", "living_coal", "firecracker", "sunseed", "little_supernova", "cinder_steps"], "Spreading Fire",
		"When a burning foe falls, its fire leaps to one nearby foe for each resonant relic.", "Fire knows fire."],
	"frost": [["winter_mint", "deep_freeze", "aurora", "snowglobe"], "Deep Cold",
		"Chill builds: a few frost hits in quick succession freeze a foe solid (fewer with each resonant relic).", "Cold upon cold upon cold."],
	"storm": [["copper_wire", "storm_lantern", "aurora"], "Thunderhead",
		"Lightning leaps to one more foe for each resonant relic.", "The storm gathers its own."],
	"venom": [["bitter_tea", "honeycomb", "blood_orange"], "Virulence",
		"Poison builds with every hit instead of only refreshing.", "Bitterness accumulates."],
	"radiance": [["seeking_spark", "living_coal", "bottled_dawn", "dark_star"], "Dawn",
		"Your spells lay foes bare (they take 30% more damage) for a moment longer with each resonant relic.", "Bright things reveal."],
	"glass": [["shattered_star", "splinter", "ghost_thread", "glass_sun", "grave_glass"], "Facets",
		"Spells split into one more shard for each resonant relic, and shards strike harder.", "Every crack is another edge."],
	"wax": [["warm_wax", "wide_wick", "heavy_ember", "steady_hand"], "Molten",
		"Your spells leave wax where they fly, and waxed foes are slowed.", "Warm wax holds on."],
	"tide": [["skipping_stone", "moon_shard", "mirror_box"], "Undertow",
		"Soaked foes take 12% more damage from everything for each resonant relic.", "The deep pulls down."]}

static func element_color(element: String) -> Color:
	return ELEMENT_COLORS.get(element, Color.WHITE)

## The elements a spell, blast or status carries: its spellbook's own first,
## then any its relics or items add.
static func elements_of(stats: Dictionary) -> Array:
	var result: Array = []
	var own := str(stats.get("element", ""))
	if own != "": result.append(own)
	for pair in [["burn", "ember"], ["chill", "frost"], ["chain", "storm"], ["poison", "venom"], ["wet", "tide"], ["waxen", "wax"]]:
		if float(stats.get(pair[0], 0)) > 0 and pair[1] not in result: result.append(pair[1])
	return result

## A spellbook's element; the classic catalog books take theirs from what
## they do.
static func weapon_element(weapon: Dictionary) -> String:
	if str(weapon.get("element", "")) != "": return str(weapon.element)
	var effects: Dictionary = weapon.get("effects", {})
	for pair in [["burn", "ember"], ["chill", "frost"], ["chain", "storm"], ["homing", "radiance"]]:
		if float(effects.get(pair[0], 0)) > 0: return pair[1]
	return ""

## The status a lone element brings, for shards and spreading.
static func element_stats(element: String) -> Dictionary:
	var result := {"element": element}
	match element:
		"ember": result.burn = 1.0
		"frost": result.chill = 1.0
		"venom": result.poison = 1.0
		"storm": result.chain = 1.0
		"tide": result.wet = 1.0
		"wax": result.waxen = 1.0
	return result

## Which reaction two elements set off, or "".
static func reaction(a: String, b: String) -> String:
	if a == b: return ""
	for id in REACTIONS:
		var r: Array = REACTIONS[id]
		if r[1] == "*": continue
		if (r[0] == a and r[1] == b) or (r[0] == b and r[1] == a): return id
	if "radiance" in [a, b]: return "flare"
	if "glass" in [a, b]: return "refract"
	return ""

static func reaction_name(id: String) -> String:
	return REACTIONS[id][2] if REACTIONS.has(id) else ""

static func reaction_color(id: String) -> Color:
	return REACTIONS[id][3] if REACTIONS.has(id) else Color.WHITE

## The pairings every one of whose relics is carried.
static func pairings_for(inventory: Array) -> Array:
	var result: Array = []
	for id in PAIRINGS:
		if PAIRINGS[id][0] in inventory and PAIRINGS[id][1] in inventory: result.append(id)
	return result

static func has_pairing(inventory: Array, id: String) -> bool:
	return PAIRINGS.has(id) and PAIRINGS[id][0] in inventory and PAIRINGS[id][1] in inventory

## The pairings that taking this relic would complete.
static func completes(inventory: Array, relic: String) -> Array:
	var result: Array = []
	for id in PAIRINGS:
		var pair: Array = PAIRINGS[id]
		if relic == pair[0] and pair[1] in inventory and pair[0] not in inventory: result.append(id)
		elif relic == pair[1] and pair[0] in inventory and pair[1] not in inventory: result.append(id)
	return result

## How many distinct relics carried sing with this element.
static func resonance(inventory: Array, element: String) -> int:
	if not RESONANCE.has(element): return 0
	var count := 0
	for relic in RESONANCE[element][0]:
		if relic in inventory: count += 1
	return count

static func resonates(relic: String, element: String) -> bool:
	return RESONANCE.has(element) and relic in RESONANCE[element][0]

## What a spellbook's spells carry beyond its own effects: its element, the
## resonance of the relics carried with it, and the pairings spells apply.
static func spell_stats(inventory: Array, element: String) -> Dictionary:
	var result := {"element": element}
	var count := resonance(inventory, element)
	if count > 0:
		result["resonance"] = float(count)
		match element:
			"storm": result["chain"] = float(count)
			"glass": result["split"] = float(count)
	for id in pairings_for(inventory):
		var flag: String = PAIRINGS[id][6]
		if flag != "": result[flag] = 1.0
	return result

## Every combination in the journal's order, as "r:", "p:" and "e:" ids.
static func all_ids() -> Array:
	var result: Array = []
	for id in REACTIONS: result.append("r:" + id)
	for id in PAIRINGS: result.append("p:" + id)
	for element in ELEMENT_ORDER: result.append("e:" + element)
	return result

## [name, recipe, what it does, hint, colour] for a journal or banner entry.
static func entry(combo: String) -> Array:
	var kind := combo.get_slice(":", 0)
	var id := combo.get_slice(":", 1)
	match kind:
		"r":
			var r: Array = REACTIONS[id]
			var recipe := "%s + %s" % [ELEMENT_NAMES[r[0]], "any other element" if r[1] == "*" else ELEMENT_NAMES[r[1]]]
			return [r[2], recipe, r[4], r[5], r[3]]
		"p":
			var p: Array = PAIRINGS[id]
			return [p[2], "", p[4], p[5], p[3]]
		"e":
			var e: Array = RESONANCE[id]
			return [e[1], "%s spellbooks" % ELEMENT_NAMES[id], e[2], e[3], element_color(id)]
	return ["", "", "", "", Color.WHITE]
