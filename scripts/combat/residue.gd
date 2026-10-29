class_name ResidueField
extends Node3D
## What a fight leaves on the floor, and how it reacts. Tiles of wax, ice,
## fire, moss and glass sit on a fine grid over the room; spore clouds float
## above it. Burn ignites wax and moss (fire spreads along them), melts ice
## and sets spores off; chill turns wax to ice and puts fire out; poison
## spreads through a cloud; glass splits a shot crossing it. Lives for one
## fight: nothing here is saved.
const TILE := .8
const FIRE_LIFE := 3.2
const ICE_LIFE := 9.0
const SPREAD_DELAY := .28
const MAX_CLOUDS := 4
const CLOUD_LIFE := 6.5
const CLOUD_BLAST := 22.0
const COLORS := {"wax": Color(.86, .78, .6, .85), "ice": Color(.68, .86, .96, .7), "fire": Color(1.0, .55, .2, 1.0),
	"moss": Color(.42, .62, .33, .9), "glass": Color(.82, .94, 1.0, .55)}
var game: Node3D
var geometry: RoomGeometry
# Vector2i tile -> {"kind", "age", "life", "spread"}.
var tiles: Dictionary = {}
var clouds: Array = []
var views: Dictionary = {}
var dirty := {}
var tick = 0.0
var flicker = 0.0

func setup(owner_game: Node3D, room_geometry: RoomGeometry) -> void:
	game = owner_game
	geometry = room_geometry
	for kind in COLORS:
		# Overlapping low discs read as puddles rather than tiles.
		var mesh = CylinderMesh.new()
		mesh.top_radius = TILE * .68
		mesh.bottom_radius = TILE * .68
		mesh.height = .012
		mesh.radial_segments = 10
		mesh.rings = 1
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = mesh
		var view = MultiMeshInstance3D.new()
		view.multimesh = multimesh
		view.material_override = tile_material(kind)
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kind in ["fire", "ice", "glass"]: view.layers = 2
		add_child(view)
		views[kind] = view

static func tile_material(kind: String) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = .35 if kind in ["ice", "glass", "wax"] else .9
	if kind in ["fire", "ice", "glass"]:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if kind == "fire":
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return mat

static func key(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / TILE), floori(at.z / TILE))

static func center(tile: Vector2i) -> Vector3:
	return Vector3((tile.x + .5) * TILE, 0, (tile.y + .5) * TILE)

func kind_at(at: Vector3) -> String:
	return tiles.get(key(at), {}).get("kind", "")

## Tiles inside the floor within a radius of a point.
func tiles_in(at: Vector3, radius: float) -> Array:
	var result: Array = []
	var low = key(at - Vector3(radius, 0, radius))
	var high = key(at + Vector3(radius, 0, radius))
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			var tile = Vector2i(x, y)
			var c = center(tile)
			if Vector2(c.x - at.x, c.z - at.z).length() <= radius and geometry.contains(Vector2(c.x, c.z), .2):
				result.append(tile)
	return result

## Lays a kind over a patch. Fire only takes where something can burn.
func add(kind: String, at: Vector3, radius: float) -> void:
	for tile in tiles_in(at, radius):
		var current: String = tiles.get(tile, {}).get("kind", "")
		if kind == "fire" and current not in ["wax", "moss"]: continue
		if current == "fire" and kind != "fire": continue
		set_tile(tile, kind)

func set_tile(tile: Vector2i, kind: String) -> void:
	var previous: String = tiles.get(tile, {}).get("kind", "")
	if kind == "":
		tiles.erase(tile)
	else:
		var life = {"fire": FIRE_LIFE, "ice": ICE_LIFE}.get(kind, -1.0)
		tiles[tile] = {"kind": kind, "age": 0.0, "life": life, "spread": SPREAD_DELAY, "under": previous if kind in ["fire", "ice"] else ""}
	dirty[previous] = true
	dirty[kind] = true

## Burn, chill and poison meeting what lies here.
func react(at: Vector3, radius: float, stats: Dictionary) -> void:
	if float(stats.get("burn", 0)) > 0 or float(stats.get("explosion", 0)) > 0:
		ignite(at, radius)
	if float(stats.get("chill", 0)) > 0:
		freeze(at, radius)
	if float(stats.get("poison", 0)) > 0:
		var cloud = cloud_at(at)
		if cloud >= 0: poison_cloud(cloud)

func ignite(at: Vector3, radius: float) -> void:
	for tile in tiles_in(at, radius):
		var current: String = tiles.get(tile, {}).get("kind", "")
		if current in ["wax", "moss"]: set_tile(tile, "fire")
		elif current == "ice": set_tile(tile, "wax")
	for i in range(clouds.size() - 1, -1, -1):
		if Vector2(clouds[i].at.x - at.x, clouds[i].at.z - at.z).length() < clouds[i].radius + radius * .5:
			explode_cloud(i)

func freeze(at: Vector3, radius: float) -> void:
	for tile in tiles_in(at, radius):
		var current: String = tiles.get(tile, {}).get("kind", "")
		if current == "wax": set_tile(tile, "ice")
		elif current == "fire": set_tile(tile, "wax" if tiles[tile].under == "wax" else "")

func slows(at: Vector3) -> float:
	var factor = 1.0
	if kind_at(at) == "moss": factor *= .75
	if cloud_at(at) >= 0: factor *= .8
	return factor

## Whether a segment crosses glass; the first crossing splits a shot.
func crosses_glass(from: Vector3, to: Vector3) -> bool:
	var steps = maxi(1, ceili(from.distance_to(to) / (TILE * .5)))
	for i in steps + 1:
		if kind_at(from.lerp(to, float(i) / steps)) == "glass": return true
	return false

## Moss tiles linked to a point through touching moss, from those within reach.
func moss_linked(at: Vector3, reach: float, kinds := ["moss"]) -> Array:
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
			seen[next] = true
			queue.append(next)
	return queue

func add_cloud(at: Vector3, radius: float) -> void:
	if clouds.size() >= MAX_CLOUDS: remove_cloud(0)
	var view = Node3D.new()
	add_child(view)
	view.position = Vector3(at.x, 0, at.z)
	for i in 3:
		var puff = Geo.sphere(view, Vector3(cos(i * 2.1) * radius * .35, .7 + i * .15, sin(i * 2.1) * radius * .35), radius * (.62 - i * .08), Color(.62, .7, .5))
		puff.material_override = cloud_material(false)
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clouds.append({"at": Vector3(at.x, 0, at.z), "radius": radius, "age": 0.0, "poisoned": false, "view": view})

static func cloud_material(poisoned: bool) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(.48, .78, .36, .34) if poisoned else Color(.62, .66, .5, .3)
	return mat

func cloud_at(at: Vector3) -> int:
	for i in clouds.size():
		if Vector2(clouds[i].at.x - at.x, clouds[i].at.z - at.z).length() < clouds[i].radius: return i
	return -1

func remove_cloud(index: int) -> void:
	if is_instance_valid(clouds[index].view): clouds[index].view.queue_free()
	clouds.remove_at(index)

func poison_cloud(index: int) -> void:
	var cloud: Dictionary = clouds[index]
	if not cloud.poisoned:
		cloud.poisoned = true
		cloud.age = minf(cloud.age, CLOUD_LIFE * .4)
		for puff in cloud.view.get_children(): puff.material_override = cloud_material(true)

## Fire sets spores off: everything inside is struck, and the blast lights
## what lies beneath.
func explode_cloud(index: int) -> void:
	var cloud: Dictionary = clouds[index]
	remove_cloud(index)
	Effects.ring_burst(game.scene_root, cloud.at, Color("c9d47a"), cloud.radius)
	Effects.burst(game.scene_root, cloud.at + Vector3.UP * .6, Color("e6d27a"), 12, 1.6)
	game.shake = maxf(game.shake, .18)
	Audio.play_sound("kill", .7)
	game.make_noise(cloud.at, 3.0)
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy) and enemy.alive and enemy.targetable and Vector2(enemy.global_position.x - cloud.at.x, enemy.global_position.z - cloud.at.z).length() < cloud.radius + enemy.radius:
			enemy.take_hit(CLOUD_BLAST, (enemy.global_position - cloud.at).normalized() * 2.0, false, false, "blast")
	if Vector2(game.player.global_position.x - cloud.at.x, game.player.global_position.z - cloud.at.z).length() < cloud.radius:
		game.player.hurt(1.0, cloud.at)
	ignite(cloud.at, cloud.radius * .8)

func update_sim(delta: float) -> void:
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
					if tiles.has(next) and tiles[next].kind in ["wax", "moss"]: set_tile(next, "fire")
		if entry.life > 0 and entry.age >= entry.life:
			# Fire leaves nothing; ice melts back to the wax it was.
			set_tile(tile, entry.under if entry.kind == "ice" else "")
	for i in range(clouds.size() - 1, -1, -1):
		var cloud: Dictionary = clouds[i]
		cloud.age += delta
		if cloud.age >= CLOUD_LIFE:
			remove_cloud(i)
			continue
		if kind_at(cloud.at) == "fire":
			explode_cloud(i)
			continue
		if touch:
			for enemy in game.enemies:
				if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable: continue
				var inside = Vector2(enemy.global_position.x - cloud.at.x, enemy.global_position.z - cloud.at.z).length() < cloud.radius
				if not inside: continue
				if cloud.poisoned: enemy.apply_status({"poison": .8})
				elif enemy.poison_time > 0: poison_cloud(i)
	if touch:
		for enemy in game.enemies:
			if is_instance_valid(enemy) and enemy.alive and enemy.targetable and kind_at(enemy.global_position) == "fire":
				enemy.apply_status({"burn": 1.2})
		if kind_at(game.player.global_position) == "fire":
			game.player.hurt(1.0, game.player.global_position)
	flicker += delta
	if tiles.values().any(func(entry): return entry.kind == "fire"): dirty["fire"] = true
	for kind in dirty.keys():
		if views.has(kind): rebuild(kind)
	dirty.clear()

func rebuild(kind: String) -> void:
	var chosen: Array = tiles.keys().filter(func(tile): return tiles[tile].kind == kind)
	var multimesh: MultiMesh = views[kind].multimesh
	multimesh.instance_count = chosen.size()
	var base: Color = COLORS[kind]
	for i in chosen.size():
		var tile: Vector2i = chosen[i]
		var h = absi(hash(tile))
		var turn = Basis(Vector3.UP, float(h % 360) * .0175).scaled(Vector3(1, 1, 1) * (.85 + float(h % 7) * .06))
		var lift = {"wax": .025, "moss": .03, "ice": .035, "glass": .04, "fire": .05}[kind]
		multimesh.set_instance_transform(i, Transform3D(turn, center(tile) + Vector3(0, lift, 0)))
		var tint = base
		if kind == "fire":
			var wave = .7 + .3 * sin(flicker * 11.0 + float(h % 17))
			tint = Color(base.r * wave, base.g * wave * .9, base.b * wave * .6, 1.0)
		elif kind == "wax":
			tint = base.darkened(float(h % 5) * .03)
		multimesh.set_instance_color(i, tint)
