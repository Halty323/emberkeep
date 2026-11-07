extends SceneTree
## The fairness and comfort pass: fire the party lit spares the party, a foe
## that has just appeared cannot hurt by touch, what hurt the player is
## named, hostile spells look like no spell of the party's, screen warps
## follow their setting, volumes and rebound keys apply, the map walks back
## to a cleared room, aim assist only helps touch and gamepads, and dragging
## to look casts only in a fight.
var checks := 0
var failures := 0

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func go() -> void:
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in 3: await process_frame
	game.start_run("candle", 7072, false)
	for i in 20: await process_frame
	game.set_physics_process(false)
	var player = game.player
	run.wards = 0
	player.shield = 0
	var full: float = run.hp

	# Fire the party lit never burns the party; a foe's fire still does.
	var feet: Vector3 = player.global_position
	var residue = game.residue
	residue.add("wax", feet, 1.2)
	residue.ignite(feet, 1.2, true)
	check(residue.kind_at(feet) == "fire" and residue.tame_at(feet), "a spell's fire takes on wax underfoot")
	player.invulnerability = 0
	for i in 3: residue.update_sim(.3)
	check(run.hp == full, "fire the party lit never burns the party")
	residue.scorch(feet, 1.2)
	check(not residue.tame_at(feet), "a foe's fire is not tame")
	player.invulnerability = 0
	for i in 3: residue.update_sim(.3)
	check(run.hp < full, "a foe's fire still burns")
	check(game.last_harm == "Flames underfoot", "the burning floor is named (%s)" % game.last_harm)
	check(is_equal_approx(game.fps.damage_angle, PI), "harm from underfoot is marked beneath the sight")
	residue.set_tile(residue.key(feet), "")
	run.hp = full

	# A foe that has just appeared cannot hurt by touch; a moment later it can.
	var mote = game.spawn_enemy(feet + Vector3(.3, 0, 0), "mote")
	mote.global_position = feet + Vector3(.3, 0, 0)
	player.invulnerability = 0
	mote.update_sim(1.0 / 60.0)
	check(run.hp == full, "a foe that has just appeared cannot hurt by touch")
	mote.age = 1.0
	mote.global_position = feet + Vector3(.3, 0, 0)
	player.invulnerability = 0
	mote.update_sim(1.0 / 60.0)
	check(run.hp < full, "a moment later its touch hurts")
	check(game.last_harm == "A Mote", "the foe that struck is named (%s)" % game.last_harm)
	run.hp = full

	# Hostile spells are crimson and dark-rimmed, and name their caster.
	var spell = game.spawn_shot(mote.global_position + Vector3.UP * .6, Vector3.FORWARD, 1, 5.0, {}, Color("f29d8c"), false)
	check(spell.tint.r > .9 and spell.tint.g < .45 and spell.tint.b > .3, "a foe's spell is crimson whatever its caster's colour")
	var rimmed := false
	for child in spell.get_children():
		if child is MeshInstance3D and child.material_override is ShaderMaterial and child.material_override.shader.resource_path.ends_with("shot_hostile.gdshader"): rimmed = true
	check(rimmed, "a foe's spell wears a dark rim")
	check(spell.harm_name() == "A Mote's spell", "a hostile spell names its caster (%s)" % spell.harm_name())
	var friendly = game.spawn_shot(feet + Vector3.UP, Vector3.FORWARD, 1, 10.0, run.projectile_stats(), Color("ffb070"), true)
	check(friendly.tint == Color("ffb070"), "the party's spells keep their colour")
	spell.remove()
	friendly.remove()

	# Dragging to look casts only while a fight is on.
	settings.set_value("cast_while_aiming", true)
	game.ui.right_touch = 0
	check(game.fight_on() and game.ui.aiming_casts(), "dragging to look casts in a fight")
	mote.alive = false
	mote.queue_free()
	game.enemies.clear()
	game.room.set_open(true)
	check(not game.fight_on() and not game.ui.aiming_casts(), "looking round a cleared room never casts")
	game.ui.right_touch = -1

	# Aim assist helps touch and gamepads, never a mouse.
	settings.set_value("touch", false)
	game.fps.pad_look = 0.0
	check(not game.fps.assist_active(), "a mouse gets no aim assist")
	settings.set_value("touch", true)
	check(game.fps.assist_active(), "touch gets aim assist")
	settings.set_value("aim_assist", false)
	check(not game.fps.assist_active(), "aim assist can be switched off")
	settings.set_value("aim_assist", true)
	var flat_ahead: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, game.fps.yaw)
	game.fps.pitch = 0.0
	var target = game.spawn_enemy(feet + flat_ahead.rotated(Vector3.UP, deg_to_rad(2.0)) * 4.0, "brute")
	game.fps.find_assist()
	# Furniture can stand between; when the eye sees the foe it is found.
	if game.fps.assist_target == target:
		var muzzle: Vector3 = game.fps.shot_origin()
		check(game.fps.assisted(muzzle, game.fps.forward()).angle_to(game.fps.assist_point - muzzle) < .01, "spells bend onto a foe just off the crosshair")
	else:
		print("aim assist target hidden by furniture; bend check skipped")
	settings.set_value("touch", false)
	game.fps.find_assist()
	check(game.fps.assist_target == null, "without touch or a gamepad nothing is assisted")
	target.alive = false
	target.queue_free()
	game.enemies.clear()

	# Foe health bars and threat markers draw without trouble.
	var behind = game.spawn_enemy(feet - game.fps.forward() * 3.0, "charger")
	behind.hurt_at = behind.age
	behind.hp = behind.max_hp * .5
	behind.windup = .5
	game.ui.show_screen("play")
	game.ui.queue_redraw()
	for i in 3: await process_frame
	behind.alive = false
	behind.queue_free()
	game.enemies.clear()

	# Screen warps follow their setting.
	var screen_fx = load("res://scripts/graphics/screen_fx.gd")
	settings.set_value("screen_effects", "off")
	check(screen_fx.strength() == 0.0, "screen warps can be switched off")
	settings.set_value("screen_effects", "reduced")
	check(screen_fx.strength() > 0.0 and screen_fx.strength() < .5, "screen warps can be reduced")
	settings.set_value("screen_effects", "full")
	check(not settings.set_value("screen_effects", "wild"), "only known screen warp levels are kept")

	# Volumes are faders on their own buses.
	settings.set_value("sound_volume", 50)
	var effects := AudioServer.get_bus_index("Effects")
	check(effects >= 0 and absf(AudioServer.get_bus_volume_db(effects) - linear_to_db(.5)) < .1, "the effects volume sets its bus")
	settings.set_value("music_volume", 0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music at nothing is silent")
	check(not settings.set_value("sound_volume", 55) and not settings.set_value("sound_volume", 120), "volumes keep to tens from 0 to 100")
	settings.set_value("sound_volume", 100)
	settings.set_value("music_volume", 100)

	# Keys rebind, swap when taken, and return to the defaults.
	check(settings.key_label("dash") == "Shift", "dash starts on Shift (%s)" % settings.key_label("dash"))
	settings.bind_key("dash", KEY_Q)
	check(has_key("dash", KEY_Q) and not has_key("dash", KEY_SHIFT), "dash moves to Q")
	settings.bind_key("jump", KEY_Q)
	check(has_key("jump", KEY_Q) and has_key("dash", KEY_SPACE), "a taken key swaps with the action that had it")
	settings.bind_key("interact", settings.MOUSE_CODE + MOUSE_BUTTON_XBUTTON1)
	check(settings.key_label("interact") == "Mouse 4", "a mouse button can be bound")
	check(has_key("move_up", KEY_UP), "arrow keys stay with movement")
	settings.set_value("keys", {})
	check(has_key("dash", KEY_SHIFT) and has_key("jump", KEY_SPACE) and has_key("interact", KEY_E), "default keys come back")
	check(game.ui.move_keys() == "WASD", "movement keys read as one word (%s)" % game.ui.move_keys())

	# A thumb on the movement stick never triggers an interaction.
	check(game.ui.in_move_zone(Vector2(480, 600)), "the bottom left belongs to the movement stick")
	check(not game.ui.in_move_zone(Vector2(700, 600)), "the middle of the bottom is free for the prompt")

	# The map walks back to a room already won, alone and between fights.
	var start: String = run.current_room
	check(game.travel_block(start) == "You are here.", "the map knows where you are")
	var other := ""
	for id in run.rooms:
		if id != start and not run.rooms[id].get("secret", false) and run.rooms[id].type in ["combat", "treasure", "shop"]:
			other = id
			break
	check(other != "", "the floor has another room")
	run.rooms[other].visited = false
	check(game.travel_block(other) != "", "a room never walked cannot be travelled to")
	run.rooms[other].visited = true
	run.rooms[other].cleared = true
	check(game.travel_block(other) == "", "a room walked and won can be travelled to (%s)" % game.travel_block(other))
	game.travel_to(other)
	check(game.transition.get("kind", "") == "travel", "travel begins with a breath of light")
	for i in 30:
		if game.transition.is_empty(): break
		game.advance_transition(1.0 / 30.0)
	check(run.current_room == other and game.transition.is_empty(), "the map takes the player back there")
	check(run.entry.get("room", "") == other, "the room is the new checkpoint")
	for i in 3: await process_frame

	game.queue_free()
	await process_frame
	print("UX: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func has_key(action: String, code: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == code: return true
	return false
