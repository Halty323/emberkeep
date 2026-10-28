class_name PropBuilder
extends RefCounted
## Procedural placeholder furniture. Each recipe is built in prop space with
## its back toward -Z and its footprint centred on the origin; the caller
## rotates the node. Small details only add cosmetic meshes: collision and
## breakable state never depend on the detail setting.

static func build(parent: Node3D, def: Dictionary, record: Dictionary, detail: int) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	node.position = Vector3(record.position[0], 0, record.position[1])
	node.rotation.y = int(record.rotation) * PI / 2.0
	node.set_meta("prop_id", record.id)
	var w := float(def.size[0])
	var d := float(def.size[1])
	var h := float(def.height)
	var color := Color(def.get("color", "#5d4a3a"))
	var dark := color.darkened(.25)
	var brass := Color("b1925c")
	match def.recipe:
		"pillar":
			Geo.box(node, Vector3(0, .6, 0), Vector3(1.2, 1.2, 1.2), Color("4f5855"))
			Geo.box(node, Vector3(0, 1.22, 0), Vector3(1.35, .14, 1.35), Color("747b68"))
		"table":
			Geo.box(node, Vector3(0, h - .05, 0), Vector3(w, .1, d), color)
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					Geo.box(node, Vector3(sx * (w / 2 - .12), (h - .1) / 2, sz * (d / 2 - .12)), Vector3(.1, h - .1, .1), dark)
			if detail > 0:
				Geo.cylinder(node, Vector3(-.4, h + .05, .1), .09, .1, Color("d9cfb8"))
				Geo.box(node, Vector3(.35, h + .03, -.05), Vector3(.4, .05, .3), Color("8a5a48"))
		"chair", "stool":
			Geo.box(node, Vector3(0, h - .04, 0), Vector3(w, .08, d), color)
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					Geo.box(node, Vector3(sx * (w / 2 - .07), (h - .08) / 2, sz * (d / 2 - .07)), Vector3(.07, h - .08, .07), dark)
			if def.recipe == "chair":
				Geo.box(node, Vector3(0, h + .3, -d / 2 + .04), Vector3(w, .6, .07), color)
		"bookcase", "shelf":
			if def.recipe == "bookcase":
				Geo.box(node, Vector3(0, h / 2, 0), Vector3(w, h, d), dark)
			var shelves := 4 if def.recipe == "bookcase" else 2
			var base := 0.15 if def.recipe == "bookcase" else h - .7
			for i in shelves:
				var y := base + i * (h - .2) / shelves if def.recipe == "bookcase" else base + i * .55
				Geo.box(node, Vector3(0, y, .04), Vector3(w + .04, .06, d - .04), color)
				if detail > 0:
					var x := -w / 2 + .15
					var spine := 0
					while x < w / 2 - .15:
						var book_w := .07 + float(posmod(spine * 7 + i * 3, 4)) * .025
						var book_h := .22 + float(posmod(spine * 5 + i, 3)) * .05
						var tone: Color = [Color("8a4b3c"), Color("4f6b5a"), Color("7a6a3f"), Color("51577a"), Color("9a7a5a")][posmod(spine + i * 2, 5)]
						Geo.box(node, Vector3(x + book_w / 2, y + .03 + book_h / 2, .06), Vector3(book_w, book_h, d * .7), tone)
						x += book_w + .015
						spine += 1
						if detail == 1 and spine > 6: break
		"cupboard":
			Geo.box(node, Vector3(0, h / 2, 0), Vector3(w, h, d), color)
			Geo.box(node, Vector3(0, h / 2, d / 2 + .01), Vector3(.03, h - .2, .02), dark)
			for sx in [-1, 1]:
				Geo.box(node, Vector3(sx * .1, h * .55, d / 2 + .03), Vector3(.05, .12, .04), brass, .2)
			Geo.box(node, Vector3(0, h + .04, 0), Vector3(w + .08, .08, d + .08), dark)
		"bench":
			Geo.box(node, Vector3(0, h - .05, 0), Vector3(w, .1, d), color)
			for sx in [-1, 1]:
				Geo.box(node, Vector3(sx * (w / 2 - .2), (h - .1) / 2, 0), Vector3(.12, h - .1, d - .1), dark)
		"crate":
			Geo.box(node, Vector3(0, h / 2, 0), Vector3(w, h, d), color)
			for s in [-1, 1]:
				Geo.box(node, Vector3(0, h / 2, s * (d / 2 + .005)), Vector3(w * .95, .1, .02), dark)
				Geo.box(node, Vector3(s * (w / 2 + .005), h / 2, 0), Vector3(.02, .1, d * .95), dark)
		"barrel":
			Geo.cylinder(node, Vector3(0, h / 2, 0), w / 2, h, color)
			for y in [.18, h - .18]:
				Geo.cylinder(node, Vector3(0, y, 0), w / 2 + .02, .06, Color("5a5a55"))
		"jar":
			Geo.sphere(node, Vector3(0, .32, 0), w / 2, color)
			Geo.cylinder(node, Vector3(0, .62, 0), w * .28, .16, color.darkened(.1))
		"brazier":
			Geo.cylinder(node, Vector3(0, .35, 0), .14, .7, dark)
			Geo.cylinder(node, Vector3(0, .78, 0), w / 2, .18, Color("5f5a50"))
			Geo.sphere(node, Vector3(0, .9, 0), .2, Color("ffb35c"), 2.4)
			Geo.halo(node, Vector3(0, .03, 0), 2.6, Color(1, .62, .26, .22))
		"book_pile":
			for i in 3 + detail:
				var tone: Color = [Color("8a4b3c"), Color("4f6b5a"), Color("7a6a3f"), Color("51577a"), Color("9a7a5a")][i % 5]
				var book := Geo.box(node, Vector3(sin(i * 1.7) * .05, .04 + i * .07, cos(i * 2.3) * .04), Vector3(w * .8, .065, d * .75), tone)
				book.rotation.y = sin(i * 2.9) * .3
				book.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"rug":
			var rug := Geo.box(node, Vector3(0, -.004, 0), Vector3(w, .02, d), color)
			rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var border := Geo.box(node, Vector3(0, -.008, 0), Vector3(w + .16, .02, d + .16), Color("a68a5c"))
			border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if detail > 0:
				var inner := Geo.box(node, Vector3(0, 0, 0), Vector3(w * .6, .02, d * .5), color.lightened(.12))
				inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"partition":
			Geo.box(node, Vector3(0, h / 2, 0), Vector3(w, h, d), color)
			Geo.box(node, Vector3(0, h + .04, 0), Vector3(w + .08, .08, d + .08), Color("747b68"))
		"workbench":
			Geo.box(node, Vector3(0, h - .06, 0), Vector3(w, .12, d), color)
			for sx in [-1, 1]:
				Geo.box(node, Vector3(sx * (w / 2 - .15), (h - .12) / 2, 0), Vector3(.14, h - .12, d - .1), dark)
			Geo.box(node, Vector3(0, .2, 0), Vector3(w - .3, .06, d - .2), dark)
			if detail > 0:
				Geo.box(node, Vector3(-.5, h + .04, 0), Vector3(.5, .06, .12), Color("8a8a80"))
				Geo.cylinder(node, Vector3(.6, h + .1, .1), .08, .2, brass, .2)
		"cot":
			Geo.box(node, Vector3(0, h - .1, 0), Vector3(w, .12, d), dark)
			Geo.box(node, Vector3(0, h - .01, 0), Vector3(w - .1, .08, d - .1), Color("b9ab8e"))
			Geo.box(node, Vector3(-w / 2 + .3, h + .06, 0), Vector3(.4, .1, d - .25), Color("d8ccb0"))
			for sx in [-1, 1]:
				Geo.box(node, Vector3(sx * (w / 2 - .08), (h - .16) / 2, 0), Vector3(.08, h - .16, d), dark)
	if not def.get("shadow", false):
		for child in node.get_children():
			if child is GeometryInstance3D:
				child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
