class_name DungeonRoom
extends Node3D
## View of one logical room. Floors and walls are built from the union of its
## footprint cells; walls exist only on exposed edges and every edge keeps its
## doorway socket, filled either by a portal's gate or by a wall plug.
const MAX_LANTERN_SHADOWS = 1
const MAX_ACTIVE_FILLS = 5
const FILL_HYSTERESIS = 3.0
const WALL_BACK_HEIGHT = 2.8
const WALL_FRONT_HEIGHT = 1.8
const WALL_CUTAWAY_HEIGHT = .45
const CUTAWAY_REACH = 3.0
var game: Node3D
var data: Dictionary = {}
var geometry: RoomGeometry
var decor_rng = RandomNumberGenerator.new()
# Selected warm fill lights; large rooms move a small pool between lanterns.
var lamps: Array[OmniLight3D] = []
var lantern_points: Array[Vector3] = []
# Every lantern, burning or dead: {"at", "burning", "glass", "pool", "glow"}.
# Shooting a dead one relights it; snuffing puts one out. Burning ones make up
# lantern_points and feed the fill lights.
var lanterns: Array = []
# Other light a fight carries (a dropped lantern): nodes with a "reach" meta.
var extra_lights: Array = []
var lanterns_changed = false
const LANTERN_POOL := 4.4
# This floor theme's stone, walls and motes (content/floors.json); empty in
# the title room, which keeps the default stone.
var look: Dictionary = {}
# The floor sheets and slabs: lit by the key light, but left out of the water's
# mirrored view, which looks up from below the floor.
const GROUND_LAYER := 8
var lamp_assignment: Array[int] = []
var shadow_lamps: Array[SpotLight3D] = []
# This floor's light (FloorLight): lantern warmth, glow and how many still burn.
var light: Dictionary = FloorLight.profile(0)
var _quality_enabled = null
var gates: Array[Node3D] = []
var sockets: Dictionary = {}
var open = true
var entry_portal := ""
var time = 0.0
var ember_mesh: MultiMeshInstance3D
var ember_origins: Array[Vector3] = []
var obstacles: Array[Dictionary] = []
var front_walls: Array[Dictionary] = []
var navigators: Dictionary = {}
var first_person_room := false
var terrain: FirstPersonTerrain
var pedestal := Vector3.ZERO
# Live view of each prop: {"record", "definition", "node", "base", "health"}.
var props: Dictionary = {}
var occluders: Array = []
var detail_meshes: Array = []
var effects: EffectsPool
var cloths: Array = []
var paintings: Dictionary = {}
var candle_points: Array[Vector3] = []
var interiors_report: Dictionary = {}
# All eye-level lanterns share three static finish surfaces and one flame
# material. Many fixtures do not allocate a material or mesh per metal bar.
static var first_person_lantern_model: ArrayMesh
static var first_person_lantern_flame: QuadMesh

func build(owner_game: Node3D, room: Dictionary, preview := false) -> void:
	game = owner_game
	first_person_room = game.get("first_person") == true and not preview
	data = room
	decor_rng.seed = int(room.get("seed", 53))
	light = FloorLight.profile(0) if preview else FloorLight.current()
	if first_person_room: light = FloorLight.first_person(light)
	# Each floor theme has its own stone, walls and drifting motes.
	look = {} if preview else Run.theme().get("look", {})
	effects = EffectsPool.new()
	add_child(effects)
	geometry = RoomGeometry.new(Run.local_cells(room) if room.has("cells") else [Vector2i.ZERO])
	geometry.apply_shader_mask()
	if room.has("pedestal"):
		pedestal = Vector3(float(room.pedestal[0]), 0, float(room.pedestal[1]))
	collect_sockets(room, preview)
	if first_person_room:
		resolve_vertical_openings()
		terrain = FirstPersonTerrain.new()
		terrain.setup(self,false)
		geometry.terrain = terrain
	build_floor()
	build_walls()
	if first_person_room:
		terrain.build(self)
		RoomPartitions.build(self)
	var points: Array = room.get("lights", default_lights())
	var all_points: Array[Vector3]=[]
	for point in points: all_points.append(Vector3(float(point[0]),0,float(point[1])))
	if terrain and terrain.loft:
		var deck: Rect2=terrain.loft.deck
		for x in [deck.position.x+.8,deck.end.x-.8]: all_points.append(Vector3(x,LoftRoom.RISE,deck.position.y+.8))
	var burning: Array = FloorLight.lit_lanterns(all_points.size(), light, int(room.get("seed", 53)))
	# A room remembers lanterns relit or put out once its fight was over.
	if room.has("lit") and not preview: burning = room.lit.map(func(i): return int(i))
	# The dark store keeps its lanterns dead: only the altar's flame burns.
	elif room.get("type", "") == "dark": burning = []
	if terrain and terrain.loft and not room.has("lit"):
		for i in range(points.size(),all_points.size()):
			if i not in burning: burning.append(i)
	for i in all_points.size(): make_lantern(all_points[i],i in burning)
	make_fill_lights()
	var room_type: String = room.get("type", "combat")
	if room_type in ["start", "treasure", "rest", "shop", "dark"] or preview:
		Geo.box(self, pedestal + Vector3(0, -.003, 0), Vector3(6.2, .03, 4.6), {"shop": Color("514450"), "dark": Color("2a1a26")}.get(room_type, Color("5d4c3e")))
		Geo.ring(self, pedestal + Vector3(0, .035, 0), 1.65, Color("9e875c"), .025)
		Geo.ring(self, pedestal + Vector3(0, .035, 0), 1.45, Color("7c7359"), .018)
	var records: Array = room.get("props", [])
	if not room.has("props") and room_type in ["combat", "boss"] and not preview:
		# Rooms saved before resolved dressing derive the same pillars.
		var pillars = FloorGenerator.pillar_points(geometry.cells, int(room.seed), Vector2(pedestal.x, pedestal.z))
		for i in pillars.size():
			records.append({"id": "%s:p%d" % [room.get("id", ""), i], "kind": "pillar", "position": [pillars[i].x, pillars[i].y], "rotation": 0, "size": [1.3, 1.3]})
	build_props(records)
	if first_person_room: DungeonStyle.dress_props(self)
	# Containers are solid: navigation and spawns route around them.
	for chest in room.get("chests", []):
		var at = Vector2(float(chest.position[0]), float(chest.position[1]))
		obstacles.append({"position": Vector3(at.x, 0, at.y), "radius": .7, "height":float(chest.get("height",0)), "rect": Rect2(at - Vector2(.5, .33), Vector2(1.0, .66))})
	build_paintings()
	make_candles()
	make_embers()
	add_ambient_emitters()
	if first_person_room:
		interiors_report = ThemedInteriors.decorate(self)
		FirstPersonArchitecture.build(self)
	set_open(true)
	apply_lighting_quality()

static func default_lights() -> Array:
	return Content.record("rooms", "hearth_1x1").lights.map(func(anchor):
		var at = RoomGeometry.resolve_anchor([Vector2i.ZERO], 0, anchor)
		return [at.x, at.y])

func collect_sockets(room: Dictionary, preview: bool) -> void:
	for edge in geometry.exposed_edges():
		sockets[socket_key(edge.cell, edge.dir)] = {"cell": edge.cell, "dir": edge.dir, "portal": "", "state": "wall"}
	if preview:
		for direction in RoomGeometry.DIRECTIONS:
			sockets[socket_key(Vector2i.ZERO, direction)].state = "open"
		return
	for portal_id in room.get("portals", []):
		var side = Run.portal_side(portal_id, room.id)
		var key = socket_key(side.cell, side.dir)
		if sockets.has(key):
			sockets[key].portal = portal_id
			sockets[key].state = Run.portals[portal_id].state

static func socket_key(cell: Vector2i, direction: Vector2i) -> String:
	return "%d,%d,%d,%d" % [cell.x, cell.y, direction.x, direction.y]

## Resolve a shaft for old saves before floor/ceiling collision is built.
## Fresh floors already carry these deterministic reservations.
func resolve_vertical_openings() -> void:
	var field := "stairs" if data.get("type","") == "boss" else ("stairwell" if data.get("type","") == "start" and Run.floor_number > 1 else "")
	if field.is_empty() or data.has(field): return
	var zones: Array = FloorGenerator.reserved_zones({"portals":Run.portals},data)
	var blockers: Array = []
	for prop in data.get("props",[]):
		if not prop.get("destroyed",false): blockers.append(Furnisher.record_rect(prop))
	for chest in data.get("chests",[]):
		var at := Vector2(float(chest.position[0]),float(chest.position[1]))
		blockers.append(Rect2(at-Vector2(.5,.33),Vector2(1,.66)))
	for wall in data.get("partitions",[]): blockers.append(RoomPartitions.rect(wall))
	data[field] = FloorGenerator.point_array(Staircase.find_spot(geometry,zones,Vector2(pedestal.x,pedestal.z),blockers))

static var section_meshes: Dictionary = {}

func build_floor() -> void:
	var material = DungeonStyle.floor_material(look) if first_person_room else Look.floor_material(look)
	for cell in geometry.cells:
		var center := RoomGeometry.cell_center(cell)
		if first_person_room:
			var whole := Rect2(center-RoomGeometry.HALF,RoomGeometry.CELL)
			var sections: Array[Rect2] = terrain.floor_sections(whole)
			if data.has("stairwell"):
				var well := FloorGenerator.vec2(data.stairwell)
				# Existing well collision blocks the whole opening from normal
				# play; the scripted arrival fits inside this smaller square.
				sections = FirstPersonTerrain.subtract_rects(sections,Rect2(well-Vector2.ONE*1.25,Vector2.ONE*2.5))
			for area in sections: build_ground_section(area,material)
			var roof_sections: Array[Rect2] = [whole]
			for key in ["stairs","stairwell"]:
				if not data.has(key): continue
				var at := FloorGenerator.vec2(data[key])
				var radius := Staircase.OUTER+.65
				roof_sections = FirstPersonTerrain.subtract_rects(roof_sections,Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2.0))
			for roof in roof_sections:
				var at := roof.get_center()
				var ceiling = Geo.box(self,Vector3(at.x,ceiling_height()+.15,at.y),Vector3(roof.size.x,.3,roof.size.y),Color("454847"))
				ceiling.set_meta("surface_role","ceiling")
				ceiling.material_override = DungeonStyle.ceiling_material(look)
				Geo.collider(self,ceiling.position,Vector3(roof.size.x,.3,roof.size.y))
			for beam in [-1,1]:
				var beam_rect := Rect2(center+Vector2(beam*5.4-.12,-7),Vector2(.24,14))
				var beams: Array[Rect2] = [beam_rect]
				for key in ["stairs","stairwell"]:
					if not data.has(key): continue
					var at := FloorGenerator.vec2(data[key])
					beams = FirstPersonTerrain.subtract_rects(beams,Rect2(at-Vector2.ONE*2.2,Vector2.ONE*4.4))
				for beam_part in beams:
					var at := beam_part.get_center()
					var joist = Geo.box(self,Vector3(at.x,ceiling_height()-.3,at.y),Vector3(beam_part.size.x,.5,beam_part.size.y),Color("514839"))
					joist.material_override = DungeonStyle.wood_material(Color("514839"))
		else:
			var sheet := MeshInstance3D.new()
			sheet.mesh = Look.floor_mesh()
			sheet.material_override = material
			sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sheet.position = Vector3(center.x,Look.FLOOR_TOP,center.y)
			sheet.layers = GROUND_LAYER
			add_child(sheet)
			Geo.box(self,Vector3(center.x,-.55,center.y),Vector3(18.6,.7,14.6),Color(look.get("base","242d31"))).layers = GROUND_LAYER
			Geo.box(self,Vector3(center.x,-.96,center.y),Vector3(17.9,.25,13.9),Color(look.get("under","19232b"))).layers = GROUND_LAYER
	if first_person_room:
		for key in ["stairs","stairwell"]:
			if data.has(key): StairCinematic.build_shaft(self,FloorGenerator.vec2(data[key]),Staircase.OUTER+.65)

func build_ground_section(area: Rect2, material: Material) -> void:
	if area.size.x < .01 or area.size.y < .01: return
	var key := str(area.size)
	if not section_meshes.has(key):
		if section_meshes.size() >= 96: section_meshes.clear()
		var plane := PlaneMesh.new()
		plane.size = area.size
		section_meshes[key] = plane
	var at := area.get_center()
	var sheet := MeshInstance3D.new()
	sheet.mesh = section_meshes[key]
	sheet.material_override = material
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.position = Vector3(at.x,Look.FLOOR_TOP,at.y)
	sheet.layers = GROUND_LAYER
	add_child(sheet)
	Geo.collider(self,Vector3(at.x,-.12,at.y),Vector3(area.size.x,.24,area.size.y))
	# Under-floor facing is cut along the same cellar/stair opening. A full
	# slab here would hide the lower room even after its top sheet was cut.
	Geo.box(self,Vector3(at.x,-.55,at.y),Vector3(area.size.x,.7,area.size.y),Color(look.get("base","242d31"))).layers = GROUND_LAYER
	Geo.box(self,Vector3(at.x,-.96,at.y),Vector3(area.size.x,.25,area.size.y),Color(look.get("under","19232b"))).layers = GROUND_LAYER

func build_walls() -> void:
	for segment in geometry.wall_segments():
		var box = RoomGeometry.segment_box(segment)
		var front = RoomGeometry.is_front(segment.dir)
		var height = ceiling_height()-.05 if first_person_room else (WALL_FRONT_HEIGHT if front else WALL_BACK_HEIGHT)
		make_wall(Vector3(box.center.x, height / 2, box.center.y), Vector3(box.size.x, height, box.size.y),
			segment.dir if front and not first_person_room else Vector2i.ZERO, segment.line, segment.from, segment.to)
	for key in sockets:
		var socket: Dictionary = sockets[key]
		if socket.state in ["open", "locked", "revealed"]:
			make_gate(socket)
		else:
			make_plug(socket)

func make_plug(socket: Dictionary) -> void:
	var direction: Vector2i = socket.dir
	if socket.state == "concealed":
		make_seam_hints(socket)
	var front = RoomGeometry.is_front(direction)
	var height = ceiling_height()-.05 if first_person_room else (WALL_FRONT_HEIGHT if front else WALL_BACK_HEIGHT)
	var point = RoomGeometry.socket_point(socket.cell, direction)
	var at = point + Vector2(direction) * .15
	var line = point.dot(Vector2(direction).abs())
	var along = point.dot(Vector2(absi(direction.y), absi(direction.x)))
	socket["walls"] = make_wall(Vector3(at.x, height / 2, at.y), Vector3(.45, height, 2.5) if direction.x != 0 else Vector3(2.5, height, .45),
		direction if front and not first_person_room else Vector2i.ZERO, line, along - 1.25, along + 1.25)

## Subtle tells of a concealed passage: cracked mortar on the inner face, a
## little rubble at its foot and a faint draft of dust.
func make_seam_hints(socket: Dictionary) -> void:
	var direction: Vector2i = socket.dir
	var inward = -Vector2(direction)
	var point = RoomGeometry.socket_point(socket.cell, direction) + inward * .02
	var across = Vector2(absi(direction.y), absi(direction.x))
	var hints = Node3D.new()
	hints.name = "SeamHints"
	add_child(hints)
	var crack_color = Color("23292d")
	for i in 5:
		var along = (i - 2) * .32
		var at = point + across * along
		var crack = Geo.box(hints, Vector3(at.x, .5 + i * .27, at.y), Vector3(.05 + across.x * .22, .04, .05 + across.y * .22), crack_color)
		crack.rotation.y = .5 * (1 if i % 2 == 0 else -1)
		crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 4:
		var at = point + inward * (.25 + .12 * (i % 2)) + across * ((i - 1.5) * .35)
		var rubble = Geo.box(hints, Vector3(at.x, .05, at.y), Vector3(.14, .1, .12) * (1.0 + .3 * (i % 3)), Color("5a5d58"))
		rubble.rotation.y = i * .8
		rubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	socket["hints"] = hints

## Opens a revealed passage in the live room: the plug and its tells go, a
## doorway takes their place. Collision changes with the visible wall.
func reveal_socket(portal_id: String) -> void:
	for key in sockets:
		var socket: Dictionary = sockets[key]
		if socket.portal != portal_id or socket.state != "concealed": continue
		socket.state = "revealed"
		var walls: Dictionary = socket.get("walls", {})
		for part in ["body", "cap", "collider", "shadow_caster"]:
			if walls.has(part) and is_instance_valid(walls[part]): walls[part].queue_free()
		front_walls.erase(walls)
		if socket.has("hints"): socket.hints.queue_free()
		make_gate(socket)
		set_open(open)
		var at = RoomGeometry.socket_point(socket.cell, socket.dir)
		Effects.burst(self, Vector3(at.x, .8, at.y), Color("8f8a7c"), 12, 1.4)

func make_gate(socket: Dictionary) -> void:
	if first_person_room:
		var doorway := DungeonDoorway.build(self,socket)
		socket["gate"] = doorway
		gates.append(doorway)
		return
	var direction: Vector2i = socket.dir
	var at = RoomGeometry.socket_point(socket.cell, direction) + Vector2(direction) * .15
	var gate = Node3D.new()
	add_child(gate)
	gate.position = Vector3(at.x, 0, at.y)
	var rotated = direction.x != 0
	var post_height = 2.8 if first_person_room else (WALL_BACK_HEIGHT - .25 if direction.x + direction.y < 0 else 1.5)
	var sill = Geo.box(gate, Vector3(0, -.015, 0), Vector3(.8, .08, 2.25) if rotated else Vector3(2.25, .08, .8), Color("b69c6a"))
	if first_person_room: sill.material_override = DungeonStyle.wall_material(Color("827359"), true)
	for s in [-1, 1]:
		var post = Geo.box(gate, Vector3(0, post_height / 2, s * 1.1) if rotated else Vector3(s * 1.1, post_height / 2, 0), Vector3(.25, post_height, .25), Color("797263"))
		if first_person_room: post.material_override = DungeonStyle.wall_material(Color("797263"), true)
	if post_height > 1.5:
		var lintel = Geo.box(gate, Vector3(0, post_height, 0), Vector3(.3, .18, 2.5) if rotated else Vector3(2.5, .18, .3), Color("797263"))
		if first_person_room: lintel.material_override = DungeonStyle.wall_material(Color("797263"), true)
	var gate_height = 2.7 if first_person_room else 1.45
	var barrier = Geo.box(gate, Vector3(0, gate_height / 2, 0), Vector3(.16, gate_height, 2.0) if rotated else Vector3(2.0, gate_height, .16), Color("66504a") if first_person_room else Color("b85e4c"), .08 if first_person_room else .7)
	if first_person_room:
		barrier.material_override = DungeonStyle.wood_material(Color("66504a"))
		var upper_wall = Geo.box(gate, Vector3(0, 4.2, 0), Vector3(.45, 2.5, 2.5) if rotated else Vector3(2.5, 2.5, .45), Color("393a36"))
		upper_wall.material_override = DungeonStyle.wall_material(Color(look.get("wall","393a36")),false,DungeonStyle.theme_for(look))
		Geo.collider(gate, Vector3(0, 4.2, 0), Vector3(.45, 2.5, 2.5) if rotated else Vector3(2.5, 2.5, .45))
	barrier.name = "Barrier"
	if not first_person_room:
		Geo.halo(gate, Vector3(0, .035, 0), 3.5, Color(.92, .62, .25, .28))
	# An open doorway's outline glows (posts, sill and any lintel), brightest
	# where the floor is darkest, so every way out shows.
	var outline = Node3D.new()
	outline.name = "Outline"
	gate.add_child(outline)
	var glow = Color(1.0, .7, .36) * light.doorway
	var inner = 1.1 - .125 - .035
	var side = post_height - (.09 if post_height > 1.5 else 0.0)
	for s in [-1, 1]:
		Geo.glow_box(outline, Vector3(0, side / 2, s * inner) if rotated else Vector3(s * inner, side / 2, 0),
			Vector3(.28, side, .07) if rotated else Vector3(.07, side, .28), glow)
	var across = [.04] + ([post_height - .12] if post_height > 1.5 else [])
	for y in across:
		Geo.glow_box(outline, Vector3(0, y, 0), Vector3(.28, .06, inner * 2.0) if rotated else Vector3(inner * 2.0, .06, .28), glow)
	gate.set_meta("portal", socket.portal)
	socket["gate"] = gate
	gates.append(gate)

func make_wall(at: Vector3, dimensions: Vector3, front_side := Vector2i.ZERO, line := 0.0, from := 0.0, to := 0.0) -> Dictionary:
	var body = Geo.box(self, at, dimensions, Color(look.get("wall", "394148")))
	body.set_meta("surface_role","wall")
	body.material_override = DungeonStyle.wall_material(Color(look.get("wall", "394148")), false, DungeonStyle.theme_for(look)) if first_person_room else Look.wall_material(Color(look.get("wall", "394148")))
	var cap = Geo.box(self, at + Vector3(0, dimensions.y / 2 + .035, 0), Vector3(dimensions.x + .06, .09, dimensions.z + .06), Color(look.get("cap", "656358")))
	cap.material_override = DungeonStyle.wall_material(Color(look.get("cap", "656358")), true, DungeonStyle.theme_for(look)) if first_person_room else Look.wall_material(Color(look.get("cap", "656358")), true)
	var collider = Geo.collider(self, at, dimensions + Vector3(0, 2, 0))
	var entry = {"body": body, "cap": cap, "collider": collider}
	if front_side != Vector2i.ZERO:
		# Keep a static full-height occluder while the visible wall cuts away.
		# This avoids transparent wall passes and moving shadow-map casters.
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var caster = Geo.box(self, at, dimensions, Color(look.get("wall", "394148")))
		caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		entry.merge({"shadow_caster": caster, "side": front_side, "height": dimensions.y,
			"line": line, "from": from, "to": to})
		front_walls.append(entry)
	return entry

## Front segments lower when an actor stands within reach of their inner face
## along the boundary normal; collision and shadow occluders never move.
func wall_obstructs(wall: Dictionary, point: Vector3) -> bool:
	var side: Vector2i = wall.side
	var across = point.x if side.x != 0 else point.z
	var along = point.z if side.x != 0 else point.x
	var inward = wall.line - across
	return inward > -1.0 and inward < CUTAWAY_REACH and along > wall.from - CUTAWAY_REACH and along < wall.to + CUTAWAY_REACH

func floor_height(at: Vector3) -> float:
	return terrain.height_at(at) if terrain else 0.0

func ceiling_height() -> float:
	return LoftRoom.CEILING if terrain and terrain.loft else 5.45

func update_wall_visibility(focus: Vector3, delta: float, others: Array = []) -> void:
	if first_person_room: return
	for wall in front_walls:
		var near = wall_obstructs(wall, focus)
		if not near:
			for actor in others:
				if wall_obstructs(wall, actor):
					near = true
					break
		var target = WALL_CUTAWAY_HEIGHT if near else WALL_FRONT_HEIGHT
		var height = target if delta <= 0 else move_toward(wall.height, target, delta * 7.0)
		if is_equal_approx(height, wall.height): continue
		wall.height = height
		wall.body.scale.y = height / WALL_FRONT_HEIGHT
		wall.body.position.y = height / 2
		wall.cap.position.y = height + .035
	# Free-standing pieces lower when they actually stand between the camera
	# and an actor; their collision and shadow occluder stay on the base.
	for occluder in occluders:
		var hidden = prop_obstructs(occluder, focus)
		if not hidden:
			for actor in others:
				if prop_obstructs(occluder, actor):
					hidden = true
					break
		var goal = .35 if hidden else 1.0
		var value = goal if delta <= 0 else move_toward(occluder.current, goal, delta * 5.0)
		if is_equal_approx(value, occluder.current): continue
		occluder.current = value
		occluder.node.scale.y = value

const VIEW_GROUND = Vector2(-0.6332378, -0.7739573)

func prop_obstructs(occluder: Dictionary, point: Vector3) -> bool:
	var offset = Vector2(point.x, point.z) - occluder.position
	var behind = offset.dot(VIEW_GROUND)
	var across = Vector2(-VIEW_GROUND.y, VIEW_GROUND.x)
	var reach = absf(across.x) * occluder.half.x + absf(across.y) * occluder.half.y + .6
	return behind > 0 and behind < 2.6 and absf(offset.dot(across)) < reach

## Builds every intact prop. Small details at Low hide decorative pieces only;
## collision, breakables and layout are identical at every detail level.
func build_props(records: Array) -> void:
	var batch = DetailBatch.new()
	var detail: int = Settings.detail_level()
	var rng = RandomNumberGenerator.new()
	rng.seed = int(data.get("seed", 53)) + 4049
	for record in records:
		var definition: Dictionary = Content.record("furniture", record.kind)
		if definition.is_empty() or record.get("destroyed", false):
			continue
		if definition.detail == "decor" and detail == 0:
			continue
		var at = Vector2(float(record.position[0]), float(record.position[1]))
		var built = PropVisuals.build(self, record, definition, detail, batch, geometry.cell_at(at), rng)
		props[record.id] = {"record": record, "definition": definition, "node": built.node, "base": built.base,
			"health": float(definition.get("breakable", {}).get("health", 0))}
		if definition.recipe == "pillar":
			if first_person_room:
				# The two existing stone plinth meshes get the shared carved
				# finish before wax/flame pieces are added above them.
				for part in built.node.get_children():
					if not part is MeshInstance3D: continue
					var original = part.material_override
					if original is StandardMaterial3D:
						part.material_override = DungeonStyle.structural_material(look,original.albedo_color,part.position.y > 1.0)
			make_candle(Vector3(at.x, 1.32, at.y), .6)
		var cloth = built.node.get_node_or_null("Cloth")
		if cloth: cloths.append(cloth)
		if definition.get("solid", false):
			var size = Vector2(float(record.size[0]), float(record.size[1]))
			obstacles.append({"id": record.id, "position": Vector3(at.x, 0, at.y), "radius": maxf(size.x, size.y) * .5 + .4,
				"rect": Rect2(at - size / 2.0, size)})
		if not built.occluder.is_empty():
			built.occluder["id"] = record.id
			built.occluder["current"] = 1.0
			occluders.append(built.occluder)
	detail_meshes = batch.build(self)

func prop_count(kind := "") -> int:
	return props.values().filter(func(entry): return kind == "" or entry.record.kind == kind).size()

## Returns true when this hit broke the prop.
func damage_prop(id: String, amount: float) -> bool:
	if not props.has(id) or not props[id].definition.has("breakable"):
		return false
	props[id].health -= amount
	var node: Node3D = props[id].node
	node.scale = Vector3(1.08, .93, 1.08)
	create_tween().tween_property(node, "scale", Vector3.ONE, .12)
	return props[id].health <= 0

## Removes a broken prop's view, collision and navigation blocker once.
func break_prop(id: String) -> void:
	if not props.has(id):
		return
	var entry: Dictionary = props[id]
	props.erase(id)
	entry.node.queue_free()
	entry.base.queue_free()
	obstacles = obstacles.filter(func(obstacle): return obstacle.get("id", "") != id)
	occluders = occluders.filter(func(occluder): return occluder.id != id)
	for navigator in navigators.values():
		navigator.remove_blocker(id)

## A dead lantern keeps its post and cold glass but gives no light or glow,
## and never joins the fill-light pool.
func make_lantern(p: Vector3, burning := true) -> void:
	if first_person_room:
		make_first_person_lantern(p, burning)
		return
	Geo.box(self, p + Vector3(0, .28, 0), Vector3(.85, .55, .85), Color("424d4c"))
	Geo.box(self, p + Vector3(0, .61, 0), Vector3(1.0, .12, 1.0), Color("716f5d"))
	Geo.cylinder(self, p + Vector3(0, 1.03, 0), .14, .8, Color("ac9061"))
	var glass = Geo.box(self, p + Vector3(0, 1.6, 0), Vector3(.5, .55, .5), Color("f7bb6d"), 1.05)
	Geo.box(self, p + Vector3(0, 1.94, 0), Vector3(.68, .12, .68), Color("826d51"))
	for x in [-.22, .22]:
		for z in [-.22, .22]:
			var bar = Geo.box(self, p + Vector3(x, 1.6, z), Vector3(.035, .65, .035), Color("6e6654"))
			bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pool = Geo.halo(self, p + Vector3(0, .03, 0), 7.5, Color(1, .57, .17, .2 * light.glow))
	var glow = Geo.halo(self, p + Vector3(0, 1.65, 0), 2.0, Color(1, .6, .2, .4 * light.glow))
	glow.rotation_degrees.x = 58
	lanterns.append({"at": p, "burning": burning, "glass": glass, "pool": pool, "glow": glow})
	show_lantern(lanterns.back())
	if burning: lantern_points.append(p)

## An open metal cage with a real flame replaces the opaque luminous cube.
## The only emission belongs to the tiny flame: pools on walls and floors
## come from the real lights, without tilted additive halo cards.
func make_first_person_lantern(p: Vector3, burning: bool) -> void:
	var casing = MeshInstance3D.new()
	casing.name = "LanternCage"
	casing.mesh = lantern_model()
	casing.set_surface_override_material(0,DungeonStyle.wall_material(Color("55534c"), true))
	casing.position = p
	casing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(casing)
	if not first_person_lantern_flame:
		first_person_lantern_flame = QuadMesh.new()
		first_person_lantern_flame.size = Vector2(.25, .48)
	var flame = MeshInstance3D.new()
	flame.name = "LanternFlame"
	flame.mesh = first_person_lantern_flame
	flame.material_override = DungeonStyle.candle_flame()
	flame.position = p + Vector3(0, 1.58, 0)
	flame.layers = Geo.FLAME_LAYER
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	# Retain the lantern view contract for gameplay without rendering fake
	# floor light or a glowing plane through the camera.
	var pool = Node3D.new()
	pool.name = "NoFloorLightCard"
	add_child(pool)
	var glow = Node3D.new()
	glow.name = "NoAirLightCard"
	add_child(glow)
	lanterns.append({"at": p, "burning": burning, "glass": flame, "pool": pool, "glow": glow})
	show_lantern(lanterns.back())
	if burning: lantern_points.append(p)

static func lantern_model() -> ArrayMesh:
	if first_person_lantern_model: return first_person_lantern_model
	first_person_lantern_model = ArrayMesh.new()
	var tube = CylinderMesh.new()
	tube.top_radius = 1
	tube.bottom_radius = 1
	tube.height = 1
	tube.radial_segments = 16
	var cube = Geo.shared_box(Vector3.ONE)
	var handle = TorusMesh.new()
	handle.inner_radius = .105
	handle.outer_radius = .125
	handle.rings = 16
	handle.ring_segments = 6
	for finish in 3:
		var tool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var material = StandardMaterial3D.new()
		material.albedo_color = [Color("55534c"), Color("343a3d"), Color("a18a5b")][finish]
		material.roughness = [.82, .4, .32][finish]
		material.metallic = [0.0, .8, .72][finish]
		tool.set_material(material)
		if finish == 0:
			tool.append_from(cube, 0, Transform3D(Basis.IDENTITY.scaled(Vector3(.75,.12,.75)),Vector3(0,.06,0)))
			tool.append_from(cube, 0, Transform3D(Basis.IDENTITY.scaled(Vector3(.55,.35,.55)),Vector3(0,.29,0)))
			tool.append_from(cube, 0, Transform3D(Basis.IDENTITY.scaled(Vector3(.64,.09,.64)),Vector3(0,.51,0)))
		elif finish == 1:
			tool.append_from(tube,0,Transform3D(Basis.IDENTITY.scaled(Vector3(.058,.7,.058)),Vector3(0,.91,0)))
			for y in [1.25,1.89]:
				tool.append_from(tube,0,Transform3D(Basis.IDENTITY.scaled(Vector3(.28,.06,.28)),Vector3(0,y,0)))
			for x in [-.2,.2]:
				for z in [-.2,.2]:
					tool.append_from(cube,0,Transform3D(Basis.IDENTITY.scaled(Vector3(.025,.61,.025)),Vector3(x,1.57,z)))
			tool.append_from(handle,0,Transform3D(Basis(Vector3.RIGHT,PI/2),Vector3(0,2.045,0)))
		else:
			for y in [.57,1.18]:
				tool.append_from(tube,0,Transform3D(Basis.IDENTITY.scaled(Vector3(.11,.09,.11)),Vector3(0,y,0)))
			tool.append_from(tube,0,Transform3D(Basis.IDENTITY.scaled(Vector3(.19,.045,.19)),Vector3(0,1.32,0)))
			tool.append_from(tube,0,Transform3D(Basis.IDENTITY.scaled(Vector3(.055,.09,.055)),Vector3(0,1.38,0)))
		tool.commit(first_person_lantern_model)
	return first_person_lantern_model

func show_lantern(lantern: Dictionary) -> void:
	if first_person_room:
		lantern.glass.visible = lantern.burning
		lantern.pool.visible = false
		lantern.glow.visible = false
		return
	lantern.glass.material_override = (DungeonStyle.lantern_glass() if first_person_room else Geo.material(Color("f7bb6d"), 1.05)) if lantern.burning else Geo.material(Color("3d3a35"))
	lantern.pool.visible = lantern.burning
	lantern.glow.visible = lantern.burning

## Relights or puts out one lantern; the fill lights follow the burning ones.
func set_lantern(index: int, burning: bool) -> bool:
	if index < 0 or index >= lanterns.size() or lanterns[index].burning == burning: return false
	lanterns[index].burning = burning
	lanterns_changed = true
	show_lantern(lanterns[index])
	lantern_points.clear()
	for lantern in lanterns:
		if lantern.burning: lantern_points.append(lantern.at)
	refresh_fill_lights()
	var at: Vector3 = lanterns[index].at + Vector3(0, 1.6, 0)
	Effects.burst(self, at, Color("ffd08a") if burning else Color("5a5650"), 10 if burning else 6, 1.2)
	return true

func burning_indices() -> Array:
	return range(lanterns.size()).filter(func(i): return lanterns[i].burning)

func has_dark() -> bool:
	return lantern_points.size() < lanterns.size()

## Whether a point stands in a burning lantern's pool or another fight light.
func lit_at(p: Vector3) -> bool:
	for point in lantern_points:
		if Vector2(point.x - p.x, point.z - p.z).length() < LANTERN_POOL: return true
	for node in extra_lights:
		if is_instance_valid(node) and Vector2(node.global_position.x - p.x, node.global_position.z - p.z).length() < float(node.get_meta("reach", 3.0)): return true
	return false

## The lantern (burning or dead, as asked) nearest a floor point within reach.
func lantern_near(flat: Vector2, reach: float, burning: bool) -> int:
	var best = -1
	for i in lanterns.size():
		if lanterns[i].burning != burning: continue
		var d = Vector2(lanterns[i].at.x, lanterns[i].at.z).distance_to(flat)
		if d < reach and (best < 0 or d < Vector2(lanterns[best].at.x, lanterns[best].at.z).distance_to(flat)):
			best = i
	return best

func make_fill_lights() -> void:
	# Unshadowed fills preserve warm lantern pools in both quality modes. A
	# small pool serves big rooms; it moves only when the selection changes.
	for i in mini(MAX_ACTIVE_FILLS, lantern_points.size()):
		lamps.append(make_fill_light(lantern_points[i]))
		lamp_assignment.append(i)
	# Keep one warm key shadow; the other lanterns are inexpensive fills. Four
	# overlapping shadow lights still cost too much on mobile GLES3 renderers.
	if not lantern_points.is_empty() and shadow_lamps.size() < MAX_LANTERN_SHADOWS:
		make_shadow_light(lantern_points[0])

## After a lantern changes: as many fills as burning lanterns allow, the
## shadow lamp on a burning one or dark when none burn.
func refresh_fill_lights() -> void:
	var wanted = mini(MAX_ACTIVE_FILLS, lantern_points.size())
	while lamps.size() > wanted:
		lamps.pop_back().queue_free()
	while lamps.size() < wanted:
		lamps.append(make_fill_light(Vector3.ZERO))
	lamp_assignment.clear()
	for slot in wanted:
		lamp_assignment.append(slot)
		lamps[slot].position = lantern_points[slot] + fill_offset()
	if not lantern_points.is_empty():
		if shadow_lamps.is_empty(): make_shadow_light(lantern_points[0])
		else: place_shadow_light(shadow_lamps[0], lantern_points[0])
	_quality_enabled = null
	apply_lighting_quality()

func fill_offset() -> Vector3:
	return Vector3(0, 1.65 if first_person_room else 2.2, 0)

func make_fill_light(at: Vector3) -> OmniLight3D:
	var lamp = Geo.light(self, at + fill_offset(), light.lamp_color, light.lamp, 8.4 if first_person_room else 7.0)
	if first_person_room:
		lamp.omni_attenuation = 1.55
		lamp.light_size = .18
		lamp.light_specular = .7
	return lamp

func lantern_distance(index: int, focus: Vector3) -> float:
	return lantern_points[index].distance_to(focus)

## Chooses the lanterns nearest the view. A lantern replaces a selected one
## only when it is clearly closer, so lights do not flap at the boundary.
func update_light_selection(focus: Vector3) -> bool:
	if lantern_points.size() <= lamps.size():
		return false
	var flat = focus
	var changed = false
	for candidate in lantern_points.size():
		if candidate in lamp_assignment: continue
		var worst = 0
		for slot in lamp_assignment.size():
			if lantern_distance(lamp_assignment[slot], flat) > lantern_distance(lamp_assignment[worst], flat): worst = slot
		if lantern_distance(candidate, flat) + FILL_HYSTERESIS < lantern_distance(lamp_assignment[worst], flat):
			lamp_assignment[worst] = candidate
			lamps[worst].position = lantern_points[candidate] + fill_offset()
			changed = true
	if changed and not shadow_lamps.is_empty():
		var nearest = lamp_assignment[0]
		for index in lamp_assignment:
			if lantern_distance(index, flat) < lantern_distance(nearest, flat): nearest = index
		place_shadow_light(shadow_lamps[0], lantern_points[nearest])
	return changed

func make_shadow_light(p: Vector3) -> void:
	# A fixed inward-facing spotlight needs one map instead of six cube faces.
	var shadow_light = SpotLight3D.new()
	shadow_light.light_color = light.lamp_color
	shadow_light.light_cull_mask = Geo.LIT_LAYERS
	shadow_light.light_energy = light.shadow
	shadow_light.spot_range = 13.0
	shadow_light.spot_angle = 58.0
	shadow_light.spot_angle_attenuation = 1.5
	shadow_light.shadow_bias = .06
	shadow_light.shadow_normal_bias = .7
	shadow_light.shadow_opacity = 1.0
	if first_person_room:
		shadow_light.spot_range = 11.0
		shadow_light.spot_angle = 76.0
		shadow_light.spot_angle_attenuation = 1.1
		shadow_light.shadow_bias = .025
		shadow_light.shadow_normal_bias = .3
		shadow_light.shadow_opacity = .78
		shadow_light.shadow_blur = 1.3
		shadow_light.light_size = .22
		shadow_light.light_specular = .55
	shadow_light.visible = false
	add_child(shadow_light)
	place_shadow_light(shadow_light, p)
	shadow_lamps.append(shadow_light)

func place_shadow_light(shadow_light: SpotLight3D, p: Vector3) -> void:
	# Aim inward toward the lantern's own cell, as the 1x1 room always did.
	var center = RoomGeometry.cell_center(geometry.cell_at(Vector2(p.x, p.z)))
	shadow_light.position = p + Vector3(0, 1.72 if first_person_room else 2.2, 0)
	shadow_light.look_at(Vector3(center.x + (p.x - center.x) * .3, 0, center.y + (p.z - center.y) * .3))

func make_candle(p: Vector3, height: float) -> void:
	var wax = Geo.cylinder(self, p + Vector3(0, height / 2, 0), .12, height, Color("c9ad7e"))
	wax.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A little pool of melted wax at the base.
	var pool = Geo.cylinder(self, p + Vector3(0, .01, 0), .2, .02, Color("d9c08f"))
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	candle_points.append(p + Vector3(0, height + .2, 0))
	if first_person_room:
		var flame = MeshInstance3D.new()
		flame.mesh = DungeonStyle.candle_flame_mesh()
		flame.material_override = DungeonStyle.candle_flame()
		flame.position = p + Vector3(0,height+.13,0)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.layers = Geo.FLAME_LAYER
		add_child(flame)
	else:
		var flame = Geo.sphere(self, p + Vector3(0, height + .1, 0), .11, Color("ffe0a1"), 2.0)
		flame.scale = Vector3(.7, 1.5, .7)
	if not first_person_room:
		Geo.halo(self, p + Vector3(0, .025, 0), 2.3, Color(1, .5, .13, .14))

func make_candles() -> void:
	# Candles line the exposed rear and front walls, alternating between them.
	var edges = geometry.exposed_edges().filter(func(edge): return edge.dir.x == 0)
	var rear = edges.filter(func(edge): return edge.dir.y < 0)
	var front = edges.filter(func(edge): return edge.dir.y > 0)
	var ordered: Array = []
	for i in maxi(rear.size(), front.size()):
		if i < rear.size(): ordered.append(rear[i])
		if i < front.size(): ordered.append(front[i])
	for i in roundi(5 * ordered.size() * float(look.get("candles", 1.0))):
		var edge: Dictionary = ordered[i % ordered.size()]
		var center = RoomGeometry.cell_center(edge.cell)
		var p = Vector3(decor_rng.randf_range(-6.5, 6.5), 0, edge.dir.y * 6.2)
		if absf(p.x) < 1.7:
			p.x += 3.0
		make_candle(p + Vector3(center.x, 0, center.y), decor_rng.randf_range(.45, .85))

func make_embers() -> void:
	ember_mesh = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh = SphereMesh.new()
	mesh.radius = .025
	mesh.height = .05
	mesh.radial_segments = 4
	mesh.rings = 3
	mm.mesh = mesh
	# Drifting embers spend part of the room's ambient budget; the rest is
	# left to the pool's emitters.
	var count = int(Settings.effect_budget("ambient") * .55)
	effects.configure(count)
	mm.instance_count = count
	for i in count:
		var floor_point = geometry.random_point(decor_rng, .2)
		ember_origins.append(Vector3(floor_point.x, decor_rng.randf_range(.1, 4.0), floor_point.y))
	ember_mesh.multimesh = mm
	ember_mesh.material_override = Geo.material(Color(look.get("motes", "efbc78")), 1.2)
	ember_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ember_mesh)

func build_paintings() -> void:
	for mount in data.get("mounts", []):
		var painting: Dictionary = Content.record("paintings", mount.get("painting", ""))
		if painting.is_empty():
			continue
		paintings[mount.id] = PaintingView.build(self, mount, painting, PaintingLibrary.wall_texture(painting.id))
		paintings[mount.id]["painting"] = painting.id

## A few deliberate atmosphere sources rather than every object at once.
func add_ambient_emitters() -> void:
	for i in range(0, candle_points.size(), 4):
		effects.add_emitter("candle_wisp", candle_points[i], .05)
	for i in mini(2, lantern_points.size()):
		effects.add_emitter("firefly", lantern_points[i * 2 % lantern_points.size()] + Vector3(0, 1.6, 0), .9)
	var dusty = 0
	for entry in props.values():
		match entry.definition.recipe:
			"brazier": effects.add_emitter("brazier_spark", entry.node.position + Vector3(0, 1.1, 0), .12)
			"bookcase", "wall_shelf", "cupboard":
				if dusty < 3:
					effects.add_emitter("shelf_dust", entry.node.position + Vector3(0, 1.6, 0), .6)
					dusty += 1

## Lazily built navigation per actor clearance class.
## Something solid placed after the room was built (the stair, a stairwell):
## spawn points and paths respect it from now on.
func add_obstacle(id: String, at: Vector2, radius: float, height := 0.0) -> void:
	obstacles.append({"id": id, "position": Vector3(at.x, 0, at.y), "radius": radius,
		"rect": Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0),"height":height})
	navigators.clear()

func navigation(clearance := .5, level := 0.0) -> RoomNavigation:
	var key = Vector2(snappedf(clearance,.05),level)
	if not navigators.has(key):
		var blockers := {}
		for i in obstacles.size():
			if terrain and terrain.loft and absf(float(obstacles[i].get("height",0))-level)>.5: continue
			blockers[obstacles[i].get("id", "obstacle%d" % i)] = obstacles[i].rect
		navigators[key] = RoomNavigation.new(geometry, clearance, blockers,level)
	return navigators[key]

## A concealed doorway in this room that a Miner's Lantern could point at.
func hidden_seam() -> Dictionary:
	for key in sockets:
		if sockets[key].state == "concealed": return sockets[key]
	return {}

func show_seam_hint(seam: Dictionary, duration: float) -> void:
	var at = RoomGeometry.socket_point(seam.cell, seam.dir) - Vector2(seam.dir) * .35
	var hint = Geo.halo(self, Vector3(at.x, .05, at.y), 3.2, Color(1.0, .82, .45, .55))
	var glint = Geo.sphere(self, Vector3(at.x, 1.1, at.y), .12, Color("ffe2a0"), 2.6)
	var tween = create_tween()
	tween.tween_interval(duration)
	tween.tween_callback(hint.queue_free)
	tween.tween_callback(glint.queue_free)

func blocked_at(point: Vector2) -> bool:
	for obstacle in obstacles:
		if obstacle.rect.grow(.4).has_point(point): return true
	return false

func set_open(value: bool) -> void:
	open = value
	for gate in gates:
		var opened: bool=value or (not entry_portal.is_empty() and gate.get_meta("portal","")==entry_portal)
		var barrier:=gate.get_node("Barrier")
		barrier.visible = not opened
		barrier.process_mode=Node.PROCESS_MODE_DISABLED if opened else Node.PROCESS_MODE_INHERIT
		gate.get_node("Outline").visible = opened

func apply_lighting_quality() -> void:
	var enabled: bool = Settings.values.shadows
	if _quality_enabled == enabled:
		return
	_quality_enabled = enabled
	for light in shadow_lamps:
		light.shadow_enabled = enabled
		# With every lantern out there is nothing for it to hang on.
		light.visible = enabled and not lantern_points.is_empty()

func _process(delta: float) -> void:
	time += delta
	apply_lighting_quality()
	for i in lamps.size():
		var flicker = sin(time * 1.7 + i * 2.4) * .018 + sin(time * 4.1 + i) * .009 if first_person_room else sin(time * 3.1 + i * 2.4) * .042 + sin(time * 7.2 + i) * .02
		lamps[i].light_energy = light.lamp * (1.0 + flicker)
	if first_person_room:
		for lamp in shadow_lamps: lamp.light_energy = light.shadow * (1.0 + sin(time * 2.2) * .018)
	for i in cloths.size():
		cloths[i].rotation.x = sin(time * 1.3 + i * 1.7) * .09
	if ember_mesh:
		for i in ember_origins.size():
			var p: Vector3 = ember_origins[i]
			p.y = fposmod(p.y + time * .16, 4.0)
			p.x += sin(time * .35 + i) * .25
			ember_mesh.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
