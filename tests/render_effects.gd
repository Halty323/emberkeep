extends SceneTree
## Opt-in OpenGL capture of pooled effects: ./tools/render.sh effects
## A frozen moment of bursts, a ring, a beam, scorch marks and ambient motes.
var failures = 0
var game
var run
var Fx

func _initialize() -> void:
	if OS.get_environment("EMBERKEEP_RENDER_TEST") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use tools/render.sh effects with a real display, not --headless.")
		quit(1)
		return
	call_deferred("capture")

func fail(message: String) -> void:
	failures += 1
	push_error("FAIL: " + message)

func capture() -> void:
	run = root.get_node("Run")
	Fx = load("res://scripts/fx.gd")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_run("candle", 4242, false)
	await process_frame
	game.set_physics_process(false)
	var pool = game.room.effects
	Fx.death_puff(Vector3(-3, .5, 1), Color("9f8eb2"), true)
	Fx.prop_dust(Vector3(3, .5, 1), Color("8a6a4a"))
	Fx.chest_open(Vector3(0, 0, -3))
	Fx.ring_burst(null, Vector3(2, 0, -1), Color("a3dacf"), 1.8)
	Fx.beam(null, Vector3(-4, .7, -2), Vector3(-1, .7, -3), Color("c4c2ff"))
	Fx.floor_mark(Vector3(1, 0, 2.5), Color(.08, .06, .05, .55), 1.2, 30.0)
	Fx.dash_dust(Vector3(0, 0, 0), Vector3.RIGHT)
	for i in 6: pool._process(1.0 / 60.0)
	game.paused = true
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var path = OS.get_environment("EMBERKEEP_RENDER_OUTPUT").path_join("effects.png")
	if root.get_texture().get_image().save_png(path) != OK: fail("could not save")
	print("EFFECT_RENDER effects counts=", pool.active_counts(), " image=", path)
	game.end_run(false)
	game.queue_free()
	await process_frame
	print("EMBERKEEP EFFECT RENDER RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
