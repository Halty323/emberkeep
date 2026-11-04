extends SceneTree
## Opt-in native check of the loading screen: a run begins behind it, the
## first room is built a slice at a time and the floor's shaders compile
## before play shows. Needs a display (or Xvfb); EMBERKEEP_LOADING_CAPTURE
## names an output directory for a capture of the screen.
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
	var out := OS.get_environment("EMBERKEEP_LOADING_CAPTURE")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for i in 3: await process_frame
	game.begin_run("candle", 31609250, false)
	await process_frame
	check(game.ui.mode == "loading" and game.loading, "a new run opens on the loading screen")
	var seen := 0.0
	var frames := 0
	while game.loading and frames < 3000:
		await process_frame
		frames += 1
		seen = maxf(seen, game.ui.loading_progress)
		if frames == 6 and out != "": root.get_viewport().get_texture().get_image().save_png(out.path_join("loading.png"))
	check(not game.loading and game.ui.mode == "play" and not game.paused, "play begins once the run is ready (%d frames)" % frames)
	check(seen >= 1.0 and frames > 3, "the bar fills across several frames")
	check(is_instance_valid(game.player) and game.room.data == game.get_node("/root/Run").rooms[game.get_node("/root/Run").current_room], "the first room is the one built behind the screen")
	check(game.prebuilt == null, "the built room was adopted, not left aside")
	game.queue_free()
	for i in 3: await process_frame
	print("LOADING: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
