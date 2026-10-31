extends DungeonEnemy
## Wax clinging to the ceiling. Only its shadow shows, drifting after the last
## loud noise (or the player when all is quiet); it drops with a splash of wax,
## then crawls, leaving more wax behind it.
const FALL := .6
const LAST_DROP := 7.0
var state = "ceiling"
var fall_time = 0.0
var trail = 2.5
var shadow: MeshInstance3D

func stats() -> Array:
	return [14, 2.2, .38, "d9c9a0"]

func prepare() -> void:
	targetable = false
	visual.visible = false
	halo.visible = false
	collision_mask = 1
	shadow = Geo.cylinder(self, Vector3(0, .02, 0), .55, .02, Color("1a1612"))
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	timer = 2.4 + rng.randf() * 1.2

func behave(delta: float, _distance: float, _direction: Vector3) -> Vector3:
	match state:
		"ceiling":
			var target: Vector3 = game.player.global_position
			var noise: Dictionary = game.latest_noise(1.0, 2.5)
			if not noise.is_empty(): target = noise.at
			var to: Vector3 = target - global_position
			to.y = 0
			if (timer <= 0 and to.length() < 2.2) or age > LAST_DROP:
				state = "falling"
				fall_time = FALL
				begin_mark()
				return Vector3.ZERO
			return to.normalized() if to.length() > .3 else Vector3.ZERO
		"falling":
			fall_time -= delta
			shadow.scale = Vector3.ONE * (.6 + .4 * fall_time / FALL)
			if fall_time <= 0: land()
			return Vector3.ZERO
	trail -= delta
	if trail <= 0:
		trail = 2.5
		if game.residue: game.residue.add("wax", global_position, .5)
	return steer_toward(game.player.global_position, delta)

func begin_mark() -> void:
	if is_instance_valid(warning): warning.queue_free()
	warning = Geo.ring(self, Vector3(0, .05, 0), 1.0, Color("e8d6a8"), .06)

func land() -> void:
	state = "ground"
	targetable = true
	visual.visible = true
	halo.visible = true
	shadow.visible = false
	collision_mask = 7 | PropVisuals.FURNITURE_LAYER
	speed *= .6
	if is_instance_valid(warning): warning.queue_free()
	if game.residue: game.residue.add("wax", global_position, 1.5)
	Effects.ring_burst(game.scene_root, global_position, Color("e8d6a8"), 1.4)
	Audio.play_sound("hit", .6)
	if game.player.global_position.distance_to(global_position) < 1.0: game.player.hurt(1.0, global_position)

func update_light_state() -> void:
	if state == "ground": super.update_light_state()

func on_death() -> void:
	if game.residue: game.residue.add("wax", global_position, 1.2)
