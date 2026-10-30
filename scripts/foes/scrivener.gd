extends DungeonEnemy
## The archivist's clerk. It writes glyphs on the floor where the player
## stands; a moment later a glyph flares and leaves ink behind that drags at
## the feet. Ink burns away.
const FLARE := 1.1
const REACH := 1.0
const INK := 1.3
var glyphs: Array = []

func stats() -> Array:
	return [30, 1.3, .45, "6b6f88"]

func eye_height() -> float:
	return .9

func build_body(light: Dictionary) -> void:
	var body = Geo.cylinder(visual, Vector3(0, .55, 0), .34, 1.1, color, light.foe_body, .22)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.box(visual, Vector3(.38, .9, -.1), Vector3(.05, .5, .05), Color("d8c8a0"), light.foe_body)

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	for i in range(glyphs.size() - 1, -1, -1):
		glyphs[i].time -= delta
		if glyphs[i].time <= 0: flare(i)
	var move = steer_toward(game.player.global_position, delta)
	if has_sight:
		move = direction * (1.0 if distance > 6.5 else (-.6 if distance < 4.0 else 0.0))
		if timer <= 0 and glyphs.size() < 2:
			timer = 2.6
			write(game.player.global_position)
	return move

func write(at: Vector3) -> void:
	at.y = 0
	var mark = Node3D.new()
	game.scene_root.add_child(mark)
	mark.position = at
	Geo.ring(mark, Vector3(0, .05, 0), REACH, Color("8a8fc0"), .05)
	for angle in [0.0, PI / 3, -PI / 3]:
		var stroke = Geo.box(mark, Vector3(0, .05, 0), Vector3(REACH * 1.5, .01, .05), Color("8a8fc0"), .6)
		stroke.rotation.y = angle
	glyphs.append({"at": at, "time": FLARE, "mark": mark})
	visual.scale = Vector3(1.15, .9, 1.15)

func flare(index: int) -> void:
	var glyph: Dictionary = glyphs[index]
	glyphs.remove_at(index)
	if is_instance_valid(glyph.mark): glyph.mark.queue_free()
	Effects.ring_burst(game.scene_root, glyph.at, Color("8a8fc0"), REACH)
	if game.residue: game.residue.add("ink", glyph.at, INK)
	if game.player.global_position.distance_to(glyph.at) < REACH: game.player.hurt(1.0, glyph.at)

func on_death() -> void:
	for glyph in glyphs:
		if is_instance_valid(glyph.mark): glyph.mark.queue_free()
	glyphs.clear()
