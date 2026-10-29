class_name Foes
extends RefCounted
## Builds every kind of foe and composes encounters floor by floor: each floor
## brings its own foes, mixes in some from below, and from the halls up dresses
## a share of them as elites.
# Preloaded, so no foe's script compiles mid-run the first time it appears.
const SCRIPTS := {
	"snuffer": preload("res://scripts/foes/snuffer.gd"), "drip": preload("res://scripts/foes/drip.gd"),
	"shackled": preload("res://scripts/foes/shackled.gd"), "sporecap": preload("res://scripts/foes/sporecap.gd"),
	"rootling": preload("res://scripts/foes/rootling.gd"), "lichen": preload("res://scripts/foes/lichen.gd"),
	"lampwright": preload("res://scripts/foes/lampwright.gd"), "prism": preload("res://scripts/foes/prism.gd"),
	"cinderling": preload("res://scripts/foes/cinderling.gd"), "shackle_post": preload("res://scripts/foes/fixture.gd"),
	"dropped_lantern": preload("res://scripts/foes/fixture.gd"), "ember": preload("res://scripts/foes/fixture.gd"),
	"warden": preload("res://scripts/foes/warden.gd"), "mosskeeper": preload("res://scripts/foes/mosskeeper.gd"),
	"bulb": preload("res://scripts/foes/bulb.gd"), "last_light": preload("res://scripts/foes/last_light.gd")}
const BOSSES := ["warden", "mosskeeper", "last_light"]
const BOSS_NAMES := {"warden": "THE HEARTH WARDEN", "mosskeeper": "THE MOSSKEEPER", "last_light": "THE LAST LIGHT"}
# [kind, weight, most per room]. A rootling counts twice: they grow in pairs.
const ROSTERS := {
	1: [["mote", 3.0, 9], ["spitter", 2.0, 9], ["charger", 2.0, 9], ["snuffer", 1.4, 2], ["drip", 1.4, 3], ["shackled", .7, 1]],
	2: [["mote", 1.4, 9], ["spitter", 1.4, 9], ["charger", 1.3, 9], ["splitter", 1.8, 9], ["brute", 1.2, 3],
		["sporecap", 1.4, 2], ["rootling", 1.1, 1], ["lichen", 1.2, 2], ["drip", .6, 2]],
	3: [["mote", .8, 9], ["spitter", 1.1, 9], ["charger", 1.4, 9], ["splitter", 1.1, 9], ["brute", 1.3, 3],
		["lampwright", 1.1, 2], ["prism", 1.1, 2], ["cinderling", 1.8, 4], ["lichen", .8, 2], ["sporecap", .6, 2], ["rootling", .5, 1]]}
const ELITE_CHANCE := {1: 0.0, 2: .2, 3: .33}
const ELITES := ["gilded", "twinned", "volatile", "warded"]

static func create(kind: String) -> DungeonEnemy:
	if SCRIPTS.has(kind): return SCRIPTS[kind].new()
	return DungeonEnemy.new()

static func boss_kind(floor_number: int) -> String:
	return BOSSES[clampi(floor_number, 1, 3) - 1]

## An encounter's foes: [{"kind", "elite", "partner", "twin"}], from the
## room's own seeded stream so a restarted fight is the same fight.
static func compose(floor_number: int, count: int, gen: RandomNumberGenerator) -> Array:
	var roster: Array = ROSTERS[clampi(floor_number, 1, 3)]
	var plan: Array = []
	var taken := {}
	while plan.size() < count:
		var choices = roster.filter(func(entry): return taken.get(entry[0], 0) < entry[2] and (entry[0] != "rootling" or count - plan.size() >= 2))
		var total = 0.0
		for entry in choices: total += entry[1]
		var roll = gen.randf() * total
		var kind: String = choices.back()[0]
		for entry in choices:
			roll -= entry[1]
			if roll <= 0:
				kind = entry[0]
				break
		taken[kind] = taken.get(kind, 0) + 1
		if kind == "rootling":
			plan.append({"kind": kind, "elite": "", "partner": plan.size() + 1, "twin": -1})
			plan.append({"kind": kind, "elite": "", "partner": plan.size() - 1, "twin": -1})
		else:
			plan.append({"kind": kind, "elite": "", "partner": -1, "twin": -1})
	var chance: float = ELITE_CHANCE[clampi(floor_number, 1, 3)]
	for i in plan.size():
		if plan[i].kind == "rootling" or plan[i].elite != "" or gen.randf() >= chance: continue
		var twist: String = ELITES[gen.randi_range(0, ELITES.size() - 1)]
		if twist == "twinned":
			var mate = -1
			for j in range(i + 1, plan.size()):
				if plan[j].kind != "rootling" and plan[j].elite == "":
					mate = j
					break
			if mate < 0: twist = "volatile"
			else:
				plan[mate].elite = "twinned"
				plan[mate].twin = i
				plan[i].twin = mate
		plan[i].elite = twist
	return plan
