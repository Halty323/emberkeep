class_name SpellbookLooks
extends RefCounted
## Every relic leaves its own mark on the spellbook or the arm that holds it:
## a candle on the board, a gem in a brass corner, a ribbon or a charm, a
## turning sigil over the pages, frost or embers on the edges; a ring, a
## bangle, a bracer, a wrap, a tattoo, wings at the cuff. Marks of one kind
## take the next free place, so relics stack visibly. Static marks are
## merged into two meshes (lit and glowing); only sigils, motes and candle
## flames move.
## [part, kind, colour, variant]
const LOOKS := {
	"echo_bell": ["book", "charm", "d9c27a", "coin"],
	"war_drum": ["arm", "bangle", "b0603a", ""],
	"black_pearl": ["book", "gem", "3a3f52", ""],
	"phantom_veil": ["arm", "wrap", "c8d0e8", ""],
	"storm_crown": ["book", "sigil", "c4b8ff", ""],
	"phoenix_feather": ["arm", "tattoo", "ff8a4a", ""],
	"prism_lens": ["book", "inlay", "e8f8ff", ""],
	"seismic_boots": ["arm", "bracer", "8a7a62", ""],
	"spyglass": ["book", "stick", "b89a5a", ""],
	"meteor_charm": ["book", "charm", "ffb070", "stone"],
	"fractal_seed": ["book", "crust", "c8f0f5", "frost"],
	"crimson_grail": ["arm", "ring", "b0303a", ""],
	"warm_wax": ["book", "candle", "efe2c4", ""],
	"quick_wick": ["arm", "bangle", "d9b15e", "spark"],
	"soft_boots": ["arm", "wrap", "7f9fc4", ""],
	"heartstone": ["book", "gem", "d8484f", ""],
	"long_match": ["book", "stick", "c9a46a", "match"],
	"brass_barrel": ["book", "lens", "c8a060", ""],
	"heavy_ember": ["arm", "bracer", "4c5157", "iron"],
	"lucky_penny": ["book", "charm", "c89a4a", "coin"],
	"lodestone": ["book", "charm", "5a5e66", "stone"],
	"pocket_change": ["arm", "bangle", "c9a24f", "coins"],
	"sugar_rush": ["book", "ribbon", "e88ab0", ""],
	"wide_wick": ["book", "sigil", "ffd9a0", "wide"],
	"steady_hand": ["arm", "glove", "6b4a35", ""],
	"red_thread": ["arm", "wrap", "c4303c", "thread"],
	"second_wind": ["arm", "tattoo", "9fd0ff", ""],
	"dried_rose": ["book", "pressed", "b8485a", "rose"],
	"warm_soup": ["book", "ribbon", "e08a40", ""],
	"sharp_spark": ["arm", "ring", "ffe08a", ""],
	"splinter": ["book", "stick", "a98458", "splinter"],
	"skipping_stone": ["book", "charm", "8c949a", "stone"],
	"seeking_spark": ["book", "sigil", "ffe5a0", "seek"],
	"chili_oil": ["book", "crust", "ff6a2a", "ember"],
	"winter_mint": ["book", "crust", "bfe8ff", "frost"],
	"bitter_tea": ["book", "crust", "86bf66", "moss"],
	"copper_wire": ["arm", "wrap", "c87a4a", "wire"],
	"firecracker": ["book", "charm", "d8402a", "cracker"],
	"forked_wick": ["book", "candle", "e8dcc0", "twin"],
	"rear_view": ["arm", "ring", "d0d8e0", ""],
	"side_candles": ["book", "inlay", "e8c070", ""],
	"moon_shard": ["book", "charm", "cfe0ff", "moon"],
	"thorn_crown": ["arm", "thorns", "5d6b3c", ""],
	"cinder_steps": ["arm", "tattoo", "ff7a3a", ""],
	"snowglobe": ["book", "charm", "d8f0ff", "globe"],
	"amber_guard": ["arm", "bracer", "d89a3a", "amber"],
	"firefly_jar": ["book", "mote", "e8ff80", "2"],
	"hungry_flame": ["book", "inlay", "ff9040", ""],
	"hunters_mark": ["arm", "tattoo", "d03040", "mark"],
	"last_light": ["book", "candle", "f0e0c8", "stub"],
	"honeycomb": ["book", "charm", "e8b040", "comb"],
	"old_clock": ["arm", "watch", "c8a868", ""],
	"twin_flame": ["book", "sigil", "ffb070", "twin"],
	"shattered_star": ["book", "crust", "c8f0ff", "glass"],
	"storm_lantern": ["book", "sigil", "b8b0ff", "storm"],
	"living_coal": ["book", "gem", "ff5a20", "coal"],
	"deep_freeze": ["arm", "bracer", "a8d8ff", "frost"],
	"sunseed": ["book", "gem", "ffd040", ""],
	"moth_wings": ["arm", "wings", "d8c8a8", ""],
	"ghost_thread": ["arm", "wrap", "c8e0f0", "ghost"],
	"bottled_dawn": ["book", "charm", "ffd8a0", "bottle"],
	"tiny_planets": ["book", "mote", "8fb0ff", "4"],
	"blood_orange": ["arm", "ring", "e05030", ""],
	"mirror_box": ["book", "gem", "e0f0ff", "mirror"],
	"return_address": ["book", "ribbon", "a07040", "tag"],
	"velvet_mantle": ["arm", "sleeve", "6a3a7a", ""],
	"glass_sun": ["book", "sigil", "fff4c0", "sun"],
	"little_supernova": ["book", "sigil", "ffa040", "nova"],
	"aurora": ["book", "inlay", "80ffd0", "aurora"],
	"thousand_wicks": ["book", "candle", "f0e0c0", "crown"],
	"eternal_hearth": ["book", "gem", "ff8040", "hearth"],
	"comet_heart": ["arm", "bangle", "ffe0b0", "comet"],
	"black_wick": ["book", "candle", "2a2028", "black"],
	"hollow_crown": ["arm", "ring", "2e2436", "dark"],
	"widows_lantern": ["book", "charm", "6a5a8a", "lantern"],
	"grave_glass": ["book", "crust", "4a3f5c", "glass"],
	"dark_star": ["book", "sigil", "b090ff", "dark"],
	"starving_flame": ["arm", "tattoo", "b070ff", ""],
	"night_moth": ["arm", "wings", "3e3350", "dark"],
	"ash_mantle": ["arm", "sleeve", "5c5752", "ash"]}
const SLOTS := {"candle": 3, "gem": 5, "ribbon": 4, "charm": 5, "sigil": 4, "mote": 3, "crust": 4, "inlay": 3, "stick": 2,
	"lens": 1, "pressed": 2, "bangle": 4, "ring": 5, "wrap": 3, "bracer": 2, "glove": 1, "sleeve": 2, "tattoo": 3, "watch": 1,
	"wings": 2, "thorns": 1}
const GLOWING := ["mote", "sigil", "inlay", "tattoo"]

static var lit_material: StandardMaterial3D
static var glow_material: StandardMaterial3D

static func look(id: String) -> Array:
	return LOOKS.get(id, [])

## Rebuilds every mark for the relics carried, in the order they were found.
static func dress(rig: Node3D, inventory: Array) -> void:
	var marks: Node3D = rig.get_node_or_null("Marks")
	if marks == null: return
	for child in marks.get_children():
		marks.remove_child(child)
		child.free()
	reset_tints(rig)
	var lit := SurfaceTool.new()
	var glow := SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var used := {}
	var drew := false
	for id in inventory:
		var entry := look(str(id))
		if entry.is_empty(): continue
		var kind: String = entry[1]
		var slot: int = used.get(kind, 0)
		used[kind] = slot + 1
		if slot >= int(SLOTS.get(kind, 1)): continue
		drew = true
		mark(rig, marks, lit, glow, kind, slot, Color(entry[2]), str(entry[3]))
	if drew:
		commit(marks, lit, lit_mat(), "LitMarks")
		commit(marks, glow, glow_mat(), "GlowingMarks")
	pair_sigils(marks, inventory)

## Each pairing the relics complete turns as a small sigil of its own colour
## above the book's head.
static func pair_sigils(marks: Node3D, inventory: Array) -> void:
	var pairs: Array = Synergies.pairings_for(inventory)
	for i in mini(pairs.size(), 6):
		var torus := TorusMesh.new()
		torus.inner_radius = .011
		torus.outer_radius = .016
		torus.rings = 12
		torus.ring_segments = 4
		var node := MeshInstance3D.new()
		node.name = "Pairing_" + str(pairs[i])
		node.mesh = torus
		node.material_override = Geo.material(Synergies.PAIRINGS[pairs[i]][3], .8)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var rest := Transform3D(SpellbookView.frame.basis, SpellbookView.on_book(Vector3(-.1 + i * .04, .05, -.135)))
		node.transform = rest
		node.set_meta("rest", rest)
		node.set_meta("spin", 1.4 + i * .3)
		marks.add_child(node)

static func commit(marks: Node3D, tool: SurfaceTool, material: Material, label: String) -> void:
	var mesh := tool.commit()
	if mesh.get_surface_count() == 0: return
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marks.add_child(node)

static func lit_mat() -> StandardMaterial3D:
	if lit_material == null:
		lit_material = StandardMaterial3D.new()
		lit_material.vertex_color_use_as_albedo = true
		lit_material.roughness = .55
		lit_material.metallic = .25
	return lit_material

static func glow_mat() -> StandardMaterial3D:
	if glow_material == null:
		glow_material = StandardMaterial3D.new()
		glow_material.vertex_color_use_as_albedo = true
		glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return glow_material

static func reset_tints(rig: Node3D) -> void:
	var hand: MeshInstance3D = rig.get_node_or_null("Hand")
	if hand: hand.material_override = Geo.material(SpellbookView.SKIN)
	var sleeve: MeshInstance3D = rig.get_node_or_null("Sleeve")
	if sleeve: sleeve.material_override = Geo.material(SpellbookView.SLEEVE)
	var cuff: MeshInstance3D = rig.get_node_or_null("Cuff")
	if cuff: cuff.material_override = Geo.material(SpellbookView.CUFF)

## Turns sigils, carries motes round the book and lets nothing else move.
static func animate(rig: Node3D, time: float) -> void:
	var marks: Node3D = rig.get_node_or_null("Marks")
	if marks == null: return
	for node in marks.get_children():
		if node.has_meta("spin"):
			node.transform = node.get_meta("rest") * Transform3D(Basis(Vector3.UP, time * float(node.get_meta("spin"))), Vector3.ZERO)
		elif node.has_meta("orbit"):
			var phase: float = time * float(node.get_meta("orbit")) + float(node.get_meta("phase"))
			var center: Vector3 = node.get_meta("center")
			var radius: float = node.get_meta("radius")
			node.position = center + SpellbookView.frame.basis * Vector3(cos(phase) * radius, .05 + sin(phase * 1.7) * .02, sin(phase) * radius * .6)

## Directions in the rig's own space: world up, and along the forearm.
static func up_on_book() -> Vector3:
	return (SpellbookView.frame.basis.inverse() * Vector3.UP).normalized()

static func mark(rig: Node3D, marks: Node3D, lit: SurfaceTool, glow: SurfaceTool, kind: String, slot: int, color: Color, variant: String) -> void:
	var book := SpellbookView.frame
	match kind:
		"candle":
			var corners := [Vector3(-.15, .006, -.104), Vector3(.15, .006, -.104), Vector3(-.15, .006, .1)]
			if variant == "crown":
				for i in 5: candle(marks, lit, book, Vector3(-.1 + i * .05, .03, -.112), color, .022 + (i % 2) * .008, .006)
			else:
				var height := .018 if variant == "stub" else (.05 if variant == "twin" else .04)
				candle(marks, lit, book, corners[slot], color, height, .011)
				if variant == "twin": candle(marks, lit, book, corners[slot] + Vector3(.022 * (-1 if slot == 1 else 1), 0, .012), color, .03, .008)
		"gem":
			var places := [Vector3(-.163, .012, -.107), Vector3(.163, .012, -.107), Vector3(-.163, .012, .107), Vector3(.163, .012, .107), Vector3(0, -.006, .121)]
			var size := .016 if variant in ["hearth", "coal"] else .011
			SpellbookView.box(lit, book * Transform3D(Basis(Vector3.UP, PI / 4), places[slot]), Vector3.ZERO, Vector3(size, size * .8, size), color.darkened(.2))
			SpellbookView.sphere(glow, book * Transform3D(Basis(), places[slot] + Vector3(0, size * .5, 0)), size * .55, color.lightened(.3) if variant != "mirror" else Color(.9, .97, 1.0))
		"ribbon":
			var x: float = [-.05, .035, -.1, .09][slot]
			var start := book * Vector3(x, .02, .1)
			var down := Vector3(0, -1, .12).normalized()
			for i in 6:
				var at := start + down * (i * .02) + Vector3(sin(i * .9) * .004, 0, 0)
				SpellbookView.box(lit, Transform3D(Basis(Vector3.BACK, sin(i * .9) * .2), at), Vector3.ZERO, Vector3(.012, .022, .002), color)
			var tip := start + down * .125
			if variant == "tag":
				SpellbookView.box(lit, Transform3D(Basis(Vector3.BACK, .3), tip), Vector3.ZERO, Vector3(.032, .022, .003), Color("d8c8a0"))
				SpellbookView.box(lit, Transform3D(Basis(Vector3.BACK, .3), tip + Vector3(0, 0, .002)), Vector3.ZERO, Vector3(.012, .012, .003), color.darkened(.3))
			else:
				for side: int in [-1, 1]:
					SpellbookView.box(lit, Transform3D(Basis(Vector3.BACK, side * .45), tip + Vector3(side * .004, -.004, 0)), Vector3.ZERO, Vector3(.006, .016, .002), color.darkened(.15))
		"charm":
			var hang := book * Vector3(-.03 + slot * .016, -.016, .124)
			var drop := .04 + (slot % 3) * .014
			SpellbookView.limb(lit, hang, hang + Vector3(0, -drop, .01), .0015, .0015, Color("8b7a5a"))
			charm(lit, glow, hang + Vector3(0, -drop - .012, .01), color, variant)
		"sigil":
			var node := MeshInstance3D.new()
			var torus := TorusMesh.new()
			var radius: float = float([.042, .052, .034, .062][slot]) * (1.3 if variant in ["wide", "sun", "nova"] else 1.0)
			torus.inner_radius = radius
			torus.outer_radius = radius + (.0025 if variant != "sun" else .004)
			torus.rings = 40
			torus.ring_segments = 4
			node.mesh = torus
			node.material_override = Geo.material(color.darkened(.15), .7) if variant != "dark" else Geo.material(color.darkened(.35), .6)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var rest := book * Transform3D(Basis(Vector3.RIGHT, .25 * slot) * Basis(Vector3.BACK, -.2 + .15 * slot), Vector3(.085 - slot * .055, .045 + slot * .014, -.02 + slot * .012))
			node.set_meta("rest", rest)
			node.set_meta("spin", (.6 + slot * .35) * (-1 if slot % 2 else 1))
			marks.add_child(node)
			node.transform = rest
			# Rune beads on the ring, and a second linked ring for twins.
			for i in (6 if variant != "seek" else 3):
				var bead := MeshInstance3D.new()
				bead.mesh = Geo.shared_box(Vector3.ONE * .006)
				bead.material_override = node.material_override
				bead.position = Vector3(cos(i * TAU / 6) * radius, 0, sin(i * TAU / 6) * radius)
				node.add_child(bead)
			if variant in ["twin", "storm", "aurora", "nova"]:
				var inner := MeshInstance3D.new()
				var small := TorusMesh.new()
				small.inner_radius = radius * .62
				small.outer_radius = radius * .62 + .003
				small.rings = 32
				small.ring_segments = 4
				inner.mesh = small
				inner.material_override = node.material_override
				inner.rotation = Vector3(.9, 0, .4)
				node.add_child(inner)
		"mote":
			for i in int(variant):
				var mote := MeshInstance3D.new()
				var ball := SphereMesh.new()
				ball.radius = .008 if variant == "1" else .011
				ball.height = ball.radius * 2.0
				ball.radial_segments = 8
				ball.rings = 4
				mote.mesh = ball
				var hue := color
				hue.h = fposmod(hue.h + i * .12, 1.0)
				mote.material_override = Geo.material(hue, 2.0)
				mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mote.set_meta("orbit", (1.4 - i * .2) * (1.0 + slot * .25) * (-1.0 if slot % 2 else 1.0))
				mote.set_meta("phase", i * TAU / maxf(1, int(variant)) + slot)
				mote.set_meta("center", book.origin)
				mote.set_meta("radius", .19 + i * .015 + slot * .035)
				marks.add_child(mote)
		"crust":
			var edges := [[Vector3(-.17, .004, -.1), Vector3(-.17, .004, .1)], [Vector3(.17, .004, -.1), Vector3(.17, .004, .1)],
				[Vector3(-.15, .004, .115), Vector3(-.02, .004, .115)], [Vector3(.02, .004, .115), Vector3(.15, .004, .115)]]
			var edge: Array = edges[slot]
			for i in 9:
				var t := (i + .5) / 9.0
				var at: Vector3 = edge[0].lerp(edge[1], t) + Vector3(0, fmod(i * .37, 1.0) * .006, 0)
				crystal(lit, glow, book, at, color, variant, i)
		"inlay":
			var lines := [[Vector3(-.159, .016, -.1), Vector3(-.159, .016, .1)], [Vector3(.159, .016, -.1), Vector3(.159, .016, .1)], [Vector3(-.15, .016, .108), Vector3(.15, .016, .108)]]
			var line: Array = lines[slot]
			for i in 12:
				var hue := color
				if variant == "aurora": hue.h = fposmod(hue.h + i * .05, 1.0)
				var at: Vector3 = line[0].lerp(line[1], (i + .5) / 12.0)
				SpellbookView.box(glow, book * Transform3D(Basis(), at), Vector3.ZERO, Vector3(.004, .02, .016) if slot < 2 else Vector3(.024, .02, .004), hue)
		"stick":
			var from := book * Vector3(.012 + slot * .03, .028, -.03)
			var to := book * Vector3(.03 + slot * .05, .05, -.2)
			SpellbookView.limb(lit, from, to, .0028, .0024, color)
			if variant == "match": SpellbookView.sphere(lit, Transform3D(Basis(), to), .0055, Color("b0302a"))
		"lens":
			var center := Transform3D(SpellbookView.frame.basis * Basis(Vector3.RIGHT, -.35), book * Vector3(.09, .05, .025))
			SpellbookView.ring(lit, center, .03, .036, color)
			SpellbookView.limb(lit, center * Vector3(0, 0, .033), center * Vector3(0, 0, .085), .003, .003, color.darkened(.3))
			SpellbookView.cylinder(glow, center, .03, .001, Color(.5, .6, .62))
		"pressed":
			var at := book * Vector3([.168, -.168][slot], .014, [.02, -.04][slot])
			for i in 5:
				var petal := Transform3D(Basis(Vector3.UP, i * TAU / 5) * Basis(Vector3.RIGHT, .4), at)
				SpellbookView.box(lit, petal, Vector3(0, 0, .01), Vector3(.01, .002, .018), color if variant == "rose" else Color("7a9a4a"))
		"bangle":
			var where := SpellbookView.on_arm([.018, .034, .05, .064][slot])
			var basis := arm_basis()
			SpellbookView.ring(lit, Transform3D(basis, where), .036, .042, color)
			if variant in ["spark", "comet"]:
				SpellbookView.sphere(glow, Transform3D(basis, where + basis.x * .04), .006, color.lightened(.4))
			elif variant == "coins":
				for i in 5: SpellbookView.cylinder(lit, Transform3D(basis * Basis(Vector3.UP, i * TAU / 5), where) * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(.044, 0, 0)), .008, .002, color.lightened(.15))
		"ring":
			var fingers := [Vector3(.17, -.012, -.042), Vector3(.17, -.012, -.014), Vector3(.17, -.012, .014), Vector3(.17, -.012, .042), Vector3(-.04, .02, .07)]
			var at := book * Transform3D(Basis(Vector3.BACK, deg_to_rad(-8)) * Basis(Vector3.RIGHT, PI / 2), fingers[slot])
			SpellbookView.ring(lit, at, .011, .015, color)
			SpellbookView.sphere(glow if variant != "dark" else lit, at * Transform3D(Basis(), Vector3(-.014, 0, 0)), .0055, color.lightened(.35))
		"wrap":
			var basis := arm_basis()
			for i in 5:
				var at := SpellbookView.on_arm(.004 + slot * .018 + i * .0035)
				SpellbookView.ring(lit if variant != "ghost" else glow, Transform3D(basis * Basis(Vector3.FORWARD, .25 + i * .05), at), .035, .0385 if variant != "thread" else .0365, color)
		"bracer":
			var basis := arm_basis()
			var along := .14 + slot * .16
			SpellbookView.limb(lit, SpellbookView.on_arm(along), SpellbookView.on_arm(along + .13), .076, .086, color)
			for i in 4:
				SpellbookView.sphere(glow if variant in ["amber", "frost"] else lit, Transform3D(basis, SpellbookView.on_arm(along + .02 + i * .03) + basis.x * .08), .007, color.lightened(.35))
		"glove":
			var hand: MeshInstance3D = rig.get_node_or_null("Hand")
			if hand: hand.material_override = Geo.material(color)
		"sleeve":
			var node: MeshInstance3D = rig.get_node_or_null("Sleeve" if slot == 0 else "Cuff")
			if node: node.material_override = Geo.material(color)
		"tattoo":
			var basis := arm_basis()
			var side: Vector3 = [basis.x, -basis.x, basis.z][slot]
			for i in 5:
				SpellbookView.box(glow, Transform3D(basis, SpellbookView.on_arm(.008 + i * .012) + side * .037), Vector3.ZERO, Vector3(.004, .009, .004), color)
			if variant == "mark": SpellbookView.ring(glow, Transform3D(basis * Basis(Vector3.RIGHT, PI / 2), SpellbookView.on_arm(.03) + side * .039), .007, .009, color)
		"watch":
			var basis := arm_basis()
			var face := Transform3D(basis * Basis(Vector3.BACK, PI / 2), SpellbookView.on_arm(.04) + basis.x * .039)
			SpellbookView.cylinder(lit, face, .014, .006, color)
			SpellbookView.cylinder(glow, face * Transform3D(Basis(), Vector3(0, .0035, 0)), .011, .001, Color("f0e8d0"))
			SpellbookView.ring(lit, Transform3D(basis, SpellbookView.on_arm(.04)), .036, .040, color.darkened(.35))
		"wings":
			var basis := arm_basis()
			for side: int in [-1, 1]:
				var root := SpellbookView.on_arm(.08) + basis.x * side * .06
				var wing := Transform3D(basis * Basis(Vector3.FORWARD, side * (.7 + slot * .3)), root)
				SpellbookView.box(lit, wing, Vector3(side * .03, .02, 0), Vector3(.06, .045, .003), color)
				SpellbookView.box(glow, wing, Vector3(side * .03, .02, .002), Vector3(.012, .012, .001), color.lightened(.4) if variant != "dark" else Color("b070ff"))
		"thorns":
			var basis := arm_basis()
			for i in 14:
				var angle := i * .9
				var at := SpellbookView.on_arm(.09 + i * .022) + (basis.x * cos(angle) + basis.z * sin(angle)) * .075
				SpellbookView.limb(lit, at, at + (basis.x * cos(angle) + basis.z * sin(angle)) * .018, .006, .0005, color)

## The forearm's frame: Y along it toward the elbow, X to its outer side.
static func arm_basis() -> Basis:
	var up := SpellbookView.forearm
	var side := up.cross(Vector3.FORWARD).normalized()
	return Basis(side, up, side.cross(up)).orthonormalized()

static func candle(marks: Node3D, lit: SurfaceTool, book: Transform3D, at: Vector3, color: Color, height: float, radius: float) -> void:
	var up := Vector3.UP
	var base := book * at
	var basis := Basis(up.cross(Vector3.BACK).normalized(), up, up.cross(Vector3.BACK).normalized().cross(up)).orthonormalized()
	SpellbookView.cylinder(lit, Transform3D(basis, base + up * height * .5), radius, height, color)
	SpellbookView.limb(lit, base + up * height, base + up * (height + .006), .0012, .0012, Color("2a2420"))
	var flame := MeshInstance3D.new()
	flame.mesh = DungeonStyle.candle_flame_mesh()
	flame.material_override = DungeonStyle.candle_flame()
	flame.scale = Vector3.ONE * (.12 + radius * 2.0)
	flame.position = base + up * (height + .012)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marks.add_child(flame)

static func charm(lit: SurfaceTool, glow: SurfaceTool, at: Vector3, color: Color, variant: String) -> void:
	match variant:
		"coin": SpellbookView.cylinder(lit, Transform3D(Basis(Vector3.RIGHT, PI / 2), at), .012, .003, color)
		"stone": SpellbookView.sphere(lit, Transform3D(Basis().scaled(Vector3(1.2, .8, .9)), at), .011, color)
		"cracker":
			SpellbookView.cylinder(lit, Transform3D(Basis(Vector3.BACK, .3), at), .006, .026, color)
			SpellbookView.sphere(glow, Transform3D(Basis(), at + Vector3(.005, .016, 0)), .003, Color("ffcf70"))
		"moon":
			SpellbookView.ring(glow, Transform3D(Basis(Vector3.RIGHT, PI / 2), at), .007, .012, color)
		"globe":
			SpellbookView.sphere(glow, Transform3D(Basis(), at), .012, color)
			SpellbookView.cylinder(lit, Transform3D(Basis(), at + Vector3(0, -.013, 0)), .008, .005, Color("8b6a44"))
		"comb": SpellbookView.cylinder(lit, Transform3D(Basis(Vector3.RIGHT, PI / 2), at), .012, .006, color)
		"bottle":
			SpellbookView.sphere(glow, Transform3D(Basis().scaled(Vector3(1, 1.3, 1)), at), .01, color)
			SpellbookView.cylinder(lit, Transform3D(Basis(), at + Vector3(0, .016, 0)), .004, .008, Color("8b6a44"))
		"lantern":
			SpellbookView.box(lit, Transform3D(Basis(), at), Vector3.ZERO, Vector3(.016, .022, .016), color.darkened(.4))
			SpellbookView.sphere(glow, Transform3D(Basis(), at), .006, Color("c8a0ff"))
		_: SpellbookView.sphere(lit, Transform3D(Basis(), at), .01, color)

static func crystal(lit: SurfaceTool, glow: SurfaceTool, book: Transform3D, at: Vector3, color: Color, variant: String, i: int) -> void:
	var lean := Basis(Vector3.BACK, sin(i * 2.3) * .5) * Basis(Vector3.RIGHT, cos(i * 1.7) * .4)
	match variant:
		"ember": SpellbookView.box(glow, book * Transform3D(lean, at), Vector3.ZERO, Vector3(.008, .004, .012), color.lerp(Color("ffd070"), fmod(i * .31, 1.0)))
		"frost": SpellbookView.box(glow, book * Transform3D(lean, at), Vector3(0, .008, 0), Vector3(.004, .018 + fmod(i * .41, 1.0) * .012, .004), color)
		"moss": SpellbookView.sphere(lit, book * Transform3D(Basis().scaled(Vector3(1.4, .6, 1.4)), at), .007, color.darkened(fmod(i * .23, .3)))
		_: SpellbookView.box(lit if variant != "glass" else glow, book * Transform3D(lean, at), Vector3(0, .006, 0), Vector3(.003, .016, .008), color)
