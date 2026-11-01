extends SceneTree
## Opt-in eye-level material/lighting captures on real generated geometry.
## Run with a display, disposable XDG storage and EMBERKEEP_LIGHT_CAPTURE.
var game
var run
var output := ""
var measurements: Array = []

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("capture")

func capture() -> void:
	output = OS.get_environment("EMBERKEEP_LIGHT_CAPTURE")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Set EMBERKEEP_LIGHT_CAPTURE and run with an OpenGL display")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	settings.set_value("small_details", "high")
	settings.set_value("effects_detail", "high")
	if OS.get_environment("EMBERKEEP_LIGHT_CAPTURE_POLICY") != "desktop":
		RenderPolicy.device_override = RenderPolicy.for_device("Android", "Imagination", "PowerVR", "gl_compatibility")
	settings.apply_render_policy()
	run = root.get_node("Run")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	for fixture in [
		{"name":"cellar-entry", "theme":"cellar", "depth":1, "shape":"single"},
		{"name":"cistern-bend", "theme":"cistern", "depth":3, "shape":"bend", "seed":64217},
		{"name":"halls-interior", "theme":"halls", "depth":3, "shape":"wide"},
		{"name":"kiln-workshop", "theme":"kiln", "depth":3, "shape":"wide"}
	]:
		if not await compose(fixture):
			game.queue_free()
			await process_frame
			quit(1)
			return
	var file := FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(measurements, "  "))
	game.queue_free()
	await process_frame
	print("LIGHT/MATERIAL CAPTURES: ", measurements.size(), " collision-clear eye-level scenes; policy=", RenderPolicy.current().reason)
	quit()

func compose(fixture: Dictionary) -> bool:
	game.start_run("candle", int(fixture.get("seed",18523427)), false)
	run.floor_plan = [fixture.theme,fixture.theme,fixture.theme,fixture.theme,fixture.theme]
	run.floor_twists = ["","","","",""]
	run.floor_number = fixture.depth
	run.generate_floor()
	var selected := false
	for id in run.rooms:
		var record: Dictionary = run.rooms[id]
		if record.type != "combat": continue
		var cells: int = record.cells.size()
		if fixture.shape == "single" and cells != 1: continue
		if fixture.shape == "bend" and cells != 3: continue
		if fixture.shape in ["gallery","wide"] and cells < 2: continue
		run.current_room = id
		game.enter_room(Vector3(0,0,2))
		if fixture.shape == "gallery" and not game.room.terrain.ledge.has_area(): continue
		selected = true
		break
	if not selected:
		push_error("No generated capture room matches " + fixture.name)
		return false
	game.paused = true
	for actor in game.enemies: actor.queue_free()
	game.enemies.clear()
	game.room.set_open(true)
	game.ui.toast_time = 0
	game.ui.floor_title_start = -100
	await process_frame
	await physics_frame
	var room = game.room
	var target: Vector3
	var preferred: Vector2
	if fixture.shape == "gallery":
		target = Vector3(room.terrain.ledge.get_center().x, 1.8, room.terrain.ledge.get_center().y)
		preferred = Vector2(room.terrain.ramp.get_center().x + 1.5, room.terrain.ramp.end.y + 3.0)
	else:
		var center: Vector2 = room.geometry.center()
		var first: Vector2 = room.geometry.cell_center(room.geometry.cells[0])
		target = Vector3(center.x, 1.25, center.y - 3.5)
		preferred = first + Vector2(4.5,4.2)
	var position = find_viewpoint(preferred, target)
	if position == null:
		push_error("No collision-clear viewpoint for " + fixture.name)
		return false
	var at: Vector3 = position
	game.player.place(at)
	game.player.velocity = Vector3.ZERO
	game.player.push = Vector3.ZERO
	game.player.invulnerability = 100
	var direction: Vector3 = (target - (at + Vector3.UP * game.fps.EYE)).normalized()
	game.fps.yaw = atan2(-direction.x,-direction.z)
	game.fps.pitch = asin(direction.y)
	game.update_camera(.016)
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(fixture.name + ".png"))
	var report := {"scene": fixture.name, "theme": fixture.theme, "depth":fixture.depth,
		"room": run.current_room, "seed":run.seed_value, "cells": room.geometry.cells.size(),
		"eye": [game.camera.global_position.x,game.camera.global_position.y,game.camera.global_position.z],
		"standing_capsule_clear": capsule_clear(at), "camera_projection": game.camera.projection,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,
		"texture_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0}
	measurements.append(report)
	print("LIGHT/MATERIAL CAPTURE: ", JSON.stringify(report))
	return report.standing_capsule_clear

func find_viewpoint(preferred: Vector2, target: Vector3) -> Variant:
	var candidates: Array[Vector2] = [preferred]
	for radius in [1.0,2.0,3.0,4.0]:
		for direction in 12: candidates.append(preferred + Vector2.RIGHT.rotated(TAU * direction/12) * radius)
	for point in candidates:
		if not game.room.geometry.contains(point,.6) or game.room.blocked_at(point): continue
		var at := Vector3(point.x,0,point.y)
		at.y = game.room.floor_height(at) + .03
		if capsule_clear(at) and near_sightline_clear(at, target): return at
	return null

func capsule_clear(at: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = .36
	shape.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * .85)
	query.collision_mask = 1 | PropVisuals.FURNITURE_LAYER
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

# A physically valid spot can still put a pillar across most of the picture.
# Reserve the first few metres of the focal sightline for overview captures.
func near_sightline_clear(at: Vector3, target: Vector3) -> bool:
	var eye: Vector3 = at + Vector3.UP * game.fps.EYE
	var direction := (target-eye).normalized()
	var end := eye + direction * minf(3.2, eye.distance_to(target)-.1)
	var ray := PhysicsRayQueryParameters3D.create(eye,end,1 | PropVisuals.FURNITURE_LAYER,[game.player.get_rid()])
	return game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
