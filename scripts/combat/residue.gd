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
const LOOKS := {"wax": [Color(.86, .78, .6, .9), .12, 0.0, .45, .025], "ice": [Color(.7, .87, .97, .82), .35, 0.0, .15, .03],
	"fire": [Color(1.0, .55, .2, .95), 1.6, 1.0, .9, .035], "moss": [Color(.42, .62, .33, .92), .08, 0.0, .9, .028],
	"glass": [Color(.82, .94, 1.0, .62), .4, 0.0, .1, .032], "water": [Color(.2, .4, .5, .72), .18, 0.0, .05, .022],
	"ink": [Color(.1, .08, .14, .88), .05, 0.0, .3, .026]}
const STEAM_LIFE := 3.5
# How much each kind slows whoever wades through it.
const DRAG := {"moss": .75, "water": .8, "ink": .6}
const SHOCK_REACH := 400
var game: Node3D
var geometry: RoomGeometry
# Vector2i tile -> {"kind", "age", "life", "spread", "under"}.
var tiles: Dictionary = {}
var clouds: Array = []
# Per kind: {"view", "image", "texture"}; one texel per tile over the room.
var views: Dictionary = {}
var grid_origin := Vector2i.ZERO
var grid_size := Vector2i.ONE
var dirty := {}
var tick = 0.0

func setup(owner_game: Node3D, room_geometry: RoomGeometry) -> void:
	game = owner_game
	geometry = room_geometry
	# A tile of margin on every side lets the edges fade out cleanly.
	var area: Rect2 = geometry.bounds()
	grid_origin = key(Vector3(area.position.x, 0, area.position.y)) - Vector2i.ONE
	grid_size = key(Vector3(area.end.x, 0, area.end.y)) - grid_origin + Vector2i(2, 2)
	for kind in LOOKS:
		var look: Array = LOOKS[kind]
		var image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_R8)
		var texture = ImageTexture.create_from_image(image)
		var mat = ShaderMaterial.new()
		mat.shader = preload("res://shaders/residue.gdshader")
		mat.set_shader_parameter("mask", texture)
		mat.set_shader_parameter("tint", look[0])
		mat.set_shader_parameter("glow", look[1])
		mat.set_shader_parameter("flicker", look[2])
		mat.set_shader_parameter("roughness_value", look[3])
		mat.set_shader_parameter("grid_origin", Vector2(grid_origin) * TILE)
		mat.set_shader_parameter("grid_size", Vector2(grid_size))
		mat.set_shader_parameter("tile", TILE)
		var plane = PlaneMesh.new()
		plane.size = Vector2(grid_size) * TILE
		var view = MeshInstance3D.new()
		view.mesh = plane
		view.material_override = mat
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.position = Vector3((grid_origin.x + grid_size.x / 2.0) * TILE, look[4], (grid_origin.y + grid_size.y / 2.0) * TILE)
		view.visible = false
		add_child(view)
		views[kind] = {"view": view, "image": image, "texture": texture}

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

## Every tile of this room's floor.
func floor_tiles() -> Array:
	var result: Array = []
	for x in range(grid_origin.x, grid_origin.x + grid_size.x):
		for y in range(grid_origin.y, grid_origin.y + grid_size.y):
			var c = center(Vector2i(x, y))
			if geometry.contains(Vector2(c.x, c.z), .2): result.append(Vector2i(x, y))
	return result

## Lays a kind over a patch. Fire only takes where something can burn. A
## lasting patch (a floor's own hazard) never melts or burns out by itself.
func add(kind: String, at: Vector3, radius: float, lasting := false) -> void:
	for tile in tiles_in(at, radius):
		var current: String = tiles.get(tile, {}).get("kind", "")
		if kind == "fire" and current not in ["wax", "moss"]: continue
		if current == "fire" and kind != "fire": continue
		set_tile(tile, kind, lasting)

## Fire that takes on bare stone too, for a little while: a vent's breath.
func scorch(at: Vector3, radius: float) -> void:
	for tile in tiles_in(at, radius):
		if tiles.get(tile, {}).get("kind", "") == "water": continue
		set_tile(tile, "fire")

func set_tile(tile: Vector2i, kind: String, lasting := false) -> void:
	var previous: String = tiles.get(tile, {}).get("kind", "")
	if kind == "":
		tiles.erase(tile)
	else:
		var life = -1.0 if lasting else {"fire": FIRE_LIFE, "ice": ICE_LIFE}.get(kind, -1.0)
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
	var boiled = false
	for tile in tiles_in(at, radius):
		var current: String = tiles.get(tile, {}).get("kind", "")
		if current in ["wax", "moss"]: set_tile(tile, "fire")
		elif current == "ice": set_tile(tile, tiles[tile].under)
		elif current == "ink": set_tile(tile, "")
		elif current == "water": boiled = true
	if boiled and cloud_at(at) < 0: add_cloud(at, maxf(1.2, radius * 1.4), "steam")
	for i in range(clouds.size() - 1, -1, -1):
		if clouds[i].kind == "spores" and Vector2(clouds[i].at.x - at.x, clouds[i].at.z - at.z).length() < clouds[i].radius + radius * .5:
			explode_cloud(i)

func freeze(at: Vector3, radius: float) -> void:
	for tile in tiles_in(at, radius):
		var current: String = tiles.get(tile, {}).get("kind", "")
		if current in ["wax", "water"]: set_tile(tile, "ice")
		elif current == "fire": set_tile(tile, "wax" if tiles[tile].under == "wax" else "")

func slows(at: Vector3) -> float:
	var factor: float = DRAG.get(kind_at(at), 1.0)
	var cloud = cloud_at(at)
	if cloud >= 0 and clouds[cloud].kind == "spores": factor *= .8
	return factor

## Lightning striking a foe in water runs through the whole pool: every foe
## standing in the same water takes a share. Returns how many it reached.
func shock(at: Vector3, damage: float, struck: Dictionary = {}) -> int:
	if kind_at(at) != "water": return 0
	var pool := {}
	for tile in moss_linked(at, .5, ["water"]).slice(0, SHOCK_REACH): pool[tile] = true
	var reached = 0
	for enemy in game.enemies.duplicate():
		if not is_instance_valid(enemy) or not enemy.alive or struck.has(enemy.entity_id): continue
		if not pool.has(key(enemy.global_position)): continue
		Effects.beam(game, at + Vector3.UP * .1, enemy.global_position + Vector3.UP * .4, Color("c4e2ff"))
		enemy.shocked(damage)
		reached += 1
	return reached

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

## A cloud of spores (poison spreads through it, fire sets it off) or of
## steam (it only hides what is inside, and soon thins away).
func add_cloud(at: Vector3, radius: float, kind := "spores") -> void:
	if clouds.size() >= MAX_CLOUDS: remove_cloud(0)
	var view = Node3D.new()
	add_child(view)
	view.position = Vector3(at.x, 0, at.z)
	for i in 3:
		var puff = Geo.sphere(view, Vector3(cos(i * 2.1) * radius * .35, .7 + i * .15, sin(i * 2.1) * radius * .35), radius * (.62 - i * .08), Color(.62, .7, .5))
		puff.material_override = cloud_material(false, kind)
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clouds.append({"at": Vector3(at.x, 0, at.z), "radius": radius, "age": 0.0, "poisoned": false, "view": view, "kind": kind,
		"life": STEAM_LIFE if kind == "steam" else CLOUD_LIFE})

static func cloud_material(poisoned: bool, kind := "spores") -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if kind == "steam": mat.albedo_color = Color(.86, .9, .94, .3)
	else: mat.albedo_color = Color(.48, .78, .36, .34) if poisoned else Color(.62, .66, .5, .3)
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
	if cloud.kind == "spores" and not cloud.poisoned:
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
		if cloud.age >= cloud.life:
			remove_cloud(i)
			continue
		if cloud.kind != "spores": continue
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
			if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable: continue
			var under = kind_at(enemy.global_position)
			if under == "fire": enemy.apply_status({"burn": 1.2})
			# Water puts a burning foe out.
			elif under == "water": enemy.burn_time = 0.0
		if kind_at(game.player.global_position) == "fire":
			game.player.hurt(1.0, game.player.global_position)
	for kind in dirty.keys():
		if views.has(kind): rebuild(kind)
	dirty.clear()

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
	entry.texture.update(image)
	entry.view.visible = count > 0
