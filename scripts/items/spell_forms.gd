class_name SpellForms
extends RefCounted
## What a cast is, carried in its stats as numbers so a co-op guest draws it
## the same: "ray", "smite" (lightning) or "erupt" (an eruption, 1 + the
## element's place in Forge.ELEMENTS) for spells that do not fly, and
## "form" (its place in Forge.FORMS) for how a flying spell looks.

static func mark(stats: Dictionary, weapon: Dictionary) -> void:
	match str(weapon.get("archetype", "projectile")):
		"ray": stats["ray"] = 1.0
		"lightning": stats["smite"] = 1.0
		"eruption": stats["erupt"] = 1.0 + float(maxi(0, Forge.ELEMENTS.keys().find(str(weapon.get("element", "ember")))))
	var form := Forge.FORMS.find(str(weapon.get("form", "orb")))
	if form > 0: stats["form"] = float(form)

## The same stats as a plain flying spell (sparks, shards thrown off).
static func flying(stats: Dictionary) -> Dictionary:
	var result := stats.duplicate()
	for key in ["ray", "smite", "erupt", "form"]: result.erase(key)
	return result

static func archetype(stats: Dictionary) -> String:
	if float(stats.get("ray", 0)) > 0: return "ray"
	if float(stats.get("smite", 0)) > 0: return "lightning"
	if float(stats.get("erupt", 0)) > 0: return "eruption"
	return "projectile"

static func form(stats: Dictionary) -> String:
	return Forge.FORMS[clampi(int(stats.get("form", 0)), 0, Forge.FORMS.size() - 1)]
