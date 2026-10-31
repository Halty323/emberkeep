extends DungeonEnemy
## A drowned keeper with a bucket. It keeps its distance and throws water
## where the player stands: the splash hurts, leaves a pool behind, and puts
## out any lantern it lands beside.
const FLIGHT := .9
const SPLASH := 1.1
const POOL := 1.4
const DOUSE := 1.9
var lob: Dictionary = {}
var pail: MeshInstance3D

func stats() -> Array:
	return [22, 1.2, .45, "7a8f96"]

func eye_height() -> float:
	return .78

func build_body(light: Dictionary) -> void:
	var body = Geo.cylinder(visual, Vector3(0, .5, 0), .36, 1.0, color, light.foe_body)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.sphere(visual, Vector3(0, 1.08, 0), .24, color.lightened(.15), light.foe_body)
	pail = Geo.cylinder(visual, Vector3(.42, .55, -.1), .17, .28, Color("6f6a5e"), light.foe_body)

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	if not lob.is_empty():
		lob.time -= delta
		if lob.time <= 0: splash()
	var move = steer_toward(game.player.global_position, delta)
	if has_sight:
		move = direction * (1.0 if distance > 6.0 else (-.6 if distance < 4.0 else 0.0))
		if timer <= 0 and lob.is_empty():
			timer = 3.6
			var at: Vector3 = game.player.global_position
			at.y = 0
			lob = {"at": at, "time": FLIGHT, "mark": Geo.ring(game.scene_root, at + Vector3(0, .05, 0), SPLASH, Color("9fd8e0"), .05)}
			visual.scale = Vector3(1.2, .8, 1.2)
	pail.visible = lob.is_empty()
	return move

func splash() -> void:
	var at: Vector3 = lob.at
	if is_instance_valid(lob.mark): lob.mark.queue_free()
	lob = {}
	Effects.ring_burst(game.scene_root, at, Color("9fd8e0"), SPLASH)
	Effects.burst(game.scene_root, at + Vector3.UP * .3, Color("bfe8f0"), 10, 1.2)
	Audio.play_sound("hit", .8)
	if game.residue: game.residue.add("water", at, POOL)
	if game.player.global_position.distance_to(at) < SPLASH: game.player.hurt(1.0, at)
	for i in game.room.burning_indices():
		var lantern: Vector3 = game.room.lanterns[i].at
		if Vector2(lantern.x - at.x, lantern.z - at.z).length() < DOUSE: game.snuff(i)

func on_death() -> void:
	if not lob.is_empty() and is_instance_valid(lob.mark): lob.mark.queue_free()
	if game.residue: game.residue.add("water", global_position, 1.0)
