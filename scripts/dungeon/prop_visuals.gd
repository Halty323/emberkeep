class_name PropVisuals
extends RefCounted
## Replaceable procedural visuals for each furniture recipe: rough wood,
## stone and brass with beveled caps and warm accents. Recipes are built in
## a local frame (width along x, depth along z, front facing +z).
const RECIPES := ["pillar", "table", "chair", "bookcase", "bench", "cupboard", "crate", "barrel", "jar", "brazier",
	"wall_shelf", "book_pile", "rug", "partition", "workbench", "cot", "painting_frame"]
# Solid furniture that does not block shots collides on its own layer.
const FURNITURE_LAYER := 8
const WOOD := Color("6b4e36")
const DARK_WOOD := Color("4e3a2a")
const LIGHT_WOOD := Color("8a6845")
const BRASS := Color("b39258")
const STONE := Color("4f5855")
const BOOKS := [Color("7c3f35"), Color("3f5a4a"), Color("6a5a2e"), Color("40506b"), Color("8a6a3a"), Color("5b3b52"), Color("a68a5a")]
const RUGS := [[Color("6e3b33"), Color("c49a5a")], [Color("3d4f5c"), Color("b8a27a")], [Color("5a4a2e"), Color("9fb08c")]]

## Builds one prop. Returns {"node", "base", "collider", "occluder"}. The
## visual node may cut away for the camera; collision and any shadow-only
## occluder live on a separate static base that never moves.
static func build(room: Node3D, record: Dictionary, definition: Dictionary, detail: int, batch: DetailBatch, cell: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var node = Node3D.new()
	room.add_child(node)
	node.position = Vector3(float(record.position[0]), 0, float(record.position[1]))
	node.rotation.y = -float(record.get("rotation", 0)) * PI / 2.0
	var w = float(definition.size[0])
	var d = float(definition.size[1])
	var h = float(definition.height)
	var put = func(local: Transform3D, color: Color): batch.add(cell, node.transform * local, color)
	match definition.recipe:
		"pillar":
			Geo.box(node, Vector3(0, .6, 0), Vector3(1.2, 1.2, 1.2), STONE)
			Geo.box(node, Vector3(0, 1.22, 0), Vector3(1.35, .14, 1.35), Color("747b68"))
		"table":
			Geo.box(node, Vector3(0, h - .05, 0), Vector3(w, .1, d), LIGHT_WOOD)
			for x in [-1, 1]:
				for z in [-1, 1]:
					Geo.box(node, Vector3(x * (w / 2 - .12), (h - .1) / 2, z * (d / 2 - .12)), Vector3(.1, h - .1, .1), DARK_WOOD)
			if detail >= 1:
				put.call(Transform3D(Basis().scaled(Vector3(.32, .06, .24)).rotated(Vector3.UP, .4), Vector3(-.3, h + .03, .1)), BOOKS[rng.randi_range(0, BOOKS.size() - 1)])
				Geo.cylinder(node, Vector3(.4, h + .1, -.15), .05, .2, Color("c9ad7e"))
		"chair":
			Geo.box(node, Vector3(0, .45, 0), Vector3(w, .07, d), WOOD)
			Geo.box(node, Vector3(0, .78, -d / 2 + .04), Vector3(w, .6, .07), WOOD)
			for x in [-1, 1]:
				for z in [-1, 1]:
					Geo.box(node, Vector3(x * (w / 2 - .06), .21, z * (d / 2 - .06)), Vector3(.06, .42, .06), DARK_WOOD)
		"bookcase":
			Geo.box(node, Vector3(0, h / 2, -d / 2 + .04), Vector3(w, h, .08), DARK_WOOD)
			for x in [-1, 1]:
				Geo.box(node, Vector3(x * (w / 2 - .04), h / 2, 0), Vector3(.08, h, d), WOOD)
			Geo.box(node, Vector3(0, h, 0), Vector3(w + .1, .08, d + .06), LIGHT_WOOD)
			var shelves = 4
			var fill = [.45, .75, .92][detail]
			for shelf in shelves:
				var y = .1 + shelf * (h - .1) / shelves
				Geo.box(node, Vector3(0, y, 0), Vector3(w - .1, .05, d - .04), WOOD)
				var x = -w / 2 + .14
				while x < w / 2 - .14:
					var thickness = rng.randf_range(.06, .11)
					if rng.randf() < fill:
						var tall = rng.randf_range(.26, .4)
						var lean = rng.randf_range(-.18, .18) if rng.randf() < .15 else 0.0
						put.call(Transform3D(Basis().scaled(Vector3(thickness, tall, d * .7)).rotated(Vector3.BACK, lean), Vector3(x, y + .03 + tall / 2, .02)),
							BOOKS[rng.randi_range(0, BOOKS.size() - 1)])
					x += thickness + .012
		"bench":
			Geo.box(node, Vector3(0, h - .04, 0), Vector3(w, .08, d), LIGHT_WOOD)
			for x in [-1, 1]:
				Geo.box(node, Vector3(x * (w / 2 - .2), (h - .08) / 2, 0), Vector3(.12, h - .08, d - .1), DARK_WOOD)
		"cupboard":
			Geo.box(node, Vector3(0, h / 2, 0), Vector3(w, h, d), WOOD)
			Geo.box(node, Vector3(0, h + .03, 0), Vector3(w + .08, .07, d + .06), LIGHT_WOOD)
			for x in [-1, 1]:
				Geo.box(node, Vector3(x * w / 4, h * .55, d / 2 + .01), Vector3(w / 2 - .1, h * .75, .02), DARK_WOOD)
				Geo.sphere(node, Vector3(x * .06, h * .55, d / 2 + .04), .035, BRASS)
			if detail >= 1:
				for i in 2 + detail:
					put.call(Transform3D(Basis().scaled(Vector3(.12, .22, .12)), Vector3(-w / 2 + .25 + i * .3, h + .17, 0)), Color("8fa3a0") if i % 2 == 0 else Color("b48a5e"))
		"crate":
			Geo.box(node, Vector3(0, h / 2, 0), Vector3(w, h, d), LIGHT_WOOD)
			for y in [.12, h - .12]:
				put.call(Transform3D(Basis().scaled(Vector3(w + .02, .08, d + .02)), Vector3(0, y, 0)), DARK_WOOD)
			put.call(Transform3D(Basis().scaled(Vector3(.08, h * 1.25, .02)).rotated(Vector3.BACK, .78), Vector3(0, h / 2, d / 2 + .01)), DARK_WOOD)
		"barrel":
			Geo.cylinder(node, Vector3(0, h / 2, 0), w / 2 - .04, h, WOOD, 0.0, w / 2 - .1)
			for y in [.18, h - .18]:
				var hoop = Geo.ring(node, Vector3(0, y, 0), w / 2 - .05, Color("5d5a52"), .03)
				hoop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			Geo.cylinder(node, Vector3(0, h + .01, 0), w / 2 - .1, .03, DARK_WOOD)
		"jar":
			var belly = Geo.sphere(node, Vector3(0, .3, 0), w / 2, Color("a7684a"))
			belly.scale = Vector3(1, 1.15, 1)
			Geo.cylinder(node, Vector3(0, .62, 0), .1, .14, Color("b97a58"))
			var lip = Geo.ring(node, Vector3(0, .69, 0), .11, Color("d9a87a"), .02)
			lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"brazier":
			for i in 3:
				var leg = Geo.box(node, Vector3(cos(TAU * i / 3) * .25, .4, sin(TAU * i / 3) * .25), Vector3(.06, .8, .06), Color("4a4540"))
				leg.rotation.z = .08
			Geo.cylinder(node, Vector3(0, .86, 0), .4, .2, Color("5c544a"), 0.0, .26)
			var coals = Geo.sphere(node, Vector3(0, .95, 0), .26, Color("ff9a4d"), 2.2)
			coals.scale = Vector3(1, .35, 1)
			var flame = Geo.sphere(node, Vector3(0, 1.15, 0), .16, Color("ffd28a"), 2.6)
			flame.scale = Vector3(.8, 1.6, .8)
			flame.name = "Flame"
			# Warmth without a real light: the shared budget keeps one shadow light.
			Geo.halo(node, Vector3(0, .03, 0), 3.6, Color(1, .55, .2, .26))
			var glow = Geo.halo(node, Vector3(0, 1.1, 0), 1.6, Color(1, .6, .25, .4))
			glow.rotation_degrees.x = 58
		"wall_shelf":
			Geo.box(node, Vector3(0, h - .3, 0), Vector3(w, .06, d), LIGHT_WOOD)
			for x in [-1, 1]:
				Geo.box(node, Vector3(x * (w / 2 - .15), h - .42, -d / 2 + .06), Vector3(.05, .22, .12), DARK_WOOD)
			for i in [2, 4, 6][detail]:
				var bottle = rng.randf() < .5
				var scale = Vector3(.1, rng.randf_range(.18, .3), .1) if bottle else Vector3(rng.randf_range(.06, .1), rng.randf_range(.2, .3), .2)
				put.call(Transform3D(Basis().scaled(scale), Vector3(-w / 2 + .2 + i * (w - .4) / 6.0, h - .27 + scale.y / 2, 0)),
					Color("7fa39a") if bottle else BOOKS[rng.randi_range(0, BOOKS.size() - 1)])
		"book_pile":
			var y = 0.0
			for i in rng.randi_range(2, 4):
				var thickness = rng.randf_range(.05, .08)
				put.call(Transform3D(Basis().scaled(Vector3(rng.randf_range(.32, .42), thickness, rng.randf_range(.24, .3))).rotated(Vector3.UP, rng.randf_range(-.4, .4)),
					Vector3(0, y + thickness / 2, 0)), BOOKS[rng.randi_range(0, BOOKS.size() - 1)])
				y += thickness
		"rug":
			var colors: Array = RUGS[rng.randi_range(0, RUGS.size() - 1)]
			var base = Geo.box(node, Vector3(0, -.005, 0), Vector3(w, .02, d), colors[1])
			base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var field = Geo.box(node, Vector3(0, .0, 0), Vector3(w - .3, .02, d - .3), colors[0])
			field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if detail >= 1:
				for x in [-1, 1]:
					for i in 7:
						put.call(Transform3D(Basis().scaled(Vector3(.12, .015, .03)), Vector3(x * (w / 2 + .05), .0, -d / 2 + .15 + i * (d - .3) / 6.0)), colors[1])
		"partition":
			Geo.box(node, Vector3(0, h / 2, 0), Vector3(w, h, d), Color("5a5f58"))
			Geo.box(node, Vector3(0, h + .04, 0), Vector3(w + .08, .08, d + .08), Color("767a6a"))
		"workbench":
			Geo.box(node, Vector3(0, h - .06, 0), Vector3(w, .12, d), LIGHT_WOOD)
			for x in [-1, 1]:
				Geo.box(node, Vector3(x * (w / 2 - .12), (h - .12) / 2, 0), Vector3(.12, h - .12, d - .1), DARK_WOOD)
			Geo.box(node, Vector3(0, .25, 0), Vector3(w - .3, .06, d - .2), WOOD)
			if detail >= 1:
				put.call(Transform3D(Basis().scaled(Vector3(.35, .05, .08)).rotated(Vector3.UP, .3), Vector3(-.4, h + .03, 0)), Color("8a8f92"))
				put.call(Transform3D(Basis().scaled(Vector3(.18, .14, .18)), Vector3(.5, h + .07, -.1)), BRASS)
		"cot":
			Geo.box(node, Vector3(0, .22, 0), Vector3(w, .12, d), DARK_WOOD)
			for x in [-1, 1]:
				for z in [-1, 1]:
					Geo.box(node, Vector3(x * (w / 2 - .08), .08, z * (d / 2 - .08)), Vector3(.08, .16, .08), DARK_WOOD)
			Geo.box(node, Vector3(0, .33, 0), Vector3(w - .1, .1, d - .1), Color("c9b896"))
			Geo.box(node, Vector3(.25, .4, 0), Vector3(w * .65, .06, d - .06), Color("6c4a52"))
			Geo.box(node, Vector3(-w / 2 + .3, .42, 0), Vector3(.35, .1, d - .3), Color("e2d6bc"))
		"painting_frame":
			Geo.box(node, Vector3(0, h / 2, 0), Vector3(w, h, d), Color("6d5232"))
	var base = Node3D.new()
	room.add_child(base)
	base.transform = node.transform
	var collider: StaticBody3D = null
	if definition.get("solid", false):
		collider = Geo.collider(base, Vector3(0, 1.0, 0), Vector3(w, 2.0, d))
		collider.collision_layer = 1 if definition.get("blocks_shots", false) else FURNITURE_LAYER
		collider.set_meta("prop_id", record.id)
	# Free-standing pieces taller than a small foe can hide one from the camera.
	var occludes = h >= 1.0 and definition.placement != "wall"
	if not definition.get("shadow", false) or occludes:
		for child in node.get_children():
			if child is GeometryInstance3D: child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var occluder = {}
	if occludes:
		if definition.get("shadow", false):
			var caster = Geo.box(base, Vector3(0, h / 2, 0), Vector3(w, h, d), DARK_WOOD)
			caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		occluder = {"node": node, "position": Vector2(node.position.x, node.position.z),
			"half": Vector2(float(record.size[0]), float(record.size[1])) / 2.0, "height": 1.0}
	return {"node": node, "base": base, "collider": collider, "occluder": occluder}
