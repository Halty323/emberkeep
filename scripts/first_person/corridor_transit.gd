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
# An armed doorway stays armed until the player is this far from it, so
# pacing along the arming edge never rebuilds the corridor and its neighbour.
const DISARM_DISTANCE := 5.5
# In co-op the passage's turn is a gate: nobody passes it before the party
# is all in the passage, and nobody walks back past it once moved on.
const GATE := .35
# Co-op: this player stands at the gate, waiting for the others.
var coop_held := false

func setup(owner_game) -> void: game=owner_game

# Staging starts the frame after a corridor is built or a handoff, never in it.
var stage_pending := false

## The hidden neighbour builds a slice per frame while the corridor is walked.
func _process(_delta: float) -> void:
	if stage_pending:
		stage_pending = false
		FrameWatch.mark("next room, first slice")
		preload_room()
	elif is_instance_valid(staged_room) and staged_room.building:
		FrameWatch.mark("next room, building")
		staged_room.resume_build()
	elif is_instance_valid(staged_room) and int(staged_room.get_meta("warm", 0)) < WARM_FRAMES:
		warm_staged()

# Once built, the neighbour is drawn for a few frames where it stands, out
# of sight behind the corridor's walls, so the driver compiles its shaders
# and uploads its meshes now rather than on the step into it.
const WARM_FRAMES := 3

func warm_staged() -> void:
	var count := int(staged_room.get_meta("warm", 0)) + 1
	staged_room.set_meta("warm", count)
	FrameWatch.mark("next room, first draw")
	staged_room.visible = count < WARM_FRAMES

## Large discarded trees are deleted over several frames.
func discard(node: Node) -> void:
	if game and game.get("reaper"): game.reaper.reap(node)
	else:
		if node.get_parent(): node.get_parent().remove_child(node)
		node.queue_free()

func reset() -> void:
	stage_pending=false
	if is_instance_valid(staged_room): discard(staged_room)
	staged_room=null
	staged_id=""
	if is_instance_valid(preview):
		preview.visible=true
		preview.process_mode=Node.PROCESS_MODE_INHERIT
	preview=null
	if is_instance_valid(active): discard(active)
	active=null
	portal_id=""
	left_room=false
	coop_held=false
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
	var armed_distance := INF
	for id in Run.rooms[Run.current_room].get("portals",[]):
		if Run.portals[id].state not in ["open","revealed"]: continue
		var side:=Run.portal_side(id,Run.current_room)
		var door:=RoomGeometry.socket_point(side.cell,side.dir)
		var distance:=door.distance_to(point)
		if id==portal_id: armed_distance=distance
		if distance<separation:
			separation=distance
			nearest=id
	if not nearest.is_empty() and nearest!=portal_id: arm(nearest)
	elif nearest.is_empty() and is_instance_valid(active) and armed_distance>DISARM_DISTANCE: reset()

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
	FrameWatch.mark("corridor built")
	active=WalkableCorridor.new()
	active.name="ActiveCorridor"
	add_child(active)
	active.build(CorridorPlan.from_room(plan,portal,source_room),false,game.room.look)
	hide_preview()
	stage_pending=true

func preload_room() -> void:
	if not is_instance_valid(active) or not Run.active: return
	var other: String=destination_room if Run.current_room==source_room else source_room
	if is_instance_valid(staged_room) and staged_id==other: return
	if is_instance_valid(staged_room): discard(staged_room)
	staged_room=DungeonRoom.new()
	staged_id=other
	# Hidden and inert from the start: its colliders never join the world
	# until the handoff adopts it.
	staged_room.visible=false
	staged_room.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(staged_room)
	var offset: Vector2=destination_offset if Run.current_room==source_room else -destination_offset
	staged_room.position=Vector3(offset.x,0,offset.y)
	# Returns after the first slice; _process() builds the rest.
	staged_room.build(game,Run.rooms[other],false,true)
	# Staging a neighbor must not steal the active room's particles.
	EffectsPool.current=game.room.effects

func take_preloaded(id: String) -> DungeonRoom:
	if not is_instance_valid(staged_room) or staged_id!=id: return null
	# Reached before its last slice: finish it now.
	staged_room.resume_build(true)
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
	if not is_instance_valid(active): return false
	var local := point-Vector2(active.position.x,active.position.z)
	if not active.contains_point(local,margin): return false
	if gated():
		var along := CorridorPlan.project(active.path,local)
		if Run.current_room==source_room and along>handoff+GATE: return false
		if Run.current_room==destination_room and along<handoff-GATE: return false
	return true

func gated() -> bool:
	return game!=null and game.get("party")!=null and game.party.climbing()

func walking() -> bool:
	return is_instance_valid(active) and is_instance_valid(game.player) and not game.room.geometry.contains(Vector2(game.player.position.x,game.player.position.z),.1)

func advance() -> void:
	if not is_instance_valid(active) or not is_instance_valid(game.player): return
	var point:=Vector2(game.player.position.x,game.player.position.z)
	var local_point:=point-Vector2(active.position.x,active.position.z)
	var along:=CorridorPlan.project(active.path,local_point)
	if walking(): left_room=true
	if gated():
		# The party moves on together (Party.gather), never one player alone.
		coop_held=Run.current_room==source_room and along>=handoff-.05
	elif Run.current_room==source_room and along>handoff+.25:
		rebase(destination_room,destination_offset)
	elif Run.current_room==destination_room and along<handoff-.25:
		rebase(source_room,-destination_offset)
	if left_room and game.room.geometry.contains(Vector2(game.player.position.x,game.player.position.z),1.05):
		reset()
		if not gated(): game.activate_corridor_encounter()

func rebase(destination: String, offset: Vector2) -> void:
	FrameWatch.mark("room handoff")
	var shift:=Vector3(offset.x,0,offset.y)
	# All camera-relative positions stay identical during this atomic step.
	active.position-=shift
	active.reset_physics_interpolation()
	game.enter_corridor_room(destination,portal_id,shift)
	handoffs+=1
	preview=null
	hide_preview()
	stage_pending=true
