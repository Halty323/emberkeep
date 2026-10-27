extends SceneTree
## Structural regressions for the mobile lighting budget and settings lifecycle.
## Actual GL shader appearance and frame cost are checked by the render harness.
var checks = 0
var failures = 0
var stage: Node3D
var run: Node
var settings: Node

func _initialize() -> void:
	call_deferred("test_lighting")

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

func all_lights(node: Node) -> Array:
	return descendants(node).filter(func(child): return child is Light3D)

func shadowed_lights(node: Node) -> Array:
	return all_lights(node).filter(func(light): return light.shadow_enabled)

func verify_room_budget(room: Node3D, enabled: bool, label: String) -> void:
	var lights = all_lights(room)
	var shadowed = shadowed_lights(room)
	var omni = lights.filter(func(light): return light is OmniLight3D)
	var spots = lights.filter(func(light): return light is SpotLight3D)
	check(omni.size() == 4, label + ": four unshadowed lantern fill lights")
	check(spots.size() == 1, label + ": a single fixed key shadow for the room")
	check(shadowed.size() <= 1, label + ": at most one local shadow map")
	check((not shadowed.is_empty()) == enabled, label + ": requested shadow quality applied")
	for light in lights:
		check(light.light_cull_mask == 1, label + ": real lights exclude halo geometry")
		if light is OmniLight3D:
			check(not light.shadow_enabled, label + ": omni lights never allocate cube shadows")
	for light in shadowed:
		check(light is SpotLight3D, label + ": each lantern shadow uses a single spot map")
	for spot in spots:
		check(spot.visible == enabled, label + ": shadow spots match the quality setting")
	var halo_count = 0
	for node in descendants(room):
		if not node is MeshInstance3D or not node.material_override is ShaderMaterial:
			continue
		var shader_material: ShaderMaterial = node.material_override
		if shader_material.shader.resource_path != "res://shaders/halo.gdshader":
			continue
		halo_count += 1
		check(node.layers == 2, label + ": halo uses the unlit effects layer")
		check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			label + ": halo cannot cast a rectangular shadow")
	check(halo_count > 0, label + ": the room keeps its cozy glow effects")

func new_room(enabled: bool) -> Node3D:
	settings.set_value("shadows", enabled)
	# Resolve this gameplay script after project autoloads are registered. A
	# static DungeonRoom annotation in a SceneTree entry script loads it too soon.
	var room = load("res://scripts/world.gd").new()
	stage.add_child(room)
	room.build(stage, {"type": "start", "seed": 81}, true)
	return room

func test_lighting() -> void:
	run = root.get_node("Run")
	settings = root.get_node("Settings")
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	# Inspect immediately: disabled quality must not spend one frame rendering
	# costly shadows before a process callback catches up with the saved setting.
	var low = new_room(false)
	verify_room_budget(low, false, "startup low quality")
	low.queue_free()
	await process_frame
	var room = new_room(true)
	verify_room_budget(room, true, "startup high quality")
	var original_ids = all_lights(room).map(func(light): return light.get_instance_id())
	check(room.has_method("apply_lighting_quality"), "room exposes a cached quality transition")
	if room.has_method("apply_lighting_quality"):
		for enabled in [false, true, false, true]:
			var fill_energy = room.lamps.map(func(light): return light.light_energy)
			settings.set_value("shadows", enabled)
			room.call("apply_lighting_quality")
			verify_room_budget(room, enabled, "quality toggle")
			check(room.lamps.map(func(light): return light.light_energy) == fill_energy,
				"quality changes preserve the warm fill lighting")
			check(all_lights(room).map(func(light): return light.get_instance_id()) == original_ids,
				"quality changes reuse the room's existing lights")
		for frame in 120:
			room._process(1.0 / 60.0)
		check(all_lights(room).map(func(light): return light.get_instance_id()) == original_ids,
			"flicker updates do not rebuild lighting nodes")
	stage.queue_free()
	await process_frame
	print("EMBERKEEP LIGHTING TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
