extends SceneTree
## Opt-in native capture of the touch controls: play with the dash cooling
## (its arc under the crosshair) and the screen for arranging the controls.
## Needs a display (or Xvfb) and EMBERKEEP_TOUCH_CAPTURE set to an output
## directory.
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func frames(count: int) -> void:
	for i in count: await process_frame

func shot(out: String, label: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	if out != "": image.save_png(out.path_join("touch_%s.png" % label))
	print("TOUCH CAPTURE %s" % label)

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_TOUCH_CAPTURE")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	settings.set_value("touch", true)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	game.start_run("candle", 7072, false)
	await frames(40)
	game.player.dash_cooldown = 0
	game.player.dash()
	await frames(3)
	shot(out, "play")
	game.ui.open_layout()
	game.ui.layout_selected = "fire"
	await frames(4)
	shot(out, "layout")
	settings.set_value("touch", false)
	game.queue_free()
	await frames(3)
	quit(0)
