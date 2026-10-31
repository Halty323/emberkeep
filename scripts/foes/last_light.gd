extends DungeonEnemy
## The Last Light, the thief of the player's light, at the top of the tower.
## It fires the player's own weapon back at them (its count, spread, speed,
## seeking, ricochets and wave) and drains the room's lanterns one by one,
## each making it stronger; relighting a lantern takes that strength back.
## Near the end it swallows every lantern and can be hurt only in light: a
## lantern's pool or the player's own glow. When it falls, the light returns.
const DRAIN_EVERY := 7.5
const CHANNEL := 1.2
const INTERRUPT := 30.0
const MOST_RADIANCE := 4
const FINAL := .35
var radiance = 0
var drain = 5.0
var channel: Dictionary = {}
var fire_timer = 1.5
var final = false
var strafe = 1.0
var beam_tick = 0.0

func is_boss() -> bool:
	return true

func stats() -> Array:
	return [300, 2.2, .8, "4a3a6e"]

func eye_height() -> float:
	return 1.5

func build_body(light: Dictionary) -> void:
	var body = Geo.cylinder(visual, Vector3(0, .6, 0), .55, 1.0, color, maxf(.2, light.foe_body))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.sphere(visual, Vector3(0, 1.45, 0), .58, Color("5c4a86"), maxf(.2, light.foe_body))
	Geo.sphere(visual, Vector3(0, 1.0, 0), .2, Color("f4ecff"), 2.2)
	Geo.light(visual, Vector3(0, 1.4, 0), Color("cbbcff"), .9, 4.5)
	Geo.ring(self, Vector3(0, .035, 0), 1.1, Color("8a78c0"), .05)

func prepare() -> void:
	strafe = 1.0 if entity_id % 2 == 0 else -1.0

## Where light can touch it: a lantern's pool or the player's own glow.
func in_light() -> bool:
	return game.room.lit_at(global_position) or global_position.distance_to(game.player.global_position) <= game.player_light_radius()

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	if not final and hp <= max_hp * FINAL: go_final()
	fire_timer -= delta * tempo()
	if fire_timer <= 0 and channel.is_empty():
		mirror_volley(direction)
		fire_timer = cadence()
	if not final:
		if channel.is_empty():
			drain -= delta
			if drain <= 0 and not game.room.lantern_points.is_empty():
				channel = {"lantern": game.room.lantern_near(Vector2(position.x, position.z), 999.0, true), "time": CHANNEL, "taken": 0.0}
		else:
			channel.time -= delta
			beam_tick -= delta
			var at: Vector3 = game.room.lanterns[channel.lantern].at + Vector3(0, 1.6, 0)
			if beam_tick <= 0:
				beam_tick = .15
				Effects.beam(game, global_position + Vector3.UP * 1.0, at, Color("b49cff"))
			if channel.taken >= INTERRUPT:
				channel = {}
				drain = DRAIN_EVERY
				knock_velocity += -direction * 4.0
				Effects.burst(game.scene_root, global_position + Vector3.UP, Color("f4ecff"), 10)
				game.ui.notify("Its drain breaks", "", Color("cbbcff"))
			elif channel.time <= 0:
				game.snuff(channel.lantern)
				radiance = mini(MOST_RADIANCE, radiance + 1)
				channel = {}
				drain = DRAIN_EVERY
				Effects.ring_burst(game.scene_root, global_position, Color("b49cff"), 1.6)
			return Vector3.ZERO
	if not has_sight or distance > 9.0:
		return steer_toward(game.player.global_position, delta)
	# Circles at its own distance; at the end it presses in.
	var wanted = 3.0 if final else 6.0
	var side = direction.cross(Vector3.UP) * strafe
	return (side * .8 + direction * (1.0 if distance > wanted + 1.0 else (-.8 if distance < wanted - 1.0 else 0.0))).normalized()

## How often it fires: a slowed copy of the player's own rhythm.
func cadence() -> float:
	var weapon: Dictionary = Run.weapon()
	var shooting: Dictionary = Run.projectile_stats()
	return clampf(float(weapon.cooldown) / maxf(.5, float(shooting.rate)) * 2.4 * (1.0 - .1 * radiance), .4, 2.2)

## The player's weapon turned around: same count, spread and flight.
func mirror_volley(direction: Vector3) -> void:
	var weapon: Dictionary = Run.weapon()
	var shooting: Dictionary = Run.projectile_stats()
	var count = mini(int(weapon.count + shooting.shots), 9)
	var spread: float = weapon.spread
	if count > int(weapon.count) and shooting.radial <= 0: spread += (count - int(weapon.count)) * .115
	var mirrored = {"size": float(shooting.get("size", 1)) * 1.2}
	for key in ["homing", "bounce", "wave"]:
		if float(shooting.get(key, 0)) > 0: mirrored[key] = shooting[key]
	var pace = clampf(float(weapon.speed) * float(shooting.shot_speed) * .55, 5.0, 12.0)
	for i in count:
		var angle = TAU * float(i) / count if shooting.radial > 0 else (float(i) / maxf(1, count - 1) - .5) * spread
		var d = direction.rotated(Vector3.UP, angle)
		game.spawn_shot(global_position + Vector3.UP * .65 + d * (radius + .2), d, 1, pace, mirrored, Color("b49cff"), false)
	Audio.play_sound("shoot", .7)

func damage_scale(_cause: String) -> float:
	if final and not in_light(): return 0.0
	return 1.0 - .12 * radiance

func take_hit(damage: float, impulse: Vector3, critical := false, dot := false, cause := "hit") -> void:
	var before = hp
	super.take_hit(damage, impulse, critical, dot, cause)
	if not channel.is_empty(): channel.taken += before - hp

## A lantern relit is strength taken back.
func on_relight(_index: int) -> void:
	if radiance <= 0: return
	radiance -= 1
	Effects.burst(game.scene_root, global_position + Vector3.UP, Color("fff3c4"), 8)

func go_final() -> void:
	final = true
	channel = {}
	for i in game.room.burning_indices():
		game.snuff(i)
		radiance = mini(MOST_RADIANCE, radiance + 1)
	speed *= 1.3
	game.shake = maxf(game.shake, .25)
	game.ui.notify("It swallows every lantern", "Only light can touch it now: relight them, keep it close.", Color("cbbcff"))

## The light comes home: every lantern burns and the flame runs high.
func on_death() -> void:
	for i in game.room.lanterns.size():
		game.room.set_lantern(i, true)
	game.kindle_heat = 12.0
	game.kindle_quiet = 0.0
	game.ui.notify("Your light returns", "", Color("fff3c4"))
