extends SceneTree
## Opt-in native capture of co-op as a player sees it: a teammate's figure
## in the room with the party's HUD, a fallen teammate being rekindled, this
## player's own fallen view, and the lobby. One process pretends to host a
## party of three (no network is opened). Needs a display (or Xvfb) and
## EMBERKEEP_COOP_CAPTURE set to an output directory.
var game
var run
var session
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

func shot(out: String, label: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	if out != "": image.save_png(out.path_join("coop_%s.png" % label))
	print("COOP CAPTURE %s" % label)

func pretend_party() -> void:
	session.online = true
	session.hosting = true
	session.status = "party"
	session.local_peer_id = 1
	session.roster = {1: {"name": "Ash", "slot": 0, "weapon": "candle"}, 2: {"name": "Wren", "slot": 1, "weapon": "candle"}, 3: {"name": "Moss", "slot": 2, "weapon": "candle"}}

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_COOP_CAPTURE")
	run = root.get_node("Run")
	session = root.get_node("Session")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	pretend_party()
	game.ui.show_screen("lobby")
	await frames(20)
	shot(out, "lobby")
	game.start_run("candle", 31609250, false)
	await frames(40)
	var party = game.party
	var player = game.player
	game.fps.yaw = 0.0
	game.fps.pitch = -.08
	var ahead: Vector3 = player.global_position + Vector3(-.6, 0, -3.2)
	ahead.y = game.room.floor_height(ahead)
	var aside: Vector3 = player.global_position + Vector3(1.6, 0, -4.6)
	aside.y = game.room.floor_height(aside)
	party.states[2] = {"p": ahead, "y": .5, "hp": 4.0, "mhp": 6.0, "down": false, "w": Color("8fd0f0"), "ep": 0}
	party.states[3] = {"p": aside, "y": -.3, "hp": 6.0, "mhp": 8.0, "down": false, "w": Color("b6f0a0"), "ep": 0}
	for id in [2, 3]: party.ensure_member(id).show_state(party.states[id], true)
	check(party.members.size() == 2 and party.climbing(), "two teammates stand in the room")
	await frames(30)
	shot(out, "teammates")
	# A fallen teammate, half rekindled, with the passage notice.
	party.states[3].down = true
	party.members[3].show_state(party.states[3])
	party.revive[3] = .55
	party.members[3].show_revive(.55)
	party.notice = "Waiting for Wren"
	game.fps.yaw = -.35
	await frames(20)
	check(party.members[3].revive_ring.visible, "a fallen teammate shows the rekindling ring")
	shot(out, "rekindling")
	# This player's own fall.
	party.fall()
	party.revive[1] = .3
	await frames(20)
	check(party.downed and run.active, "a fallen player stays in the climb")
	shot(out, "fallen")
	party.rise(true)
	session.online = false
	session.status = ""
	session.roster = {}
	party.reset()
	run.active = false
	game.queue_free()
	await frames(3)
	print("COOP CAPTURE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
