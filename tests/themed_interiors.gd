extends SceneTree
var checks := 0
var failures := 0
var game
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("exercise")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)
func settle() -> void:
	for i in 2: await process_frame
func exercise() -> void:
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	var content = root.get_node("Content")
	var interiors = load("res://scripts/dungeon/themed_interiors.gd")
	var geometry = load("res://scripts/dungeon/room_geometry.gd")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	settings.set_value("small_details", "high")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.set_process(false)
	var seen := {}
	var room_count := 0
	for theme in content.families.floors:
		for seed_value in [18523427, 64217, 81031, 52043, 79011, 31691]:
			game.start_run("candle", seed_value, false)
			run.floor_plan = [theme.id, theme.id, theme.id, theme.id, theme.id]
			run.floor_twists = ["", "", "", "", ""]
			run.floor_number = 3
			run.generate_floor()
			for id in run.rooms:
				if run.rooms[id].type != "combat" or run.rooms[id].cells.size() < 2: continue
				run.current_room = id
				break
			game.enter_room(Vector3(0,0,2))
			game.paused = true
			await settle()
			room_count += 1
			var room = game.room
			var report: Dictionary = room.interiors_report
			check(report.theme == theme.id, "correct interior identity: " + theme.id)
			check(report.pieces > 0 and report.walls.size() + report.tops.size() > 0, "recognizable theme scene exists: " + theme.id)
			check(report.batches <= 4 and report.vertices <= interiors.MAX_VERTICES[2], "merged geometry stays inside budgets")
			seen[theme.id] = true
			var before = JSON.stringify(run.rooms[run.current_room])
			var state: int = run.rng.state
			var a: Dictionary = interiors.plan(room, theme.id, 2)
			var b: Dictionary = interiors.plan(room, theme.id, 2)
			check(JSON.stringify(a) == JSON.stringify(b), "seeded interior plan is repeatable")
			check(run.rng.state == state and JSON.stringify(run.rooms[run.current_room]) == before, "interior planning leaves gameplay state and RNG untouched")
			for anchor in a.walls:
				check(not room.geometry.contains(anchor.at, .34), "wall displays stay outside player-centre clearance")
				var ribs = room.get_node_or_null("VaultRibs")
				if ribs:
					var obstructed = false
					for index in ribs.multimesh.instance_count:
						var transform: Transform3D = ribs.multimesh.get_instance_transform(index)
						if transform.basis.y.length() > 4.0 and Vector2(transform.origin.x,transform.origin.z).distance_to(anchor.at) < 1.55: obstructed = true
					check(not obstructed, "architectural pilasters leave the story niche visible")
				for socket in room.sockets.values():
					check(anchor.at.distance_to(geometry.socket_point(socket.cell,socket.dir)) > 1.32, "wall display clears portal")
			for anchor in a.scatter:
				check(interiors.scatter_clear(room, Vector2(anchor.at.x,anchor.at.z)), "low scatter keeps doors, chests, galleries and viewing spots clear")
			for anchor in a.tops:
				check(room.props.has(anchor.id), "clutter stands on an existing prop")
				var definition: Dictionary = room.props[anchor.id].definition
				check(absf(anchor.at.y - float(room.props[anchor.id].record.get("height", 0)) - float(definition.height) - .025) < .001, "clutter uses the existing surface height")
				check(not definition.has("breakable") and not room.props[anchor.id].record.get("destroyed",false), "permanent clutter never floats after a container breaks")
			# Re-decorating a disposable container proves the builder adds only
			# mesh surfaces; collision, light and navigation budgets stay fixed.
			var collider_count = room.find_children("*", "CollisionObject3D", true, false).size()
			var light_count = room.find_children("*", "Light3D", true, false).size()
			var holder = Node3D.new()
			room.add_child(holder)
			var builder = interiors.new()
			builder.report = {"theme": theme.id}
			builder.wall_scene(theme.id,Transform3D.IDENTITY,1)
			builder.finish(holder)
			check(room.find_children("*", "CollisionObject3D", true, false).size() == collider_count and room.find_children("*", "Light3D", true, false).size() == light_count, "story geometry adds no collision or lights")
			holder.queue_free()
	# Every low decoration can be stepped over and never becomes head-height
	# geometry in an otherwise empty combat lane.
	for theme in interiors.THEMES:
		var builder = interiors.new()
		builder.floor_scene(theme,Transform3D.IDENTITY,1)
		for tool in builder.groups.values():
			var mesh: ArrayMesh = tool.commit()
			check(mesh.get_aabb().end.y <= .12, "floor scatter stays below ankle height: " + theme)
	# Exhausted budgets omit a whole vignette, not some of its triangles.
	for theme in interiors.THEMES:
		var probe = interiors.new()
		probe.limit = 1
		var accepted: bool = probe.try_scene(func(): probe.wall_scene(theme,Transform3D.IDENTITY,1))
		check(not accepted and probe.vertex_count == 0 and probe.groups.is_empty(), "tiny budget skips a complete wall vignette: " + theme)
		var complete = interiors.new()
		complete.limit = interiors.MAX_VERTICES[0]
		check(complete.try_scene(func(): complete.wall_scene(theme,Transform3D.IDENTITY,1)), "each complete theme vignette fits the lowest room budget")
		var vertices: int = complete.vertex_count
		complete.limit = vertices
		check(not complete.try_scene(func(): complete.wall_scene(theme,Transform3D.IDENTITY,1)) and complete.vertex_count == vertices, "full budget preserves already complete scene: " + theme)
	for detail in 3:
		var a: Dictionary = interiors.plan(game.room, run.theme_id(), detail)
		check(a.walls.size() <= 4 and a.tops.size() <= (8 if game.room.terrain and game.room.terrain.loft else 4) and a.scatter.size() <= 12, "all quality levels cap cosmetic placements")
	check(seen.size() == 8, "all eight floor themes receive authored interior scenes")
	check(interiors.primitive_arrays.size() <= 4 and interiors.finishes.size() <= 4, "primitive and finish caches stay bounded")
	game.queue_free()
	await settle()
	print("THEMED INTERIORS: %d checks, %d failures; %d furnished seeded rooms / %d themes" % [checks,failures,room_count,seen.size()])
	quit(0 if failures==0 else 1)
