class_name CorridorTransit
extends Node3D
## Bounded room streaming inside a genuinely walkable opaque connector.
## No camera rail, fade or input lock. Only the coordinate origin changes
## behind the middle elbows; player motion and the corridor remain continuous.
var game
var active: WalkableCorridor
var preview: Node3D
var portal_id := ""
var source_room := ""
var destination_room := ""
var destination_offset := Vector2.ZERO
var handoff := 0.0
var left_room := false
var handoffs := 0
var staged_room: DungeonRoom
var staged_id := ""

func setup(owner_game) -> void: game=owner_game

func reset() -> void:
	if is_instance_valid(staged_room):
		remove_child(staged_room)
		staged_room.queue_free()
	staged_room=null
	staged_id=""
	if is_instance_valid(preview):
		preview.visible=true
		preview.process_mode=Node.PROCESS_MODE_INHERIT
	preview=null
	if is_instance_valid(active):
		remove_child(active)
		active.queue_free()
	active=null
	portal_id=""
	left_room=false
	if game and is_instance_valid(game.room):
		game.room.entry_portal=""
		game.room.set_open(game.room.open)

func prepare() -> void:
	if not is_instance_valid(game.player) or not is_instance_valid(game.room): return
	var point:=Vector2(game.player.position.x,game.player.position.z)
	if not game.room.geometry.contains(point,.1): return
	if left_room or not game.room.open: return
	var nearest := ""
	var separation := 4.0
	for id in Run.rooms[Run.current_room].get("portals",[]):
		if Run.portals[id].state not in ["open","revealed"]: continue
		var side:=Run.portal_side(id,Run.current_room)
		var door:=RoomGeometry.socket_point(side.cell,side.dir)
		var distance:=door.distance_to(point)
		if distance<separation:
			separation=distance
			nearest=id
	if not nearest.is_empty() and nearest!=portal_id: arm(nearest)
	elif nearest.is_empty() and is_instance_valid(active): reset()

func arm(id: String) -> void:
	if id==portal_id or not Run.portals.has(id) or not game.room.open: return
	if Run.portals[id].state not in ["open","revealed"]: return
	reset()
	var portal: Dictionary=Run.portals[id]
	var plan:=CorridorPlan.ensure(portal,Run.rooms)
	source_room=Run.current_room
	destination_room=Run.other_room(id,source_room)
	destination_offset=FloorGenerator.vec2(plan.offset_b)*(1.0 if source_room==portal.a.room else -1.0)
	handoff=float(plan.handoff) if source_room==portal.a.room else float(plan.length)-float(plan.handoff)
	portal_id=id
	active=WalkableCorridor.new()
	active.name="ActiveCorridor"
	add_child(active)
	active.build(CorridorPlan.from_room(plan,portal,source_room),false,game.room.look)
	hide_preview()
	call_deferred("preload_room")

func preload_room() -> void:
	if not is_instance_valid(active) or not Run.active: return
	var other: String=destination_room if Run.current_room==source_room else source_room
	if is_instance_valid(staged_room) and staged_id==other: return
	if is_instance_valid(staged_room):
		remove_child(staged_room)
		staged_room.queue_free()
	staged_room=DungeonRoom.new()
	staged_id=other
	add_child(staged_room)
	var offset: Vector2=destination_offset if Run.current_room==source_room else -destination_offset
	staged_room.position=Vector3(offset.x,0,offset.y)
	staged_room.build(game,Run.rooms[other])
	staged_room.visible=false
	staged_room.process_mode=Node.PROCESS_MODE_DISABLED
	# Staging a neighbor must not change the active room's global effect mask.
	game.room.geometry.apply_shader_mask()
	EffectsPool.current=game.room.effects

func take_preloaded(id: String) -> DungeonRoom:
	if not is_instance_valid(staged_room) or staged_id!=id: return null
	var result:=staged_room
	remove_child(result)
	staged_room=null
	staged_id=""
	result.position=Vector3.ZERO
	result.visible=true
	result.process_mode=Node.PROCESS_MODE_INHERIT
	return result

func hide_preview() -> void:
	for gate in game.room.gates:
		if gate.get_meta("portal","")!=portal_id: continue
		preview=gate.get_node_or_null("Connector")
		if preview:
			preview.visible=false
			preview.process_mode=Node.PROCESS_MODE_DISABLED
		break

func contains_point(point: Vector2, margin := .0) -> bool:
	return is_instance_valid(active) and active.contains_point(point-Vector2(active.position.x,active.position.z),margin)

func walking() -> bool:
	return is_instance_valid(active) and is_instance_valid(game.player) and not game.room.geometry.contains(Vector2(game.player.position.x,game.player.position.z),.1)

func advance() -> void:
	if not is_instance_valid(active) or not is_instance_valid(game.player): return
	var point:=Vector2(game.player.position.x,game.player.position.z)
	var local_point:=point-Vector2(active.position.x,active.position.z)
	var along:=CorridorPlan.project(active.path,local_point)
	if walking(): left_room=true
	if Run.current_room==source_room and along>handoff+.25:
		rebase(destination_room,destination_offset)
	elif Run.current_room==destination_room and along<handoff-.25:
		rebase(source_room,-destination_offset)
	if left_room and game.room.geometry.contains(Vector2(game.player.position.x,game.player.position.z),1.05):
		reset()
		game.activate_corridor_encounter()

func rebase(destination: String, offset: Vector2) -> void:
	var shift:=Vector3(offset.x,0,offset.y)
	# All camera-relative positions stay identical during this atomic step.
	active.position-=shift
	active.reset_physics_interpolation()
	game.enter_corridor_room(destination,portal_id,shift)
	handoffs+=1
	preview=null
	hide_preview()
	call_deferred("preload_room")
