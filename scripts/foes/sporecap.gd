extends DungeonEnemy
## A mushroom that keeps its distance and lobs spore pods where the player
## stands. A cloud hides whatever is inside it and drags at the feet; fire
## sets it off and poison runs through it. It bursts into one when it falls.
const POD := .9
const CLOUD := 1.9
var lob: Dictionary = {}

func stats() -> Array:
	return [30, 1.0, .5, "b9a98a"]

func eye_height() -> float:
	return .62

func build_body(light: Dictionary) -> void:
	Geo.cylinder(visual, Vector3(0, .32, 0), .22, .64, Color("d8ccb0"), light.foe_body)
	var cap = Geo.cylinder(visual, Vector3(0, .78, 0), .62, .3, color, light.foe_body, .28)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	if not lob.is_empty():
		lob.time -= delta
		if lob.time <= 0:
			if game.residue: game.residue.add_cloud(lob.at, CLOUD)
			if is_instance_valid(lob.mark): lob.mark.queue_free()
			lob = {}
	var move = steer_toward(game.player.global_position, delta)
	if has_sight:
		move = direction * (1.0 if distance > 6.0 else (-.6 if distance < 3.5 else 0.0))
		if timer <= 0 and lob.is_empty():
			timer = 4.2
			var at: Vector3 = game.player.global_position
			at.y = 0
			lob = {"at": at, "time": POD, "mark": Geo.ring(game.scene_root, at + Vector3(0, .05, 0), CLOUD, Color("b8c98a"), .05)}
			visual.scale = Vector3(1.25, .75, 1.25)
	return move

func on_death() -> void:
	if not lob.is_empty() and is_instance_valid(lob.mark): lob.mark.queue_free()
	if game.residue: game.residue.add_cloud(global_position, 2.0)
