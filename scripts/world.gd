class_name DungeonRoom
extends Node3D
const MAX_LANTERN_SHADOWS = 1
const WALL_BACK_HEIGHT = 2.8
const WALL_FRONT_HEIGHT = 1.8
const WALL_CUTAWAY_HEIGHT = .45
var game: Node3D
var decor_rng = RandomNumberGenerator.new()
var lamps: Array[OmniLight3D] = []
var shadow_lamps: Array[SpotLight3D] = []
var _quality_enabled = null
var gates: Array[Node3D] = []
var open = true
var time = 0.0
## The ambient batch of this room's effect pool (embers, wisps, dust).
var ember_mesh: MultiMeshInstance3D
var effects: EffectPool
var candle_points: Array = []
var obstacles: Array[Dictionary] = []
var front_walls: Array[Dictionary] = []
const LIGHT_POOL = 4
var geometry := RoomGeometry.new()
var navigation: RoomNavigation
var sockets: Array = []
var lantern_points: Array[Vector3] = []
var lamp_targets: Array[int] = []
## Saved furniture by prop id: {node, collider, obstacle, record}.
var props: Dictionary = {}
## Walls and hint debris standing in a concealed doorway, by portal id.
var concealed: Dictionary = {}
var _room: Dictionary = {}

func build(owner_game: Node3D, room: Dictionary, preview := false, layout := {}) -> void:
	game = owner_game
	_room = room
	decor_rng.seed = int(room.get("seed", 53))
	geometry = RoomGeometry.new(layout.get("cells", [Vector2i.ZERO]))
	# Every glow built for this room (and its actors) clips to its footprint.
	Geo.footprint = geometry.shader_rects()
	effects = EffectPool.new()
	add_child(effects)
	effects.setup(owner_game, geometry, int(room.get("seed", 53)))
	sockets = layout.get("sockets", [])
	if preview and sockets.is_empty():
		for direction in RoomGeometry.DIRECTIONS:
			sockets.append({"portal": "", "cell": Vector2i.ZERO, "dir": direction, "other": "", "state": "open"})
	var palette = [Color("49433d"), Color("45413b"), Color("4d463e"), Color("413e39"), Color("50473e")]
	for color_index in palette.size():
		var points: Array[Vector3] = []
		for cell in geometry.cells:
			var center := geometry.cell_center(cell)
			for x in range(-9, 9):
				for z in range(-7, 7):
					var gx := x + cell.x * 18
					var gz := z + cell.y * 14
					if posmod(gx * 37 + gz * 19 + gx * gz, 5) == color_index:
						points.append(Vector3(center.x + x + .5, -.16, center.y + z + .5))
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var tile = BoxMesh.new()
		tile.size = Vector3(.975, .25, .975)
		mm.mesh = tile
		mm.instance_count = points.size()
		for i in points.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
		var mesh = MultiMeshInstance3D.new()
		mesh.multimesh = mm
		mesh.material_override = Geo.material(palette[color_index])
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
	for cell in geometry.cells:
		var center := geometry.cell_center(cell)
		Geo.box(self, Vector3(center.x, -.55, center.y), Vector3(18.6, .7, 14.6), Color("242d31"))
		Geo.box(self, Vector3(center.x, -.96, center.y), Vector3(17.9, .25, 13.9), Color("19232b"))
	# Walls only on exposed edges; open seams inside one room have no wall.
	# The near sides cut away when an actor is behind them.
	for side in geometry.exposed_sides():
		build_side(side)
	# Lanterns stand against walls; corners that open onto the room have none.
	for p in Furnishing.lantern_points(geometry):
		lantern_points.append(Vector3(p.x, 0, p.y))
	for p in lantern_points:
		make_lantern(p)
	for i in mini(LIGHT_POOL, lantern_points.size()):
		# A fixed pool of unshadowed fills follows the player across large rooms.
		lamps.append(Geo.light(self, lantern_points[i] + Vector3(0, 2.2, 0), Color("ffbc71"), .6, 7.0))
		lamp_targets.append(i)
	if not lantern_points.is_empty():
		make_shadow_light(lantern_points[0])
	var room_type: String = room.get("type", "combat")
	if room_type in ["start", "treasure", "rest", "shop"] or preview:
		Geo.box(self, Vector3(0, -.003, 0), Vector3(6.2, .03, 4.6), Color("514450") if room_type == "shop" else Color("5d4c3e"))
		Geo.ring(self, Vector3(0, .035, 0), 1.65, Color("9e875c"), .025)
		Geo.ring(self, Vector3(0, .035, 0), 1.45, Color("7c7359"), .018)
	if room.has("props") and not preview:
		for record in room.props:
			if not record.get("destroyed", false):
				build_prop(record)
	elif room_type in ["combat", "boss"] and not preview:
		for index in geometry.cells.size():
			var cell: Vector2i = geometry.cells[index]
			var center := geometry.cell_center(cell)
			var points = [Vector3(-3.5, 0, -2.7), Vector3(3.5, 0, 2.7)]
			if (int(room.seed) + index) % 2 == 0:
				points = [Vector3(-3.8, 0, 2.7), Vector3(3.8, 0, -2.7)]
			for local in points:
				var p: Vector3 = local + Vector3(center.x, 0, center.y)
				var dims = Vector3(1.2, 1.2, 1.2)
				Geo.box(self, p + Vector3(0, .6, 0), dims, Color("4f5855"))
				Geo.box(self, p + Vector3(0, 1.22, 0), Vector3(1.35, .14, 1.35), Color("747b68"))
				Geo.collider(self, p + Vector3(0, 1.0, 0), Vector3(1.3, 2.0, 1.3))
				obstacles.append({"position": p, "radius": 1.05})
				make_candle(p + Vector3(0, 1.32, 0), .6)
	# Small details: decorative candles only; collision and layout never change.
	for cell in geometry.cells:
		var center := geometry.cell_center(cell)
		for i in [4, 10, 14][Settings.detail_level()]:
			var side = -1 if i % 2 == 0 else 1
			var p = Vector3(decor_rng.randf_range(-6.5, 6.5), 0, side * 6.2)
			if absf(p.x) < 1.7:
				p.x += 3.0
			if geometry.has_cell(cell + Vector2i(0, side)):
				continue
			if blocked_at(Vector2(p.x + center.x, p.z + center.y), .3, true):
				continue
			make_candle(p + Vector3(center.x, 0, center.y), decor_rng.randf_range(.45, .85))
	if room.has("mount") and room.has("painting") and not preview:
		build_painting(room.mount, room.painting)
	var shelves: Array = []
	for id in props:
		if props[id].record.def in ["bookcase", "shelf"]:
			var rect := Furnishing.record_rect(props[id].record)
			shelves.append(Vector3(rect.get_center().x, 0, rect.get_center().y))
	effects.populate_ambient(candle_points, lantern_points, shelves)
	ember_mesh = effects.ambient_mesh
	if geometry.cells.size() > 1 or not props.is_empty():
		navigation = RoomNavigation.new(geometry, obstacles)
	set_open(true)
	apply_lighting_quality()

func build_prop(record: Dictionary) -> void:
	var def: Dictionary = Content.get_def("furniture", record.def)
	if def.is_empty():
		return
	var node := PropBuilder.build(self, def, record, Settings.detail_level())
	var entry := {"node": node, "record": record}
	var rect := Furnishing.record_rect(record)
	if record.def == "pillar":
		make_candle(Vector3(rect.get_center().x, 1.32, rect.get_center().y), .6)
	if def.blocks:
		var height := maxf(.4, float(def.height))
		var body := Geo.collider(self, Vector3(rect.get_center().x, height / 2.0, rect.get_center().y), Vector3(rect.size.x, height, rect.size.y))
		body.set_meta("prop_id", record.id)
		entry.collider = body
		entry.obstacle = {"position": Vector3(rect.get_center().x, 0, rect.get_center().y), "radius": minf(rect.size.x, rect.size.y) / 2.0, "rect": rect}
		obstacles.append(entry.obstacle)
	props[record.id] = entry

## A wall-mounted painting: procedural frame, the real reproduction scaled to
## fit without cropping or stretching, and a plaque. While an image is still
## pending import, a plainly marked plate stands in; never substitute art.
func build_painting(mount: Dictionary, id: String) -> void:
	var record := Gallery.painting(id)
	if record.is_empty():
		return
	var node := Node3D.new()
	add_child(node)
	node.name = "Painting"
	node.set_meta("painting", id)
	var dir := Vector2(mount.dir[0], mount.dir[1])
	node.position = Vector3(mount.position[0], Furnishing.MOUNT_HEIGHT, mount.position[1])
	node.rotation.y = atan2(-dir.x, -dir.y)
	var area := Vector2(mount.size[0], mount.size[1]) - Vector2(.3, .3)
	var aspect: float = float(record.aspect)
	var size := Vector2(area.x, area.x / aspect) if area.x / aspect <= area.y else Vector2(area.y * aspect, area.y)
	var frame := Color("8a6a3c") if record.kind != "wall painting" else Color("6d6a62")
	for side in [-1, 1]:
		Geo.box(node, Vector3(side * (size.x / 2 + .07), 0, .03), Vector3(.14, size.y + .28, .08), frame)
		Geo.box(node, Vector3(0, side * (size.y / 2 + .07), .03), Vector3(size.x + .28, .14, .08), frame)
	var canvas := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	canvas.mesh = quad
	canvas.position = Vector3(0, 0, .04)
	var mat := StandardMaterial3D.new()
	mat.roughness = .9
	var tex := Gallery.texture(id)
	if tex:
		mat.albedo_texture = tex
		# A little self-light keeps the work readable in a dim room without
		# adding a light (the local light budget stays unchanged).
		mat.emission_enabled = true
		mat.emission_texture = tex
		mat.emission_energy_multiplier = .25
	else:
		mat.albedo_color = Color("2b2a27")
		var note := Label3D.new()
		note.text = "IMAGE PENDING\n" + record.title
		note.font_size = 28
		note.pixel_size = .006
		note.modulate = Color("c4bda7")
		note.position = Vector3(0, 0, .05)
		node.add_child(note)
	canvas.material_override = mat
	canvas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	canvas.name = "Canvas"
	node.add_child(canvas)
	Geo.box(node, Vector3(0, -size.y / 2 - .32, .05), Vector3(.7, .16, .04), Color("b1925c"), .15)

## True when p (XZ) is within `margin` of a blocking prop (or any prop).
func blocked_at(p: Vector2, margin := .5, include_decor := false) -> bool:
	for id in props:
		var entry: Dictionary = props[id]
		if not entry.has("obstacle") and not include_decor: continue
		if Furnishing.record_rect(entry.record).grow(margin).has_point(p):
			return true
	return false

## Remove a broken prop's visuals, collision and navigation block once.
func remove_prop(id: String) -> void:
	if not props.has(id):
		return
	var entry: Dictionary = props[id]
	props.erase(id)
	if is_instance_valid(entry.node): entry.node.queue_free()
	if entry.has("collider") and is_instance_valid(entry.collider):
		entry.collider.queue_free()
	if entry.has("obstacle"):
		obstacles.erase(entry.obstacle)
		navigation = RoomNavigation.new(geometry, obstacles)

## Miner's Lantern: make every concealed seam in this room glow for a while.
## The hint only points; the wall still needs a bomb or breach to open.
func highlight_seams(duration: float) -> Array:
	var lit: Array = []
	for socket in sockets:
		if not concealed.has(socket.portal): continue
		var center := geometry.cell_center(socket.cell)
		var direction: Vector2i = socket.dir
		var at := Vector3(center.x + direction.x * 9.15, 0, center.y + direction.y * 7.15) - Vector3(direction.x, 0, direction.y) * .3
		var glow := Geo.halo(self, at + Vector3(0, .04, 0), 3.0, Color(.95, .78, .45, .5))
		var seam := Geo.box(self, at + Vector3(0, .9, 0), Vector3(.06, 1.6, .06), Color("f1cc8a"), 2.4)
		for node in [glow, seam]:
			node.name = "SeamHint"
			concealed[socket.portal].append(node)
			get_tree().create_timer(duration).timeout.connect(func(): if is_instance_valid(node): node.queue_free())
		lit.append(socket.portal)
	return lit

## Open a concealed doorway in place: drop the wall and debris, build a gate.
func reveal_socket(portal: String) -> void:
	for socket in sockets:
		if socket.portal == portal:
			socket.state = "open"
			if concealed.has(portal):
				for node in concealed[portal]:
					if is_instance_valid(node): node.queue_free()
				front_walls = front_walls.filter(func(w): return is_instance_valid(w.body) and not w.body in concealed[portal])
				concealed.erase(portal)
			var center := geometry.cell_center(socket.cell)
			var direction: Vector2i = socket.dir
			var sign_value := float(direction.x + direction.y)
			make_gate(socket, Vector3(center.x + direction.x * 9.15, 0, center.y + direction.y * 7.15), direction, sign_value)
			set_open(open)

func socket_for(cell: Vector2i, direction: Vector2i) -> Dictionary:
	for socket in sockets:
		if socket.cell == cell and socket.dir == direction:
			return socket
	return {}

## World-space doorway point for a socket (on the cell edge).
func socket_position(socket: Dictionary) -> Vector3:
	var p := geometry.socket_point(socket.cell, socket.dir)
	return Vector3(p.x, 0, p.y)

func build_side(side: Dictionary) -> void:
	var cell: Vector2i = side.cell
	var direction: Vector2i = side.dir
	var center := geometry.cell_center(cell)
	var horizontal = direction.y != 0
	var sign_value := float(direction.x + direction.y)
	var height = WALL_BACK_HEIGHT if sign_value < 0 else WALL_FRONT_HEIGHT
	var length = 9.0 if horizontal else 7.0
	var front_side = direction if sign_value > 0 else Vector2i.ZERO
	for part in [-1, 1]:
		var along = float(part) * (length + 1.2) / 2.0
		var pos = Vector3(center.x + along, height / 2.0, center.y + sign_value * 7.2) if horizontal else Vector3(center.x + sign_value * 9.2, height / 2.0, center.y + along)
		var dims = Vector3(length - 1.2, height, .45) if horizontal else Vector3(.45, height, length - 1.2)
		make_wall(pos, dims, front_side)
	var socket := socket_for(cell, direction)
	var at = Vector3(center.x + direction.x * 9.15, 0, center.y + direction.y * 7.15)
	if not socket.is_empty() and socket.get("state", "open") != "concealed":
		make_gate(socket, at, direction, sign_value)
	else:
		var nodes := make_wall(at + Vector3(0, height / 2, 0), Vector3(.45, height, 2.5) if direction.x != 0 else Vector3(2.5, height, .45), front_side)
		if not socket.is_empty():
			# A concealed seam: cracked mortar, a draft of dust and loose rubble.
			nodes.append_array(make_seam_hint(at, direction, height))
			concealed[socket.portal] = nodes

func make_seam_hint(at: Vector3, direction: Vector2i, height: float) -> Array:
	var nodes: Array = []
	var inward := -Vector3(direction.x, 0, direction.y)
	var along := Vector3(absf(direction.y), 0, absf(direction.x))
	var face := at + inward * .24
	for i in 4:
		var crack := Geo.box(self, face + along * (sin(i * 2.1) * .5) + Vector3(0, .35 + i * height * .18, 0),
			Vector3(.04, .32, .04), Color("23292d"))
		crack.rotation = Vector3(0, 0, .5 * sin(i * 1.3)) if direction.y != 0 else Vector3(.5 * sin(i * 1.3), 0, 0)
		crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nodes.append(crack)
	for i in 5:
		var rubble := Geo.box(self, face + inward * (.25 + .18 * (i % 3)) + along * ((i - 2) * .32) + Vector3(0, .06, 0),
			Vector3.ONE * (.1 + .04 * (i % 2)), Color("4c4a44"))
		rubble.rotation.y = i * .9
		rubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nodes.append(rubble)
	return nodes

func make_gate(socket: Dictionary, at: Vector3, direction: Vector2i, sign_value: float) -> void:
	var gate = Node3D.new()
	add_child(gate)
	gate.position = at
	gate.set_meta("portal", socket.portal)
	var rotated = direction.x != 0
	var post_height = WALL_BACK_HEIGHT - .25 if sign_value < 0 else 1.5
	Geo.box(gate, Vector3(0, -.015, 0), Vector3(.8, .08, 2.25) if rotated else Vector3(2.25, .08, .8), Color("b69c6a"))
	for s in [-1, 1]:
		Geo.box(gate, Vector3(0, post_height / 2, s * 1.1) if rotated else Vector3(s * 1.1, post_height / 2, 0), Vector3(.25, post_height, .25), Color("797263"))
	if post_height > 1.5:
		Geo.box(gate, Vector3(0, post_height, 0), Vector3(.3, .18, 2.5) if rotated else Vector3(2.5, .18, .3), Color("797263"))
	var barrier = Geo.box(gate, Vector3(0, .75, 0), Vector3(.16, 1.45, 2.0) if rotated else Vector3(2.0, 1.45, .16), Color("b85e4c"), .7)
	barrier.name = "Barrier"
	Geo.halo(gate, Vector3(0, .035, 0), 3.5, Color(.92, .62, .25, .28))
	gates.append(gate)

func make_wall(at: Vector3, dimensions: Vector3, front_side := Vector2i.ZERO) -> Array:
	var body = Geo.box(self, at, dimensions, Color("394148"))
	var cap = Geo.box(self, at + Vector3(0, dimensions.y / 2 + .035, 0), Vector3(dimensions.x + .06, .09, dimensions.z + .06), Color("656358"))
	var collider = Geo.collider(self, at, dimensions + Vector3(0, 2, 0))
	var nodes: Array = [body, cap, collider]
	if front_side != Vector2i.ZERO:
		# Keep a static full-height occluder while the visible wall cuts away.
		# This avoids transparent wall passes and moving shadow-map casters.
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var caster = Geo.box(self, at, dimensions, Color("394148"))
		caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var along_x := front_side.y != 0
		var span := Vector2(at.x - dimensions.x / 2, at.x + dimensions.x / 2) if along_x else Vector2(at.z - dimensions.z / 2, at.z + dimensions.z / 2)
		front_walls.append({"body": body, "cap": cap, "shadow_caster": caster,
			"collider": collider, "side": front_side, "height": dimensions.y,
			"plane": at.z if along_x else at.x, "span": span})
		nodes.append(caster)
	return nodes

## Lower a foreground wall when the player or an enemy stands just inside it,
## using the wall's own boundary normal and extent rather than room-wide axes.
func update_wall_visibility(focus: Vector3, delta: float, others: Array = []) -> void:
	for wall in front_walls:
		var near = _behind_wall(wall, focus)
		for actor in others:
			if _behind_wall(wall, actor):
				near = true
				break
		var target = WALL_CUTAWAY_HEIGHT if near else WALL_FRONT_HEIGHT
		var height = target if delta <= 0 else move_toward(wall.height, target, delta * 7.0)
		if is_equal_approx(height, wall.height): continue
		wall.height = height
		wall.body.scale.y = height / WALL_FRONT_HEIGHT
		wall.body.position.y = height / 2
		wall.cap.position.y = height + .035

func _behind_wall(wall: Dictionary, p: Vector3) -> bool:
	var depth: float = p.z if wall.side.y > 0 else p.x
	var along: float = p.x if wall.side.y > 0 else p.z
	return depth > wall.plane - 3.2 and depth < wall.plane + 1.0 and along > wall.span.x - 2.0 and along < wall.span.y + 2.0

func make_lantern(p: Vector3) -> void:
	Geo.box(self, p + Vector3(0, .28, 0), Vector3(.85, .55, .85), Color("424d4c"))
	Geo.box(self, p + Vector3(0, .61, 0), Vector3(1.0, .12, 1.0), Color("716f5d"))
	Geo.cylinder(self, p + Vector3(0, 1.03, 0), .14, .8, Color("ac9061"))
	Geo.box(self, p + Vector3(0, 1.6, 0), Vector3(.5, .55, .5), Color("f7bb6d"), 1.05)
	Geo.box(self, p + Vector3(0, 1.94, 0), Vector3(.68, .12, .68), Color("826d51"))
	for x in [-.22, .22]:
		for z in [-.22, .22]:
			var bar = Geo.box(self, p + Vector3(x, 1.6, z), Vector3(.035, .65, .035), Color("6e6654"))
			bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Geo.halo(self, p + Vector3(0, .03, 0), 7.5, Color(1, .57, .17, .2))
	var glow = Geo.halo(self, p + Vector3(0, 1.65, 0), 2.0, Color(1, .6, .2, .4))
	glow.rotation_degrees.x = 58

## Move the pooled fills to the lanterns nearest `focus`. Lights move only when
## the selection actually changes, with hysteresis against flicker at borders.
func update_light_selection(focus: Vector3) -> void:
	if lantern_points.size() <= lamps.size():
		return
	var order: Array = range(lantern_points.size())
	order.sort_custom(func(a, b): return lantern_points[a].distance_squared_to(focus) < lantern_points[b].distance_squared_to(focus))
	var wanted: Array = order.slice(0, lamps.size())
	for slot in lamps.size():
		if lamp_targets[slot] in wanted:
			wanted.erase(lamp_targets[slot])
	for slot in lamps.size():
		if wanted.is_empty():
			break
		var current: int = lamp_targets[slot]
		if current in order.slice(0, lamps.size()):
			continue
		var candidate: int = wanted[0]
		if lantern_points[current].distance_to(focus) - lantern_points[candidate].distance_to(focus) < 2.0:
			continue
		wanted.pop_front()
		lamp_targets[slot] = candidate
		lamps[slot].position = lantern_points[candidate] + Vector3(0, 2.2, 0)

func make_shadow_light(p: Vector3) -> void:
	# A fixed inward-facing spotlight needs one map instead of six cube faces.
	var shadow_light = SpotLight3D.new()
	shadow_light.light_color = Color("ffbc71")
	shadow_light.light_cull_mask = 1
	shadow_light.light_energy = 1.5
	shadow_light.spot_range = 13.0
	shadow_light.spot_angle = 58.0
	shadow_light.spot_angle_attenuation = 1.5
	shadow_light.shadow_bias = .06
	shadow_light.shadow_normal_bias = .7
	shadow_light.shadow_opacity = 1.0
	shadow_light.visible = false
	add_child(shadow_light)
	shadow_light.position = p + Vector3(0, 2.2, 0)
	shadow_light.look_at(Vector3(p.x * .3, 0, p.z * .3))
	shadow_lamps.append(shadow_light)

func make_candle(p: Vector3, height: float) -> void:
	var wax = Geo.cylinder(self, p + Vector3(0, height / 2, 0), .12, height, Color("c9ad7e"))
	wax.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flame = Geo.sphere(self, p + Vector3(0, height + .1, 0), .11, Color("ffe0a1"), 2.0)
	flame.scale = Vector3(.7, 1.5, .7)
	candle_points.append(p + Vector3(0, height + .12, 0))
	Geo.halo(self, p + Vector3(0, .025, 0), 2.3, Color(1, .5, .13, .14))

func set_open(value: bool) -> void:
	open = value
	for gate in gates:
		gate.get_node("Barrier").visible = not value

func apply_lighting_quality() -> void:
	var enabled: bool = Settings.values.shadows
	if _quality_enabled == enabled:
		return
	_quality_enabled = enabled
	for light in shadow_lamps:
		light.shadow_enabled = enabled
		light.visible = enabled

func _process(delta: float) -> void:
	time += delta
	apply_lighting_quality()
	if is_instance_valid(game) and "player" in game and is_instance_valid(game.player) and game.player.get_parent() == get_parent():
		update_light_selection(game.player.position)
	for i in lamps.size():
		lamps[i].light_energy = .6 + sin(time * 3.1 + i * 2.4) * .025 + sin(time * 7.2 + i) * .012
