extends DungeonEnemy
## A moth drawn to flame. It flies to the nearest burning lantern, flutters a
## moment and puts it out; with every lantern dark it comes for the player's
## own light instead.
const HOVER := 1.0
var target_lantern = -1
var hover = 0.0
var wings: Array = []

func stats() -> Array:
	return [10, 3.0, .3, "cfc7b0"]

func eye_height() -> float:
	return .98

func build_body(light: Dictionary) -> void:
	Geo.sphere(visual, Vector3(0, .9, 0), radius, color, light.foe_body)
	for side in [-1, 1]:
		var wing = Geo.box(visual, Vector3(side * .36, .95, 0), Vector3(.48, .04, .34), Color("e8e0c8"), light.foe_body)
		wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wings.append(wing)

func behave(delta: float, _distance: float, _direction: Vector3) -> Vector3:
	for i in wings.size():
		wings[i].rotation.z = sin(age * (40.0 if hover > 0 else 26.0)) * .55 * (1 if i == 0 else -1)
	if game.room.lantern_points.is_empty():
		return steer_toward(game.player.global_position, delta)
	if target_lantern < 0 or not game.room.lanterns[target_lantern].burning:
		target_lantern = game.room.lantern_near(Vector2(position.x, position.z), 999.0, true)
		hover = 0.0
	var at: Vector3 = game.room.lanterns[target_lantern].at
	if Vector2(at.x - position.x, at.z - position.z).length() < 1.15:
		hover += delta * tempo()
		if hover >= HOVER:
			game.snuff(target_lantern)
			target_lantern = -1
			hover = 0.0
		return Vector3.ZERO
	return steer_toward(at, delta)
