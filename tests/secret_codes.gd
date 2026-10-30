extends SceneTree
## Stateful regression for the all-relics and Paint Sprayer secrets and their
## hidden mobile entry.
var checks = 0
var failures = 0
var game
var run
var catalog

func _initialize() -> void:
	call_deferred("test_secret_codes")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func check_all_relics(expected_extra := 0) -> void:
	check(run.inventory.size() == catalog.items.size() + expected_extra, "grant contains all relics and preserves existing stacks")
	for item in catalog.items:
		check(item.id in run.inventory, "relic granted: " + item.id)
		check(item.id in run.profile.discovered, "relic discovered: " + item.id)

func test_secret_codes() -> void:
	run = root.get_node("Run")
	catalog = root.get_node("Content")
	check(run.has_method("grant_all_relics"), "run exposes a bulk relic grant")
	if not run.has_method("grant_all_relics"):
		quit(1)
		return
	var inactive_inventory = run.inventory.duplicate()
	var inactive_profile = JSON.stringify(run.profile)
	check(run.grant_all_relics() == 0, "no-active-run bulk grant is rejected")
	check(run.inventory == inactive_inventory and JSON.stringify(run.profile) == inactive_profile,
		"inactive grant leaves inventory and profile unchanged")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	check(not game.redeem_secret_code("ALLRELICS"), "secret cannot be redeemed from the title")
	game.start_run("needle", 140026, false)
	game.pause_game()
	var original_seed: int = run.seed_value
	var original_coins: int = run.coins
	var original_rooms = JSON.stringify(run.rooms)
	var original_stats = run.stats.duplicate()
	run.hp = 3
	check(not game.redeem_secret_code("ALLRELIC"), "partial code is rejected")
	check(not game.redeem_secret_code("WRONG"), "incorrect code is rejected")
	check(run.inventory.is_empty() and run.stats == original_stats, "incorrect codes do not alter run state")
	check(game.redeem_secret_code("  allrelics\n"), "secret accepts case differences and surrounding whitespace")
	check_all_relics()
	check(run.weapon_id == "needle" and run.coins == original_coins and run.seed_value == original_seed,
		"relic secret preserves weapon, currency and seed")
	check(JSON.stringify(run.rooms) == original_rooms, "relic secret preserves room progress")
	check(run.stats.homing > 0 and run.stats.split > 0 and run.stats.chain > 0 and run.stats.heal_each_room > 0,
		"granted relics rebuild live combat effects")
	var expected_hp = minf(run.stats.max_hp, 3.0 + maxf(0, run.stats.max_hp - original_stats.max_hp))
	check(is_equal_approx(run.hp, expected_hp), "grant heals added maximum health without exceeding its cap")
	check(game.player.orbit_meshes.size() == mini(8, int(run.stats.orbitals)), "main immediately refreshes orbitals")
	check(game.player.shield >= int(run.stats.shield), "main immediately grants relic guards")
	var granted_inventory = run.inventory.duplicate()
	var granted_stats = run.stats.duplicate()
	var granted_hp: float = run.hp
	game.player.shield = 0
	var orbital_ids = game.player.orbit_meshes.map(func(mesh): return mesh.get_instance_id())
	check(game.redeem_secret_code("ALLRELICS"), "repeated valid code is accepted")
	check(run.inventory == granted_inventory and run.stats == granted_stats and run.hp == granted_hp,
		"repeat does not duplicate relics, change stats, or heal again")
	check(game.player.shield == 0, "repeat does not refill spent relic guards")
	check(game.player.orbit_meshes.map(func(mesh): return mesh.get_instance_id()) == orbital_ids,
		"repeat does not rebuild existing orbital actors")
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://run.json"))
	check(saved.inventory == granted_inventory and saved.hp == granted_hp, "grant is persisted in run checkpoint")
	var saved_profile = JSON.parse_string(FileAccess.get_file_as_string("user://profile.json"))
	check(saved_profile.discovered.size() == catalog.items.size(), "all discoveries persist to the profile")
	run.inventory.clear()
	run.hp = 1
	check(run.load_run(), "granted checkpoint loads")
	check(run.inventory == granted_inventory and run.stats == granted_stats and run.hp == granted_hp,
		"all relics, rebuilt effects and health survive save/load")
	# The bulk operation is idempotent while retaining legitimately stacked relics.
	game.start_run("candle", 140027, false)
	run.gain_item("warm_wax")
	run.gain_item("warm_wax")
	check(run.grant_all_relics() == catalog.items.size() - 1, "bulk grant reports the number of missing relics added")
	check_all_relics(1)
	check(run.inventory.count("warm_wax") == 2, "existing relic stacks are preserved")
	var stack_stats = run.stats.duplicate()
	check(run.grant_all_relics() == 0, "complete collection receives no extra items")
	check(run.inventory.count("warm_wax") == 2 and run.stats == stack_stats, "repeat preserves existing stacks and effects")
	# Repair discovery metadata even when the inventory is already complete.
	var complete_inventory = run.inventory.duplicate()
	run.profile.discovered.clear()
	run.save_profile()
	check(run.grant_all_relics() == 0, "discovery repair adds no duplicate relics")
	check(run.profile.discovered.size() == catalog.items.size(), "complete inventory repairs missing profile discoveries")
	var repaired_profile = JSON.parse_string(FileAccess.get_file_as_string("user://profile.json"))
	check(repaired_profile.discovered.size() == catalog.items.size(), "repaired discoveries are saved without granting new items")
	check(run.inventory == complete_inventory and run.stats == stack_stats, "discovery repair leaves inventory stacks and stats unchanged")
	# The hidden title trigger is usable through the native GUI on mobile too.
	game.start_run("candle", 140028, false)
	game.pause_game()
	await process_frame
	# Rapid screen transitions can let Godot rename queued/replacement controls.
	# Test the native button's connected action rather than its transient name.
	var triggers = game.ui.content.get_children().filter(func(child):
		return child is Button and child.is_connected("pressed", Callable(game.ui, "register_secret_tap")))
	check(triggers.size() == 1, "pause title has a native touch-compatible trigger")
	for tap in 4:
		if not triggers.is_empty(): triggers[0].pressed.emit()
	check(game.ui.mode == "pause", "fewer than five title taps keep the entry hidden")
	if not triggers.is_empty(): triggers[0].pressed.emit()
	await process_frame
	check(game.ui.mode == "secret" and game.paused, "five title taps open the secret entry while paused")
	check(is_instance_valid(game.ui.secret_field) and game.ui.secret_field is LineEdit,
		"secret entry provides a native text field for the Android keyboard")
	game.ui.submit_secret_code("NOPE")
	check(game.ui.mode == "secret" and game.paused and run.inventory.is_empty(), "invalid submission stays paused without granting items")
	check(not game.ui.secret_feedback.is_empty(), "invalid submission provides feedback")
	game.ui.close_secret_code()
	check(game.ui.mode == "pause" and game.paused and run.inventory.is_empty(), "cancel returns to pause without granting relics")
	for tap in 5: game.ui.register_secret_tap()
	game.ui.submit_secret_code("allrelics")
	check(game.ui.mode == "play" and not game.paused, "valid mobile entry resumes the run")
	check(run.inventory.size() == catalog.items.size(), "valid mobile entry grants every relic")
	# Desktop typing uses only the paused screen and ignores key auto-repeat.
	game.start_run("candle", 140029, false)
	game.pause_game()
	var echo_event = InputEventKey.new()
	echo_event.pressed = true
	echo_event.echo = true
	echo_event.unicode = "A".unicode_at(0)
	game.ui._input(echo_event)
	for character in "ALLRELICS":
		var key = InputEventKey.new()
		key.pressed = true
		key.unicode = character.unicode_at(0)
		game.ui._input(key)
	check(run.inventory.size() == catalog.items.size() and game.ui.mode == "play" and not game.paused,
		"typing the desktop secret while paused grants all relics and resumes")
	game.start_run("candle", 140030, false)
	for character in "ALLRELICS":
		var key = InputEventKey.new()
		key.pressed = true
		key.unicode = character.unicode_at(0)
		game.ui._input(key)
	check(run.inventory.is_empty(), "normal gameplay typing cannot accidentally activate the paused-only secret")
	await test_paint_sprayer()
	game.return_to_title()
	check(not game.redeem_secret_code("ALLRELICS"), "secret stays inactive after returning to title")
	check(not game.redeem_secret_code("PAINTSPRAYER"), "sprayer secret stays inactive after returning to title")
	game.queue_free()
	await process_frame
	await process_frame
	print("EMBERKEEP SECRET CODE TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

## PAINTSPRAYER skips the painting collection for the weapon alone.
func test_paint_sprayer() -> void:
	var collection = root.get_node("Collection")
	var unlocks_before = run.profile.unlocks.duplicate()
	var paintings_before = run.profile.paintings.duplicate()
	run.profile.unlocks.clear()
	run.save_profile()
	game.start_run("paint_sprayer", 140031, false)
	var fallback: String = run.weapon_id
	check(fallback != "paint_sprayer", "a locked Paint Sprayer cannot start a run before the code")
	game.pause_game()
	var coins: int = run.coins
	var inventory = run.inventory.duplicate()
	var rooms = JSON.stringify(run.rooms)
	check(not game.redeem_secret_code("PAINTSPRAY"), "partial sprayer code is rejected")
	check(not collection.weapon_available("paint_sprayer") and run.weapon_id == fallback, "rejected codes leave the weapon locked and out of hand")
	check(game.redeem_secret_code("  paintsprayer\n"), "sprayer secret accepts case differences and surrounding whitespace")
	check(run.weapon_id == "paint_sprayer", "sprayer secret puts the weapon in hand")
	check(collection.weapon_available("paint_sprayer") and run.profile.unlocks.count("paint_sprayer") == 1,
		"sprayer secret unlocks the weapon for later runs")
	check("paint_sprayer" in collection.available_weapons().map(func(weapon): return weapon.id), "the unlocked sprayer joins the starters")
	check(run.profile.paintings == paintings_before, "sprayer secret discovers no paintings")
	check(run.inventory == inventory and run.coins == coins and run.seed_value == 140031 and JSON.stringify(run.rooms) == rooms,
		"sprayer secret leaves relics, coins, seed and rooms alone")
	var saved_profile = JSON.parse_string(FileAccess.get_file_as_string("user://profile.json"))
	check("paint_sprayer" in saved_profile.unlocks, "the unlock is saved to the profile")
	var saved_run = JSON.parse_string(FileAccess.get_file_as_string("user://run.json"))
	check(saved_run.weapon == "paint_sprayer", "the weapon in hand is saved with the run")
	check(game.redeem_secret_code("PAINTSPRAYER") and run.profile.unlocks.count("paint_sprayer") == 1,
		"repeating the sprayer secret never duplicates the unlock")
	# Typed on a keyboard while paused, in a run holding something else.
	game.start_run("needle", 140032, false)
	game.pause_game()
	for character in "PAINTSPRAYER":
		var key = InputEventKey.new()
		key.pressed = true
		key.unicode = character.unicode_at(0)
		game.ui._input(key)
	check(run.weapon_id == "paint_sprayer" and game.ui.mode == "play" and not game.paused,
		"typing the sprayer secret while paused equips it and resumes")
	# The hidden mobile entry takes it too.
	game.start_run("needle", 140033, false)
	game.pause_game()
	await process_frame
	for tap in 5: game.ui.register_secret_tap()
	game.ui.submit_secret_code("PaintSprayer")
	check(run.weapon_id == "paint_sprayer" and game.ui.mode == "play" and not game.paused, "valid mobile entry equips the sprayer and resumes")
	check(run.inventory.is_empty(), "the sprayer secret grants no relics")
	game.start_run("paint_sprayer", 140034, false)
	check(run.weapon_id == "paint_sprayer", "an unlocked sprayer can start a new run")
	run.profile.unlocks = unlocks_before
	run.save_profile()
