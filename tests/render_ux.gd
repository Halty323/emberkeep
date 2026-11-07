extends SceneTree
## Opt-in native capture of the fairness pass: foes' crimson dark-rimmed
## spells, a hurt foe's health bar, and threat markers for a foe winding up
## out of view and a spell flying in from behind. Needs a display (or Xvfb)
## and EMBERKEEP_UX_CAPTURE set to an output directory.
var game

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func frames(count: int) -> void:
	for i in count: await process_frame

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_UX_CAPTURE")
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	game.start_run("candle", 7072, false)
	await frames(30)
	run.floor_number = 3
	var fight: Array = run.rooms.keys().filter(func(id): return run.rooms[id].type == "combat")
	run.current_room = fight[0]
	run.rooms[fight[0]].cleared = true
	game.enter_room(Vector3(0, 0, 4))
	await frames(30)
	game.set_physics_process(false)
	game.player.place(Vector3(0, game.room.floor_height(Vector3(0, 0, 5)), 5))
	game.fps.yaw = 0.0
	game.fps.pitch = -.05
	await frames(4)
	var feet: Vector3 = game.player.global_position
	# A hurt foe ahead, its health bar showing, casting at the player.
	var ahead = game.spawn_enemy(feet + Vector3(-1.2, 0, -5.0), "spitter")
	ahead.hp = ahead.max_hp * .55
	ahead.hurt_at = ahead.age
	ahead.shoot_fan(Vector3(.2, 0, 1).normalized(), 3, .4)
	# A charger winding up behind and to the right; a spell coming from the left.
	var behind = game.spawn_enemy(feet + Vector3(2.2, 0, 2.5), "charger")
	behind.windup = .6
	game.spawn_shot(feet + Vector3(-5.0, 1.0, .5), Vector3(1, 0, -.1).normalized(), 1, 5.0, {}, Color("f29d8c"), false)
	for spell in game.shots:
		if is_instance_valid(spell): for i in 30: spell.update_sim(1.0 / 60.0)
	game.ui.show_screen("play")
	await frames(6)
	var image: Image = root.get_viewport().get_texture().get_image()
	if out != "": image.save_png(out.path_join("ux_threats.png"))
	print("UX CAPTURE threats")
	game.queue_free()
	await frames(3)
	quit(0)
