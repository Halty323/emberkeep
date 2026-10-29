extends DungeonEnemy
## A lamplighter. Every foe in its lantern's light moves and attacks faster,
## though the light also exposes them. When it falls the lantern stays
## burning on the floor; shoot it and it bursts.
const AURA := 3.5
var lamp: MeshInstance3D
var strafe = 1.0

func stats() -> Array:
	return [34, 1.5, .45, "c9a46a"]

func build_body(light: Dictionary) -> void:
	Geo.sphere(visual, Vector3(0, .5, 0), radius, color, light.foe_body)
	Geo.cylinder(visual, Vector3(.36, .9, 0), .04, 1.2, Color("6e6654"))
	lamp = Geo.box(visual, Vector3(.36, 1.55, 0), Vector3(.3, .34, .3), Color("f7bb6d"), 1.4)
	var aura = Geo.halo(visual, Vector3(0, .03, 0), AURA * 2.0, Color(1, .7, .3, .16))
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func prepare() -> void:
	set_meta("reach", AURA)
	game.room.extra_lights.append(self)
	strafe = 1.0 if entity_id % 2 == 0 else -1.0

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	for other in game.enemies:
		if other != self and is_instance_valid(other) and other.alive and other.global_position.distance_to(global_position) < AURA:
			other.aura_haste = .3
	if timer <= 0:
		shoot_fan(direction, 1, 0.0, 4.5)
		timer = 3.0
	if not has_sight or distance > 8.0:
		return steer_toward(game.player.global_position, delta)
	# Keeps a lamplighter's distance, circling.
	var side = direction.cross(Vector3.UP) * strafe
	return (side + direction * (.6 if distance > 6.5 else (-.8 if distance < 4.5 else 0.0))).normalized()

func on_death() -> void:
	game.room.extra_lights.erase(self)
	game.spawn_enemy(global_position, "dropped_lantern")
