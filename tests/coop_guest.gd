extends SceneTree
## The second player in tests/coop.gd: a real game in its own process that
## joins the host over the loopback network and does what the host's test
## asks (walk into a passage, strike a foe, cast, fall, wait at the stair),
## then reports what it sees. It writes its own checks to a result file.
var game
var port := 0
var result_path := ""
var player_name := "Guest"
var checks := 0
var failures := 0
var notes: Array = []
var done := false

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
		if arg.begins_with("--name="): player_name = arg.trim_prefix("--name=")
	call_deferred("exercise")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		notes.append(label)
		push_error("FAIL (guest): " + label)

func exercise() -> void:
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var session = root.get_node("Session")
	session.message_received.connect(on_message)
	var problem: String = session.join_party("127.0.0.1", player_name, "candle", port)
	check(problem == "", "a join starts: " + problem)
	var started := Time.get_ticks_msec()
	while not done and Time.get_ticks_msec() - started < 150000:
		await process_frame
	check(done, "the host's test finished within its time")
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "notes": notes}))
		file.close()
	session.leave_party()
	game.queue_free()
	for i in 3: await process_frame
	quit(0)

func reply(data: Dictionary) -> void:
	root.get_node("Session").send(1, "test_reply", data)

func report() -> Dictionary:
	var run = root.get_node("Run")
	var drawn := 0
	for shot in game.shots:
		if is_instance_valid(shot) and shot.cosmetic and shot.owner_peer != root.get_node("Session").local_peer_id: drawn += 1
	return {"room": run.current_room, "floor": run.floor_number, "active": run.active, "hp": run.hp, "kills": run.kills,
		"foes": game.party.puppets.size() if run.active else 0, "down": game.party.downed, "drawn": drawn,
		"open": is_instance_valid(game.room) and game.room.open, "rooms": run.rooms.size(), "coins": run.coins,
		"pickups": game.pickups.size() if run.active else 0, "position": game.player.global_position if run.active and is_instance_valid(game.player) else Vector3.ZERO,
		"in_menu": game.in_menu, "mode": game.ui.mode, "figures": figures()}

## The other players' figures as this guest sees them: id -> position.
func figures() -> Dictionary:
	var result := {}
	for id in game.party.members:
		if is_instance_valid(game.party.members[id]): result[id] = game.party.members[id].global_position
	return result

func on_message(_from: int, kind: String, data) -> void:
	if kind != "test" or not data is Dictionary: return
	var run = root.get_node("Run")
	match str(data.get("cmd", "")):
		"report": reply(report())
		"walk":
			var corridors = game.corridors
			if corridors.portal_id != str(data.portal) or not is_instance_valid(corridors.active): corridors.arm(str(data.portal))
			var spot: Dictionary = load("res://scripts/dungeon/corridor_plan.gd").sample(corridors.active.path, float(data.along))
			var at: Vector2 = spot.at + Vector2(corridors.active.position.x, corridors.active.position.z)
			game.player.position = Vector3(at.x, .03, at.y)
			game.player.last_valid = game.player.position
			reply({"walked": true})
		"enter":
			var spot: Vector2 = game.room.geometry.safe_point(Vector2(1.2, 0.5), .5, game.room.blocked_at)
			game.player.position = Vector3(spot.x, game.room.floor_height(Vector3(spot.x, 0, spot.y)) + .03, spot.y)
			game.player.last_valid = game.player.position
			reply({"entered": true})
		"hit":
			var target = null
			for foe in game.party.puppets.values():
				if is_instance_valid(foe) and foe.alive and foe.targetable and not foe.inert:
					target = foe
					break
			check(target != null, "a drawn foe can be struck")
			if target:
				check(target.puppet, "the guest's foe is the host's, drawn")
				target.take_hit(float(data.damage), Vector3.ZERO, false, false, "shot")
				reply({"hit": target.entity_id})
			else: reply({"hit": 0})
		"cast":
			var shot = game.spawn_shot(game.player.global_position + Vector3.UP * 1.3, game.fps.forward(), 3.0, 12.0, run.projectile_stats(), Color("8fd0f0"), true)
			check(shot != null and shot.cosmetic, "a guest's own spell is drawn at once")
			reply({"cast": shot.net_id if shot else 0})
		"fall":
			game.player_fell()
			reply({"fell": game.party.downed})
		"stair":
			# Walk up to this player's own stair, raising it if this room has none.
			if not is_instance_valid(game.stairs): game.raise_stairs(false)
			game.player.position = game.stairs.approach_point()
			game.player.last_valid = game.player.position
			reply(game.party.at_the_stair())
		"done":
			done = true
