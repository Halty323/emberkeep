class_name SpellSounds
extends RefCounted
## Which sound a spell makes, and when. A flying spell's cast sounds of its
## element, pitched by its look. A ray buzzes as it fires, and a lingering
## beam hums while it burns. Lightning crackles as it gathers for a breath
## (scripts/shot.gd holds the strike back that long), then cracks where it
## lands; lightning from the sky is thunder. An eruption draws a soft breath
## as its rune is drawn, the ground rumbles under the rune while it charges
## (a falling star whistles down instead), and then what rises sounds as its
## element does. Each device plays the sounds of the spells it draws itself
## (Audio.play_local), so co-op never doubles them.
const ELEMENT_PITCH := {"ember": .95, "frost": 1.12, "storm": 1.05, "venom": .9, "radiance": 1.08, "glass": 1.15, "wax": .85, "tide": .92}
const FORM_PITCH := {"orb": 1.0, "shard": 1.1, "needle": 1.22, "comet": .82, "mote": 1.3, "disc": .94}

## The sound of a cast leaving the book (quieter and higher for an echo).
static func cast(stats: Dictionary, count := 1, echo := false) -> void:
	var element := str(stats.get("element", ""))
	var vary := randf_range(.97, 1.03) * (1.16 if echo else 1.0)
	var softer := -6.0 if echo else 0.0
	match SpellForms.archetype(stats):
		"ray": Audio.play_local("ray", float(ELEMENT_PITCH.get(element, 1.0)) * vary, softer)
		"lightning": Audio.play_local("charge", vary, softer)
		"eruption": Audio.play_local("conjure", float(ELEMENT_PITCH.get(element, 1.0)) * vary, softer)
		_:
			var id := "cast_" + element
			if not Audio.sounds.has(id): id = "shoot"
			Audio.play_local(id, float(FORM_PITCH.get(SpellForms.form(stats), 1.0)) * vary * (1.0 + float(count) * .01), softer)

## Lightning landing: a crack, or thunder for a bolt from the sky.
static func crack(shot: Node3D, at: Vector3) -> void:
	var sky := float(shot.stats.get("sky", 0)) > 0
	Audio.play_local_at("thunder" if sky else "crack", shot, at, randf_range(.92, 1.08))

## The ground stirring under an eruption's rune (a falling star's whistle).
static func stir(shot: Node3D, at: Vector3, rising: int) -> void:
	Audio.play_local_at("whistle" if rising == RelicPowers.METEOR else "rumble", shot, at, randf_range(.95, 1.05))

## What rises, sounding as its element does.
static func rise(shot: Node3D, at: Vector3, rising: int) -> void:
	var kind: String = SpellShapes.RISINGS[clampi(rising, 0, SpellShapes.RISINGS.size() - 1)]
	Audio.play_local_at("rise_" + kind, shot, at, randf_range(.94, 1.06))

## A lingering ray's beam humming while it burns.
static func hum(shot: Node3D, at: Vector3) -> void:
	Audio.play_local_at("hum", shot, at, randf_range(.95, 1.05))
