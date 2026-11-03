extends SceneTree
## Opt-in native capture of combinations: foes carrying elements, a reaction
## word, a frozen foe, the journal's combinations and a reliquary card's
## hint. Needs a display (or Xvfb) and EMBERKEEP_SYNERGY_CAPTURE set to an
## output directory.
var game
var run

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func frames(count: int) -> void:
	for i in count: await process_frame

func shot(out: String, label: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	if out != "": image.save_png(out.path_join("synergy_%s.png" % label))
	print("SYNERGY CAPTURE %s" % label)

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_SYNERGY_CAPTURE")
	run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	game.start_run("candle", 31609250, false)
	await frames(40)
	game.set_physics_process(false)
	game.fps.yaw = 0.0
	game.fps.pitch = -.05
	var foes: Array = []
	for x in [-1.8, 0.0, 1.8]:
		var foe = game.spawn_enemy(game.player.position + Vector3(x, 0, -4.0), "brute")
		foe.max_hp = 500.0
		foe.hp = 500.0
		foes.append(foe)
	foes[0].apply_status({"chill": 1.0, "poison": 1.0})
	foes[2].apply_status({"wet": 1.0, "element": "storm"})
	foes[1].apply_status({"wet": 1.0})
	foes[1].age += .3
	foes[1].apply_status({"chill": 1.0, "hit": 12.0})
	foes[0].age += .3
	foes[0].apply_status({"burn": 1.0, "hit": 12.0})
	run.inventory = ["chili_oil", "firecracker", "copper_wire", "skipping_stone", "winter_mint"]
	await frames(6)
	shot(out, "reactions")
	game.ui.journal_tab = "combos"
	game.ui.journal_page = 0
	game.ui.show_screen("journal")
	await frames(6)
	shot(out, "journal")
	run.inventory = ["chili_oil"]
	game.ui.offers = [{"kind": "item", "id": "firecracker", "price": 0}, {"kind": "item", "id": "living_coal", "price": 0}, {"kind": "item", "id": "warm_wax", "price": 0}]
	game.ui.shop = false
	game.ui.dark = false
	game.ui.show_screen("reward")
	await frames(6)
	shot(out, "card")
	game.queue_free()
	await frames(3)
	quit(0)
