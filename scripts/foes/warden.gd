extends DungeonEnemy
## The Hearth Warden, the cellar's jailer. Blind, it hunts by sound and slams
## down where the last loud noise came from. The lantern it swings casts a
## cone of light: only a player standing in that light can hurt it, and
## standing there means being seen. At half health it puts out every lantern
## in the room; then its own lantern can be shot apart, which stuns it, and
## blind rage follows.
const CONE_ANGLE := 28.0
const CONE_REACH := 8.5
const SWING := .85
const SWING_FLIP := 6.0
const SLAM_REACH := 2.4
const GLANCING := .15
const LANTERN_HP := 45.0
const STUN := 3.5
var swing_angle = 0.0
var swing_dir = 1.0
var swing_flip = SWING_FLIP
var phase = 1
var lantern_hp = LANTERN_HP
var lantern_broken = false
var stunned = 0.0
var target = Vector3.ZERO
var slam_cooldown = 2.0
var summon = 12.0
var lantern: MeshInstance3D
var cone: MeshInstance3D
var spot: SpotLight3D

func is_boss() -> bool:
	return true

func stats() -> Array:
	return [260, 1.0, 1.0, "c4a27a"]

func build_body(light: Dictionary) -> void:
	var body = Geo.box(visual, Vector3(0, 1.2, 0), Vector3(1.8, 2.2, 1.8), color, light.foe_body)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.box(visual, Vector3(0, 1.55, -.92), Vector3(1.5, .2, .06), Color("3a3028"))
	Geo.cylinder(visual, Vector3(0, 2.4, 0), .65, .32, Color("72624b"))
	Geo.ring(self, Vector3(0, .035, 0), 1.3, Color("b08361"), .055)
	lantern = Geo.box(self, Vector3(0, 1.4, 1.7), Vector3(.45, .55, .45), Color("ffcb7d"), 1.6)
	lantern.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane = PlaneMesh.new()
	plane.size = Vector2.ONE * CONE_REACH * 2.0
	cone = MeshInstance3D.new()
	cone.mesh = plane
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/cone.gdshader")
	mat.set_shader_parameter("half_angle", deg_to_rad(CONE_ANGLE))
	cone.material_override = mat
	cone.layers = 2
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)
	cone.position = Vector3(0, .045, 0)
	spot = SpotLight3D.new()
	spot.light_color = Color("ffc27a")
	spot.light_energy = 2.2
	spot.spot_range = CONE_REACH + 1.5
	spot.spot_angle = CONE_ANGLE
	spot.light_cull_mask = Geo.LIT_LAYERS
	add_child(spot)

func eye_height() -> float:
	return 1.55

func prepare() -> void:
	target = global_position
	swing_angle = float(entity_id % 6)

func swing_direction() -> Vector3:
	return Vector3(sin(swing_angle), 0, cos(swing_angle))

## Whether a point stands in the swinging lantern's light.
func in_cone(p: Vector3) -> bool:
	if lantern_broken: return false
	var to: Vector3 = p - global_position
	to.y = 0
	if to.length() > CONE_REACH or to.length() < .01: return to.length() < .01
	return rad_to_deg(to.normalized().angle_to(swing_direction())) < CONE_ANGLE

func behave(delta: float, _distance: float, _direction: Vector3) -> Vector3:
	swing_angle += SWING * swing_dir * delta * (1.4 if phase == 2 else 1.0)
	swing_flip -= delta
	if swing_flip <= 0:
		swing_flip = SWING_FLIP
		swing_dir *= -1.0
	var aim = swing_direction()
	cone.rotation.y = swing_angle
	lantern.position = aim * 1.7 + Vector3(0, 1.4, 0)
	spot.position = lantern.position
	spot.look_at(global_position + aim * 5.0 + Vector3(0, -.6, 0), Vector3.UP)
	if phase == 1 and hp <= max_hp * .5: enter_phase_two()
	if phase == 2 and not lantern_broken: guard_lantern()
	if stunned > 0:
		stunned -= delta
		visual.rotation.z = sin(age * 18.0) * .06
		return Vector3.ZERO
	visual.rotation.z = 0.0
	slam_cooldown -= delta * tempo()
	summon -= delta
	if summon <= 0:
		summon = 12.0
		for side in [-1, 1]:
			game.spawn_enemy(global_position + Vector3(side * 1.8, 0, 1.0), "mote")
	# The light shows it the player; otherwise it follows sound.
	if in_cone(game.player.global_position):
		target = game.player.global_position
	else:
		var noise: Dictionary = game.latest_noise(1.0, 3.0)
		if not noise.is_empty(): target = noise.at
	if windup > 0: return Vector3.ZERO
	var to: Vector3 = target - global_position
	to.y = 0
	if to.length() < SLAM_REACH and slam_cooldown <= 0:
		begin_windup(to.normalized() if to.length() > .01 else aim, .8, SLAM_REACH, Color("eaa16f"))
		slam_cooldown = 1.6 if lantern_broken else 2.6
		return Vector3.ZERO
	if to.length() < .6: return Vector3.ZERO
	return steer_toward(target, delta)

func windup_done() -> void:
	Effects.ring_burst(game.scene_root, global_position, Color("eaa16f"), SLAM_REACH)
	game.shake = maxf(game.shake, .2)
	Audio.play_sound("kill", .5)
	if game.player.global_position.distance_to(global_position) < SLAM_REACH + .3:
		game.player.hurt(1.0, global_position)
	for i in 10:
		var d = Vector3.RIGHT.rotated(Vector3.UP, TAU * i / 10.0 + age * .3)
		game.spawn_shot(global_position + Vector3.UP * .6 + d * 1.1, d, 1, 4.5, {}, Color("f29d8c"), false)

## Only a player in its light hurts it; stunned, it takes double.
func damage_scale(cause: String) -> float:
	if stunned > 0: return 2.0
	if lantern_broken or cause in ["dot", "blast"]: return 1.0
	return 1.0 if in_cone(game.player.global_position) else GLANCING

func enter_phase_two() -> void:
	phase = 2
	for i in game.room.burning_indices(): game.snuff(i)
	game.shake = maxf(game.shake, .25)
	game.ui.notify("The Warden puts out the lanterns", "Shoot the lantern it swings.", Color("e0a18b"))

## Friendly shots that reach the swinging lantern chip at it.
func guard_lantern() -> void:
	for shot in game.shots:
		if not is_instance_valid(shot) or not shot.alive or not shot.friendly: continue
		if Vector2(shot.global_position.x - lantern.global_position.x, shot.global_position.z - lantern.global_position.z).length() > .6: continue
		lantern_hp -= shot.damage
		Effects.play("hit_spark", lantern.global_position, Color("ffcb7d"))
		shot.remove()
		if lantern_hp <= 0:
			break_lantern()
			return

func break_lantern() -> void:
	lantern_broken = true
	stunned = STUN
	lantern.visible = false
	cone.visible = false
	spot.visible = false
	Effects.burst(game.scene_root, lantern.global_position, Color("ffcb7d"), 14, 1.8)
	Audio.play_sound("hurt", .7)
	game.shake = maxf(game.shake, .3)
	game.ui.notify("Its lantern shatters", "Stunned for a moment, then blind with rage.", Color("e0a18b"))
