class_name Foes
extends RefCounted
## Builds every kind of foe and composes encounters floor by floor: each floor
## theme brings its own foes (content/floors.json), mixes in some from the
## floors below it in this climb, and from the second floor up dresses a share
## of them as elites.
# Preloaded, so no foe's script compiles mid-run the first time it appears.
const SCRIPTS := {
	"snuffer": preload("res://scripts/foes/snuffer.gd"), "drip": preload("res://scripts/foes/drip.gd"),
	"shackled": preload("res://scripts/foes/shackled.gd"), "sporecap": preload("res://scripts/foes/sporecap.gd"),
	"rootling": preload("res://scripts/foes/rootling.gd"), "lichen": preload("res://scripts/foes/lichen.gd"),
	"lampwright": preload("res://scripts/foes/lampwright.gd"), "prism": preload("res://scripts/foes/prism.gd"),
	"cinderling": preload("res://scripts/foes/cinderling.gd"), "shackle_post": preload("res://scripts/foes/fixture.gd"),
	"dropped_lantern": preload("res://scripts/foes/fixture.gd"), "ember": preload("res://scripts/foes/fixture.gd"),
	"warden": preload("res://scripts/foes/warden.gd"), "mosskeeper": preload("res://scripts/foes/mosskeeper.gd"),
	"bulb": preload("res://scripts/foes/bulb.gd"), "last_light": preload("res://scripts/foes/last_light.gd"),
	"lurker": preload("res://scripts/foes/lurker.gd"), "bailer": preload("res://scripts/foes/bailer.gd"),
	"mourner": preload("res://scripts/foes/mourner.gd"), "tallow": preload("res://scripts/foes/tallow.gd"),
	"pages": preload("res://scripts/foes/pages.gd"), "scrivener": preload("res://scripts/foes/scrivener.gd"),
	"clinker": preload("res://scripts/foes/clinker.gd"), "bellows": preload("res://scripts/foes/bellows.gd"),
	"cog": preload("res://scripts/foes/cog.gd"), "chime": preload("res://scripts/foes/chime.gd"),
	"sluice": preload("res://scripts/foes/sluice.gd"), "chandler": preload("res://scripts/foes/chandler.gd"),
	"effigy": preload("res://scripts/foes/effigy.gd"), "archivist": preload("res://scripts/foes/archivist.gd"),
	"kilnmother": preload("res://scripts/foes/kilnmother.gd"), "hourkeeper": preload("res://scripts/foes/hourkeeper.gd")}
const BOSSES := ["warden", "mosskeeper", "last_light", "sluice", "chandler", "archivist", "kilnmother", "hourkeeper"]
# The five kinds every floor shares; a floor's own foes are what make it.
const CLASSICS := ["mote", "spitter", "charger", "splitter", "brute"]
# Foes of floors already climbed this run come back, rarer, one at a time.
const EARLIER_WEIGHT := .3
const ELITE_CHANCE := [0.0, .2, .3, .36, .42]
const ELITES := ["gilded", "twinned", "volatile", "warded"]

static func create(kind: String) -> DungeonEnemy:
	if SCRIPTS.has(kind): return SCRIPTS[kind].new()
	return DungeonEnemy.new()

static func known(kind: String) -> bool:
	return SCRIPTS.has(kind) or DungeonEnemy.KINDS.has(kind)

static func boss_kind(theme: Dictionary) -> String:
	return theme.get("boss", {}).get("kind", "warden")

## A boss's name, as the floor that keeps it calls it.
static func boss_name(kind: String) -> String:
	for theme in Content.families.get("floors", []):
		if theme.boss.kind == kind: return theme.boss.name
	return kind.to_upper()

static func elite_chance(depth: int) -> float:
	return ELITE_CHANCE[clampi(depth, 1, ELITE_CHANCE.size()) - 1]

## [kind, weight, most per room] for a floor: its own roster, then the
## signature foes of the floors below it in this run's climb.
static func roster_for(theme_id: String, depth: int, plan: Array) -> Array:
	var roster: Array = Content.record("floors", theme_id).get("roster", []).map(func(entry): return entry.duplicate())
	var have := {}
	for entry in roster: have[entry[0]] = true
	for i in mini(depth - 1, plan.size()):
		for entry in Content.record("floors", plan[i]).get("roster", []):
			if have.has(entry[0]) or entry[0] in CLASSICS: continue
			have[entry[0]] = true
			roster.append([entry[0], entry[1] * EARLIER_WEIGHT, mini(entry[2], 1)])
	return roster

## An encounter's foes: [{"kind", "elite", "partner", "twin"}], from the
## room's own seeded stream so a restarted fight is the same fight. A rootling
## takes two places: they grow in pairs.
static func compose(roster: Array, chance: float, count: int, gen: RandomNumberGenerator) -> Array:
	var plan: Array = []
	var taken := {}
	while plan.size() < count:
		var choices = roster.filter(func(entry): return taken.get(entry[0], 0) < entry[2] and (entry[0] != "rootling" or count - plan.size() >= 2))
		if choices.is_empty(): choices = [["mote", 1.0, 99]]
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
	for i in plan.size():
		if plan[i].kind in ["rootling", "pages"] or plan[i].elite != "" or gen.randf() >= chance: continue
		var twist: String = ELITES[gen.randi_range(0, ELITES.size() - 1)]
		if twist == "twinned":
			var mate = -1
			for j in range(i + 1, plan.size()):
				if plan[j].kind not in ["rootling", "pages"] and plan[j].elite == "":
					mate = j
					break
			if mate < 0: twist = "volatile"
			else:
				plan[mate].elite = "twinned"
				plan[mate].twin = i
				plan[i].twin = mate
		plan[i].elite = twist
	return plan
