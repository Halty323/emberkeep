class_name Drops
extends RefCounted
## Resolves a data-defined drop table into concrete records. Coin amounts are
## split into silver (5) and copper (1) coins, so every value comes from the
## pickup catalog instead of a special case.

static func roll(table_id: String, rng: RandomNumberGenerator, luck := 0.0, coin_bonus := 0.0, exclude_active := "") -> Array:
	var result: Array = []
	for entry in Content.record("drop_tables", table_id).rolls:
		if entry.has("coins"):
			var expected = float(entry.coins) * (1.0 + coin_bonus)
			var amount = int(floor(expected)) + int(rng.randf() < fposmod(expected, 1.0))
			result.append_array(coins(maxi(amount, int(entry.get("minimum", 0)))))
		elif entry.has("pickup"):
			if rng.randf() < float(entry.get("chance", 1.0)) + float(entry.get("luck", 0.0)) * luck:
				for i in int(entry.get("count", 1)):
					result.append({"def": entry.pickup})
		elif entry.has("one_of"):
			var total = 0.0
			for choice in entry.one_of: total += float(choice.weight)
			var pick = rng.randf() * total
			for choice in entry.one_of:
				pick -= float(choice.weight)
				if pick <= 0:
					for i in int(choice.get("count", 1)): result.append({"def": choice.pickup})
					break
		elif entry.has("active"):
			var roll_value = rng.randf()
			var pool = Content.families.actives.filter(func(active): return active.id != exclude_active)
			if roll_value < float(entry.active) and not pool.is_empty():
				result.append({"active": pool[rng.randi_range(0, pool.size() - 1)].id})
	return result

static func coins(amount: int) -> Array:
	var result: Array = []
	for i in amount / 5: result.append({"def": "silver_coin"})
	for i in amount % 5: result.append({"def": "copper_coin"})
	return result

## Positions around a source for several drops, kept inside the room.
static func scatter(count: int, index: int, center: Vector3) -> Vector3:
	if count <= 1:
		return center
	var angle = TAU * float(index) / count + .4
	return center + Vector3(sin(angle), 0, cos(angle)) * (.45 + .1 * (index % 3))
