extends DungeonEnemy
## A clockwork crawler. It moves only on the tick: a sharp lunge toward the
## player, then a dead stop until the next one. Struck while it stands still,
## its spring jumps and the next tick comes early.
const TICK := .85
const JUMP := .35
var gear: MeshInstance3D

func stats() -> Array:
	return [26, 1.0, .4, "b08a4a"]

func build_body(light: Dictionary) -> void:
	gear = Geo.cylinder(visual, Vector3(0, .35, 0), .42, .3, color, light.foe_body)
	gear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for i in 6:
		var tooth = Geo.box(gear, Vector3(cos(i * TAU / 6) * .45, 0, sin(i * TAU / 6) * .45), Vector3(.16, .26, .16), color.darkened(.15), light.foe_body)
		tooth.rotation.y = -i * TAU / 6

func prepare() -> void:
	timer = TICK * (1.0 + float(entity_id % 3) * .33)

func behave(_delta: float, _distance: float, direction: Vector3) -> Vector3:
	if charge_time > 0: return Vector3.ZERO
	if timer <= 0:
		timer = TICK
		charge_direction = direction.rotated(Vector3.UP, rng.randf_range(-.25, .25))
		charge_time = .22
		gear.rotation.y += PI / 3
		Audio.play_sound("hit", 1.6)
	return Vector3.ZERO

func charge_speed() -> float:
	return 9.0

func turns() -> bool:
	return false

func take_hit(damage: float, impulse: Vector3, critical := false, dot := false, cause := "hit") -> void:
	if charge_time <= 0 and not dot: timer = minf(timer, JUMP)
	super.take_hit(damage, impulse, critical, dot, cause)
