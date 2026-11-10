class_name ResidueField
extends Node3D
## What a fight leaves on the floor, and how it reacts. Tiles of wax, ice,
## fire, moss, glass, water and ink sit on a fine grid over the room; spore
## and steam clouds float above it. Burn ignites wax and moss (fire spreads
## along them), melts ice back to what it was, boils water into steam, burns
## ink away and sets spores off; chill turns wax and water to ice and puts
## fire out; poison spreads through a spore cloud; glass splits a shot
## crossing it; lightning runs through a whole pool of water. A floor theme
## lays some of it down for good (FloorHazards). Lives for one visit: nothing
## here is saved, and a room lays the same floor again from its seed.
const TILE := .8
const FIRE_LIFE := 3.2
const ICE_LIFE := 9.0
const SPREAD_DELAY := .28
const MAX_CLOUDS := 4
const CLOUD_LIFE := 6.5
const CLOUD_BLAST := 22.0
# Per kind: colour (alpha is its opacity), glow so it shows in the dark,
# shimmer, roughness and height above the floor.
const LOOKS := {"wax": [Color(.86, .78, .6, .9), .12, 0.0, .45, .025], "ice": [Color(.55, .72, .81, .72), .04, 0.0, .22, .03],
	"fire": [Color(1.0, .55, .2, .95), 1.6, 1.0, .9, .035], "moss": [Color(.42, .62, .33, .92), .08, 0.0, .9, .028],
	"glass": [Color(.82, .94, 1.0, .62), .4, 0.0, .1, .032], "water": [Color(.2, .4, .5, .72), .02, 0.0, .05, .022],
	"ink": [Color(.1, .08, .14, .88), .05, 0.0, .3, .026]}
const STEAM_LIFE := 3.5
const WATERY := ["water", "ice"]
# The order the residue shader knows kinds by.
const KINDS := ["wax", "ice", "fire", "moss", "glass", "water", "ink"]
const MAX_RIPPLES := 8
var ripples: Array = []
var clock = 0.0
var wade = 0.0
var rain = 0.0
# Rain is cosmetic: its own stream, never the gameplay generator.
var drizzle := RandomNumberGenerator.new()
# How much each kind slows whoever wades through it.
const DRAG := {"moss": .75, "water": .8, "ink": .6}
const SHOCK_REACH := 400
var first_person := false
var game: Node3D
var geometry: RoomGeometry
# Vector2i tile -> {"kind", "age", "life", "spread", "under"}.
var tiles: Dictionary = {}
var clouds: Array = []
# All clouds share one lit sheet. Its density is a max-union, so neither
# overlapping clouds nor the front/back of old sphere meshes stack white.
var cloud_view: MeshInstance3D
var mist_material: ShaderMaterial
# Per kind: {"view", "image", "texture"}; one texel per tile over the room.
var views: Dictionary = {}
var grid_origin := Vector2i.ZERO
var grid_size := Vector2i.ONE
var dirty := {}
var tick = 0.0
var elevated_surface: ArrayMesh
var surface_level := 0.0
var upper_field: ResidueField
# Co-op host: the tiles and clouds changed since the guests last heard.
var logging := false
var net_tiles: Dictionary = {}
var clouds_changed := false

func setup(owner_game: Node3D, room_geometry: RoomGeometry, elevation := 0.0) -> void:
	surface_level=elevation
	game = owner_game
	first_person = game.get("first_person") == true
	geometry = room_geometry
	grid_for(geometry)
	for kind in LOOKS:
		var look: Array = LOOKS[kind]
		var image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_R8)
		# The texture shows `shown`, which eases toward the mask (`image`):
		# patches spread out and drain away instead of popping.
		var shown = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_R8)
		var texture = ImageTexture.create_from_image(shown)
		var mat = ShaderMaterial.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(grid_size) * TILE
		if kind in WATERY and RenderPolicy.current().refraction:
			# Water and ice: reflective, refracting, and for water, rolling.
			mat.shader = preload("res://shaders/water_stylized.gdshader") if first_person else preload("res://shaders/water.gdshader")
			mat.set_shader_parameter("frozen", 1.0 if kind == "ice" else 0.0)
			mat.set_shader_parameter("detail", Look.detail())
			if game.get("mirror") and is_instance_valid(game.mirror): mat.set_shader_parameter("reflection", game.mirror.get_texture())
			if kind == "water" and Look.quality() > 0 and not first_person:
				plane.subdivide_width = int(plane.size.x * 3)
				plane.subdivide_depth = int(plane.size.y * 3)
		else:
			mat.shader = preload("res://shaders/residue.gdshader")
			mat.set_shader_parameter("tint", look[0])
			mat.set_shader_parameter("glow", look[1])
			mat.set_shader_parameter("flicker", look[2])
			mat.set_shader_parameter("roughness_value", look[3])
			mat.set_shader_parameter("kind", KINDS.find(kind))
			mat.set_shader_parameter("first_person", first_person)
			mat.set_shader_parameter("detail", Look.detail())
		mat.set_shader_parameter("mask", texture)
		mat.set_shader_parameter("grid_origin", Vector2(grid_origin) * TILE)
		mat.set_shader_parameter("grid_size", Vector2(grid_size))
		mat.set_shader_parameter("tile", TILE)
		var view = MeshInstance3D.new()
		if first_person and geometry.terrain and geometry.terrain.ledge.has_area():
			if not elevated_surface: elevated_surface = build_elevated_surface()
			view.mesh = elevated_surface
		else:
			view.mesh = plane
		view.material_override = mat
		view.layers = 8
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.position = Vector3(0,look[4],0) if elevated_surface else Vector3((grid_origin.x + grid_size.x / 2.0) * TILE, look[4], (grid_origin.y + grid_size.y / 2.0) * TILE)
		view.visible = false
		add_child(view)
		views[kind] = {"view": view, "image": image, "shown": shown, "level": PackedFloat32Array(), "easing": false, "texture": texture, "count": 0, "material": mat}
		views[kind].level.resize(grid_size.x * grid_size.y)
	drizzle.seed = Content.stable_hash("drizzle:%d" % grid_origin.x)
	setup_cloud_surface()

func setup_cloud_surface() -> void:
	cloud_view = MeshInstance3D.new()
	cloud_view.name = "MistSurface"
	cloud_view.mesh = QuadMesh.new() if first_person else PlaneMesh.new()
	mist_material = ShaderMaterial.new()
	mist_material.shader = preload("res://shaders/mist_eye.gdshader") if first_person else preload("res://shaders/mist.gdshader")
	mist_material.set_shader_parameter("detail", Look.detail())

	cloud_view.material_override = mist_material
	# Receive existing dungeon lighting, without reflection or shadow passes.
	cloud_view.layers = 8
	cloud_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_view.visible = false
	add_child(cloud_view)

## Only one transparent surface is drawn, even when several clouds meet.
## Fade uses simulation age; pausing cannot consume a cloud's lifetime.
func refresh_cloud_surface() -> void:
	if not is_instance_valid(cloud_view): return
	cloud_view.visible = not clouds.is_empty()
	if clouds.is_empty(): return
	var fields = PackedVector4Array()
	var tints = PackedColorArray()
	var area := Rect2()
	for i in clouds.size():
		var cloud: Dictionary = clouds[i]
		var at = Vector2(cloud.at.x, cloud.at.z)
		var fade = smoothstep(0.0, .18, float(cloud.age)) * smoothstep(0.0, .85, float(cloud.life - cloud.age))
		fields.append(Vector4(at.x, at.y, cloud.radius, fade))
		if cloud.kind == "steam": tints.append(Color(.57, .66, .69, .2))
		else: tints.append(Color(.34, .56, .23, .23) if cloud.poisoned else Color(.48, .55, .34, .22))
		var patch = Rect2(at - Vector2.ONE * cloud.radius * 1.15, Vector2.ONE * cloud.radius * 2.3)
		area = patch if i == 0 else area.merge(patch)
	while fields.size() < MAX_CLOUDS:
		fields.append(Vector4.ZERO)
		tints.append(Color.TRANSPARENT)
	var center = area.get_center()
	var low_height := 0.0
	var high_height := 0.0
	if first_person:
		low_height = float(clouds[0].at.y)
		high_height = low_height
		for cloud in clouds:
			low_height = minf(low_height,cloud.at.y)
			high_height = maxf(high_height,cloud.at.y)
	var sheet_height := (low_height+high_height)*.5
	var plane = cloud_view.mesh
	var dimensions = area.size
	if first_person:
		var radius_max = 0.0
		for cloud in clouds: radius_max = maxf(radius_max, cloud.radius)
		dimensions = Vector2(area.size.length(),radius_max*1.8+high_height-low_height)
		cloud_view.rotation.y = game.fps.yaw
		# Project centres into the shared billboard's local plane. Keeping
		# shader fields in that plane avoids per-fragment 3D projections.
		var right: Vector3 = game.fps.right()
		for index in clouds.size():
			var field: Vector4 = fields[index]
			var offset = Vector3(field.x - center.x, 0, field.y - center.y)
			fields[index] = Vector4(offset.dot(right),(clouds[index].at.y-sheet_height)*1.3,field.z,field.w)
	if plane.size != dimensions: plane.size = dimensions
	if first_person: mist_material.set_shader_parameter("sheet_size", dimensions)
	cloud_view.position = Vector3(center.x,sheet_height+.8 if first_person else .62,center.y)
	mist_material.set_shader_parameter("sheet_origin", center)
	mist_material.set_shader_parameter("cloud_fields", fields)
	mist_material.set_shader_parameter("cloud_tints", tints)
	mist_material.set_shader_parameter("clock", clock)

## Rings spreading on water from a point (a shot landing, a foot wading).
func ripple(at: Vector3, strength := 1.0) -> void:
	var field:=layer_at(at)
	if field!=self: field.ripple(at,strength);return
	if kind_at(at) != "water": return
	if ripples.size() >= MAX_RIPPLES: ripples.pop_front()
	ripples.append(Vector4(at.x, at.z, clock, strength))

## Whether anything here would show the mirror.
func reflective() -> bool:
	# One reflection plane cannot correctly represent both storeys. Keep
	# their existing lit surface response rather than mirror the wrong floor.
	if first_person and geometry.terrain and geometry.terrain.ledge.has_area(): return false
	return RenderPolicy.current().reflections and WATERY.any(func(kind): return views[kind].count > 0)

## Water and ice show the mirror only while it runs.
func set_mirror(active: bool) -> void:
	if is_instance_valid(upper_field): upper_field.set_mirror(active)
	if not RenderPolicy.current().refraction: return
	for kind in WATERY:
		views[kind].material.set_shader_parameter("reflect_strength", .65 if active else 0.0)

## Visual only: rain on the cistern's pools, wading rings, the ripple clock.
## How fast a patch spreads in and drains away (mask units a second).
const SPREAD_RATE := 3.2
# How long after a field is made its patches appear at once, unanimated.
const SETTLE := .4
const DRAIN_RATE := 1.8
# Small particles each kind gives off now and then, and its splash colour.
const WISPS := {"fire": ["#ffb050", .05], "ink": ["#4a3a66", .3], "moss": ["#c8e08a", .45], "glass": ["#e8f6ff", .35], "wax": ["#f4e8c8", 1.6], "water": ["#9cc8d8", 1.2]}
var wisp_wait := 0.0

## Eases each kind's shown mask toward its tiles, a few texels at a time.
func ease_masks(delta: float) -> void:
	for kind in views:
		var entry: Dictionary = views[kind]
		if not entry.easing: continue
		var level: PackedFloat32Array = entry.level
		var target: PackedByteArray = entry.image.get_data()
		var out := PackedByteArray()
		out.resize(level.size())
		var moving := false
		var any := false
		for i in level.size():
			var goal := float(target[i]) / 255.0
			var now := level[i]
			if now != goal:
				now = minf(goal, now + delta * SPREAD_RATE) if goal > now else maxf(goal, now - delta * DRAIN_RATE)
				level[i] = now
				moving = true
			if now > 0.0: any = true
			out[i] = int(now * 255.0)
		entry.level = level
		entry.shown.set_data(grid_size.x, grid_size.y, false, Image.FORMAT_R8, out)
		entry.texture.update(entry.shown)
		entry.easing = moving
		entry.view.visible = any or entry.count > 0
		# The liquid's body follows, a few times a second while it moves.
		entry.body_wait = float(entry.get("body_wait", 0.0)) - delta
		if first_person and (not moving or entry.body_wait <= 0.0):
			entry.body_wait = BODY_STEP
			build_body(kind)

# ---------------------------------------------------------------- bodies
# First person, every patch is real geometry: a low heightfield over its
# tiles that domes up from the floor at the shore to a rounded top, so a
# pool of wax or ink has thickness at a glance and a silhouette at grazing
# angles. Built on the CPU from the eased mask (no vertex texture reads),
# only while a patch spreads or drains.
const BODY_STEP := .05
const THICKNESS := {"wax": .14, "ink": .1, "moss": .09, "water": .07, "ice": .06, "glass": .035, "fire": .04}
var ground_cache := {}

## The eased mask at a point in tile units from the grid's corner, read
## as the GPU's linear filter reads it.
func level_at(level: PackedFloat32Array, gx: float, gz: float) -> float:
	var fx := gx - .5
	var fz := gz - .5
	var x0 := floori(fx)
	var z0 := floori(fz)
	var tx := fx - x0
	var tz := fz - z0
	return lerpf(lerpf(texel(level, x0, z0), texel(level, x0 + 1, z0), tx), lerpf(texel(level, x0, z0 + 1), texel(level, x0 + 1, z0 + 1), tx), tz)

func texel(level: PackedFloat32Array, x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= grid_size.x or z >= grid_size.y: return 0.0
	return level[z * grid_size.x + x]

## The floor under a lattice point, remembered (the room never changes).
func ground_at(lattice: Vector2i, sub: int) -> float:
	var key_value := Vector3i(lattice.x, lattice.y, sub)
	if not ground_cache.has(key_value):
		var at := Vector3((grid_origin.x + float(lattice.x) / sub) * TILE, surface_level, (grid_origin.y + float(lattice.y) / sub) * TILE)
		ground_cache[key_value] = ground_height(at)
	return ground_cache[key_value]

func build_body(kind: String) -> void:
	var entry: Dictionary = views[kind]
	var level: PackedFloat32Array = entry.level
	var cells := {}
	for i in level.size():
		if level[i] <= 0.0: continue
		var x := i % grid_size.x
		var z := i / grid_size.x
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var cell := Vector2i(x + dx, z + dz)
				if cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y: cells[cell] = true
	if cells.is_empty(): return
	# Big lasting pools take fewer steps a tile.
	var sub := 3 if cells.size() < 140 else 2
	var thick: float = THICKNESS.get(kind, .04)
	var heights := {}
	var height := func(lattice: Vector2i) -> float:
		if heights.has(lattice): return heights[lattice]
		var c := level_at(level, float(lattice.x) / sub, float(lattice.y) / sub)
		var rise := clampf((c - .4) / .55, 0.0, 1.0)
		var dome := 1.0 - (1.0 - rise) * (1.0 - rise)
		var value: float = ground_at(lattice, sub) + thick * dome
		heights[lattice] = value
		return value
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var span := TILE / sub
	for cell in cells:
		var base: Vector2i = cell * sub
		var low := INF
		var high := -INF
		for corner in [Vector2i.ZERO, Vector2i(sub, 0), Vector2i(0, sub), Vector2i(sub, sub)]:
			var g: float = ground_at(base + corner, sub)
			low = minf(low, g)
			high = maxf(high, g)
		# A cliff between storeys is no floor to pool on.
		if high - low > .65: continue
		var start := vertices.size()
		for j in sub + 1:
			for i in sub + 1:
				var lattice: Vector2i = base + Vector2i(i, j)
				var x := (grid_origin.x + float(lattice.x) / sub) * TILE
				var z := (grid_origin.y + float(lattice.y) / sub) * TILE
				vertices.append(Vector3(x, height.call(lattice), z))
				var dx: float = height.call(lattice + Vector2i(1, 0)) - height.call(lattice - Vector2i(1, 0))
				var dz: float = height.call(lattice + Vector2i(0, 1)) - height.call(lattice - Vector2i(0, 1))
				normals.append(Vector3(-dx / (2.0 * span), 1.0, -dz / (2.0 * span)).normalized())
				uvs.append(Vector2(x, z))
		for j in sub:
			for i in sub:
				var a := start + j * (sub + 1) + i
				indices.append_array([a, a + 1, a + sub + 2, a, a + sub + 2, a + sub + 1])
	if vertices.is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	entry.view.mesh = mesh
	entry.view.position = Vector3(0, float(LOOKS[kind][4]) * .6, 0)
	entry.material.set_shader_parameter("body_mesh", true)

## Embers off fire, bubbles off ink, spores off moss, glints off glass,
## drips over wax and water: one at a time from a random tile, locally.
func give_off(delta: float) -> void:
	wisp_wait -= delta
	if wisp_wait > 0 or tiles.is_empty() or EffectsPool.current == null or not is_instance_valid(EffectsPool.current): return
	wisp_wait = .09
	var tile: Vector2i = tiles.keys()[randi() % tiles.size()]
	var kind: String = tiles[tile].kind
	if not WISPS.has(kind) or randf() > float(WISPS[kind][1]) * (3.0 if kind == "fire" else 1.0): return
	var at := cell_center(tile) + Vector3(randf_range(-.35, .35), .04, randf_range(-.35, .35))
	EffectsPool.current.emit("residue_wisp", at, Color(WISPS[kind][0]))

func animate(delta: float) -> void:
	if is_instance_valid(upper_field): upper_field.animate(delta)
	clock += delta
	ease_masks(delta)
	give_off(delta)
	if not RenderPolicy.current().refraction: return
	if views.water.count == 0: return
	wade -= delta
	if wade <= 0:
		wade = .3
		if is_instance_valid(game.player) and game.player.velocity.length() > .5: ripple(game.player.global_position, .6)
		for enemy in game.enemies:
			if is_instance_valid(enemy) and enemy.alive and enemy.targetable and (enemy.entity_id + int(clock * 10)) % 3 == 0:
				ripple(enemy.global_position, .5)
	if Run.active and Run.theme().get("hazard", "") == "water":
		rain -= delta
		if rain <= 0:
			rain = .16
			var wet: Array = tiles.keys()
			if not wet.is_empty():
				var tile: Vector2i = wet[drizzle.randi_range(0, wet.size() - 1)]
				var at = cell_center(tile) + Vector3(drizzle.randf_range(-.4, .4), 0, drizzle.randf_range(-.4, .4))
				ripple(at, .35)
	var packed = PackedVector4Array(ripples)
	while packed.size() < MAX_RIPPLES: packed.append(Vector4.ZERO)
	views.water.material.set_shader_parameter("ripples", packed)
	views.water.material.set_shader_parameter("clock", clock)

static func key(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / TILE), floori(at.z / TILE))

static func center(tile: Vector2i) -> Vector3:
	return Vector3((tile.x + .5) * TILE, 0, (tile.y + .5) * TILE)

func layer_at(at: Vector3) -> ResidueField:
	if surface_level<1 and first_person and geometry.terrain and geometry.terrain.loft and geometry.terrain.loft.upper(at):
		return upper()
	return self

func upper() -> ResidueField:
	if not is_instance_valid(upper_field):
		upper_field=ResidueField.new()
		upper_field.name="UpstairsResidue"
		add_child(upper_field)
		upper_field.setup(game,geometry,LoftRoom.RISE)
		upper_field.logging=logging
	return upper_field

func cell_center(tile: Vector2i) -> Vector3:
	var at:=center(tile)
	at.y=ground_height(at)
	return at

func ground_height(at: Vector3) -> float:
	if first_person and geometry.terrain:
		return geometry.terrain.height_at(Vector3(at.x,surface_level,at.z)) if geometry.terrain.loft else geometry.terrain.height_at(at)
	return 0.0

func touches_floor(at: Vector3, tolerance := .35) -> bool:
	return not first_person or absf(at.y-ground_height(at)) <= tolerance

## Whether the fire here was lit by the party (harmless to them).
func tame_at(at: Vector3) -> bool:
	var field:=layer_at(at)
	if field!=self: return field.tame_at(at)
	return bool(tiles.get(key(at), {}).get("tame", false))

func kind_at(at: Vector3) -> String:
	var field:=layer_at(at)
	if field!=self: return field.kind_at(at)
	return tiles.get(key(at), {}).get("kind", "") if touches_floor(at) else ""

## One shared mesh follows the room's physical floor, including cellar ramps.
## Cliff-crossing quads are omitted instead of stretching a puddle up a wall.
## A tile of margin on every side lets the edges fade out cleanly.
func grid_for(room_geometry: RoomGeometry) -> void:
	var area: Rect2 = room_geometry.bounds()
	grid_origin = key(Vector3(area.position.x, 0, area.position.y)) - Vector2i.ONE
	grid_size = key(Vector3(area.end.x, 0, area.end.y)) - grid_origin + Vector2i(2, 2)

# The split-level surface depends only on the room's fixed footprint and
# terrain, so it is kept on the geometry: built once, while a staged room
# is prepared, instead of on the frame the room is entered.
func surface_meta() -> String:
	return "residue_surface_%d" % roundi(surface_level * 100.0)

func build_elevated_surface() -> ArrayMesh:
	if geometry.has_meta(surface_meta()): return geometry.get_meta(surface_meta())
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(grid_origin.x,grid_origin.x+grid_size.x): surface_column(surface,x)
	return finish_surface(surface)

func surface_column(surface: SurfaceTool, x: int) -> void:
	for z in range(grid_origin.y,grid_origin.y+grid_size.y):
		var points: Array[Vector3] = [Vector3(x*TILE,0,z*TILE),Vector3((x+1)*TILE,0,z*TILE),Vector3((x+1)*TILE,0,(z+1)*TILE),Vector3(x*TILE,0,(z+1)*TILE)]
		if not geometry.contains(Vector2((x+.5)*TILE,(z+.5)*TILE),.05): continue
		var low := INF
		var high := -INF
		for i in 4:
			points[i].y = ground_height(points[i])
			low = minf(low,points[i].y)
			high = maxf(high,points[i].y)
		if high-low > .65: continue
		for index in [0,1,2,0,2,3]:
			surface.set_uv(Vector2(points[index].x,points[index].z))
			surface.add_vertex(points[index])

func finish_surface(surface: SurfaceTool) -> ArrayMesh:
	surface.generate_normals()
	var mesh := surface.commit()
	geometry.set_meta(surface_meta(), mesh)
	return mesh

## Builds a staged first-person room's ledge surfaces a column per slice:
## the floor's, and on a two-storey room the upstairs one too (made the
## first time anything upstairs touches residue, often a foe on its first
## step).
static func prepare_surface(room) -> void:
	var room_geometry: RoomGeometry = room.geometry
	if not room_geometry.terrain or not room_geometry.terrain.ledge.has_area(): return
	var levels: Array[float] = [0.0]
	if room_geometry.terrain.loft: levels.append(LoftRoom.RISE)
	for level in levels:
		var field := ResidueField.new()
		field.first_person = true
		field.geometry = room_geometry
		field.surface_level = level
		field.grid_for(room_geometry)
		if not room_geometry.has_meta(field.surface_meta()):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for x in range(field.grid_origin.x,field.grid_origin.x+field.grid_size.x):
				field.surface_column(surface,x)
				await room.pace()
			field.finish_surface(surface)
		field.free()

## Tiles inside the floor within a radius of a point.
func tiles_in(at: Vector3, radius: float) -> Array:
	var field:=layer_at(at)
	if field!=self: return field.tiles_in(at,radius)
	var result: Array = []
	var low = key(at - Vector3(radius, 0, radius))
	var high = key(at + Vector3(radius, 0, radius))
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			var tile = Vector2i(x, y)
			var c = cell_center(tile)
			if first_person and geometry.terrain and geometry.terrain.loft:
				var loft=geometry.terrain.loft
				if surface_level>1 and not loft.upper(Vector3(c.x,surface_level,c.z)): continue
				if surface_level<1 and loft.stairs.has_point(Vector2(c.x,c.z)): continue
			if first_person and absf(at.y-ground_height(c)) > maxf(.9,radius*.7): continue
			if Vector2(c.x - at.x, c.z - at.z).length() <= radius and geometry.contains(Vector2(c.x, c.z), .2):
				result.append(tile)
	return result

## Every tile of this room's floor.
func floor_tiles() -> Array:
	var result: Array = []
	for x in range(grid_origin.x, grid_origin.x + grid_size.x):
		for y in range(grid_origin.y, grid_origin.y + grid_size.y):
			var c = cell_center(Vector2i(x, y))
			if geometry.contains(Vector2(c.x, c.z), .2): result.append(Vector2i(x, y))
	return result

## Lays a kind over a patch. Fire only takes where something can burn. A
## lasting patch (a floor's own hazard) never melts or burns out by itself.
func add(kind: String, at: Vector3, radius: float, lasting := false) -> void:
	var field:=layer_at(at)
	if field!=self: field.add(kind,at,radius,lasting);return
	for tile in tiles_in(at, radius):
		var current: String = tiles.get(tile, {}).get("kind", "")
		if kind == "fire" and current not in ["wax", "moss"]: continue
		if current == "fire" and kind != "fire": continue
		set_tile(tile, kind, lasting)

## Fire that takes on bare stone too, for a little while: a vent's breath.
func scorch(at: Vector3, radius: float) -> void:
	var field:=layer_at(at)
	if field!=self: field.scorch(at,radius);return
	for tile in tiles_in(at, radius):
		if tiles.get(tile, {}).get("kind", "") == "water": continue
		set_tile(tile, "fire")

## `tame` fire was lit by the party (a spell, a bomb, a blast of theirs): it
## burns foes but never the players who lit it.
func set_tile(tile: Vector2i, kind: String, lasting := false, tame := false) -> void:
	var previous: String = tiles.get(tile, {}).get("kind", "")
	if kind == "":
		tiles.erase(tile)
	else:
		var life = -1.0 if lasting else {"fire": FIRE_LIFE, "ice": ICE_LIFE}.get(kind, -1.0)
		tiles[tile] = {"kind": kind, "age": 0.0, "life": life, "spread": SPREAD_DELAY, "under": previous if kind in ["fire", "ice"] else "", "tame": tame and kind == "fire"}
	dirty[previous] = true
	dirty[kind] = true
	# A new patch lands with a splash of its own colour (only on this device).
	if kind != "" and kind != previous and kind in LOOKS and randf() < .45 and EffectsPool.current != null and is_instance_valid(EffectsPool.current):
		var look: Array = LOOKS[kind]
		EffectsPool.current.emit("residue_splash", cell_center(tile) + Vector3.UP * .08, Color(look[0], 1.0).lightened(.15), 4)
	if logging: net_tiles[tile] = [kind, lasting]

## Burn, chill and poison meeting what lies here (only the party's spells
## react, so what they light is tame).
func react(at: Vector3, radius: float, stats: Dictionary) -> void:
	var field:=layer_at(at)
	if field!=self: field.react(at,radius,stats);return
	if float(stats.get("burn", 0)) > 0 or float(stats.get("explosion", 0)) > 0:
		ignite(at, radius, true)
	if float(stats.get("chill", 0)) > 0:
		freeze(at, radius)
	if float(stats.get("poison", 0)) > 0:
		var cloud = cloud_at(at)
		if cloud >= 0: poison_cloud(cloud)

func ignite(at: Vector3, radius: float, tame := false) -> void:
	var field:=layer_at(at)
	if field!=self: field.ignite(at,radius,tame);return
	var boiled = false
	for tile in tiles_in(at, radius):
		var current: String = tiles.get(tile, {}).get("kind", "")
		if current in ["wax", "moss"]: set_tile(tile, "fire", false, tame)
		elif current == "ice": set_tile(tile, tiles[tile].under)
		elif current == "ink": set_tile(tile, "")
		elif current == "water": boiled = true
	if boiled and cloud_at(at) < 0: add_cloud(at, maxf(1.2, radius * 1.4), "steam")
	for i in range(clouds.size() - 1, -1, -1):
		if first_person and absf(at.y-clouds[i].at.y) > maxf(1.4,radius*.5): continue
		if clouds[i].kind == "spores" and Vector2(clouds[i].at.x - at.x, clouds[i].at.z - at.z).length() < clouds[i].radius + radius * .5:
			explode_cloud(i, tame)

func freeze(at: Vector3, radius: float) -> void:
	var field:=layer_at(at)
	if field!=self: field.freeze(at,radius);return
	for tile in tiles_in(at, radius):
		var current: String = tiles.get(tile, {}).get("kind", "")
		if current in ["wax", "water"]: set_tile(tile, "ice")
		elif current == "fire": set_tile(tile, "wax" if tiles[tile].under == "wax" else "")

func slows(at: Vector3) -> float:
	var field:=layer_at(at)
	if field!=self: return field.slows(at)
	if not touches_floor(at,.35): return 1.0
	var factor: float = DRAG.get(kind_at(at), 1.0)
	var cloud = cloud_at(at)
	if cloud >= 0 and clouds[cloud].kind == "spores": factor *= .8
	return factor

## Lightning striking a foe in water runs through the whole pool: every foe
## standing in the same water takes a share. Returns how many it reached.
func shock(at: Vector3, damage: float, struck: Dictionary = {}) -> int:
	var field:=layer_at(at)
	if field!=self: return field.shock(at,damage,struck)
	if not touches_floor(at,.5): return 0
	if kind_at(at) != "water": return 0
	var pool := {}
	for tile in moss_linked(at, .5, ["water"]).slice(0, SHOCK_REACH): pool[tile] = true
	var reached = 0
	for enemy in game.enemies.duplicate():
		if not is_instance_valid(enemy) or not enemy.alive or struck.has(enemy.entity_id): continue
		if not pool.has(key(enemy.global_position)) or not touches_floor(enemy.global_position): continue
		Effects.beam(game, at + Vector3.UP * .1, enemy.global_position + Vector3.UP * .4, Color("c4e2ff"))
		enemy.shocked(damage)
		reached += 1
	return reached

## Whether a segment crosses glass; the first crossing splits a shot.
func crosses_glass(from: Vector3, to: Vector3) -> bool:
	var field:=layer_at(from)
	if field!=self: return field.crosses_glass(from,to)
	if first_person and not touches_floor(from,.9) and not touches_floor(to,.9): return false
	var steps = maxi(1, ceili(from.distance_to(to) / (TILE * .5)))
	for i in steps + 1:
		if kind_at(from.lerp(to, float(i) / steps)) == "glass": return true
	return false

## Moss tiles linked to a point through touching moss, from those within reach.
func moss_linked(at: Vector3, reach: float, kinds := ["moss"]) -> Array:
	var field:=layer_at(at)
	if field!=self: return field.moss_linked(at,reach,kinds)
	var queue: Array = tiles_in(at, reach).filter(func(tile): return tiles.has(tile) and tiles[tile].kind in kinds)
	var seen := {}
	for tile in queue: seen[tile] = true
	var i = 0
	while i < queue.size():
		var tile: Vector2i = queue[i]
		i += 1
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = tile + step
			if seen.has(next) or not tiles.has(next) or tiles[next].kind not in kinds: continue
			if first_person and absf(ground_height(cell_center(tile))-ground_height(cell_center(next))) > .65: continue
			seen[next] = true
			queue.append(next)
	return queue

## A cloud of spores (poison spreads through it, fire sets it off) or of
## steam. A shared softly feathered surface carries their visual density.
func add_cloud(at: Vector3, radius: float, kind := "spores") -> void:
	var field:=layer_at(at)
	if field!=self: field.add_cloud(at,radius,kind);return
	if clouds.size() >= MAX_CLOUDS: remove_cloud(0)
	var view = Node3D.new()
	add_child(view)
	var height := ground_height(at)
	view.position = Vector3(at.x,height,at.z)
	clouds.append({"at": Vector3(at.x,height,at.z), "radius": radius, "age": 0.0, "poisoned": false, "view": view, "kind": kind,
		"life": STEAM_LIFE if kind == "steam" else CLOUD_LIFE})
	clouds_changed = true
	refresh_cloud_surface()

func cloud_at(at: Vector3) -> int:
	var field:=layer_at(at)
	if field!=self:
		var found:=field.cloud_at(at)
		return found+MAX_CLOUDS if found>=0 else -1
	for i in clouds.size():
		if first_person and absf(at.y-clouds[i].at.y) > 1.8: continue
		if Vector2(clouds[i].at.x - at.x, clouds[i].at.z - at.z).length() < clouds[i].radius: return i
	return -1

func remove_cloud(index: int) -> void:
	if index>=MAX_CLOUDS and is_instance_valid(upper_field):
		upper_field.remove_cloud(index-MAX_CLOUDS)
		return
	if is_instance_valid(clouds[index].view): clouds[index].view.queue_free()
	clouds.remove_at(index)
	clouds_changed = true
	refresh_cloud_surface()

func poison_cloud(index: int) -> void:
	if index>=MAX_CLOUDS and is_instance_valid(upper_field):
		upper_field.poison_cloud(index-MAX_CLOUDS)
		return
	var cloud: Dictionary = clouds[index]
	if cloud.kind == "spores" and not cloud.poisoned:
		cloud.poisoned = true
		cloud.age = minf(cloud.age, CLOUD_LIFE * .4)
		clouds_changed = true
		refresh_cloud_surface()

## Fire sets spores off: everything inside is struck, and the blast lights
## what lies beneath. Spores the party set off spare the party.
func explode_cloud(index: int, tame := false) -> void:
	if index>=MAX_CLOUDS and is_instance_valid(upper_field):
		upper_field.explode_cloud(index-MAX_CLOUDS, tame)
		return
	var cloud: Dictionary = clouds[index]
	remove_cloud(index)
	Effects.ring_burst(game.scene_root, cloud.at, Color("c9d47a"), cloud.radius)
	Effects.burst(game.scene_root, cloud.at + Vector3.UP * .6, Color("e6d27a"), 12, 1.6)
	game.shake = maxf(game.shake, .18)
	Audio.play_sound("kill", .7)
	game.make_noise(cloud.at, 3.0)
	for enemy in game.enemies.duplicate():
		if first_person and is_instance_valid(enemy) and absf(enemy.global_position.y-cloud.at.y) > 1.8: continue
		if is_instance_valid(enemy) and enemy.alive and enemy.targetable and Vector2(enemy.global_position.x - cloud.at.x, enemy.global_position.z - cloud.at.z).length() < cloud.radius + enemy.radius:
			enemy.take_hit(CLOUD_BLAST, (enemy.global_position - cloud.at).normalized() * 2.0, false, false, "blast")
	for body in NetHooks.bodies(game):
		if tame: break
		if (not first_person or absf(body.global_position.y-cloud.at.y)<=1.8) and Vector2(body.global_position.x - cloud.at.x, body.global_position.z - cloud.at.z).length() < cloud.radius:
			game.set("harm_hint", "Bursting spores")
			body.hurt(1.0, cloud.at)
			game.set("harm_hint", "")
	ignite(cloud.at, cloud.radius * .8, tame)

func update_sim(delta: float) -> void:
	if is_instance_valid(upper_field): upper_field.update_sim(delta)
	tick -= delta
	var touch = tick <= 0
	if touch: tick = .25
	for tile in tiles.keys():
		if not tiles.has(tile): continue
		var entry: Dictionary = tiles[tile]
		entry.age += delta
		if entry.kind == "fire":
			entry.spread -= delta
			if entry.spread <= 0:
				entry.spread = 99.0
				for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next: Vector2i = tile + step
					if tiles.has(next) and tiles[next].kind in ["wax", "moss"]: set_tile(next, "fire", false, bool(entry.get("tame", false)))
		if entry.life > 0 and entry.age >= entry.life:
			# Fire leaves nothing; ice melts back to the wax it was.
			set_tile(tile, entry.under if entry.kind == "ice" else "")
	for i in range(clouds.size() - 1, -1, -1):
		var cloud: Dictionary = clouds[i]
		cloud.age += delta
		if cloud.age >= cloud.life:
			remove_cloud(i)
			continue
		if cloud.kind != "spores": continue
		if kind_at(cloud.at) == "fire":
			explode_cloud(i, tame_at(cloud.at))
			continue
		if touch:
			for enemy in game.enemies:
				if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable: continue
				var inside = (not first_person or absf(enemy.global_position.y-cloud.at.y)<=1.8) and Vector2(enemy.global_position.x - cloud.at.x, enemy.global_position.z - cloud.at.z).length() < cloud.radius
				if not inside: continue
				if cloud.poisoned: enemy.apply_status({"poison": .8})
				elif enemy.poison_time > 0: poison_cloud(i)
	if touch:
		for enemy in game.enemies:
			if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable: continue
			if first_person and not touches_floor(enemy.global_position): continue
			var under = kind_at(enemy.global_position)
			if under == "fire": enemy.apply_status({"burn": 1.2})
			# Water puts a burning foe out.
			elif under == "water": enemy.burn_time = 0.0
		for body in NetHooks.bodies(game):
			if (not first_person or touches_floor(body.global_position)) and kind_at(body.global_position) == "fire" and not tame_at(body.global_position):
				game.set("harm_hint", "Flames underfoot")
				body.hurt(1.0, body.global_position)
				game.set("harm_hint", "")
	for kind in dirty.keys():
		if views.has(kind): rebuild(kind)
	dirty.clear()
	if not clouds.is_empty() or (is_instance_valid(cloud_view) and cloud_view.visible): refresh_cloud_surface()

## Redraws one kind's mask; a kind with nothing on the floor is not drawn.
func rebuild(kind: String) -> void:
	var entry: Dictionary = views[kind]
	var image: Image = entry.image
	image.fill(Color.BLACK)
	var count = 0
	for tile in tiles:
		if tiles[tile].kind != kind: continue
		var at: Vector2i = tile - grid_origin
		if at.x < 0 or at.y < 0 or at.x >= grid_size.x or at.y >= grid_size.y: continue
		image.set_pixelv(at, Color.WHITE)
		count += 1
	entry.easing = true
	entry.view.visible = count > 0 or entry.view.visible
	entry.count = count
	# Headless, nothing animates: show the mask as it is. And whatever lies
	# here as a room is entered (its lasting pools, what was spilt before)
	# is simply there, full: only new spills spread in and drain away.
	if DisplayServer.get_name() == "headless" or not is_inside_tree() or clock < SETTLE: ease_masks(10.0)

## Co-op host: what changed on the floor since last asked, for the guests.
func take_changes() -> Dictionary:
	var result := {}
	var tiles_out: Array = []
	for layer in 2:
		var field: ResidueField = self if layer == 0 else upper_field
		if not is_instance_valid(field): continue
		for tile in field.net_tiles:
			tiles_out.append([tile, field.net_tiles[tile][0], field.net_tiles[tile][1], layer])
		field.net_tiles.clear()
	if not tiles_out.is_empty(): result["t"] = tiles_out
	if clouds_changed or (is_instance_valid(upper_field) and upper_field.clouds_changed):
		var list: Array = []
		for layer in 2:
			var field: ResidueField = self if layer == 0 else upper_field
			if not is_instance_valid(field): continue
			field.clouds_changed = false
			for cloud in field.clouds: list.append([cloud.at, cloud.radius, cloud.kind, cloud.poisoned, cloud.age, cloud.life, layer])
		result["c"] = list
	return result

## Co-op guest: the host's floor, tile by tile; this field never runs its own.
func apply_net(data: Dictionary) -> void:
	for entry in data.get("t", []):
		if not entry is Array or entry.size() < 4 or not entry[0] is Vector2i: continue
		var field: ResidueField = self if int(entry[3]) == 0 else upper()
		field.set_tile(entry[0], str(entry[1]), bool(entry[2]))
	if data.get("c") is Array:
		for field in [self, upper_field]:
			if not is_instance_valid(field): continue
			while not field.clouds.is_empty(): field.remove_cloud(field.clouds.size() - 1)
		for entry in data.c:
			if not entry is Array or entry.size() < 7 or not entry[0] is Vector3: continue
			var field: ResidueField = self if int(entry[6]) == 0 else upper()
			field.add_cloud(entry[0], float(entry[1]), str(entry[2]))
			var cloud: Dictionary = field.clouds.back()
			cloud.poisoned = bool(entry[3])
			cloud.age = float(entry[4])
			cloud.life = float(entry[5])
	for field in [self, upper_field]:
		if not is_instance_valid(field): continue
		for kind in field.dirty.keys():
			if field.views.has(kind): field.rebuild(kind)
		field.dirty.clear()
		field.refresh_cloud_surface()
