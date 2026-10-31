extends SceneTree
## The same saved, furnished rooms and camera poses on two source revisions.
## Render counts are a workload comparison; software GL is not phone FPS.
var game
var run
var output := ""
var reference := ""
var policy := "powervr"
var write_reference := false
var reports: Array = []
var failures := 0

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use tools/render_ps2_update.sh with a display.")
		quit(1)
		return
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("exercise")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error("FAIL: " + message)

func warm(count := 36) -> void:
	for frame in count: await RenderingServer.frame_post_draw

func cache_stats() -> Dictionary:
	if not FileAccess.file_exists("res://scripts/graphics/dungeon_style.gd"): return {}
	var style = load("res://scripts/graphics/dungeon_style.gd")
	return {"map_families": style.maps.size(), "materials": style.materials.size()}

func mesh_triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
		var arrays = mesh.surface_get_arrays(surface)
		if arrays.is_empty(): continue
		var indices = arrays[Mesh.ARRAY_INDEX]
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		count += (indices.size() if indices != null and indices.size() > 0 else vertices.size()) / 3
	return count

func scene_triangles() -> int:
	var count := 0
	for mesh in game.find_children("*", "MeshInstance3D", true, false):
		if mesh.is_visible_in_tree() and mesh.mesh: count += mesh_triangles(mesh.mesh)
	for batch in game.find_children("*", "MultiMeshInstance3D", true, false):
		if not batch.is_visible_in_tree() or not batch.multimesh or not batch.multimesh.mesh: continue
		var instances = batch.multimesh.visible_instance_count
		if instances < 0: instances = batch.multimesh.instance_count
		count += mesh_triangles(batch.multimesh.mesh) * instances
	return count

func load_scenario(name: String, warm_theme: bool) -> void:
	paused = false
	if write_reference:
		game.start_run("candle", 18523427, false)
		if warm_theme:
			run.floor_number = 3
			run.floor_plan[2] = "halls"
			run.floor_twists[2] = ""
			run.generate_floor()
		var chosen := ""
		var ids = run.rooms.keys()
		ids.sort()
		for id in ids:
			var room: Dictionary = run.rooms[id]
			if room.type == "combat" and room.cells.size() > 1:
				chosen = id
				break
		check(chosen != "", "seed has a furnished multi-cell combat room")
		if chosen == "": return
		run.current_room = chosen
		game.enter_room(Vector3(0, 0, 2))
		var file = FileAccess.open(reference.path_join(name + ".json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(run.snapshot()))
		file.close()
	else:
		var text = FileAccess.get_file_as_string(reference.path_join(name + ".json"))
		check(not text.is_empty(), "reference snapshot exists")
		var file = FileAccess.open(run.SAVE_PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		check(run.load_run(), "reference snapshot remains loadable")
		game.continue_run()
	game.paused = true
	game.ui.toast_time = 0
	game.ui.floor_title_start = -100
	game.player.invulnerability = 100
	game.set_physics_process(false)
	game.set_process(false)
	game.fps.yaw = -.4
	game.fps.pitch = -.05
	game.update_camera(.016, true)
	# The scene tree pauses scripted decoration as well as gameplay, leaving
	# only shader clocks animated. Both revisions receive identical poses.
	paused = true
	await warm()
	var initial = cache_stats()
	game.enter_room(Vector3(0, 0, 2))
	game.paused = true
	game.ui.toast_time = 0
	game.ui.floor_title_start = -100
	game.update_camera(.016, true)
	await warm()
	check(cache_stats() == initial, "re-entering the room does not grow the material cache")

func measure_pose(name: String, at: Vector3, yaw: float, pitch: float) -> void:
	game.player.place(at)
	game.fps.yaw = yaw
	game.fps.pitch = pitch
	game.update_camera(.016, true)
	await warm()
	var calls := 0.0
	var primitives := 0.0
	for frame in 12:
		await RenderingServer.frame_post_draw
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var picture = root.get_texture().get_image()
	var path = output.path_join(name + ".png")
	picture.save_png(path)
	var record = {
		"name": name, "policy": policy, "seed": run.seed_value, "room": run.current_room,
		"theme": run.theme_id(), "floor": run.floor_number, "cells": run.rooms[run.current_room].cells.size(),
		"pose": [at.x, at.y, at.z, yaw, pitch], "camera": [game.camera.position.x, game.camera.position.y, game.camera.position.z],
		"draw_calls": calls / 12.0, "rendered_primitives": primitives / 12.0,
		"scene_mesh_triangles": scene_triangles(),
		"texture_mem_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"props": game.room.props.size(), "enemies": game.enemies.size(), "cache": cache_stats(),
		"msaa_3d": root.msaa_3d, "viewport": [picture.get_width(), picture.get_height()], "image": path}
	reports.append(record)
	print("EMBERKEEP PS2 POSE " + JSON.stringify(record))

func exercise() -> void:
	output = OS.get_environment("EMBERKEEP_PS2_OUTPUT")
	reference = OS.get_environment("EMBERKEEP_PS2_REFERENCE")
	write_reference = OS.get_environment("EMBERKEEP_PS2_WRITE_REFERENCE") == "1"
	policy = OS.get_environment("EMBERKEEP_PS2_POLICY")
	var settings = root.get_node("Settings")
	settings.set_value("effects_detail", "high")
	settings.set_value("small_details", "high")
	settings.set_value("render_scale", 1.0)
	settings.set_value("fps_limit", 0)
	settings.set_value("vsync", false)
	settings.set_value("show_fps", false)
	settings.set_value("head_bob", false)
	settings.set_value("sound", false)
	settings.set_value("music", false)
	RenderPolicy.device_override = RenderPolicy.for_device("Android", "Imagination", "PowerVR", "gl_compatibility") if policy == "powervr" else RenderPolicy.for_device("Linux", "Mesa", "llvmpipe", "gl_compatibility")
	settings.apply_render_policy()
	run = root.get_node("Run")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for spec in [["seed-room", false], ["warm-halls", true]]:
		await load_scenario(spec[0], spec[1])
		var terrain = game.room.terrain
		var ground = Vector3(0, .03, 2.0)
		ground.y += game.room.floor_height(ground)
		await measure_pose(spec[0] + "-ground", ground, -.4, -.05)
		if terrain and terrain.ledge.has_area():
			var center: Vector2 = terrain.ledge.get_center()
			var raised = Vector3(center.x, 1.23, center.y)
			await measure_pose(spec[0] + "-gallery", raised, 2.8 if center.x < 0 else -2.8, -.13)
		else:
			await measure_pose(spec[0] + "-long-view", ground + Vector3(0, 0, 1.5), -.9, .08)
	var report = {"renderer": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info().string,
		"workload_only": true, "reference_written": write_reference, "failures": failures, "poses": reports}
	var file = FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("EMBERKEEP PS2 REPORT " + JSON.stringify(report))
	paused = false
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
