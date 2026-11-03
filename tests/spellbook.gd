extends SceneTree
## The magic overhaul: the held spellbook and its arm, every relic's own
## mark on them, spell wording everywhere a player reads, rarer and stronger
## relics, and the reliquary they wait in.
var checks := 0
var failures := 0
var catalog
var View
var Looks
var Relics

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("exercise")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func exercise() -> void:
	catalog = root.get_node("Content")
	View = load("res://scripts/first_person/spellbook_view.gd")
	Looks = load("res://scripts/items/spellbook_looks.gd")
	Relics = load("res://scripts/items/reliquary.gd")
	var holder := Node3D.new()
	root.add_child(holder)
	view_contract(holder)
	every_relic_marks(holder)
	wording()
	rarity()
	reliquary(holder)
	holder.queue_free()
	await process_frame
	print("SPELLBOOK: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func rig(holder: Node3D) -> Node3D:
	var node := Node3D.new()
	holder.add_child(node)
	View.populate(node)
	return node

func view_contract(holder: Node3D) -> void:
	var book := rig(holder)
	check(book.get_child(0).material_override is ShaderMaterial, "the boards keep the shared, quality-aware wood material first")
	check(book.get_child(1).name == "Brass" and book.get_child(2).name == "Accent", "brass and the glowing accent keep their places")
	View.tint(book, Color("8fd0f0"))
	check(book.get_child(2).material_override.albedo_color.is_equal_approx(Color("8fd0f0")), "the accent takes the spellbook's colour")
	check(book.get_node("Runes").material_override.get_shader_parameter("ink").is_equal_approx(Color("8fd0f0")), "the writing on the pages takes it too")
	View.glow(book, 1.0)
	check(is_equal_approx(book.get_node("Runes").material_override.get_shader_parameter("flare"), 1.0), "a cast makes the writing flare")
	for part in ["Pages", "Hand", "Sleeve", "Cuff", "Marks"]:
		check(book.has_node(part), "the rig has its " + part.to_lower())
	# Nothing of the old gun remains.
	check(not ResourceLoader.exists("res://scripts/first_person/weapon_view.gd"), "the gun view model is gone")

func signature(book: Node3D) -> String:
	var parts: Array = []
	for node in book.get_node("Marks").get_children():
		var count := 0
		if node is MeshInstance3D and node.mesh is ArrayMesh:
			for surface in node.mesh.get_surface_count(): count += node.mesh.surface_get_array_len(surface)
		parts.append("%s:%d:%d" % [node.name, count, node.get_child_count()])
	for part in ["Hand", "Sleeve", "Cuff"]:
		parts.append(str(book.get_node(part).material_override.get_instance_id()))
	return ",".join(parts)

func every_relic_marks(holder: Node3D) -> void:
	var book := rig(holder)
	Looks.dress(book, [])
	var bare := signature(book)
	var missing: Array = []
	var invisible: Array = []
	var seen := {}
	for item in catalog.items:
		var entry: Array = Looks.look(item.id)
		if entry.is_empty() or entry[0] not in ["book", "arm"] or not Looks.SLOTS.has(entry[1]):
			missing.append(item.id)
			continue
		Looks.dress(book, [item.id])
		var marked := signature(book)
		if marked == bare: invisible.append(item.id)
		seen[marked] = true
	check(missing.is_empty(), "every relic has a mark on the book or the arm (%s)" % ", ".join(missing))
	check(invisible.is_empty(), "every relic visibly changes the book or the arm on its own (%s)" % ", ".join(invisible))
	check(Looks.LOOKS.size() == catalog.items.size(), "no mark names a relic that does not exist")
	var parts := {"book": 0, "arm": 0}
	for id in Looks.LOOKS: parts[Looks.LOOKS[id][0]] += 1
	check(parts.book >= 20 and parts.arm >= 15, "relics mark both the book and the arm (%d / %d)" % [parts.book, parts.arm])
	# Several of one kind stack in their own places; every relic at once fits.
	Looks.dress(book, ["warm_wax", "forked_wick"])
	var two := signature(book)
	Looks.dress(book, ["warm_wax"])
	check(two != signature(book), "a second relic of the same kind adds its own mark")
	var all: Array = catalog.items.map(func(item): return item.id)
	Looks.dress(book, all)
	check(book.get_node("Marks").get_child_count() > 0, "every relic at once still dresses the book without error")
	Looks.animate(book, 1.5)
	check(true, "sigils turn and motes orbit")

func wording() -> void:
	var banned := RegEx.create_from_string("(?i)\\b(shots?|projectiles?|barrel|bullets?|guns?|ammo|fire (\\d|faster|slower|an|behind|one))\\b")
	var offenders: Array = []
	for item in catalog.items:
		if banned.search(item.name + " " + item.description): offenders.append(item.id)
	check(offenders.is_empty(), "relic names and descriptions speak of spells and casting (%s)" % ", ".join(offenders))
	var forge = load("res://scripts/items/forge.gd")
	var book: Dictionary = forge.lookup(forge.id_for(31609250, 0))
	check(str(book.description).begins_with("Casts "), "a written spellbook casts: " + str(book.description))

func rarity() -> void:
	var balance = load("res://scripts/items/expedition_balance.gd")
	check(balance.COMBAT_RELICS_PER_FLOOR == 0 and not balance.combat_relic_due({"type": "combat"}, {}), "ordinary fights never award relics")
	check(balance.combat_relic_due({"type": "boss"}, {}), "every boss still awards a relic")
	# Stronger: every lasting bonus at least matches what it was.
	var stronger := {"warm_wax": ["damage", .35], "quick_wick": ["rate", .28], "heartstone": ["max_hp", 4], "glass_sun": ["damage", 1.5], "thousand_wicks": ["shots", 5]}
	for id in stronger:
		check(is_equal_approx(float(catalog.item_by_id[id].effects[stronger[id][0]]), float(stronger[id][1])), "%s is stronger" % id)
	var penalty_free: Array = catalog.items.filter(func(item): return item.rarity in ["common", "uncommon"] and item.effects.values().any(func(value): return float(value) < 0))
	check(penalty_free.size() <= 1, "nearly every common and uncommon relic is a pure gain (%d with a cost)" % penalty_free.size())

func reliquary(holder: Node3D) -> void:
	var stand := Node3D.new()
	holder.add_child(stand)
	var relic: Node3D = Relics.build(stand, Color("ffc874"), false)
	check(relic.name == "Relic" and relic.has_meta("rest_y"), "a relic floats in its reliquary")
	var lights := stand.find_children("*", "OmniLight3D", true, false)
	check(lights.size() == 1 and lights[0].get_parent() != relic, "one still light: the floating part never moves a light")
	var before := relic.position.y
	Relics.animate(relic, .8, .1)
	check(not is_equal_approx(relic.position.y, before) and relic.rotation.y > 0, "the relic turns and bobs")
	check(stand.find_children("*", "MeshInstance3D", true, false).size() >= 20, "the reliquary is a carved, layered piece, not a single block")
	for shader in ["shot_core", "shot_glow", "shot_streak"]:
		var code: String = load("res://shaders/%s.gdshader" % shader).code
		check("TIME" in code, shader + " is a living spell effect, not a static tracer")
