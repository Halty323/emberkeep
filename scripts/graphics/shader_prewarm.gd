class_name ShaderPrewarm
extends Node3D
## A material's shader is compiled the first time it is drawn, and that frame
## stalls until it is ready: on a phone, tens of milliseconds per shader. A
## first fight, first kill, first puddle or first shot would each hitch.
## So each floor begins behind the light veil with one of everything it can
## show drawn for a few frames just ahead of the eye: this floor's foes and
## boss, friendly and hostile shots, every drop, every effect, the elite ward,
## each residue surface and the water mirror, and a swatch of every material
## the floor's other rooms use (each built once, unseen, then freed). When
## the veil lifts, those shaders are built. Nothing here touches the run, its
## RNG or its entity ids.
const HOLD_FRAMES := 3
const AHEAD := 2.6
const SPACING := .32
const SWATCH := .07
const MAX_SWATCHES := 360
# Materials this warm-up already draws, or the current room already shows.
var warmed: Dictionary = {}
static var swatch_mesh: BoxMesh
static var swatch_multimesh: MultiMesh
var swatches := 0
var game
var frames_left := HOLD_FRAMES
var residue_shown: Dictionary = {}
var mist_shown := false
var lights_before := 0

static func begin(owner_game) -> ShaderPrewarm:
	var warm := ShaderPrewarm.new()
	warm.name = "ShaderPrewarm"
	warm.game = owner_game
	owner_game.scene_root.add_child(warm)
	warm.stock()
	return warm

func active() -> bool:
	return frames_left > 0

## Low on the floor ahead of the camera, wherever it looks (an arrival shot
## included): in view of the eye and of the water mirror alike.
func place_ahead() -> void:
	var camera: Camera3D = game.camera
	var forward := -camera.global_basis.z
	forward.y = 0
	forward = forward.normalized() if forward.length_squared() > .01 else Vector3.FORWARD
	var floor_y: float = game.player.global_position.y if is_instance_valid(game.player) else 0.0
	global_transform = Transform3D(Basis.looking_at(forward), Vector3(camera.global_position.x, floor_y, camera.global_position.z) + forward * AHEAD)

func slot(index: int) -> Vector3:
	var column := index % 9
	var row := index / 9
	return Vector3((column - 4) * SPACING, .05 + row * .22, row * .2)

func holder(index: int) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	node.position = slot(index)
	node.scale = Vector3.ONE * .3
	return node

func stock() -> void:
	place_ahead()
	var index := 0
	var room = game.room
	lights_before = room.extra_lights.size() if is_instance_valid(room) else 0
	var roots_before: Array = game.scene_root.get_children()
	# The floor's own foes and its boss, without joining the fight.
	var kinds: Array = []
	for entry in Foes.roster_for(Run.theme_id(), Run.floor_number, Run.floor_plan):
		if str(entry[0]) not in kinds: kinds.append(str(entry[0]))
	var boss_kind := Foes.boss_kind(Run.theme())
	if boss_kind not in kinds: kinds.append(boss_kind)
	for kind in kinds:
		if not Foes.known(kind): continue
		var foe: DungeonEnemy = Foes.create(kind)
		foe.process_mode = Node.PROCESS_MODE_DISABLED
		holder(index).add_child(foe)
		foe.setup(game, kind, 0)
		foe.remove_from_group("enemies")
		foe.collision_layer = 0
		foe.collision_mask = 0
		index += 1
	# A ward, as an elite wears it.
	var ward := Geo.sphere(holder(index), Vector3(0, .5, 0), .5, Color(.64, .86, .81), .5)
	ward.material_override = DungeonEnemy.ward_material()
	index += 1
	# Both kinds of shot, with the run's own weapon effects.
	var weapon: Dictionary = Run.weapon()
	for friendly in [true, false]:
		var shot := EmberShot.new()
		shot.process_mode = Node.PROCESS_MODE_DISABLED
		holder(index).add_child(shot)
		shot.setup(game, Vector3.ZERO, Vector3.FORWARD, 0.0, 0.0, Run.stats if friendly else {}, Color(weapon.get("color", "ffd18c")) if friendly else Color("f29d8c"), friendly)
		shot.position = Vector3.ZERO
		index += 1
	for definition in Content.families.get("pickups", []):
		var pickup := DungeonPickup.new()
		pickup.process_mode = Node.PROCESS_MODE_DISABLED
		holder(index).add_child(pickup)
		pickup.setup(game, Vector3.ZERO, str(definition.id))
		index += 1
	# Anything a setup left in the room (a vine, a fixture's light) is ours.
	if is_instance_valid(room):
		while room.extra_lights.size() > lights_before: room.extra_lights.pop_back()
	for child in game.scene_root.get_children():
		if child != self and child not in roots_before: child.reparent(self)
	if game.first_person: room_swatches()
	emit_effects()
	show_residue(true)

## Builds each other room of the floor once, hidden and inert, and keeps a
## small swatch of every material it draws with (instanced ones instanced).
## Only one room exists at a time; each is freed straight after.
func room_swatches() -> void:
	for material in collect(game.room): warmed[material] = true
	var pool = EffectsPool.current
	for id in Run.rooms:
		if id == Run.current_room or swatches >= MAX_SWATCHES: continue
		var room := DungeonRoom.new()
		room.prepare_entry = false
		room.visible = false
		room.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(room)
		room.build(game, Run.rooms[id], false, true)
		room.resume_build(true)
		var found := collect(room)
		remove_child(room)
		room.free()
		for key in found:
			if warmed.has(key) or swatches >= MAX_SWATCHES: continue
			warmed[key] = true
			add_swatch(found[key][0], found[key][1])
	EffectsPool.current = pool

## Every material a room's geometry draws with: [material, instanced].
func collect(room: Node) -> Dictionary:
	var found := {}
	if not is_instance_valid(room): return found
	for node in room.find_children("*", "GeometryInstance3D", true, false):
		var instanced: bool = node is MultiMeshInstance3D
		var materials: Array = [node.material_override, node.material_overlay]
		if node is MeshInstance3D and node.mesh:
			for surface in node.mesh.get_surface_count():
				materials.append(node.get_active_material(surface))
		for material in materials:
			if material == null: continue
			found["%d:%s" % [material.get_instance_id(), instanced]] = [material, instanced]
	return found

func add_swatch(material: Material, instanced: bool) -> void:
	if swatch_mesh == null:
		swatch_mesh = BoxMesh.new()
		swatch_mesh.size = Vector3.ONE * SWATCH
		swatch_multimesh = MultiMesh.new()
		swatch_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		swatch_multimesh.use_colors = true
		swatch_multimesh.mesh = swatch_mesh
		swatch_multimesh.instance_count = 1
		swatch_multimesh.set_instance_transform(0, Transform3D.IDENTITY)
		swatch_multimesh.set_instance_color(0, Color.WHITE)
	var node: GeometryInstance3D
	if instanced:
		node = MultiMeshInstance3D.new()
		node.multimesh = swatch_multimesh
	else:
		node = MeshInstance3D.new()
		node.mesh = swatch_mesh
	node.material_override = material
	add_child(node)
	# A low wall of swatches ahead, beside the foes and drops.
	var column := swatches % 24
	var row := swatches / 24
	node.position = Vector3((column - 11.5) * SWATCH * 1.3, .6 + row * SWATCH * 1.3, .4)
	swatches += 1

## Every effect recipe, a ring and a beam, from the room's own pool.
func emit_effects() -> void:
	var pool = EffectsPool.current
	if pool == null or not is_instance_valid(pool): return
	var at := global_position + Vector3.UP * .4
	for recipe in Content.families.get("effects", []):
		pool.emit(str(recipe.id), at, Color("ffd9a0"), 1, 1.0, Vector3.UP)
	pool.ring(at, Color("ffd9a0"), .6)
	pool.beam(at, at + global_basis.x, Color("ffd9a0"))

## Every residue surface draws (its mask is empty, so nothing shows).
func show_residue(on: bool) -> void:
	var field = game.residue
	if field == null or not is_instance_valid(field): return
	for kind in field.views:
		var view: MeshInstance3D = field.views[kind].view
		if on:
			residue_shown[kind] = view.visible
			view.visible = true
		elif residue_shown.has(kind):
			view.visible = residue_shown[kind]
	if field.cloud_view:
		if on:
			mist_shown = field.cloud_view.visible
			field.cloud_view.visible = true
		else:
			field.cloud_view.visible = mist_shown

## Counts the drawn frames, then removes everything it showed.
func step() -> void:
	if frames_left <= 0: return
	frames_left -= 1
	if frames_left > 0: return
	show_residue(false)
	# Warm-up particles must not still be drifting when the veil lifts.
	if EffectsPool.current and is_instance_valid(EffectsPool.current): EffectsPool.current.expire_transients()
	queue_free()
