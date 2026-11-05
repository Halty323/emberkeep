class_name DeathBargain
extends RefCounted
## Death's terms at a dark altar. Its right hand holds what you may take: a
## dark relic, a dark-forged spellbook or a precious relic. Its left hand
## holds the price: a curse, a permanent weakness as heavy as the thing
## taken is strong, or a trial. Fail the trial and the curse falls anyway;
## what was taken is kept either way. Death deals once per altar.
## Pure data and lookups: it names no autoload.
# id: [name, the stat it takes from, how much per point of power, text]
const CURSES := {
	"withering": ["Withering", "damage", -1.0, "Your spells strike %d%% weaker."],
	"slow_hand": ["Slow Hand", "rate", -1.0, "You cast %d%% slower."],
	"leaden_feet": ["Leaden Feet", "speed", -1.0, "You move %d%% slower."],
	"heavy_chains": ["Heavy Chains", "dash_cd", -1.5, "Your dash takes %d%% longer to return."],
	"short_reach": ["Short Reach", "range", -1.0, "Your spells fly %d%% less far."]}
# A point of power weighs this much: power 2 to 5 makes 12% to 30%.
const STEP := .06
# id: [name, what Death asks, seconds allowed (0 for none)]
const TRIALS := {
	"waves": ["Waves against the clock", "Death raises three waves of foes in this room. Clear them all within %d seconds.", 60.0],
	"quarry": ["Reaper's quarry", "Death summons a champion. Kill it within %d seconds.", 30.0],
	"harvest": ["Soul harvest", "Catch seven of Death's soul-wisps within %d seconds while foes hunt you.", 40.0],
	"no_dash": ["No dashing", "Win your next fight without dashing once.", 0.0],
	"last_breath": ["Last breath", "Fight one wave on half a heart. Your health returns when it is done.", 0.0]}
# Trials fought at once, in Death's own room.
const AT_ONCE := ["waves", "quarry", "harvest", "last_breath"]
const COLOR := Color("cdb6ef")

## Gives an offer its price: a curse sized to its power and a trial. In
## co-op the party watches while each challenger faces their own trial.
static func terms(offer: Dictionary, gen: RandomNumberGenerator) -> void:
	var power := clampi(int(offer.get("price", 3)), 2, 5)
	var curse: String = CURSES.keys()[gen.randi_range(0, CURSES.size() - 1)]
	offer["power"] = power
	offer["curse"] = {"id": curse, "amount": snappedf(STEP * power * float(CURSES[curse][2]), .001)}
	offer["trial"] = TRIALS.keys()[gen.randi_range(0, TRIALS.size() - 1)]

static func known_curse(curse) -> bool:
	return curse is Dictionary and CURSES.has(str(curse.get("id", ""))) and float(curse.get("amount", 0)) < 0

static func curse_stat(curse: Dictionary) -> String:
	return CURSES[curse.id][1]

static func curse_name(curse: Dictionary) -> String:
	return CURSES[curse.id][0]

static func curse_text(curse: Dictionary) -> String:
	return CURSES[curse.id][3] % roundi(absf(float(curse.amount)) * 100.0)

static func trial_name(id: String) -> String:
	return TRIALS[id][0] if TRIALS.has(id) else ""

static func trial_text(id: String) -> String:
	if not TRIALS.has(id): return ""
	var text: String = TRIALS[id][1]
	return text % int(TRIALS[id][2]) if "%d" in text else text

static func trial_time(id: String) -> float:
	return float(TRIALS[id][2]) if TRIALS.has(id) else 0.0
