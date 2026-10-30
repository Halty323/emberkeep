extends DungeonEnemy
## A brute chained to a post: a long reach around it but no further. Shoot
## the post down and it is free: faster, and its dragging chain smashes the
## furniture it passes, though it pays out more when it falls.
const LEASH := 4.2
const LINKS := 7
var post: DungeonEnemy
var freed = false
var links: Array = []
var slam_cooldown = 1.5
var smash = 0.0

func stats() -> Array:
	return [70, 1.0, .7, "8a8172"]

func build_body(light: Dictionary) -> void:
	var body = Geo.box(visual, Vector3(0, radius * 1.2, 0), Vector3(radius * 1.8, radius * 2.2, radius * 1.8), color, light.foe_body)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.ring(visual, Vector3(0, radius * 1.9, 0), radius * .7, Color("4f4a44"), .08)

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	if post == null and not freed:
		post = game.spawn_enemy(global_position, "shackle_post")
		post.prisoner = self
		for i in LINKS:
			var link = Geo.box(game.scene_root, Vector3.ZERO, Vector3(.18, .18, .3), Color("9a8466"), .25)
			link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			links.append(link)
	slam_cooldown -= delta * tempo()
	if windup > 0: return Vector3.ZERO
	if distance < 2.3 and slam_cooldown <= 0:
		begin_windup(direction, .7, 1.7, Color("ed9b77"))
		slam_cooldown = 2.6
		return Vector3.ZERO
	var target: Vector3 = game.player.global_position
	if not freed and is_instance_valid(post):
		var reach: Vector3 = target - post.global_position
		reach.y = 0
		if reach.length() > LEASH: target = post.global_position + reach.normalized() * LEASH
	else:
		smash -= delta
		if smash <= 0:
			smash = .25
			for id in game.room.props.keys():
				var node: Node3D = game.room.props[id].node
				if is_instance_valid(node) and node.global_position.distance_to(global_position) < radius + 1.0:
					game.hit_prop(id, 15.0)
	return steer_toward(target, delta)

func after_move(_delta: float, _distance: float, _direction: Vector3) -> void:
	if freed or not is_instance_valid(post): return
	var away: Vector3 = global_position - post.global_position
	away.y = 0
	if away.length() > LEASH:
		position = post.global_position + away.normalized() * LEASH
		last_valid = position
	for i in links.size():
		var t = (i + .5) / LINKS
		var at: Vector3 = post.global_position.lerp(global_position, t)
		links[i].global_position = at + Vector3(0, .5 + sin(t * PI) * -.25, 0)

## The slam lands where it stood.
func windup_done() -> void:
	Effects.ring_burst(game.scene_root, global_position, Color("ed9b77"), 1.9)
	game.shake = maxf(game.shake, .12)
	if game.player.global_position.distance_to(global_position) < 1.9:
		game.player.hurt(1.0, global_position)

func post_broken() -> void:
	freed = true
	speed *= 2.2
	for link in links:
		if is_instance_valid(link): link.queue_free()
	links.clear()
	game.shake = maxf(game.shake, .18)
	Audio.play_sound("hurt", .6)

func on_death() -> void:
	for link in links:
		if is_instance_valid(link): link.queue_free()
	if is_instance_valid(post) and post.alive:
		post.alive = false
		post.queue_free()
	# Set loose, it pays out twice.
	if freed and source != "":
		var data: Dictionary = Run.rooms[Run.current_room]
		var key = source + ":freed"
		if key in data.get("credited", []): return
		if not data.has("credited"): data.credited = []
		data.credited.append(key)
		var drops = Drops.roll("enemy_common", Run.rng, Run.stats.luck, Run.coin_bonus())
		for i in drops.size():
			game.spawn_pickup(Drops.scatter(drops.size(), i, global_position), drops[i].def)
