class_name ShaderPrewarm
extends Node3D
## A material's shader is compiled the first time it is drawn, and that frame
## stalls until it is ready: on a phone, tens of milliseconds per shader. A
## first fight, first kill, first puddle or first shot would each hitch.
## So each floor begins behind the light veil with one of everything it can
## show drawn for a few frames just ahead of the eye: this floor's foes and
## boss, friendly and hostile shots, every drop, every effect, the elite ward,
## each residue surface and the water mirror. Every distinct shader the floor's
## rooms use (each room built once, unseen, then freed) is also drawn in each
## lighting situation play will put it in, with one real lit corridor. When
## the veil lifts, those programs are built. Nothing here touches the run,
## its RNG or its entity ids.
const HOLD_FRAMES := 3
const AHEAD := 2.6
const SPACING := .32
const SWATCH := .07
const FAR := 36.0
# One representative material per distinct shader: key -> [material, instanced].
var shaders: Dictionary = {}
var keys: Dictionary = {}
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

## Builds each other room of the floor once, hidden and inert, notes every
## shader it draws with, and frees it. Only one room exists at a time.
func room_swatches() -> void:
	gather(self)
	gather(game.room)
	gather(game.residue)
	var pool = EffectsPool.current
	for id in Run.rooms:
		if id == Run.current_room: continue
		var room := DungeonRoom.new()
		room.prepare_entry = false
		room.visible = false
		room.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(room)
		room.build(game, Run.rooms[id], false, true)
		room.resume_build(true)
		gather(room)
		remove_child(room)
		room.free()
	EffectsPool.current = pool
	lay_swatches()
	lay_corridor()

## Notes one material per distinct shader under a node. Godot builds one
## program per shader and lighting situation, not per material, so a few
## dozen shaders cover a floor's hundreds of materials.
func gather(root: Node) -> void:
	if root == null or not is_instance_valid(root): return
	var nodes: Array = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D: nodes.append(root)
	for node in nodes:
		var instanced: bool = node is MultiMeshInstance3D
		var materials: Array = [node.material_override, node.material_overlay]
		if node is MeshInstance3D and node.mesh:
			for surface in node.mesh.get_surface_count():
				materials.append(node.get_active_material(surface))
		for material in materials:
			while material != null:
				var key := shader_key(material, instanced)
				if not shaders.has(key): shaders[key] = [material, instanced]
				material = material.next_pass

## Which compiled shader a material uses: a ShaderMaterial's shader, or a
## standard material's feature switches (its colours and amounts are only
## uniforms and share one program).
func shader_key(material: Material, instanced: bool) -> String:
	var id := material.get_instance_id()
	if not keys.has(id):
		var key := material.get_class()
		if material is ShaderMaterial:
			key += ":%d" % (material.shader.get_instance_id() if material.shader else 0)
		elif material is BaseMaterial3D:
			for property in material.get_property_list():
				if property.usage & PROPERTY_USAGE_STORAGE == 0 or property.name == "render_priority": continue
				if property.type == TYPE_BOOL or property.type == TYPE_INT: key += "|%s=%s" % [property.name, material.get(property.name)]
		else:
			key += ":%d" % id
		keys[id] = key
	return keys[id] + (":instanced" if instanced else "")

## Each shader drawn in each lighting situation play puts it in: near the eye
## under the carried light, under a shadowed spot lamp as well, and far off
## with no light at all. (The scene shader is specialised on exactly these:
## lights present or not, and an extra pass per shadowed light.)
func lay_swatches() -> void:
	var spot_cluster := Vector3(-1.4, 0, .2)
	var near_light := OmniLight3D.new()
	near_light.light_cull_mask = Geo.LIT_LAYERS
	near_light.omni_range = 3.0
	near_light.light_energy = .4
	add_child(near_light)
	near_light.position = Vector3(.6, 1.0, .3)
	var spot := SpotLight3D.new()
	spot.light_cull_mask = Geo.LIT_LAYERS
	spot.shadow_enabled = bool(Settings.values.shadows)
	spot.spot_range = 3.5
	spot.spot_angle = 24.0
	spot.light_energy = .4
	add_child(spot)
	spot.position = spot_cluster + Vector3(0, 2.6, 0)
	spot.rotation_degrees.x = -90.0
	for key in shaders:
		var material: Material = shaders[key][0]
		var instanced: bool = shaders[key][1]
		var column := swatches % 16
		var row := swatches / 16
		var across := (column - 7.5) * SWATCH * 1.3
		add_swatch(material, instanced, Vector3(across + .6, .06 + row * SWATCH * 1.3, .3))
		add_swatch(material, instanced, Vector3(across * .5, .06 + row * SWATCH * 1.3, -FAR))
		if not instanced: add_swatch(material, instanced, spot_cluster + Vector3(across * .4, .06 + row * SWATCH * 1.3, 0))
		swatches += 1

## One real corridor, lit by its own lamps, far ahead: corridor surfaces are
## lit only by corridor lamps, a situation no room surface is ever in.
func lay_corridor() -> void:
	var portals: Array = Run.rooms[Run.current_room].get("portals", [])
	if portals.is_empty(): return
	var portal: Dictionary = Run.portals[portals[0]]
	var path := CorridorPlan.from_room(CorridorPlan.ensure(portal, Run.rooms), portal, Run.current_room)
	var corridor := WalkableCorridor.new()
	# Drawn only: its collision never joins the world.
	corridor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(corridor)
	corridor.build(path, false, game.room.look)
	var middle: Vector2 = (path.front() + path.back()) * .5
	corridor.position = Vector3(-middle.x, 0, -middle.y - FAR * .5)

func add_swatch(material: Material, instanced: bool, at: Vector3) -> void:
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
	node.position = at

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
