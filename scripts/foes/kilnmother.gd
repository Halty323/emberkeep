extends DungeonEnemy
## The Kilnmother, the furnace at the heart of the kiln. Her iron door turns
## nearly every blow; it swings open on a rhythm, and only then is her heart
## open to the player. Chill on the open heart quenches her and holds the door
## open longer. She lobs slag that sets the floor alight and breathes rings
## of fire across the room. From half health she calls cinderlings each time
## the door opens.
const SHUT := 6.0
const OPEN := 3.5
const QUENCH := 1.5
const CLOSED := .15
const HEART := 1.3
const FIRE_RING_SPEED := 4.0
const FIRE_RING_REACH := 9.0
var door_open = false
var door_time = SHUT
var quenched = false
var lob_cooldown = 2.5
var ring_cooldown = 5.0
var lobs: Array = []
var fire_rings: Array = []
var door: MeshInstance3D
var heart: MeshInstance3D

func is_boss() -> bool:
	return true

func stats() -> Array:
	return [320, 1.0, 1.3, "6a4a3a"]

func eye_height() -> float:
	return 2.3

func build_body(light: Dictionary) -> void:
	var body = Geo.box(visual, Vector3(0, 1.3, 0), Vector3(2.4, 2.6, 2.2), color, light.foe_body)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.cylinder(visual, Vector3(0, 2.9, 0), .45, .8, Color("4a3a2e"), light.foe_body)
	heart = Geo.sphere(visual, Vector3(0, 1.1, 1.05), .45, Color("ff8a3a"), 2.6)
	door = Geo.box(visual, Vector3(0, 1.1, 1.15), Vector3(1.2, 1.3, .12), Color("3a302a"), light.foe_body)

func moves() -> bool:
	return false

func turns() -> bool:
	return false

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z) + PI, delta * 2.0)
	door_time -= delta
	if door_time <= 0:
		if door_open: close_door()
		else: open_door()
	door.position.x = lerpf(door.position.x, 1.25 if door_open else 0.0, delta * 8.0)
	heart.scale = Vector3.ONE * (1.0 + .08 * sin(age * 6.0))
	for i in range(lobs.size() - 1, -1, -1):
		lobs[i].time -= delta
		if lobs[i].time <= 0: land(i)
	for i in range(fire_rings.size() - 1, -1, -1):
		if spread_ring(fire_rings[i], delta): fire_rings.remove_at(i)
	lob_cooldown -= delta * tempo()
	ring_cooldown -= delta * tempo()
	if lob_cooldown <= 0:
		lob_cooldown = 2.4 if hp <= max_hp * .5 else 3.0
		for i in 3:
			var at: Vector3 = game.player.global_position + Vector3(rng.randf_range(-2.2, 2.2), 0, rng.randf_range(-2.2, 2.2)) * (0.0 if i == 0 else 1.0)
			at.y = 0
			lobs.append({"at": at, "time": 1.0 + i * .2, "mark": Geo.ring(game.scene_root, at + Vector3(0, .05, 0), 1.0, Color("ff8a4a"), .05)})
	if ring_cooldown <= 0:
		ring_cooldown = 6.5
		var node = Geo.ring(game.scene_root, Vector3(global_position.x, .08, global_position.z), 1.0, Color("ff9a4a"), .05)
		fire_rings.append({"node": node, "radius": 1.0, "hit": false})
	return Vector3.ZERO

func open_door() -> void:
	door_open = true
	quenched = false
	door_time = OPEN
	Audio.play_sound("door", .7)
	if hp <= max_hp * .5:
		for side in [-1, 1]: game.spawn_enemy(global_position + Vector3(side * 2.4, 0, 1.6), "cinderling")

func close_door() -> void:
	door_open = false
	door_time = SHUT * (.8 if hp <= max_hp * .5 else 1.0)

func land(index: int) -> void:
	var lob: Dictionary = lobs[index]
	lobs.remove_at(index)
	if is_instance_valid(lob.mark): lob.mark.queue_free()
	Effects.burst(game.scene_root, lob.at + Vector3.UP * .3, Color("ff9a4a"), 8, 1.2)
	if game.residue: game.residue.scorch(lob.at, 1.0)
	if game.player.global_position.distance_to(lob.at) < 1.0: game.player.hurt(1.0, lob.at)

## Returns true once the ring has spread past its reach. Dash through it.
func spread_ring(ring_state: Dictionary, delta: float) -> bool:
	ring_state.radius += FIRE_RING_SPEED * delta
	ring_state.node.scale = Vector3(ring_state.radius, 1, ring_state.radius)
	var to: Vector3 = game.player.global_position - global_position
	to.y = 0
	if not ring_state.hit and absf(to.length() - ring_state.radius) < .3:
		ring_state.hit = true
		game.player.hurt(1.0, global_position)
	if ring_state.radius > FIRE_RING_REACH:
		ring_state.node.queue_free()
		return true
	return false

func damage_scale(cause: String) -> float:
	if cause == "dot": return .5
	return HEART if door_open else CLOSED

func apply_status(effects: Dictionary) -> void:
	super.apply_status(effects)
	# Chill on the open heart holds the door open a little longer.
	if door_open and not quenched and float(effects.get("chill", 0)) > 0:
		quenched = true
		door_time += QUENCH
		Effects.burst(game.scene_root, heart.global_position, Color("cfe0f5"), 10, 1.2)

func on_death() -> void:
	for lob in lobs:
		if is_instance_valid(lob.mark): lob.mark.queue_free()
	for ring_state in fire_rings:
		if is_instance_valid(ring_state.node): ring_state.node.queue_free()
	lobs.clear()
	fire_rings.clear()
