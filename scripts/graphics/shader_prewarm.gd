class_name ShaderPrewarm
extends Node3D
## A material's shader is compiled the first time it is drawn, and that frame
## stalls until it is ready: on a phone, tens of milliseconds per shader. A
## first fight, first kill, first puddle or first shot would each hitch.
## So each floor begins behind the light veil with one of everything it can
## show drawn for a few frames just ahead of the eye: this floor's foes and
## boss, friendly and hostile shots, every drop, every effect, the elite ward,
## each residue surface and the water mirror. When the veil lifts, those
## shaders are built. Nothing here touches the run, its RNG or its entity ids.
const HOLD_FRAMES := 3
const AHEAD := 2.6
const SPACING := .32
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
	emit_effects()
	show_residue(true)

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
