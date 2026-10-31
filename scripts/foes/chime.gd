extends DungeonEnemy
## A bell on a frame. Every few seconds it rings, and the ring travels: a
## widening circle with gaps in it that hurts whoever it passes over. Dash
## through it, or slip through a gap.
const RING_SPEED := 4.2
const RING_REACH := 9.0
const SEGMENTS := 28
const GAPS := 3
const GAP_WIDTH := 2
var rings: Array = []

func stats() -> Array:
	return [30, .8, .48, "c9a860"]

func eye_height() -> float:
	return 1.0

func build_body(light: Dictionary) -> void:
	for side in [-1, 1]:
		Geo.box(visual, Vector3(side * .4, .7, 0), Vector3(.08, 1.4, .08), Color("6a5a3a"), light.foe_body)
	Geo.box(visual, Vector3(0, 1.4, 0), Vector3(.9, .08, .08), Color("6a5a3a"), light.foe_body)
	var bell = Geo.cylinder(visual, Vector3(0, 1.0, 0), .3, .5, color, light.foe_body, .14)
	bell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	for i in range(rings.size() - 1, -1, -1):
		if update_ring(rings[i], delta): rings.remove_at(i)
	var move = steer_toward(game.player.global_position, delta)
	if has_sight:
		move = direction * (1.0 if distance > 6.5 else (-.5 if distance < 4.0 else 0.0))
		if timer <= 0:
			timer = 3.4
			ring()
	return move

func ring() -> void:
	var node = Node3D.new()
	game.scene_root.add_child(node)
	node.position = Vector3(global_position.x, global_position.y + .1 if game.first_person else .1, global_position.z)
	var open := {}
	for g in GAPS:
		var start = rng.randi_range(0, SEGMENTS - 1)
		for k in GAP_WIDTH: open[(start + k) % SEGMENTS] = true
	var pieces: Array = []
	for i in SEGMENTS:
		if open.has(i): continue
		var piece = Geo.box(node, Vector3.ZERO, Vector3(.1, .14, .5), Color("f0d890"), 1.4)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.set_meta("index", i)
		pieces.append(piece)
	rings.append({"node": node, "radius": .6, "open": open, "pieces": pieces, "hit": false})
	Audio.play_sound("coin", .5)
	visual.scale = Vector3(1.2, .9, 1.2)

## Returns true once the ring has spread past its reach.
func update_ring(ring_state: Dictionary, delta: float) -> bool:
	ring_state.radius += RING_SPEED * delta
	for piece in ring_state.pieces:
		var angle = TAU * float(piece.get_meta("index")) / SEGMENTS
		piece.position = Vector3(cos(angle), 0, sin(angle)) * ring_state.radius
		piece.rotation.y = -angle
		piece.scale = Vector3(1, 1, ring_state.radius * TAU / SEGMENTS / .5)
	var to: Vector3 = game.player.global_position - ring_state.node.position
	to.y = 0
	if (not game.first_person or absf(game.player.position.y - ring_state.node.position.y) < .4) and not ring_state.hit and absf(to.length() - ring_state.radius) < .3:
		var index = posmod(roundi(atan2(to.z, to.x) / TAU * SEGMENTS), SEGMENTS)
		if not ring_state.open.has(index):
			ring_state.hit = true
			game.player.hurt(1.0, ring_state.node.position)
	if ring_state.radius > RING_REACH or not alive:
		ring_state.node.queue_free()
		return true
	return false

func on_death() -> void:
	for ring_state in rings:
		if is_instance_valid(ring_state.node): ring_state.node.queue_free()
	rings.clear()
