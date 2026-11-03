extends SceneTree
## Opt-in native capture of the first-person spellbook: bare, with a few
## relics, and with every relic, so each relic's mark can be seen on the book
## or the arm. Needs a display (or Xvfb) and EMBERKEEP_SPELLBOOK_CAPTURE set
## to an output directory; prints SPELLBOOK CAPTURE lines.
var game
var run
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

func frames(count: int) -> void:
	for i in count: await process_frame

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_SPELLBOOK_CAPTURE")
	run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	game.start_run("candle", 31609250, false)
	await frames(30)
	var sets := {"bare": [], "few": ["warm_wax", "heartstone", "sugar_rush", "lucky_penny", "quick_wick", "sharp_spark"],
		"many": ["warm_wax", "forked_wick", "heartstone", "living_coal", "sugar_rush", "warm_soup", "lucky_penny", "moon_shard", "firefly_jar",
			"seeking_spark", "storm_lantern", "winter_mint", "chili_oil", "side_candles", "long_match", "brass_barrel", "dried_rose",
			"quick_wick", "pocket_change", "sharp_spark", "blood_orange", "red_thread", "amber_guard", "second_wind", "cinder_steps", "old_clock", "moth_wings", "thorn_crown"],
		"dark": ["black_wick", "hollow_crown", "widows_lantern", "grave_glass", "dark_star", "starving_flame", "night_moth", "ash_mantle"]}
	if OS.get_environment("EMBERKEEP_SPELLBOOK_SET") != "": sets = {"only": OS.get_environment("EMBERKEEP_SPELLBOOK_SET").split(",")}
	for label in sets:
		run.inventory = sets[label].duplicate()
		game.fps.yaw = 2.4
		game.fps.pitch = -.12
		await frames(12)
		var marks: Node3D = game.fps.weapon_shape.get_node("Marks")
		check(sets[label].is_empty() or marks.get_child_count() > 0, label + " relics add marks to the spellbook")
		var image: Image = root.get_viewport().get_texture().get_image()
		if out != "": image.save_png(out.path_join("spellbook_%s.png" % label))
		print("SPELLBOOK CAPTURE %s relics=%d marks=%d" % [label, sets[label].size(), marks.get_child_count()])
	# A relic waiting in its reliquary, just ahead.
	game.fps.yaw = 0.0
	game.fps.pitch = -0.18
	var ahead: Vector3 = game.player.global_position + Vector3(0, 0, -2.4)
	game.make_marker("treasure", Vector3(ahead.x, game.room.floor_height(ahead), ahead.z))
	await frames(10)
	check(game.marker_visual != null and game.marker_visual.name == "Relic", "a relic waits in a reliquary")
	var shrine: Image = root.get_viewport().get_texture().get_image()
	if out != "": shrine.save_png(out.path_join("spellbook_reliquary.png"))
	game.remove_marker()
	# Spells in flight: a spread weapon cast for a moment, then caught mid-air.
	var forge = load("res://scripts/items/forge.gd")
	for seed_value in range(1, 40):
		var id: String = forge.id_for(seed_value, 0, 1)
		if forge.lookup(id).pattern in ["fan", "spiral", "ring"]:
			run.weapon_id = id
			break
	game.paused = false
	game.ui.show_screen("play")
	game.fps.yaw = 2.0
	game.fps.pitch = 0.0
	game.player.fire_cooldown = 0.0
	for i in 40:
		game.ui.fire_touch = 1
		await physics_frame
	check(game.shots.size() > 2, "casting fills the air with spells")
	var spells: Image = root.get_viewport().get_texture().get_image()
	if out != "": spells.save_png(out.path_join("spellbook_casting.png"))
	game.ui.fire_touch = -1
	print("SPELLBOOK CAPTURE casting spells=%d weapon=%s" % [game.shots.size(), run.weapon().get("pattern", "")])
	print("SPELLBOOK CAPTURE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
