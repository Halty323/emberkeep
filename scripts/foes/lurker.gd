extends DungeonEnemy
## An eel that lives in the cistern's pools. Under water it cannot be struck:
## only a ripple shows, gliding after the player (or the last loud noise when
## the player keeps to dry stone). Close enough, it surfaces and lunges, then
## lies on the surface a moment, open to everything, before slipping back
## under. Lightning in the pool still finds it. With no water it just crawls.
const LUNGE_REACH := 2.8
const SURFACED := 1.8
var submerged = false
var surfaced = 0.0
var ripple: MeshInstance3D

func stats() -> Array:
	return [24, 2.6, .4, "5f8f8a"]

func eye_height() -> float:
	return .42

func build_body(light: Dictionary) -> void:
	var body = Geo.box(visual, Vector3(0, .3, 0), Vector3(.5, .38, 1.2), color, light.foe_body)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.box(visual, Vector3(0, .26, .85), Vector3(.28, .22, .6), color.darkened(.2), light.foe_body)
	Geo.box(visual, Vector3(0, .52, -.1), Vector3(.06, .16, .7), Color("88b8b0"), light.foe_body)

func prepare() -> void:
	ripple = Geo.ring(self, Vector3(0, .04, 0), .6, Color("a8d8e0"), .04)
	ripple.visible = false
	timer = 1.2 + rng.randf()

func in_water() -> bool:
	return game.residue != null and game.residue.kind_at(global_position) == "water"

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	if surfaced > 0:
		surfaced -= delta
		if surfaced <= 0 and in_water(): submerge()
		return Vector3.ZERO
	if windup > 0 or charge_time > 0: return Vector3.ZERO
	if not submerged and in_water(): submerge()
	if distance < LUNGE_REACH and timer <= 0:
		timer = 3.2
		rise()
		begin_windup(direction, .45, 1.0, Color("a8d8e0"))
		return Vector3.ZERO
	if not submerged: return steer_toward(game.player.global_position, delta) * .7
	ripple.scale = Vector3.ONE * (1.0 + .15 * sin(age * 6.0))
	var target: Vector3 = game.player.global_position
	if game.residue.kind_at(target) != "water":
		var noise: Dictionary = game.latest_noise(1.0, 2.5)
		if not noise.is_empty(): target = noise.at
	var step = steer_toward(target, delta)
	# It keeps to the water: a step onto dry stone is not taken.
	if game.residue.kind_at(global_position + step * .7) != "water": return Vector3.ZERO
	return step * 1.25

func charge_length() -> float:
	return .35

func charge_speed() -> float:
	return 8.0

func charge_ended() -> void:
	surfaced = SURFACED

func footing_drag() -> float:
	return 1.0

func submerge() -> void:
	submerged = true
	targetable = false
	visual.visible = false
	halo.visible = false
	ripple.visible = true

func rise() -> void:
	submerged = false
	targetable = true
	visual.visible = true
	halo.visible = true
	ripple.visible = false
	Effects.ring_burst(game.scene_root, global_position, Color("a8d8e0"), 1.0)

func update_light_state() -> void:
	if not submerged: super.update_light_state()

## Lightning in the pool reaches it even under water.
func shocked(damage: float) -> void:
	var was = targetable
	targetable = true
	take_hit(damage, Vector3.ZERO, false, false, "shot")
	targetable = was if alive else false
