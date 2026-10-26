extends SceneTree
## Zoom, room visibility and contrast checks; no live player saves are used.
var checks = 0
var failures = 0
var game
var run

func _initialize() -> void:
	call_deferred("test_presentation")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func descendants(node: Node) -> Array:
	var result: Array = [node]
	for child in node.get_children():
		result.append_array(descendants(child))
	return result

func wall_meshes(room: Node3D, front: bool) -> Array:
	var result: Array = []
	for node in room.get_children():
		if not node is MeshInstance3D or not node.mesh is BoxMesh:
			continue
		var on_wall = is_equal_approx(absf(node.position.x), 9.2) or is_equal_approx(absf(node.position.z), 7.2)
		if not on_wall or node.mesh.size.y < .5:
			continue
		var is_front = is_equal_approx(node.position.x, 9.2) or is_equal_approx(node.position.z, 7.2)
		if is_front == front:
			result.append(node)
	return result

func player_in_frame(label: String) -> void:
	var view = game.get_viewport().get_visible_rect()
	for height in [.12, 1.25]:
		var world_point: Vector3 = game.player.global_position + Vector3.UP * height
		var point: Vector2 = game.camera.unproject_position(world_point)
		check(not game.camera.is_position_behind(world_point), label + ": player remains in front of camera")
		check(view.grow(-24).has_point(point), label + ": player feet/head remain inside the viewport")

func test_presentation() -> void:
	run = root.get_node("Run")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	var camera_basis: Basis = game.camera.basis
	check(is_equal_approx(game.camera.size, 18.8), "title keeps the wider room overview")
	var menu_height = game.camera.unproject_position(Vector3.UP).distance_to(game.camera.unproject_position(Vector3.ZERO))
	game.start_run("candle", 140032, false)
	game.paused = true
	check(game.camera.size < 18.8 / 1.2, "gameplay is over twenty percent larger than the old framing")
	var game_height = game.camera.unproject_position(Vector3.UP).distance_to(game.camera.unproject_position(Vector3.ZERO))
	check(game_height > menu_height * 1.2, "world objects actually project larger on screen")
	check(game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "closer camera preserves the isometric projection")
	check(game.has_method("update_camera"), "camera exposes a room-transition snap and smooth follow")
	if not game.has_method("update_camera"):
		game.queue_free()
		await process_frame
		quit(1)
		return
	# A zoomed view must continue to show the player at every doorway and corner.
	var points = [Vector3.ZERO, Vector3(-8.4, 0, 0), Vector3(8.4, 0, 0), Vector3(0, 0, -6.4), Vector3(0, 0, 6.4),
		Vector3(-8.7, 0, -6.7), Vector3(-8.7, 0, 6.7), Vector3(8.7, 0, -6.7), Vector3(8.7, 0, 6.7)]
	for point in points:
		game.player.position = point
		game.update_camera(0, true)
		check(absf(game.camera_focus.x) <= 3.601 and absf(game.camera_focus.z) <= 2.801,
			"camera follow stays bounded within the room")
		check(game.camera.basis.is_equal_approx(camera_basis), "camera snap preserves the fixed movement-axis basis")
		player_in_frame(str(point))
	game.player.position = Vector3.ZERO
	game.update_camera(0, true)
	var origin: Vector3 = game.camera_focus
	game.player.position = Vector3(6, 0, 4)
	game.update_camera(1.0 / 60.0)
	check(game.camera_focus.distance_to(origin) > .001, "camera begins following player movement")
	check(game.camera_focus.distance_to(origin) < Vector3(2.7, 0, 1.8).length(), "camera movement eases instead of snapping during play")
	for frame in 120:
		game.update_camera(1.0 / 60.0)
	check(absf(game.camera_focus.x) <= 3.601 and absf(game.camera_focus.z) <= 2.801,
		"camera follow never overshoots the room clamp")
	check(game.camera.basis.is_equal_approx(camera_basis), "smooth follow preserves the fixed movement-axis basis")
	game.enter_room(Vector3(-7.3, 0, 0))
	check(game.camera_focus.x < -1, "room entry immediately reframes the doorway spawn")
	check(game.camera.basis.is_equal_approx(camera_basis), "room transition preserves the fixed movement-axis basis")
	player_in_frame("room entry")
	# Geometry, rather than camera perspective alone, makes the walls taller.
	var rear = wall_meshes(game.room, false)
	var front = wall_meshes(game.room, true)
	check(rear.size() >= 4 and front.size() >= 4, "both rear and foreground wall segments are present")
	for mesh in rear:
		check(mesh.mesh.size.y > 1.7, "rear walls are taller than the former 1.7 units")
	for mesh in front:
		check(mesh.mesh.size.y > .48, "foreground walls are taller than the former half-unit cutaway")
	# Cutaways reveal nearby actors while leaving the collision and opaque
	# full-height shadow occluder intact. Far-side walls must not fade with them.
	check(game.room.has_method("update_wall_visibility"), "foreground walls expose an actor-visibility cutaway")
	if game.room.has_method("update_wall_visibility"):
		var original_colliders: Array = []
		for entry in game.room.front_walls:
			original_colliders.append(entry.collider.transform)
		for focus in [Vector3.ZERO, Vector3(8.4, 0, 0), Vector3(0, 0, 6.4), Vector3.ZERO]:
			game.room.update_wall_visibility(focus, 0, [])
			for index in game.room.front_walls.size():
				var entry: Dictionary = game.room.front_walls[index]
				var should_lower = (entry.side.x > 0 and focus.x > 6.0) or (entry.side.y > 0 and focus.z > 4.0)
				var visible_height: float = entry.body.mesh.size.y * entry.body.scale.y
				check(is_equal_approx(visible_height, .45 if should_lower else 1.8),
					"foreground cutaway follows the nearby side and restores full height")
				check(entry.collider.transform == original_colliders[index], "cutaway never moves the collision wall")
				check(entry.shadow_caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
					"foreground wall keeps an invisible real shadow caster")
				check(is_equal_approx(entry.shadow_caster.mesh.size.y * entry.shadow_caster.scale.y, 1.8),
					"foreground shadow occluder remains full height")
			for mesh in rear:
				check(is_equal_approx(mesh.material_override.albedo_color.a, 1.0), "rear walls remain opaque during foreground cutaways")
		game.room.update_wall_visibility(Vector3.ZERO, 0, [Vector3(8.4, 0, 0)])
		for entry in game.room.front_walls:
			if entry.side.x > 0:
				check(is_equal_approx(entry.body.mesh.size.y * entry.body.scale.y, .45),
					"nearby enemies can also reveal a foreground cutaway")
		game.room.update_wall_visibility(Vector3.ZERO, 0, [])
	for node in game.room.get_children():
		if not node is StaticBody3D: continue
		var horizontal = is_equal_approx(absf(node.position.z), 7.2)
		var vertical = is_equal_approx(absf(node.position.x), 9.2)
		if not horizontal and not vertical: continue
		var shape: BoxShape3D = node.get_child(0).shape
		check(is_equal_approx(shape.size.z if horizontal else shape.size.x, .45), "wall collision thickness stays unchanged")
		check(is_equal_approx(shape.size.x if horizontal else shape.size.z, 7.8 if horizontal else 5.8),
			"taller walls keep the doorway gap clear")
	# Real-time illumination remains dimmer while meaningful geometry casts shadows.
	var environment_nodes = game.get_children().filter(func(node): return node is WorldEnvironment)
	check(environment_nodes.size() == 1, "world keeps a single environment")
	var environment: Environment = environment_nodes[0].environment
	check(environment.ambient_light_energy > 0 and environment.ambient_light_energy < .36,
		"ambient light is dimmed while retaining a readable baseline")
	var directional = game.get_children().filter(func(node): return node is DirectionalLight3D)
	check(directional.size() == 1 and directional[0].shadow_enabled, "one directional key casts room and actor shadows")
	check(directional[0].light_energy < .45, "directional fill is dimmer than the previous wash")
	for light in game.room.lamps:
		check(light.light_energy < 2.0, "warm lantern fill is dimmer")
		check(not light.shadow_enabled, "dim fill lights cannot restore expensive cube shadows")
	check(game.room.shadow_lamps.size() == 1, "stronger contrast preserves the single local shadow budget")
	check(game.room.shadow_lamps[0].shadow_opacity >= .95, "the warm key produces full-contrast occlusion")
	for mesh in rear:
		check(mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "tall rear wall remains a shadow caster")
	game.return_to_title()
	check(is_equal_approx(game.camera.size, 18.8), "returning to title restores its overview zoom")
	check(game.camera_focus.length() < .001, "title does not inherit the last room's follow offset")
	check(game.camera.basis.is_equal_approx(camera_basis), "title reset preserves the original isometric basis")
	game.queue_free()
	await process_frame
	await process_frame
	print("EMBERKEEP PRESENTATION TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
