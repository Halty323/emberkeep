class_name ActiveItems
extends RefCounted
## Handlers for active items. Each returns ok only when the activation was
## useful; otherwise nothing is spent and the cooldown does not start.
## A new item reusing a handler is data only; a new mechanic adds a handler
## here, registers it in Content.ACTIVE_HANDLERS and gets behavioural tests.
const HANDLERS := ["heal", "gale", "ember_burst", "slow_field", "modifier", "companions", "secret_hint", "invulnerable"]
const COMPANION_BUDGET := 2

static func yes(reason := "") -> Dictionary:
	return {"ok": true, "reason": reason}

static func no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func foes(game) -> Array:
	return game.enemies.filter(func(enemy): return is_instance_valid(enemy) and enemy.alive)

static func hostile_shots(game) -> Array:
	return game.shots.filter(func(shot): return is_instance_valid(shot) and shot.alive and not shot.friendly)

static func activate(game, definition: Dictionary) -> Dictionary:
	var params: Dictionary = definition.params
	var player: Node3D = game.player
	match definition.handler:
		"heal":
			if Run.hp >= Run.stats.max_hp:
				return no("Already warm through")
			Run.heal(float(params.amount))
			Effects.ring_burst(game, player.global_position, Color(definition.color), 1.6)
		"gale":
			var radius = float(params.radius)
			var near_shots = hostile_shots(game).filter(func(shot): return shot.global_position.distance_to(player.global_position) < radius)
			var near_foes = foes(game).filter(func(enemy): return enemy.global_position.distance_to(player.global_position) < radius)
			if near_shots.is_empty() and near_foes.is_empty():
				return no("Nothing close enough to blow away")
			for shot in near_shots: shot.remove()
			for enemy in near_foes:
				var away: Vector3 = enemy.global_position - player.global_position
				away.y = 0
				enemy.knock_velocity += away.normalized() * float(params.push) / (2.5 if enemy.boss else 1.0)
			Effects.ring_burst(game, player.global_position, Color(definition.color), radius)
		"ember_burst":
			if foes(game).is_empty():
				return no("No foes to burn")
			var effects = Run.projectile_stats()
			effects.burn = float(effects.get("burn", 0)) + float(params.get("burn", 0))
			for i in int(params.count):
				var direction = Vector3.RIGHT.rotated(Vector3.UP, TAU * i / float(params.count))
				game.spawn_shot(player.global_position + Vector3(0, .6, 0) + direction * .4, direction, float(params.damage) * Run.stats.damage, float(params.speed), effects, Color(definition.color), true)
		"slow_field":
			var targets = foes(game)
			if targets.is_empty():
				return no("No foes to slow")
			for enemy in targets:
				enemy.slow(float(params.duration), float(params.boss_slow if enemy.boss else params.slow))
			Effects.ring_burst(game, player.global_position, Color(definition.color), 7.0)
		"modifier":
			if foes(game).is_empty():
				return no("No foes to face")
			Run.add_modifier(definition.id, float(params.duration), params.effects)
		"companions":
			if foes(game).is_empty():
				return no("No foes for the moths")
			if Run.flag_total("companions") + int(params.count) > COMPANION_BUDGET:
				return no("The moths are already out")
			Run.add_modifier(definition.id, float(params.duration), {}, {"companions": int(params.count), "companion_damage": float(params.damage)})
			game.sync_companions()
		"secret_hint":
			var seam: Dictionary = game.room.hidden_seam()
			if seam.is_empty():
				return no("No hidden seam in this room")
			game.room.show_seam_hint(seam, float(params.duration))
		"invulnerable":
			if foes(game).is_empty() and hostile_shots(game).is_empty():
				return no("Nothing to shelter from")
			Run.add_modifier(definition.id, float(params.duration), {}, {"invulnerable": 1})
			player.refresh_shelter()
		_:
			return no("Unknown item")
	return yes()
