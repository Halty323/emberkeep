class_name RelicPowers
extends RefCounted
## Relics that cast spells of their own. Each one works by casting a real
## spell (a ray, lightning, an eruption, a shard) through the same path any
## spell takes, so it works with every kind of spellbook and, in co-op, the
## host casts it and everyone draws it. Some answer a cast (an echo, a
## phantom's copy, a Great Cast, a falling star), some a hit (lightning from
## above, a prism's ray, the pull of a black pearl, the reach of a
## spyglass), some a kill (a phoenix's eruption, the grail's hunger) and one
## a dash (the floor erupting where you land).
const ECHO_DELAY := .35
const ECHO_SHARE := .6
const PHANTOM_SHARE := .7
const PHANTOM_REACH := 1.25
const SKY := 3.6
# A meteor is drawn as its own rising (SpellShapes.RISINGS).
const METEOR := 8

# ---------------------------------------------------------------- casting

## War Drum: every fourth cast (third with Overture) is a Great Cast.
static func great_cast(avatar: Node, stats: Dictionary) -> float:
	if float(stats.get("crescendo", 0)) <= 0: return 1.0
	avatar.casts += 1
	var overture := Run.has_pairing("overture")
	if avatar.casts % (3 if overture else 4) != 0: return 1.0
	stats.size = float(stats.get("size", 1)) + .5
	Effects.ring_burst(avatar.game, avatar.global_position, Color("ffd0a0"), 1.8)
	avatar.game.shake = maxf(avatar.game.shake, .08)
	return 3.0 if overture else 2.0

## Echo Bell: the cast rings out again (twice with Choir).
static func queue_echoes(avatar: Node, weapon: Dictionary, stats: Dictionary, damage: float, tint: Color) -> void:
	if float(stats.get("echo", 0)) <= 0: return
	var count := 2 if Run.has_pairing("choir") else 1
	for i in count:
		avatar.echoes.append({"wait": ECHO_DELAY * (i + 1), "weapon": weapon, "stats": stats, "damage": damage * ECHO_SHARE * (1.0 - .2 * i), "tint": tint.lightened(.3 + .15 * i)})

static func play_echoes(avatar: Node, delta: float) -> void:
	for echo in avatar.echoes.duplicate():
		echo.wait -= delta
		if echo.wait > 0: continue
		avatar.echoes.erase(echo)
		avatar.volley(echo.weapon, echo.stats, echo.damage, echo.tint)
		SpellSounds.cast(echo.stats, 1, true)

## Phantom Veil: where the phantoms stand, beside the caster (both sides with Legion).
static func phantoms(stats: Dictionary, side: Vector3) -> Array:
	if float(stats.get("phantom", 0)) <= 0: return []
	var spots: Array = [-side * PHANTOM_REACH]
	if Run.has_pairing("legion"): spots.append(side * PHANTOM_REACH)
	return spots

## Meteor Charm: now and then a falling star where you aim (three with Meteor Shower).
static func call_meteor(avatar: Node, stats: Dictionary, damage: float, origin: Vector3, aim: Vector3) -> void:
	if float(stats.get("meteor", 0)) <= 0 or randf() >= float(stats.meteor): return
	var star := SpellForms.flying(stats)
	star.erupt = float(METEOR + 1)
	star.explosion = maxf(float(star.get("explosion", 0)), 1.6)
	star.burn = float(star.get("burn", 0)) + .6
	var spread: Array = [-.22, 0.0, .22] if Run.has_pairing("meteor_shower") else [0.0]
	for angle in spread:
		avatar.launch_shot(origin, aim.rotated(Vector3.UP, angle), damage * 1.6, 1.0, star, Color("ffb070"), true)

## Seismic Boots: the floor erupts where a dash will end (twice with Aftershock).
static func quake(avatar: Node) -> void:
	if float(Run.stats.get("quake", 0)) <= 0: return
	var weapon: Dictionary = Run.weapon()
	var element := Synergies.weapon_element(weapon)
	if element == "": element = "glass"
	var stats := SpellForms.flying(Run.projectile_stats())
	stats.erupt = 1.0 + float(maxi(0, Forge.ELEMENTS.keys().find(element)))
	stats.anchor = 1.0
	if Run.has_pairing("aftershock"): stats.linger = 1.0
	var land: Vector3 = avatar.global_position + avatar.dash_direction * Adventurer.DASH_SPEED * Adventurer.DASH_TIME
	avatar.game.spawn_shot(land + Vector3.UP * .5, avatar.dash_direction, 10.0 * float(Run.stats.damage), 1.0, stats, Color(weapon.get("color", "#ffd18c")), true)

# ---------------------------------------------------------------- hitting

## How far the caster stands from what a spell struck.
static func reach(shot: Node, enemy: Node3D) -> float:
	var caster = shot.caster()
	return caster.global_position.distance_to(enemy.global_position) if is_instance_valid(caster) else 0.0

## After a spell strikes: lightning from above, a prism's ray, a pearl's pull.
static func on_hit(shot: Node, enemy: Node3D, power: float) -> void:
	var stats: Dictionary = shot.stats
	var game: Node = shot.game
	var at: Vector3 = enemy.global_position
	# Storm Crown: lightning from above (oftener, and leaping on, with Supercell).
	var thunder := float(stats.get("thunder", 0))
	if thunder > 0 and float(stats.get("sky", 0)) <= 0:
		var supercell := float(stats.get("supercell", 0)) > 0
		if Run.rng.randf() < (maxf(thunder, .5) if supercell else thunder):
			var bolt := SpellForms.flying(stats)
			bolt.smite = 1.0
			bolt.sky = 1.0
			bolt.thunder = 0.0
			bolt.prism = 0.0
			bolt.vortex = 0.0
			bolt.chain = float(bolt.get("chain", 0)) + (2.0 if supercell else 0.0)
			game.spawn_shot(at + Vector3.UP * SKY, Vector3.DOWN, power * .6, 1.0, bolt, Color("c4b8ff"), true)
	# Prism Lens: a ray at the nearest other foe (shards on striking, with Kaleidoscope).
	if float(stats.get("prism", 0)) > 0 and float(stats.get("prismed", 0)) <= 0:
		var other = game.nearest_enemy(at + Vector3.UP * .7, 9.0, {enemy.entity_id: true})
		if other:
			var ray := SpellForms.flying(stats)
			ray.ray = 1.0
			ray.prismed = 1.0
			ray.pierce = 0.0
			ray.bounce = 0.0
			ray.vortex = 0.0
			if float(stats.get("kaleido", 0)) > 0: ray.split = maxf(float(ray.get("split", 0)), 2.0)
			var from := at + Vector3.UP * .8
			game.spawn_shot(from, ((other.global_position + Vector3.UP * .7) - from).normalized(), power * .4, 72.0, ray, Color("fff4d8"), true)
	# Black Pearl: everything near is dragged in (and implodes, with Event Horizon).
	if float(stats.get("vortex", 0)) > 0:
		var pulled := 0
		for foe in game.enemies:
			if not is_instance_valid(foe) or not foe.alive or foe == enemy or foe.boss or foe.inert: continue
			var gap: Vector3 = at - foe.global_position
			gap.y = 0
			if gap.length() > 3.4 or gap.length() < .3: continue
			foe.shove(gap.normalized() * minf(7.0, gap.length() * 3.0))
			pulled += 1
		if pulled > 0: Effects.ring_burst(game, at, Color("8a7ae0"), 1.4)
		if pulled >= 3 and float(stats.get("horizon", 0)) > 0:
			game.blast(at + Vector3.UP * .5, 2.4, power * 1.2, true, null)
			game.reaction_word(at + Vector3.UP * 1.8, "p:event_horizon")

# ---------------------------------------------------------------- killing

## When any foe falls near the party: a phoenix's eruption, the grail's hunger.
static func on_kill(game: Node, at: Vector3) -> void:
	if float(Run.stats.get("phoenix", 0)) > 0:
		var fire := SpellForms.flying(Run.projectile_stats())
		fire.erupt = 1.0 + float(Forge.ELEMENTS.keys().find("ember"))
		fire.anchor = 1.0
		fire.burn = float(fire.get("burn", 0)) + 1.0
		fire.element = "ember"
		fire.size = 1.0
		if Run.has_pairing("pyroclasm"): fire.pyro = 1.0
		game.spawn_shot(at + Vector3.UP * .5, Vector3.FORWARD, 9.0 * float(Run.stats.damage), 1.0, fire, Color("ff8a4a"), true)
	if float(Run.stats.get("bloodlust", 0)) > 0:
		game.bloodlust = mini(10, game.bloodlust + 1)
		var hunger := {"damage": .08 * game.bloodlust}
		if Run.has_pairing("blood_moon"): hunger.crit = .04 * game.bloodlust
		Run.add_modifier("bloodlust", 900.0, hunger)

## Leaving a room: the grail's hunger is spent.
static func room_left(game: Node) -> void:
	if game.bloodlust <= 0: return
	game.bloodlust = 0
	Run.modifiers = Run.modifiers.filter(func(modifier): return modifier.source != "bloodlust")
	Run.rebuild_stats()
