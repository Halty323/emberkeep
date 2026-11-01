class_name StairCinematic
extends RefCounted
## One camera, on the existing simulation clock. The third-person view is
## only a presentation of the already-authoritative scripted stair path.
const PULLBACK := .72
const RETURN := .6
const APPROACH := .8
const CLIMB := 3.2
const CAMERA_RADIUS := .18
const SHOULDER_DISTANCE := 3.45
const SHOULDER_HEIGHT := 2.05
const SHOULDER_SIDE := .62
var active := false
var phase := ""
var entry_offset := Vector3.UP * FirstPersonController.EYE
var entry_basis := Basis.IDENTITY
var behind := Vector3.BACK
var right := Vector3.RIGHT
var lock_yaw := 0.0
var lock_pitch := 0.0
var tracked_player: Node3D
var collision_exclusions: Array[RID] = []
var well_cover: MeshInstance3D
var last_amount := 0.0

func begin(game, arriving := false) -> void:
	if not game.first_person or not is_instance_valid(game.player): return
	active = true
	phase = "arrive" if arriving else "climb"
	tracked_player = game.player
	entry_offset = game.camera.global_position - tracked_player.global_position
	entry_basis = game.camera.global_basis
	lock_yaw = game.fps.yaw
	lock_pitch = game.fps.pitch
	var travel := Vector3.FORWARD.rotated(Vector3.UP, lock_yaw)
	var path: Array = game.transition.get("path", [])
	if arriving and path.size() >= 2:
		travel = path[-1] - path[-2]
	elif is_instance_valid(game.stairs):
		travel = game.stairs.position - tracked_player.position
	travel.y = 0
	if travel.length_squared() < .001: travel = Vector3.FORWARD.rotated(Vector3.UP, lock_yaw)
	travel = travel.normalized()
	behind = -travel
	right = travel.cross(Vector3.UP).normalized()
	if arriving:
		lock_yaw = atan2(-travel.x,-travel.z)
		lock_pitch = 0.0
		entry_offset = Vector3.UP * FirstPersonController.EYE
		entry_basis = Basis(Vector3.UP,lock_yaw)
		game.fps.yaw = lock_yaw
		game.fps.pitch = lock_pitch
		Run.view_angles = [lock_yaw,lock_pitch]
	cache_collision_exclusions(game)
	if arriving:
		for mesh in game.scene_root.find_children("*","MeshInstance3D",true,false):
			if mesh.has_meta("stairwell_hole"):
				well_cover = mesh
				well_cover.visible = false
				break
	game.fps.reset_input()
	game.fps.weapon.visible = false

## Returns true only while the cinematic owns the camera. Repeated render
## frames during pause produce exactly the same pose; no wall clock is used.
func pose(game) -> bool:
	if not active: return false
	if not Run.active or not game.first_person or game.in_menu or not is_instance_valid(game.player) or game.player != tracked_player:
		cancel(game)
		return false
	if game.transition.get("kind", "") != "stairs":
		finish(game)
		return false
	var arriving: bool = game.transition.get("phase", "climb") == "arrive"
	if phase != ("arrive" if arriving else "climb"):
		begin(game,arriving)
	var time: float = game.transition.get("time",0.0)
	var total := 0.0
	for duration in game.transition.get("times",[]): total += float(duration)
	var amount := 1.0 - smoothstep(maxf(0,total-RETURN),total,time) if arriving else smoothstep(0,PULLBACK,time)
	last_amount = amount
	var player: Node3D = game.player
	var eye := player.global_position + entry_offset
	var target := player.global_position + Vector3.UP * .88
	if arriving and is_instance_valid(game.room):
		# Watch the figure emerge into the room; never point down through its
		# floor while the scripted feet are still below the stairwell.
		target.y = maxf(target.y,game.room.floor_height(player.position)+.78)
	var follow := player.global_position
	var center: Vector3 = game.stairs.global_position if is_instance_valid(game.stairs) and not arriving else game.well_spot
	follow.x = lerpf(center.x,follow.x,.38)
	follow.z = lerpf(center.z,follow.z,.38)
	var shoulder := follow + behind*SHOULDER_DISTANCE + right*SHOULDER_SIDE + Vector3.UP*SHOULDER_HEIGHT
	if arriving and is_instance_valid(game.room):
		shoulder.y = maxf(shoulder.y,game.room.floor_height(player.position)+SHOULDER_HEIGHT)
	shoulder = unobstructed(game,target,shoulder)
	var wanted := eye.lerp(shoulder,amount)
	# The blended path also needs clearance when a wall sits beside the eye.
	wanted = unobstructed(game,eye,wanted)
	var look_basis := entry_basis
	if amount>.00001 and target.distance_squared_to(wanted)>.001:
		var look_direction := (target-wanted).normalized()
		# At either eye endpoint the target is directly below the camera.
		# Avoid an undefined up vector while retaining a stable stair heading.
		var look_up := -behind if absf(look_direction.dot(Vector3.UP))>.98 else Vector3.UP
		look_basis = Basis.looking_at(look_direction,look_up)
	game.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	game.camera.keep_aspect = Camera3D.KEEP_HEIGHT
	game.camera.fov = lerpf(float(Settings.values.fov),62.0,amount)
	game.camera.near = .06
	game.camera.far = 95
	game.camera.h_offset = 0
	game.camera.global_position = wanted
	game.camera.global_basis = entry_basis.slerp(look_basis,amount).orthonormalized()
	game.camera_focus = player.global_position
	player.visual.visible = amount > .12
	player.gun.visible = false
	player.shelter.visible = false
	game.fps.weapon.visible = false
	game.fps.yaw = lock_yaw
	game.fps.pitch = lock_pitch
	game.fps.reset_input()
	if not game.ui.is_touch_platform() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if game.paused or game.ui.mode != "play" else Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(game.room): game.room.update_light_selection(player.global_position)
	return true

func cache_collision_exclusions(game) -> void:
	collision_exclusions.clear()
	if game.player is CollisionObject3D: collision_exclusions.append(game.player.get_rid())
	for body in game.scene_root.find_children("*","CollisionObject3D",true,false):
		# The solid cylinder is an AI/normal movement reservation, not the
		# visible stair geometry; a scripted climb deliberately crosses it.
		if body.has_meta("stair_camera_ignore"): collision_exclusions.append(body.get_rid())

func unobstructed(game, from: Vector3, to: Vector3) -> Vector3:
	if from.distance_squared_to(to) < .0001: return to
	var shape := SphereShape3D.new()
	shape.radius = CAMERA_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,from)
	query.motion = to-from
	query.collision_mask = 1 | PropVisuals.FURNITURE_LAYER
	query.exclude = collision_exclusions
	var result: PackedFloat32Array = game.get_world_3d().direct_space_state.cast_motion(query)
	var fraction := maxf(0.0,float(result[0])-.015) if result.size()>0 and result[0]<1.0 else 1.0
	return from.lerp(to,fraction)

## Called before a room/player is released, or after the arrival path ends.
## The ordinary FPS controller supplies the final eye transform immediately.
func finish(game) -> void:
	if not active: return
	if is_instance_valid(well_cover): well_cover.visible = true
	well_cover = null
	active = false
	phase = ""
	if is_instance_valid(game.player):
		game.player.visual.visible = false
		game.player.gun.visible = false
		game.player.set_fade(1.0)
	if is_instance_valid(game.fps):
		game.fps.yaw = lock_yaw
		game.fps.pitch = lock_pitch
		game.fps.reset_input()
		if not game.in_menu and is_instance_valid(game.player): game.fps.update_view(0)
	tracked_player = null
	collision_exclusions.clear()
	last_amount = 0.0

func cancel(game) -> void:
	finish(game)

## A small enclosed continuation above the cut ceiling, lit by the stair's
## existing top light. No new lamp, viewport or gameplay obstruction is added.
static func build_shaft(room, at: Vector2, radius: float) -> Node3D:
	var shaft := Node3D.new()
	shaft.name = "StairLightShaft"
	room.add_child(shaft)
	var height := 2.7
	var base := 5.45
	var material := DungeonStyle.wall_material(Color("89816d"),false,"masonry")
	for side in [-1,1]:
		for axis in [0,1]:
			var p := Vector3(at.x,base+height/2,at.y)
			p.x += side*(radius+.11) if axis == 0 else 0.0
			p.z += side*(radius+.11) if axis == 1 else 0.0
			var size := Vector3(.22,height,radius*2+.44) if axis == 0 else Vector3(radius*2+.44,height,.22)
			var wall := Geo.box(shaft,p,size,Color("89816d"))
			wall.material_override = material
			Geo.collider(shaft,p,size)
	var cap_at := Vector3(at.x,base+height+.13,at.y)
	var cap_size := Vector3(radius*2+.44,.26,radius*2+.44)
	var cap := Geo.box(shaft,cap_at,cap_size,Color("b8a27c"))
	cap.material_override = material
	Geo.collider(shaft,cap_at,cap_size)
	return shaft
