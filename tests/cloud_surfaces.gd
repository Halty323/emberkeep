extends SceneTree
## Cloud presentation must remain bounded without changing its timed gameplay.
class CloudFixture extends Node3D:
	var enemies: Array = []
	var player: Node3D

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("exercise")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func exercise() -> void:
	var fixture = CloudFixture.new()
	root.add_child(fixture)
	fixture.player = Node3D.new()
	fixture.add_child(fixture.player)
	var field = load("res://scripts/combat/residue.gd").new()
	fixture.add_child(field)
	var geometry = load("res://scripts/dungeon/room_geometry.gd").new([Vector2i.ZERO])
	field.setup(fixture, geometry)
	var initial_meshes = field.find_children("*", "MeshInstance3D", true, false).size()
	check(not field.cloud_view.visible, "an empty cloud field draws no mist")
	field.add_cloud(Vector3.ZERO, 2.0, "spores")
	var start_fields: PackedVector4Array = field.mist_material.get_shader_parameter("cloud_fields")
	check(is_zero_approx(start_fields[0].w), "a new cloud fades in instead of appearing as an opaque sheet")
	field.update_sim(.2)
	var live_fields: PackedVector4Array = field.mist_material.get_shader_parameter("cloud_fields")
	check(live_fields[0].w > .99, "mist reaches its intended density after the short fade")
	check(field.cloud_at(Vector3(1, 0, 0)) == 0 and field.slows(Vector3.ZERO) < 1.0,
		"the spore footprint and movement effect remain active")
	field.poison_cloud(0)
	var tints: PackedColorArray = field.mist_material.get_shader_parameter("cloud_tints")
	check(field.clouds[0].poisoned and tints[0].a <= .25,
		"poison changes the shared cloud while keeping its opacity bounded")
	for i in 7: field.add_cloud(Vector3(i * .2, 0, 0), 1.5, "steam")
	check(field.clouds.size() == field.MAX_CLOUDS, "new clouds replace the oldest at the existing cap")
	check(field.find_children("*", "MeshInstance3D", true, false).size() == initial_meshes,
		"clouds never allocate additional transparent meshes")
	check(field.cloud_view.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"mist never adds shadow casters")
	for cloud in field.clouds:
		check(cloud.view.get_child_count() == 0, "cloud records retain no overlapping sphere geometry")
		cloud.age = cloud.life - .05
	field.refresh_cloud_surface()
	var ending: PackedVector4Array = field.mist_material.get_shader_parameter("cloud_fields")
	check(ending[0].w < .05, "mist dissolves softly before its gameplay lifetime ends")
	field.update_sim(.1)
	check(field.clouds.is_empty() and not field.cloud_view.visible,
		"expired clouds remove their gameplay footprint and shared surface")
	check(field.LOOKS.ice[1] <= .06 and field.LOOKS.water[1] <= .03,
		"mobile ice and water retain only a faint emission floor")
	fixture.queue_free()
	await process_frame
	print("EMBERKEEP CLOUD SURFACES TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
