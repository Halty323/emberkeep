extends SceneTree
## Actual game transactions across vertical room clears, reloads and old saves.
var checks := 0
var failures := 0
var game
var run

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL: "+label)

func settle() -> void:
	await process_frame
	await physics_frame
	await process_frame

func quiet_room(id: String) -> void:
	run.current_room=id
	game.enter_room(Vector3(0,0,2))
	game.paused=true
	for enemy in game.enemies: enemy.queue_free()
	game.enemies.clear()

func exercise() -> void:
	run=root.get_node("Run")
	root.get_node("Settings").set_value("sound",false)
	root.get_node("Settings").set_value("music",false)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.set_physics_process(false)
	game.start_run("candle",91242,false)
	check(run.generator_version==3 and run.coins==4,"new default expedition uses new generator and scarce starting money")
	var vertical_id: String=""
	for seed_value in range(91242,91272):
		if seed_value!=91242: game.start_run("candle",seed_value,false)
		for id in run.rooms:
			# Optional chambers are real two-storey rooms now, as the primary is.
			if run.rooms[id].get("fps_terrain",{}).get("version",0)>=3 and not run.rooms[id].get("vertical_primary",false):
				vertical_id=id
				break
		if vertical_id!="": break
	check(vertical_id!="","a real seeded expedition supplies an optional vertical encounter")
	if vertical_id!="":
		quiet_room(vertical_id)
		await settle()
		var data: Dictionary=run.rooms[vertical_id]
		var height: float=game.room.terrain.rise
		var before_cleared: int=run.cleared
		game.clear_room()
		check(data.cleared and data.claimed and data.clear_reward=="chest","clearing vertical room resolves an ordinary chest instead of passive relic offers")
		check(not data.has("offers"),"vertical clear never bundles active and relic reward lists")
		var rewards: Array=data.chests.filter(func(c):return c.get("source","")=="vertical_clear")
		check(rewards.size()==1,"real clear produces exactly one ordinary chest")
		if not rewards.is_empty():
			var chest: Dictionary=rewards[0]
			check(chest.table=="normal_chest" and not chest.locked and not chest.opened,"earned chest is normal, unlocked and unopened")
			check(is_equal_approx(float(chest.height),height),"chest save record uses the upper/cellar floor height")
			check(is_equal_approx(game.chest_views[chest.id].position.y,height),"actual chest model is on the upper/cellar floor")
			check(is_equal_approx(game.interactions.targets["chest:"+chest.id].position.y,height),"chest interaction follows its model at the actual elevation")
			game.clear_room()
			check(data.chests.filter(func(c):return c.get("source","")=="vertical_clear").size()==1 and run.cleared==before_cleared+1,"duplicate clear cannot duplicate chest or clear credit")
			check(run.load_run(),"completed vertical clear reloads from disk")
			quiet_room(vertical_id)
			await settle()
			check(run.rooms[vertical_id].clear_reward_paid,"reload retains the paid clear transaction")
			check(game.chest_views.has(chest.id) and is_equal_approx(game.chest_views[chest.id].position.y,height),"reload reconstructs the earned chest at the same physical level")
			game.paused=false
			check(game.actions.open_chest(chest.id).ok,"earned ordinary chest opens after reload")
			var drops: int=run.rooms[vertical_id].get("pickups",[]).size()+run.rooms[vertical_id].get("items",[]).size()
			check(run.load_run(),"opened chest transaction reloads")
			quiet_room(vertical_id)
			check(not game.actions.open_chest(chest.id).ok,"opened chest cannot pay again after a second reload")
			check(run.rooms[vertical_id].get("pickups",[]).size()+run.rooms[vertical_id].get("items",[]).size()==drops,"reload preserves exactly the generated supplies/equipment")
	var ordinary: Array=run.rooms.keys().filter(func(id):return run.rooms[id].type=="combat" and not run.rooms[id].get("vertical_challenge",false) and not run.rooms[id].cleared)
	for id in ordinary:
		quiet_room(id)
		game.clear_room()
	var passive_awards: int=run.rooms.values().filter(func(data):return data.get("clear_reward","")=="relic").size()
	check(passive_awards<=1,"clearing multiple ordinary rooms cannot exceed the per-floor passive relic budget")
	var data: Dictionary=run.rooms[run.current_room]
	data.claimed=false
	data.offers=[{"kind":"active","id":"moth_jar","price":0}]
	var inventory_count: int=run.inventory.size()
	game.chosen_reward_shop=false
	game.chosen_reward_dark=false
	game.choose_offer(0)
	check(run.active_item.is_empty() and run.inventory.size()==inventory_count+1,"stale direct active offer is converted before the award transaction")
	run.hp=2.0
	var hp: float=run.hp
	run.next_floor()
	check(is_equal_approx(run.hp,hp),"new expeditions do not grant free floor-change healing")
	# Existing generator-2 saves keep their topology/economy on later floors.
	run.generator_version=2
	run.generate_floor()
	run.hp=2.0
	run.save_run()
	check(run.load_run() and run.generator_version==2,"old run keeps its explicit generator version")
	run.next_floor()
	check(run.rooms.size()>=17 and run.generator_version==2,"old saved run continues with its original room-count generator")
	check(run.hp>2.0,"old saved run retains its prior floor-heal rule")
	game.queue_free()
	await process_frame
	print("EXPEDITION INTEGRATION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
