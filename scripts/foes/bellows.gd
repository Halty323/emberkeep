extends DungeonEnemy
## A leather bellows on legs. It draws breath, pulling the player in, then
## blows a gust down a cone: the player is shoved back, shots in the cone are
## blown out, and any fire in the gust's path runs along it.
const GUST_ANGLE := 32.0
const GUST_REACH := 6.0
const SHOVE := 9.0
var aim = Vector3.FORWARD

func stats() -> Array:
	return [34, 1.1, .5, "8a6a4a"]

func eye_height() -> float:
	return .8

func build_body(light: Dictionary) -> void:
	var body = Geo.box(visual, Vector3(0, .6, 0), Vector3(.9, .5, 1.0), color, light.foe_body)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.box(visual, Vector3(0, .6, -.7), Vector3(.18, .18, .5), Color("5a4a3a"), light.foe_body)

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	if windup > 0:
		# Drawing breath: a gentle pull toward the nozzle.
		game.player.push = game.player.push.move_toward(-direction * 2.0, delta * 8.0)
		visual.scale = Vector3(1.0 + .25 * (1.0 - windup), 1.0, 1.0)
		return Vector3.ZERO
	var move = steer_toward(game.player.global_position, delta)
	if has_sight:
		move = direction * (1.0 if distance > 5.0 else (-.5 if distance < 3.0 else 0.0))
		if timer <= 0 and distance < GUST_REACH:
			timer = 4.2
			aim = direction
			begin_windup(direction, 1.0, 1.0, Color("d8b890"))
	return move

func in_gust(at: Vector3) -> bool:
	var to: Vector3 = at - global_position
	to.y = 0
	return to.length() < GUST_REACH and to.length() > .01 and rad_to_deg(to.normalized().angle_to(aim)) < GUST_ANGLE

func windup_done() -> void:
	Effects.play("muzzle", global_position + Vector3.UP * .6 + aim * .9, Color("e8d8b8"), -1, 2.0, aim)
	Audio.play_sound("dash", .7)
	if in_gust(game.player.global_position): game.player.push = aim * SHOVE
	for shot in game.shots.duplicate():
		if is_instance_valid(shot) and shot.alive and shot.friendly and in_gust(shot.global_position):
			Effects.play("impact", shot.global_position, shot.tint)
			shot.remove()
	# Fanned flame runs down the gust.
	if game.residue:
		var burning = false
		for step in range(1, 8):
			if game.residue.kind_at(global_position + aim * step * .8) == "fire": burning = true
			if burning: game.residue.scorch(global_position + aim * step * .8, .6)
