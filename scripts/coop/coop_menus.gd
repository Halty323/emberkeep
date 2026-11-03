class_name CoopMenus
extends RefCounted
## The co-op screens on the title (find or host a party, then the party's
## lobby) and what co-op adds to the play HUD: teammates' hearts, a fallen
## player's rekindling, and what the party is waiting for.

static func default_name() -> String:
	var saved := str(Run.profile.get("coop_name", ""))
	if saved != "": return saved
	for key in ["USERNAME", "USER"]:
		var value := OS.get_environment(key)
		if value != "": return value.capitalize()
	return "Little light"

static func field(ui, at: Vector2, width: float, value: String, placeholder: String, changed: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.position = at
	edit.size = Vector2(width, 50)
	edit.text = value
	edit.placeholder_text = placeholder
	edit.max_length = 40
	edit.add_theme_font_override("font", ui.body)
	edit.add_theme_font_size_override("font_size", 18)
	edit.add_theme_color_override("font_color", ui.INK)
	edit.add_theme_stylebox_override("normal", ui.style(Color(.04, .045, .04, .6), Color(.55, .45, .29, .5), 1))
	edit.add_theme_stylebox_override("focus", ui.style(Color(.08, .075, .05, .8), ui.GOLD, 1))
	edit.text_changed.connect(changed)
	ui.content.add_child(edit)
	return edit

static func remember(key: String, value: String) -> void:
	Run.profile[key] = value.strip_edges()
	Run.save_profile()

static func cycle_spellbook(ui) -> void:
	ui.starter_index += 1
	ui.refresh_armory_choices()
	Session.local_weapon = ui.starter_weapon().id
	if Session.online and not Session.hosting: Session.send(1, "weapon", Session.local_weapon)
	elif Session.hosting:
		Session.roster[1].weapon = Session.local_weapon
		Session.share_roster()
	ui.show_screen(ui.mode)

## Find a party on the network, or open one.
static func build_coop(ui) -> void:
	if ui.menu_seed == 0: ui.reforge()
	if not Session.discovery.seeking and not Session.online: Session.look_for_parties()
	var back = ui.title_button("← Hearth", Rect2(60, 64, 200, 54), func():
		Session.stop_looking()
		ui.show_screen("menu"))
	back.add_theme_font_size_override("font_size", 18)
	field(ui, Vector2(60, 238), 300, default_name(), "Your name", func(value): remember("coop_name", value))
	ui.title_button("Spellbook: %s" % ui.starter_weapon().name, Rect2(56, 300, 440, 54), func(): cycle_spellbook(ui))
	ui.title_button("Host a party", Rect2(56, 362, 440, 58), func(): host(ui), true)
	var keys: Array = Session.parties.keys()
	keys.sort()
	var y := 452.0
	for key in keys.slice(0, 3):
		var party: Dictionary = Session.parties[key]
		var open: bool = bool(party.get("open", true)) and int(party.get("count", 0)) < int(party.get("max", 4)) and party.get("same_content", true)
		var label := "Join %s  (%d/%d)" % [str(party.get("name", "a party")), int(party.get("count", 1)), int(party.get("max", 4))]
		var button = ui.title_button(label, Rect2(56, y, 440, 50), func(): join(ui, "%s:%d" % [party.address, int(party.port)]))
		button.disabled = not open
		button.add_theme_font_size_override("font_size", 20)
		y += 54
	field(ui, Vector2(60, 622), 250, str(Run.profile.get("coop_address", "")), "Host address", func(value): remember("coop_address", value))
	var by_address = ui.title_button("Join", Rect2(326, 620, 170, 54), func(): join(ui, str(Run.profile.get("coop_address", ""))))
	by_address.add_theme_font_size_override("font_size", 21)

static func host(ui) -> void:
	Session.stop_looking()
	var problem: String = Session.host_party(default_name(), ui.starter_weapon().id)
	if problem != "":
		ui.notify(problem, "Another program may be using it.", Color("e8c39a"))
		return
	ui.show_screen("lobby")

static func join(ui, address: String) -> void:
	if address.strip_edges().is_empty():
		ui.notify("Type the host's address", "The host's lobby shows it.", Color("e8c39a"))
		return
	var problem: String = Session.join_party(address, default_name(), ui.starter_weapon().id)
	if problem != "":
		ui.notify(problem, "", Color("e8c39a"))
		return
	ui.show_screen("coop")

static func draw_coop(ui) -> void:
	ui.draw_title_shade()
	ui.hearth_emblem(Vector2(77, 150), 11)
	ui.text("FIRES ON THE SAME NETWORK", Vector2(100, 155), 13, ui.GOLD, ui.bold)
	ui.text("Climb together", Vector2(56, 210), 40, ui.INK, ui.heading)
	ui.text("YOUR NAME", Vector2(372, 268), 12, ui.MUTED, ui.bold)
	if Session.status == "connecting":
		ui.text("Reaching %s…" % Session.host_address, Vector2(60, 440), 17, ui.GOLD)
	elif Session.parties.is_empty():
		ui.text("Looking for parties on this network…", Vector2(60, 450), 17, ui.MUTED)
		ui.text("None yet? Type the host's address below.", Vector2(60, 476), 15, ui.MUTED)
	ui.anchor(ui.widen())
	ui.text("Two to four little lights", Vector2(840, 560), 21, ui.INK, ui.heading)
	ui.text("Each keeps their own relics, coins and loot.", Vector2(842, 592), 15, ui.MUTED)
	ui.text("A fallen friend is rekindled by standing near.", Vector2(842, 616), 15, ui.MUTED)
	ui.text("Doors open when the whole party is through.", Vector2(842, 640), 15, ui.MUTED)

## The party gathers before the climb.
static func build_lobby(ui) -> void:
	var leave = ui.title_button("← Leave the party", Rect2(60, 64, 300, 54), func():
		Session.leave_party()
		ui.show_screen("coop"))
	leave.add_theme_font_size_override("font_size", 18)
	ui.title_button("Spellbook: %s" % ui.starter_weapon().name, Rect2(56, 520, 440, 54), func(): cycle_spellbook(ui))
	if Session.hosting:
		var begin = ui.title_button("Begin the climb  →", Rect2(56, 600, 440, 62), func():
			ui.game.party.begin(ui.chosen_seed()), true)
		begin.disabled = Session.roster.size() < 2

static func draw_lobby(ui) -> void:
	ui.draw_title_shade()
	ui.hearth_emblem(Vector2(77, 150), 11)
	ui.text("THE PARTY GATHERS", Vector2(100, 155), 13, ui.GOLD, ui.bold)
	ui.text("%d of %d little lights" % [Session.roster.size(), Session.MAX_PLAYERS], Vector2(56, 210), 36, ui.INK, ui.heading)
	var y := 262.0
	for id in Session.peers():
		var entry: Dictionary = Session.roster[id]
		var color: Color = Session.color_of(id)
		ui.diamond(Vector2(66, y - 7), 8, color)
		var who := str(entry.name) + ("  (host)" if int(entry.slot) == 0 else "") + ("  · you" if id == Session.local_peer_id else "")
		ui.text(who, Vector2(84, y), 21, ui.INK, ui.heading)
		var book := Forge.lookup(str(entry.weapon)) if Forge.known(str(entry.weapon)) else {}
		if not book.is_empty(): ui.text(str(book.name), Vector2(86, y + 22), 14, Color(book.color))
		y += 56
	if Session.hosting:
		var addresses: Array = Session.local_addresses()
		ui.text("Others join at " + (", ".join(addresses) if not addresses.is_empty() else "this device's network address"), Vector2(60, 496), 16, ui.GOLD)
		if Session.roster.size() < 2: ui.text("Waiting for at least one more little light…", Vector2(60, 690), 15, ui.MUTED)
	else:
		ui.text("Waiting for the host to begin the climb…", Vector2(60, 610), 18, ui.GOLD)
	ui.anchor(ui.widen())
	ui.text("Seed %d" % ui.chosen_seed(), Vector2(1080, 680), 14, ui.MUTED)

## Teammates under the HUD, the party's notice, and a fallen player's view.
static func draw_hud(ui) -> void:
	var party = ui.game.party
	if party == null or not party.climbing(): return
	ui.anchor(0)
	var y := 186.0
	for id in Session.others():
		var state: Dictionary = party.states.get(id, {})
		var color: Color = Session.color_of(id)
		ui.diamond(Vector2(30, y - 5), 6, color)
		ui.text(Session.name_of(id), Vector2(44, y), 15, ui.INK, ui.bold)
		var max_hp := float(state.get("mhp", 6.0))
		var hp := float(state.get("hp", max_hp))
		var hearts := mini(int(ceil(max_hp / 2.0)), 10)
		for i in hearts:
			var at := Vector2(48 + i * 13, y + 13)
			var fill := clampf((hp - i * 2) / 2.0, 0, 1)
			ui.diamond(at, 5, Color("4a4a40"))
			if fill > 0: ui.diamond(at, 5 * (.58 if fill < 1 else 1.0), Color("f4c68c"))
		if bool(state.get("down", false)):
			var progress := float(party.revive.get(id, 0.0))
			ui.text("fallen" + (" · %d%%" % int(progress * 100) if progress > 0 else ""), Vector2(48 + hearts * 13 + 8, y + 18), 13, Color("e0a18b"))
		y += 40
	ui.anchor(ui.widen() / 2.0)
	if party.downed:
		ui.draw_rect(Rect2(-ui.widen(), 0, ui.view_width + ui.widen(), 720), Color(.12, .02, .02, .35))
		ui.centered("You have fallen", 640, 300, 38, ui.INK, ui.heading)
		var mine := float(party.revive.get(Session.local_peer_id, 0.0))
		ui.centered("Being rekindled…" if mine > 0 else "A teammate standing beside you can rekindle you.", 640, 340, 18, ui.MUTED)
		ui.draw_rect(Rect2(490, 362, 300, 6), Color(.2, .18, .14, .8))
		if mine > 0: ui.draw_rect(Rect2(490, 362, 300 * mine, 6), Color("ffd28d"))
	elif party.notice != "":
		ui.centered(party.notice, 640, 528, 18, ui.GOLD, ui.bold)
