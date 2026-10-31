extends DungeonEnemy
## A wax copy of the player, cast by the Chandler. It mirrors the player's
## steps across the room and fires a copy of the player's own weapon back.
## Wax melts: fire hurts it three times over.
var mirror = 1
var keeper: DungeonEnemy

func stats() -> Array:
	return [34, 2.4, .38, "e8d8b8"]

func eye_height() -> float:
	return .9

func build_body(light: Dictionary) -> void:
	var body = Geo.cylinder(visual, Vector3(0, .5, 0), .3, 1.0, color, maxf(light.foe_body, .2))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.sphere(visual, Vector3(0, 1.15, 0), .24, color, maxf(light.foe_body, .2))

func prepare() -> void:
	timer = 1.6 + float(entity_id % 2) * .8
	contact_damage = false

func behave(delta: float, _distance: float, direction: Vector3) -> Vector3:
	# The player's position reflected through the Chandler's own.
	var pivot: Vector3 = keeper.global_position if is_instance_valid(keeper) and keeper.alive else game.room.pedestal
	var offset: Vector3 = game.player.global_position - pivot
	var target = pivot + Vector3(-offset.x if mirror > 0 else offset.x, 0, offset.z if mirror > 0 else -offset.z)
	if timer <= 0:
		timer = 2.2
		volley(direction)
	var to = target - global_position
	to.y = 0
	return to.normalized() if to.length() > .4 else Vector3.ZERO

func volley(direction: Vector3) -> void:
	var weapon: Dictionary = Run.weapon()
	var count = mini(int(weapon.count), 5)
	for i in count:
		var angle = TAU * float(i) / count if float(weapon.effects.get("radial", 0)) > 0 else (float(i) / maxf(1, count - 1) - .5) * float(weapon.spread)
		var d = direction.rotated(Vector3.UP, angle)
		game.spawn_shot(global_position + Vector3.UP * .6 + d * .5, d, 1, clampf(float(weapon.speed) * .5, 5.0, 10.0), {}, Color(weapon.color).lerp(Color("e8d8b8"), .5), false)

func damage_scale(cause: String) -> float:
	return 3.0 if burn_time > 0 or cause == "blast" else 1.0
