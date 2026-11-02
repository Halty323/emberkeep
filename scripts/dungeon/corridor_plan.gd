class_name CorridorPlan
extends RefCounted
## One reversible physical connector per logical portal. Two solid elbows
## hide the room-streaming seam. Paths are saved with the existing portal
## record and use their own deterministic choices, never encounter RNG.
const VERSION := 1
const WIDTH := 2.6
const LEAD := 3.6
# Deep enough to hide both complete apertures from the streaming band;
# short enough that two exits 14m apart retain separate solid walls.
const OFFSET := 5.5
const MIDDLE := 3.6

static func ensure(portal: Dictionary, rooms: Dictionary) -> Dictionary:
	var saved = portal.get("corridor",{})
	if valid(saved): return saved
	var a: Dictionary = rooms[portal.a.room]
	var b: Dictionary = rooms[portal.b.room]
	var ga := RoomGeometry.new(FloorGenerator.room_cells(a).map(func(cell): return cell-FloorGenerator.vec(a.anchor)))
	var gb := RoomGeometry.new(FloorGenerator.room_cells(b).map(func(cell): return cell-FloorGenerator.vec(b.anchor)))
	var normal := Vector2(FloorGenerator.vec(portal.a.dir))
	var tangent := Vector2(-normal.y,normal.x)
	if Content.stable_hash("corridor:%s:%s" % [str(a.seed),str(portal.id)])%2==1: tangent=-tangent
	var pa := RoomGeometry.socket_point(FloorGenerator.vec(portal.a.cell)-FloorGenerator.vec(a.anchor),FloorGenerator.vec(portal.a.dir))
	var pb := RoomGeometry.socket_point(FloorGenerator.vec(portal.b.cell)-FloorGenerator.vec(b.anchor),FloorGenerator.vec(portal.b.dir))
	var reach_a := LEAD+maxf(0,extent(ga.bounds(),normal)-pa.dot(normal))
	var reach_b := LEAD+maxf(0,extent(gb.bounds(),-normal)+pb.dot(normal))
	var end := pa+normal*(reach_a+reach_b+MIDDLE)
	var shift := end-pb
	var path: Array[Vector2] = [pa,pa+normal*reach_a,pa+normal*reach_a+tangent*OFFSET,
		end-normal*reach_b+tangent*OFFSET,end-normal*reach_b,end]
	var middle := distance(path,0,2)+MIDDLE*.5
	portal["corridor"]={"version":VERSION,"path":path.map(FloorGenerator.point_array),
		"offset_b":FloorGenerator.point_array(shift),"handoff":middle,"length":distance(path,0,path.size()-1)}
	return portal.corridor

static func valid(value) -> bool:
	if not value is Dictionary or value.get("version",0)!=VERSION: return false
	var path=value.get("path",[])
	if not path is Array or path.size()!=6 or not valid_point(value.get("offset_b")): return false
	for point in path:
		if not valid_point(point): return false
	for key in ["handoff","length"]:
		var number=value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)): return false
	var decoded:=points(value)
	for i in 5:
		var delta: Vector2=decoded[i+1]-decoded[i]
		if delta.length()<.5 or (absf(delta.x)>.001 and absf(delta.y)>.001): return false
	var total:=distance(decoded,0,5)
	var middle:=distance(decoded,0,2)+decoded[2].distance_to(decoded[3])*.5
	return total<256 and absf(total-float(value.length))<.02 and absf(middle-float(value.handoff))<.02

static func valid_point(value) -> bool:
	return value is Array and value.size()==2 and value.all(func(n): return (n is int or n is float) and is_finite(float(n)) and absf(float(n))<1024)

static func extent(rect: Rect2, direction: Vector2) -> float:
	return maxf(maxf(rect.position.dot(direction),rect.end.dot(direction)),maxf(Vector2(rect.position.x,rect.end.y).dot(direction),Vector2(rect.end.x,rect.position.y).dot(direction)))

static func points(plan: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	for value in plan.path: result.append(FloorGenerator.vec2(value))
	return result

static func from_room(plan: Dictionary, portal: Dictionary, room_id: String) -> Array[Vector2]:
	var result := points(plan)
	if portal.b.room==room_id:
		result.reverse()
		var offset := FloorGenerator.vec2(plan.offset_b)
		for i in result.size(): result[i]-=offset
	return result

static func distance(path: Array[Vector2], start: int, finish: int) -> float:
	var result := 0.0
	for i in range(start,finish): result+=path[i].distance_to(path[i+1])
	return result

static func sample(path: Array[Vector2], along: float) -> Dictionary:
	for i in path.size()-1:
		var length := path[i].distance_to(path[i+1])
		if along<=length or i==path.size()-2:
			return {"at":path[i].lerp(path[i+1],clampf(along/maxf(.001,length),0,1)),"direction":(path[i+1]-path[i]).normalized()}
		along-=length
	return {"at":path.back(),"direction":Vector2.RIGHT}

static func project(path: Array[Vector2], at: Vector2) -> float:
	var walked := 0.0
	var best := INF
	var result := 0.0
	for i in path.size()-1:
		var delta := path[i+1]-path[i]
		var t := clampf((at-path[i]).dot(delta)/maxf(.001,delta.length_squared()),0,1)
		var separation := at.distance_squared_to(path[i]+delta*t)
		if separation<best:
			best=separation
			result=walked+delta.length()*t
		walked+=delta.length()
	return result

static func strips(path: Array[Vector2]) -> Array[Rect2]:
	var result: Array[Rect2]=[]
	var half := WIDTH*.5
	for i in path.size()-1:
		var a := path[i]
		var b := path[i+1]
		var low := Vector2(minf(a.x,b.x),minf(a.y,b.y))
		var size := (b-a).abs()
		if size.x>.01: result.append(Rect2(low-Vector2(0,half),Vector2(size.x,WIDTH)))
		else: result.append(Rect2(low-Vector2(half,0),Vector2(WIDTH,size.y)))
	for i in range(1,path.size()-1): result.append(Rect2(path[i]-Vector2.ONE*half,Vector2.ONE*WIDTH))
	return result
