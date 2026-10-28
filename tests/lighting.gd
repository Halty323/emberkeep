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
	await test_floor_light()
	print("EMBERKEEP LIGHTING TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

## The tower brightens floor by floor: a captive wakes in a near-dark cellar
## and climbs toward the light. Visual only; the floors play the same.
func test_floor_light() -> void:
	var Light = load("res://scripts/dungeon/floor_light.gd")
	var title: Dictionary = Light.profile(0)
	var floors = [Light.profile(1), Light.profile(2), Light.profile(3)]
	for key in ["ambient", "key", "lamp", "glow", "shadow"]:
		check(floors[0][key] < floors[1][key] and floors[1][key] < floors[2][key], "each floor up has more " + key)
		check(floors[0][key] < title[key], "the cellar is darker than the old baseline in " + key)
	check(floors[0].lit < floors[1].lit and floors[1].lit == 1.0 and floors[2].lit == 1.0, "dead lanterns belong to the cellar")
	check(floors[0].vignette > floors[1].vignette and floors[1].vignette > floors[2].vignette, "the edge of the view closes in lower down")
	check(floors[0].background.get_luminance() < floors[1].background.get_luminance() and floors[1].background.get_luminance() < floors[2].background.get_luminance(),
		"the void between rooms lightens as the tower rises")
	check(floors[0].foe_glow > floors[1].foe_glow and floors[0].foe_body > 0, "foes carry their own glow where it is darkest")
	for profile in floors:
		check(profile.ambient < .36 and profile.key < .45 and profile.lamp < 2.0, "every floor keeps the shadow contrast")
	# Which lanterns burn is the room's own, repeatable, and never all dark.
	var burning: Array = Light.lit_lanterns(4, floors[0], 81)
	check(burning.size() == 2 and burning == Light.lit_lanterns(4, floors[0], 81), "half the cellar's lanterns burn, the same ones every time")
	check(Light.lit_lanterns(1, floors[0], 81).size() == 1 and Light.lit_lanterns(8, floors[0], 5).size() == 4, "a cellar room always keeps a light")
	check(Light.lit_lanterns(4, floors[1], 81) == [0, 1, 2, 3], "from the halls up every lantern burns")
	# Rooms in a real run take their floor's light.
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	var environment: Environment = game.room_environment.environment
	check(is_equal_approx(environment.ambient_light_energy, title.ambient) and is_equal_approx(game.key_light.light_energy, title.key), "the title keeps its own light")
	game.start_run("candle", 61001, false)
	var anchors: int = run.rooms["0,0"].get("lights", []).size()
	var rng_state = run.rng.state
	for floor in [1, 2, 3]:
		var profile: Dictionary = floors[floor - 1]
		run.floor_number = floor
		run.current_room = "0,0"
		game.enter_room(Vector3(0, 0, 2))
		var room = game.room
		check(is_equal_approx(environment.ambient_light_energy, profile.ambient) and is_equal_approx(game.key_light.light_energy, profile.key)
			and environment.background_color == profile.background and is_equal_approx(game.vignette.get_shader_parameter("strength"), profile.vignette),
			"floor %d sets its own ambient, key, void and vignette" % floor)
		check(room.lantern_points.size() == Light.lit_lanterns(anchors, profile, int(run.rooms["0,0"].seed)).size(), "floor %d burns its share of lanterns" % floor)
		check(room.lamps.size() == mini(room.MAX_ACTIVE_FILLS, room.lantern_points.size())
			and room.lamps.all(func(lamp): return lamp.light_color == profile.lamp_color), "floor %d fills only from burning lanterns, in its colour" % floor)
		var spot: SpotLight3D = room.shadow_lamps[0]
		check(room.lantern_points.any(func(p): return (p + Vector3(0, 2.2, 0)).distance_to(spot.position) < .01) and is_equal_approx(spot.light_energy, profile.shadow),
			"floor %d's shadow lamp hangs on a burning lantern" % floor)
		var foe = game.spawn_enemy(Vector3(3, 0, 0), "mote")
		var body: MeshInstance3D = foe.visual.get_child(0)
		check((body.material_override.emission_enabled and is_equal_approx(body.material_override.emission_energy_multiplier, profile.foe_body)) == (profile.foe_body > 0),
			"floor %d foes glow only where it is dark" % floor)
		game.enemies.erase(foe)
		foe.free()
	check(anchors > 2 and run.rng.state == rng_state, "lighting floors never touches the gameplay random stream")
	game.return_to_title()
	check(is_equal_approx(environment.ambient_light_energy, title.ambient) and is_equal_approx(game.key_light.light_energy, title.key), "returning to the title restores its light")
	game.queue_free()
	await process_frame
