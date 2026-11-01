class_name RoomPartitions
extends RefCounted
## Resolved, seeded masonry plans. Walls are serialized with the room, kept
## clear of its required destinations, and tested as real navigation blockers.
## Furniture is then dressed around these walls, not scattered through them.
const CLEARANCE := .7
const STEP := 1.0
const MAX_WALLS := 8

static func rect(record: Dictionary) -> Rect2:
	var size := Vector2(float(record.size[0]),float(record.size[1]))
	var at := Vector2(float(record.position[0]),float(record.position[1]))
	return Rect2(at-size/2.0,size)

static func plan(room: Dictionary, geometry: RoomGeometry, zones: Array, props: Array) -> Array:
	if int(room.get("generation",2)) < 3 or room.type in ["boss","secret"]: return []
	var rng := RandomNumberGenerator.new()
	rng.seed = Content.stable_hash("partition-plan:%d:%s" % [int(room.seed),str(room.id)])
	var records: Array = []
	var blockers: Array[Rect2] = []
	for prop in props: blockers.append(Furnisher.record_rect(prop))
	var cells: Array = geometry.cells.duplicate()
	for i in range(cells.size()-1,0,-1):
		var j := rng.randi_range(0,i)
		var swap = cells[i];cells[i]=cells[j];cells[j]=swap
	for cell in cells:
		if records.size() >= mini(MAX_WALLS,2+geometry.cells.size()*2): break
		var center := RoomGeometry.cell_center(cell)
		var patterns := [
			[Rect2(-4.6,-2.9,.48,5.8),Rect2(4.12,-2.9,.48,5.8)],
			[Rect2(-5.5,-3.8,4.2,.48),Rect2(-5.5,-3.8,.48,4.1)],
			[Rect2(1.4,3.32,4.0,.48),Rect2(4.92,-.3,.48,4.1)],
			[Rect2(-3.5,-4.65,7.0,.48)],
			[Rect2(-5.4,.8,4.2,.48),Rect2(1.2,-1.28,4.2,.48)]
		]
		var first := rng.randi_range(0,patterns.size()-1)
		for attempt in patterns.size():
			if records.size() >= mini(MAX_WALLS,2+geometry.cells.size()*2): break
			var group: Array = patterns[(first+attempt)%patterns.size()]
			var candidate: Array[Rect2] = []
			var valid := true
			for base in group:
				var area: Rect2 = Rect2(base.position+center,base.size)
				if not Furnisher.rect_inside(geometry,area.grow(1.1),.25) or Furnisher.hits_zone(area,zones,true,.7): valid=false;break
				if blockers.any(func(other): return other.grow(1.0).intersects(area)): valid=false;break
				candidate.append(area)
			if not valid or records.size()+candidate.size()>MAX_WALLS: continue
			var all: Array[Rect2] = blockers.duplicate()
			all.append_array(candidate)
			if not connected(geometry,all): continue
			for area in candidate:
				if records.size() >= MAX_WALLS: break
				var at := area.get_center()
				records.append({"id":"%s:w%d" % [room.id,records.size()],"position":FloorGenerator.point_array(at),
					"size":[area.size.x,area.size.y],"height":3.25 if (int(room.seed)+records.size())%3 else 3.75})
				blockers.append(area)
			break
	return records

## Every sampled patch of floor must remain in the same component for an
## actor wider than the player. This rejects little sealed-off alcoves too.
static func connected(geometry: RoomGeometry, blockers: Array[Rect2]) -> bool:
	var bounds := geometry.bounds()
	var width := ceili(bounds.size.x/STEP)
	var height := ceili(bounds.size.y/STEP)
	var mask := PackedByteArray();mask.resize(width*height)
	var total := 0
	var start := -1
	for y in height:
		for x in width:
			var point := bounds.position+Vector2(x+.5,y+.5)*STEP
			if not geometry.contains(point,CLEARANCE): continue
			if blockers.any(func(area): return area.grow(CLEARANCE).has_point(point)): continue
			var index := y*width+x
			mask[index]=1;total+=1;start=index
	if start < 0: return false
	var queue := PackedInt32Array([start]);mask[start]=2
	var count := 0
	while count < queue.size():
		var index := queue[count];count+=1
		var x := index%width
		for next in [index-width,index+width,index-1 if x>0 else -1,index+1 if x<width-1 else -1]:
			if next>=0 and next<mask.size() and mask[next]==1:
				mask[next]=2;queue.append(next)
	return count==total

static func build(room) -> void:
	for record in room.data.get("partitions",[]):
		if not valid_record(record,room.geometry): continue
		var area := rect(record)
		var at := area.get_center()
		var height := float(record.height)
		var node := Node3D.new();node.name="MasonryPartition";room.add_child(node)
		var body = Geo.box(node,Vector3(at.x,height/2,at.y),Vector3(area.size.x,height,area.size.y),Color("635e50"))
		body.material_override=DungeonStyle.wall_material(Color(room.look.get("wall","635e50")),false,Run.theme_id())
		var cap = Geo.box(node,Vector3(at.x,height+.045,at.y),Vector3(area.size.x+.1,.09,area.size.y+.1),Color("8b806b"))
		cap.material_override=DungeonStyle.wall_material(Color("8b806b"),true,Run.theme_id())
		Geo.collider(node,Vector3(at.x,height/2,at.y),Vector3(area.size.x,height,area.size.y))
		room.obstacles.append({"id":record.id,"position":Vector3(at.x,0,at.y),"radius":maxf(area.size.x,area.size.y)/2,
			"rect":area})

static func valid_record(record: Variant, geometry: RoomGeometry) -> bool:
	if not record is Dictionary or not record.has_all(["id","position","size","height"]): return false
	if not record.position is Array or not record.size is Array or record.position.size()!=2 or record.size.size()!=2: return false
	for number in record.position+record.size+[record.height]:
		if not (number is int or number is float) or not is_finite(float(number)): return false
	var area := rect(record)
	return area.size.x>=.3 and area.size.y>=.3 and area.size.x<=9 and area.size.y<=9 and float(record.height)>=1.5 and float(record.height)<=4.5 and Furnisher.rect_inside(geometry,area,.2)
