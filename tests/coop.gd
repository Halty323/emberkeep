extends SceneTree
## LAN co-op, end to end over the loopback network, with a party of three:
## this process hosts and starts two more game processes
## (tests/coop_guest.gd) that join. Together they check the handshake, the
## shared floor, gathering in a passage before a room changes, the fight's
## start once the party is in, the host's foes drawn and struck from a guest,
## spells cast by a guest, guests seeing each other, personal kill credit,
## blows sent to the right player, falling and rekindling, the shared stair
## to the next floor, and the end when everyone is down.
var checks := 0
var failures := 0
var game
var session
var run
var pids: Array = []
var guests: Array = []
var results: Array = []
var replies: Dictionary = {}
var solo_save := ""
const SEED := 31609250
const GUESTS := ["Wren", "Moss"]

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("exercise")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func until(condition: Callable, seconds: float) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		if condition.call(): return true
		await process_frame
	return condition.call()

func wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0: await process_frame

func begin_button() -> Button:
	for child in game.ui.content.get_children():
		if child is Button and child.text.begins_with("Begin the climb") and not child.is_queued_for_deletion(): return child
	return null

## Asks one guest to do something and waits for its answer.
func ask(guest: int, command: Dictionary) -> Dictionary:
	if not replies.has(guest): replies[guest] = []
	var before: int = replies[guest].size()
	session.send(guest, "test", command)
	await until(func(): return replies[guest].size() > before, 6.0)
	return replies[guest][before] if replies[guest].size() > before else {}

func exercise() -> void:
	session = root.get_node("Session")
	run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	# Whatever lone climb is saved here must come through untouched.
	solo_save = FileAccess.get_file_as_string("user://run.json") if FileAccess.file_exists("user://run.json") else ""
	units()
	await discovery()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	session.message_received.connect(func(from, kind, data):
		if kind != "test_reply": return
		if not replies.has(from): replies[from] = []
		replies[from].append(data))
	var port := 47630 + randi() % 300
	check(session.host_party("Ash", "candle", port) == "", "the host opens a party")
	game.ui.show_screen("lobby")
	await process_frame
	check(begin_button() != null and begin_button().disabled, "a party of one cannot set off")
	# Each guest gets its own storage, as another device would.
	var saved_data := OS.get_environment("XDG_DATA_HOME")
	for i in GUESTS.size():
		var home := OS.get_cache_dir().path_join("emberkeep-coop-%d-%d" % [port, i])
		DirAccess.make_dir_recursive_absolute(home)
		results.append(home.path_join("result.json"))
		OS.set_environment("XDG_DATA_HOME", home)
		var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/coop_guest.gd", "--", "--port=%d" % port, "--result=%s" % results[i], "--name=%s" % GUESTS[i]])
		pids.append(pid)
		check(pid > 0, "%s's game starts" % GUESTS[i])
		# One at a time, so slots follow the order they arrive in.
		check(await until(func(): return session.roster.size() == i + 2, 25.0), "%s joins the party" % GUESTS[i])
	OS.set_environment("XDG_DATA_HOME", saved_data)
	guests = session.others()
	check(guests.size() == 2 and session.slot_of(guests[0]) == 1 and session.slot_of(guests[1]) == 2, "guests take the next slots in turn")
	check(session.name_of(guests[0]) == "Wren" and session.name_of(guests[1]) == "Moss", "each joins under its own name")
	await process_frame
	check(game.ui.mode == "lobby" and begin_button() != null and not begin_button().disabled, "once guests are in, the host may begin")
	game.party.begin(SEED)
	check(run.active and run.seed_value == SEED, "the host sets off")
	check(await until(func(): return guests.all(func(id): return game.party.states.has(id)), 25.0), "every guest's player reports in")
	for id in guests:
		var guest: Dictionary = await ask(id, {"cmd": "report"})
		check(guest.get("rooms", -1) == run.rooms.size() and guest.get("room", "") == run.current_room, "%s walks the same floor" % session.name_of(id))
		check(game.party.members.has(id) and is_instance_valid(game.party.members[id]), "the host sees %s's figure" % session.name_of(id))
	await wait(.5)
	var seen: Dictionary = (await ask(guests[0], {"cmd": "report"})).get("figures", {})
	check(seen.size() == 2 and seen.has(guests[1]) and seen.has(1), "a guest sees the host and the other guest")
	var other: Dictionary = await ask(guests[1], {"cmd": "report"})
	if seen.has(guests[1]) and other.get("position") is Vector3:
		check(seen[guests[1]].distance_to(other.position) < .6, "and sees the other guest where that guest really is")
	await gather_and_fight()
	await fall_and_rekindle()
	await climb_together()
	await everyone_down()
	for id in guests: await ask(id, {"cmd": "done"})
	check(await until(func(): return pids.all(func(pid): return not OS.is_process_running(pid)), 20.0), "the guests' games end")
	for path in results:
		var text := FileAccess.get_file_as_string(path)
		var result = JSON.parse_string(text) if text != "" else null
		check(result is Dictionary and int(result.checks) > 0, "each guest wrote its own checks")
		if result is Dictionary:
			checks += int(result.checks)
			failures += int(result.failures)
			for note in result.notes: push_error("FAIL (guest): " + str(note))
	session.leave_party()
	game.queue_free()
	for i in 3: await process_frame
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
	print("COOP: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

## The parts that need no network: the handshake's rules and the packing of
## a floor for the wire.
func units() -> void:
	var Party = load("res://scripts/coop/party.gd")
	var floor_data: Dictionary = run.floor_data_for(SEED, 2)
	var packed: PackedByteArray = Party.pack(floor_data)
	check(packed.size() < var_to_bytes(floor_data).size(), "a floor is compressed for the wire")
	check(Party.unpack(packed) == floor_data, "a floor arrives exactly as it was built")
	check(Party.unpack(PackedByteArray([1, 2, 3])) == null, "a damaged floor is refused, not trusted")
	var content = root.get_node("Content")
	check(session.admission({"protocol": session.PROTOCOL_VERSION, "revision": content.revision, "name": "x"}) == "", "a matching guest is let in")
	check(session.admission({"protocol": 1, "revision": content.revision}) != "", "another protocol is turned away")
	check(session.admission({"protocol": session.PROTOCOL_VERSION, "revision": "deadbeef"}) != "", "other content is turned away")
	check(session.admission("hello") != "", "nonsense is turned away")
	var flight: Dictionary = Party.flight({"homing": 2.0, "damage": 3.0, "pierce": 0, "bounce": 1})
	check(flight.has("homing") and flight.has("bounce") and not flight.has("damage") and not flight.has("pierce"), "a drawn spell carries only how it flies")

func discovery() -> void:
	var Discovery = load("res://scripts/coop/lan_discovery.gd")
	check(Discovery.private_ipv4("192.168.1.20") and Discovery.private_ipv4("10.0.0.2") and not Discovery.private_ipv4("8.8.8.8"), "only local network addresses are offered")
	var parsed = Discovery.parse(Discovery.encode({"name": "Party"}))
	check(parsed is Dictionary and parsed.name == "Party", "an announcement reads back")
	check(Discovery.parse("hello".to_utf8_buffer()) == null, "a stray packet is ignored")
	var host = Discovery.new()
	var seeker = Discovery.new()
	host.start_host(func(): return {"name": "Loopback", "count": 1, "max": 4, "port": 47620, "protocol": 2})
	seeker.start_seek()
	var heard: Array = []
	var start := Time.get_ticks_msec()
	while heard.is_empty() and Time.get_ticks_msec() - start < 3500:
		host.poll(1.0 / 60.0)
		heard.append_array(seeker.poll(1.0 / 60.0))
		await process_frame
	host.stop()
	seeker.stop()
	# A machine without a network may block even loopback broadcasts; when a
	# party is heard, it must be the right one.
	check(heard.is_empty() or heard[0].name == "Loopback", "a party on the network is found by asking")
	print("COOP discovery heard %d answer(s)" % heard.size())

func portal_to(kind: String) -> String:
	for id in run.rooms[run.current_room].get("portals", []):
		if run.portals[id].state in ["open", "revealed"] and run.rooms[run.other_room(id, run.current_room)].type == kind: return id
	for id in run.rooms[run.current_room].get("portals", []):
		if run.portals[id].state in ["open", "revealed"]: return id
	return ""

func place_in_corridor(along: float) -> void:
	var corridors = game.corridors
	var spot: Dictionary = load("res://scripts/dungeon/corridor_plan.gd").sample(corridors.active.path, along)
	var at: Vector2 = spot.at + Vector2(corridors.active.position.x, corridors.active.position.z)
	game.player.position = Vector3(at.x, .03, at.y)
	game.player.last_valid = game.player.position

func gather_and_fight() -> void:
	var portal := portal_to("combat")
	check(portal != "", "the first room has a way on")
	var from: String = run.current_room
	var destination: String = run.other_room(portal, from)
	var corridors = game.corridors
	corridors.arm(portal)
	check(is_instance_valid(corridors.active), "the host's passage is built")
	place_in_corridor(corridors.handoff + .2)
	await ask(guests[0], {"cmd": "walk", "portal": portal, "along": 1.0})
	await wait(1.2)
	check(run.current_room == from, "the room does not change while a teammate is still behind")
	check(corridors.coop_held and game.party.notice == "Waiting for Moss", "the host waits at the turn and is told for whom (%s)" % game.party.notice)
	# Nobody passes the turn alone.
	var beyond: Dictionary = load("res://scripts/dungeon/corridor_plan.gd").sample(corridors.active.path, corridors.handoff + 1.0)
	check(not game.walkable_at(beyond.at + Vector2(corridors.active.position.x, corridors.active.position.z), .1), "nobody walks past the turn alone")
	await ask(guests[1], {"cmd": "walk", "portal": portal, "along": .6})
	check(await until(func(): return run.current_room == destination, 6.0), "once everyone is in the passage, the party moves on")
	await wait(.6)
	for id in guests:
		var guest: Dictionary = await ask(id, {"cmd": "report"})
		check(guest.get("room", "") == destination, "%s, behind, is pulled along to the same room" % session.name_of(id))
	check(game.party.epoch == 1, "the handoff begins a new frame of reference")
	if run.rooms[destination].type != "combat" or run.rooms[destination].cleared:
		print("COOP: the room past the first door holds no fight; skipping the fight checks")
		return
	for id in guests: await ask(id, {"cmd": "enter"})
	var spot: Vector2 = game.room.geometry.safe_point(Vector2(-1.2, -.5), .5, game.room.blocked_at)
	game.player.position = Vector3(spot.x, game.room.floor_height(Vector3(spot.x, 0, spot.y)) + .03, spot.y)
	game.player.last_valid = game.player.position
	check(await until(func(): return game.deferred_encounter.is_empty() and not game.enemies.is_empty(), 8.0), "the fight starts once the party is in")
	check(not game.room.open, "the room seals for its fight")
	await wait(.6)
	for id in guests:
		var guest: Dictionary = await ask(id, {"cmd": "report"})
		check(int(guest.get("foes", -1)) == game.enemies.size(), "%s sees every one of the host's foes (%d / %d)" % [session.name_of(id), int(guest.get("foes", -1)), game.enemies.size()])
		check(not guest.get("open", true), "%s's room is sealed too" % session.name_of(id))
	# A blow from a guest lands on the host's foe.
	var health := {}
	for foe in game.enemies: health[foe.entity_id] = foe.hp
	var struck: Dictionary = await ask(guests[0], {"cmd": "hit", "damage": 4.0})
	var target = null
	for foe in game.enemies:
		if foe.entity_id == int(struck.get("hit", -1)): target = foe
	check(target != null and await until(func(): return target.hp < health[target.entity_id], 3.0), "a guest's blow is applied to the host's foe")
	# A spell a guest casts is really cast on the host, as that guest's.
	var cast: Dictionary = await ask(guests[0], {"cmd": "cast"})
	check(await until(func(): return game.party.net_shots.has(int(cast.get("cast", -1))), 3.0), "a guest's spell is cast on the host")
	var real = game.party.net_shots.get(int(cast.get("cast", -1)))
	check(real != null and real.owner_peer == guests[0] and not real.cosmetic, "the real spell belongs to that guest")
	var drawn := 0
	for attempt in 6:
		drawn = int((await ask(guests[1], {"cmd": "report"})).get("drawn", 0))
		if drawn > 0: break
		await ask(guests[0], {"cmd": "cast"})
	check(drawn > 0, "the other guest sees the party's spells")
	# Foes chase whoever is nearest.
	var member = game.party.members[guests[0]]
	var foe0 = game.enemies[0]
	member.target = foe0.global_position + Vector3(.5, 0, 0)
	member.position = member.target
	game.party.states[guests[0]].p = member.target
	game.player.position = foe0.global_position + Vector3(9, 0, 0)
	check(game.party.quarry(foe0) == member, "a foe goes after the nearest teammate")
	# Clear the fight from the host; each player counts their own kills.
	var kills_before: int = run.kills
	var guard := 0
	while guard < 40 and game.enemies.any(func(e): return is_instance_valid(e) and e.alive and not e.inert):
		guard += 1
		for foe in game.enemies.duplicate():
			if not is_instance_valid(foe) or not foe.alive or foe.inert: continue
			# Some wait out of reach (on the ceiling, under water); reach them.
			foe.targetable = true
			foe.ward_up = false
			foe.take_hit(99999.0, Vector3.ZERO, false, false, "blast")
		await wait(.15)
	var left: Array = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive and not e.inert).map(func(e): return e.kind)
	check(await until(func(): return game.room.open, 5.0), "the host's room opens once its foes are gone (left: %s)" % ", ".join(left))
	await wait(.6)
	for id in guests:
		var guest: Dictionary = await ask(id, {"cmd": "report"})
		check(guest.get("open", false), "%s's room opens with the host's" % session.name_of(id))
		check(int(guest.get("foes", -1)) == 0, "%s's drawn foes are gone" % session.name_of(id))
		check(run.kills > kills_before and int(guest.get("kills", -1)) == run.kills, "%s is credited with every foe once (%d / %d)" % [session.name_of(id), int(guest.get("kills", -1)), run.kills])

func fall_and_rekindle() -> void:
	var wren: int = guests[0]
	var member = game.party.members[wren]
	await wait(1.6)
	var before: Dictionary = await ask(wren, {"cmd": "report"})
	var bystander: Dictionary = await ask(guests[1], {"cmd": "report"})
	member.invulnerable = false
	member.hurt(1.0, member.global_position + Vector3(1, 0, 0))
	await wait(.5)
	var after: Dictionary = await ask(wren, {"cmd": "report"})
	var still: Dictionary = await ask(guests[1], {"cmd": "report"})
	check(is_equal_approx(float(after.get("hp", 0)), float(before.get("hp", 0)) - 1.0), "a blow on a guest's figure is taken by that guest (%s -> %s)" % [before.get("hp"), after.get("hp")])
	check(run.hp == run.stats.max_hp and is_equal_approx(float(still.get("hp", 0)), float(bystander.get("hp", -1))), "and by no one else")
	var fell: Dictionary = await ask(wren, {"cmd": "fall"})
	check(fell.get("fell", false), "a guest falls instead of dying")
	check(await until(func(): return game.party.is_down(wren), 3.0), "the host sees the guest fallen")
	await wait(.2)
	check(member.visual.rotation.x < -1.0, "the fallen guest's figure lies on the floor")
	check(run.active, "one fallen player does not end the climb")
	check(not game.party.bodies().has(member), "foes leave a fallen player alone")
	# Standing beside them rekindles them.
	game.player.position = member.global_position + Vector3(.8, 0, 0)
	game.player.last_valid = game.player.position
	check(await until(func(): return float(game.party.revive.get(wren, 0.0)) > .3, 3.0), "standing beside a fallen teammate rekindles them")
	check(await until(func(): return not game.party.is_down(wren), 6.0), "the fallen teammate rises")
	await wait(.2)
	check(is_zero_approx(member.visual.rotation.x), "and their figure stands again")
	var risen: Dictionary = await ask(wren, {"cmd": "report"})
	check(not risen.get("down", true) and is_equal_approx(float(risen.get("hp", 0)), 2.0), "a rekindled player is back on one heart")

func climb_together() -> void:
	var floor_before: int = run.floor_number
	if not is_instance_valid(game.stairs): game.raise_stairs(false)
	game.player.position = game.stairs.approach_point()
	game.player.last_valid = game.player.position
	game.party.at_the_stair()
	check(game.party.waiting_at_stair and game.prompt_for({"kind": "exit", "prompt": ""}) == "Waiting for the party…", "the stair asks a player to wait for the party")
	# Walking off stops waiting; coming back waits again.
	game.party.waiting_at_stair = true
	game.player.global_position = game.stairs.approach_point() + Vector3(4.0, 0, 0)
	await wait(.15)
	check(not game.party.waiting_at_stair, "walking away from the stair stops waiting at it")
	game.player.position = game.stairs.approach_point()
	game.player.last_valid = game.player.position
	await wait(.1)
	game.party.at_the_stair()
	await ask(guests[0], {"cmd": "stair"})
	await wait(.8)
	check(run.floor_number == floor_before and game.party.notice == "Waiting at the stair · 2 / 3", "the stair waits for the whole party (%s)" % game.party.notice)
	await ask(guests[1], {"cmd": "stair"})
	check(await until(func(): return run.floor_number == floor_before + 1 and game.transition.is_empty(), 20.0), "the party climbs together")
	await wait(1.0)
	for id in guests:
		var guest: Dictionary = await ask(id, {"cmd": "report"})
		check(int(guest.get("floor", 0)) == run.floor_number and guest.get("room", "") == run.current_room and int(guest.get("rooms", 0)) == run.rooms.size(), "%s arrives on the same floor, in the same room" % session.name_of(id))
	check(game.party.epoch >= 2, "the new floor begins a new frame of reference")

func everyone_down() -> void:
	for id in guests:
		await ask(id, {"cmd": "fall"})
		check(await until(func(): return game.party.is_down(id), 3.0), "%s is down" % session.name_of(id))
	check(run.active, "the climb goes on while anyone stands")
	game.player_fell()
	check(await until(func(): return not run.active, 3.0), "when everyone is down at once, the climb is over")
	await wait(.5)
	for id in guests:
		var guest: Dictionary = await ask(id, {"cmd": "report"})
		check(not guest.get("active", true) and guest.get("mode", "") == "dead", "%s's climb ends too" % session.name_of(id))
	check(game.ui.mode == "dead", "the host sees the end")
	var now := FileAccess.get_file_as_string("user://run.json") if FileAccess.file_exists("user://run.json") else ""
	check(now == solo_save, "a co-op climb is never saved, and a lone climb's save is left as it was")
	# The same party can go again.
	game.party.regroup()
	await wait(.6)
	check(game.ui.mode == "lobby" and not session.started and session.roster.size() == 3, "the host brings the party back to the lobby")
	for id in guests:
		var guest: Dictionary = await ask(id, {"cmd": "report"})
		check(guest.get("mode", "") == "lobby" and guest.get("in_menu", false), "%s returns to the lobby with the party" % session.name_of(id))
