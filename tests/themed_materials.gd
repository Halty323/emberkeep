extends SceneTree
## Verify the materials bound to actual rooms, not unused source sheets.
var checks:=0
var failures:=0
var game
var reports: Array=[]
var output:=""
var Style
var PBR
var Policy

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")

func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1;push_error("FAIL: "+label)

func sheet(material: Material) -> String:
	return material.get_shader_parameter("paint").resource_path if material is ShaderMaterial else material.albedo_texture.resource_path

func exercise() -> void:
	Style=load("res://scripts/graphics/dungeon_style.gd")
	PBR=load("res://scripts/graphics/pbr_materials.gd")
	Policy=load("res://scripts/graphics/render_policy.gd")
	var run=root.get_node("Run")
	var settings=root.get_node("Settings")
	var catalog=root.get_node("Content")
	settings.set_value("sound",false);settings.set_value("music",false)
	settings.set_value("effects_detail","high")
	output=OS.get_environment("EMBERKEEP_THEME_CAPTURE")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	var rng_before: int=run.rng.state
	var walls: Dictionary={}
	var floors: Dictionary={}
	for theme in catalog.families.floors:
		var wall: ShaderMaterial=Style.wall_material(Color.WHITE,false,theme.id)
		var floor: ShaderMaterial=Style.floor_material(theme.look)
		walls[hash(wall.get_shader_parameter("paint").get_image().get_data())]=true
		floors[hash(floor.get_shader_parameter("paint").get_image().get_data())]=true
		check("/themes/"+theme.id+"/wall/" in sheet(wall),"live wall material selects the actual "+theme.id+" artwork")
		check("/themes/"+theme.id+"/floor/" in sheet(floor),"live ground material selects the actual "+theme.id+" artwork")
		check(Style.floor_material(theme.look)==floor,"the active floor reuses its shader material")
		check(PBR.theme_loaded.size()<=2,"architecture cache contains only the current floor's surfaces")
	check(walls.size()==8 and floors.size()==8,"all eight themes bind distinct authored forms rather than tinting the same texture")
	check(run.rng.state==rng_before,"loading themed artwork leaves gameplay randomness untouched")
	check(PBR.theme_maps("unknown_future_theme")==PBR.maps("masonry"),"unknown floor art has a bounded fallback")
	Policy.device_override=Policy.for_device("Android","Imagination","PowerVR","gl_compatibility")
	settings.apply_render_policy()
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game);current_scene=game
	game.set_physics_process(false);game.set_process(false)
	game.start_run("candle",31609250,false)
	var primary: Dictionary=run.rooms.values().filter(func(room):return room.get("vertical_primary",false))[0]
	var original_blueprint: Dictionary=primary.fps_terrain.duplicate(true)
	for theme in catalog.families.floors:
		run.floor_plan=[theme.id,theme.id,theme.id,theme.id,theme.id]
		run.current_room=primary.id
		game.enter_room(Vector3(0,0,5.9))
		game.paused=true
		for enemy in game.enemies: enemy.queue_free()
		game.enemies.clear()
		game.room.set_open(true)
		await process_frame
		await physics_frame
		await process_frame
		var expected: String="/themes/"+theme.id+"/"
		var wall_count:=0
		for mesh in game.room.get_children():
			if mesh.get_meta("surface_role","")!="wall": continue
			wall_count+=1
			check(expected+"wall/" in sheet(mesh.material_override),"constructed "+theme.id+" room uses its own wall material")
		check(wall_count>=4,"the actual "+theme.id+" room walls were checked")
		var gallery=game.room.get_node("TwoStoreyChamber")
		# A whole upper floor names its pieces UpperFloor/FloorSlab; the older
		# gallery, GalleryFloor/GallerySlab.
		var upstairs=gallery.get_node_or_null("UpperFloor") if gallery.has_node("UpperFloor") else gallery.get_node("GalleryFloor")
		var slab=gallery.get_node_or_null("FloorSlab") if gallery.has_node("FloorSlab") else gallery.get_node("GallerySlab")
		check(expected+"floor/" in sheet(upstairs.material_override),"the upstairs floor matches the "+theme.id+" ground")
		var structure: String=sheet(slab.material_override)
		check("/wood/" in structure if theme.look.materials.structure=="wood" else expected+"wall/" in structure,"gallery supports follow the floor's structural materials")
		for mesh in game.room.get_children():
			if mesh.get_meta("surface_role","")!="ceiling": continue
			var texture: String=sheet(mesh.material_override)
			check("/wood/" in texture if theme.look.materials.ceiling=="wood" else expected+"wall/" in texture,"the ceiling follows the "+theme.id+" architecture")
		var portal: String=primary.portals[0]
		game.corridors.arm(portal)
		var corridor_surfaces:=0
		for view in game.corridors.active.get_children():
			if view is MeshInstance3D and view.name in ["CorridorFloor","CorridorStone"]:
				corridor_surfaces+=1
				check(expected in sheet(view.material_override),"the live corridor shares "+theme.id+" surfaces")
		check(corridor_surfaces==2,"the two real corridor surface batches were checked")
		check(PBR.active_theme==theme.id and PBR.theme_loaded.size()<=2,"cross-floor texture caches are bounded after real room rebuilds")
		check(game.room.lamps.size()<=game.room.MAX_ACTIVE_FILLS and game.room.shadow_lamps.size()<=1,"new artwork does not increase room light or shadow budgets")
		check(is_zero_approx(upstairs.material_override.get_shader_parameter("relief_depth")),"PowerVR keeps its conservative surface path")
		check(primary.fps_terrain==original_blueprint,"theme changes preserve the two-storey geometry and its saved blueprint")
		if not output.is_empty(): await capture(theme.id)
	game.queue_free();await process_frame
	print("THEMED ARCHITECTURE: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func capture(theme: String) -> void:
	var loft=game.room.terrain.loft
	game.ui.toast_time=0;game.ui.floor_title_start=-100
	game.player.place(Vector3(0,.03,5.9))
	var aim: Vector3=(Vector3(loft.deck.get_center().x,1.8,loft.deck.get_center().y)-(game.player.position+Vector3.UP*1.5)).normalized()
	game.fps.yaw=atan2(-aim.x,-aim.z);game.fps.pitch=asin(aim.y)
	game.update_camera(0,true)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(theme+".png"))
	var report={"theme":theme,"room":game.room.data.id,"policy":"Android PowerVR Compatibility","texture_mb":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0,"video_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"cached_theme_surfaces":PBR.theme_loaded.size()}
	reports.append(report)
	FileAccess.open(output.path_join("measurements.json"),FileAccess.WRITE).store_string(JSON.stringify(reports,"  "))
	print("THEME GL ",JSON.stringify(report))
