extends DungeonEnemy
## Loose pages from the archive, flying as a flock. One page is nothing; the
## flock circles the player and dives in turns. Fire jumps from page to page.
## The page an encounter places brings the rest of its flock with it.
const FLOCK := 5
const ORBIT := 3.2
const CATCH := 1.5
var flock: Array = []
var leader = true
var orbit_angle = 0.0

func stats() -> Array:
	return [6, 3.0, .22, "e8e4d8"]

func eye_height() -> float:
	return .9

func build_body(light: Dictionary) -> void:
	var sheet = Geo.box(visual, Vector3(0, .9, 0), Vector3(.42, .03, .52), color, maxf(light.foe_body, .15))
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Geo.box(visual, Vector3(0, .92, 0), Vector3(.3, .01, .04), Color("3a3640"))

func prepare() -> void:
	orbit_angle = float(entity_id) * 1.3
	timer = 1.5 + float(entity_id % FLOCK) * .7

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	if leader and flock.is_empty(): gather()
	visual.rotation.z = sin(age * 9.0 + entity_id) * .5
	if windup > 0 or charge_time > 0: return Vector3.ZERO
	if timer <= 0 and distance < 6.0:
		timer = 3.0 + rng.randf() * 1.5
		begin_windup(direction, .3, .5, Color("e8e4d8"))
		return Vector3.ZERO
	orbit_angle += delta * 1.1
	var around: Vector3 = game.player.global_position + Vector3(cos(orbit_angle), 0, sin(orbit_angle)) * ORBIT
	var move = (around - global_position)
	move.y = 0
	# Keep loosely with the flock.
	var middle = Vector3.ZERO
	var mates = 0
	for page in flock:
		if is_instance_valid(page) and page.alive and page != self:
			middle += page.global_position
			mates += 1
	if mates > 0: move += (middle / mates - global_position) * .25
	return move.normalized() if move.length() > .2 else Vector3.ZERO

func gather() -> void:
	flock = [self]
	for i in FLOCK - 1:
		var at = global_position + Vector3.RIGHT.rotated(Vector3.UP, TAU * i / (FLOCK - 1)) * .9
		var page = game.spawn_enemy(at, "pages")
		page.leader = false
		flock.append(page)
	for page in flock: page.flock = flock

func charge_length() -> float:
	return .4

func charge_speed() -> float:
	return 9.0

func footing_drag() -> float:
	return 1.0

## Paper catches: fire on one page spreads to every page near it.
func apply_status(effects: Dictionary) -> void:
	var was_burning = burn_time > 0
	super.apply_status(effects)
	if was_burning or float(effects.get("burn", 0)) <= 0: return
	for page in flock:
		if is_instance_valid(page) and page.alive and page != self and page.burn_time <= 0 and page.global_position.distance_to(global_position) < CATCH:
			page.apply_status({"burn": effects.burn})
