extends DungeonEnemy
## A beetle under a mirror-bright lichen shell. Shots striking its face turn
## back on the player; its sides and back are soft, it turns slowly, and the
## shell lifts while it winds up to charge.
const MIRROR_ARC := 65.0
const TURN := 1.1
var facing = Vector3.FORWARD

func stats() -> Array:
	return [36, 1.6, .5, "7f9a83"]

func eye_height() -> float:
	return .5

func build_body(light: Dictionary) -> void:
	var body = Geo.box(visual, Vector3(0, .35, 0), Vector3(.9, .5, 1.1), color, light.foe_body)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var shell = Geo.box(visual, Vector3(0, .55, -.42), Vector3(1.0, .7, .16), Color("d6ecdf"), .35)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func prepare() -> void:
	timer = 3.0 + float(entity_id % 4) * .4

func turns() -> bool:
	return false

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	if charge_time <= 0 and windup <= 0:
		var current = atan2(facing.x, facing.z)
		var turned = current + clampf(angle_difference(current, atan2(direction.x, direction.z)), -TURN * delta, TURN * delta)
		facing = Vector3(sin(turned), 0, cos(turned))
	visual.rotation.y = atan2(-facing.x, -facing.z)
	if timer <= 0 and windup <= 0 and charge_time <= 0 and distance < 9.0:
		begin_windup(facing, .9, .8, Color("cfe3d6"))
		timer = 5.0
	return steer_toward(game.player.global_position, delta) * .8

## Its face turns a shot back toward the player; not while the shell is up.
func catch_shot(shot: EmberShot) -> bool:
	if windup > 0 or charge_time > 0: return false
	var incoming: Vector3 = -shot.direction
	incoming.y = 0
	if incoming.normalized().dot(facing) < cos(deg_to_rad(MIRROR_ARC)): return false
	var back: Vector3 = game.player.global_position + Vector3.UP * .65 - shot.global_position
	back.y = 0
	shot.friendly = false
	shot.direction = back.normalized()
	shot.damage = 1
	shot.speed = maxf(6.0, shot.speed * .7)
	shot.age = 0.0
	shot.lifetime = 2.5
	shot.hit_ids.clear()
	Effects.play("ward", shot.global_position, Color("d6ecdf"))
	Audio.play_sound("coin", .55)
	return true
