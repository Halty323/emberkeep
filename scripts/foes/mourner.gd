extends DungeonEnemy
## A mourner from the crypt. It drifts straight through walls and furniture,
## and it becomes solid enough to strike only inside light: the player's glow
## or a burning lantern's pool. Outside light its faint shape remains visible.
## Its touch takes a heart and the kindle's warmth.
var touch_cooldown = 0.0
var ghost_skins: Array = []

func stats() -> Array:
	return [28, 1.35, .42, "c9c0d8"]

func eye_height() -> float:
	return .95

func build_body(light: Dictionary) -> void:
	var body = Geo.cylinder(visual, Vector3(0, .62, 0), .4, 1.1, color, maxf(light.foe_body, .25), .22)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Geo.sphere(visual, Vector3(0, 1.22, 0), .26, color.lightened(.2), maxf(light.foe_body, .3))

func prepare() -> void:
	# Nothing solid stops it.
	collision_mask = 0
	contact_damage = false
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.get_parent() == eyes: continue
		var solid: StandardMaterial3D = mesh.material_override
		var ghost: StandardMaterial3D = solid.duplicate()
		ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost.albedo_color.a = .45
		ghost.emission_energy_multiplier = minf(solid.emission_energy_multiplier, .08)
		ghost_skins.append({"mesh": mesh, "solid": solid, "ghost": ghost})

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	touch_cooldown = maxf(0, touch_cooldown - delta)
	visual.position.y = .1 + sin(age * 2.0) * .08
	if targetable and distance < radius + .5 and touch_cooldown <= 0:
		touch_cooldown = 1.2
		game.player.hurt(1.0, global_position)
		game.kindle_heat = 0.0
	return direction

func footing_drag() -> float:
	return 1.0

## Light makes it corporeal. The ghost stays readable even when untargetable.
func update_light_state() -> void:
	var lit: bool = game.room.lit_at(global_position) or global_position.distance_to(game.player.global_position) <= game.player_light_radius()
	exposed = game.room.lit_at(global_position)
	targetable = lit
	set_shrouded(not lit)

func set_shrouded(value: bool) -> void:
	if value == shrouded: return
	shrouded = value
	for entry in ghost_skins:
		entry.mesh.material_override = entry.ghost if value else entry.solid
		entry.mesh.set_instance_shader_parameter("rim_strength", .04 if value else .16)
