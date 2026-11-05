class_name DeathTrials
extends Node
## Death's trials, owed for a bargain paid with one instead of a curse. What
## was taken is already the player's; the trial only decides whether the
## curse it holds back falls. Run.trial keeps it, so "No dashing" can wait
## across rooms and floors. A trial fought at once seals Death's room, and
## leaving the run in the middle of one counts as failing it (Run.load_run).
##
## The challenger's own device keeps the trial: its clock, its waves, its
## wisps. Whatever it raises is raised where foes live: here alone, on the
## host in co-op, which tells the challenger when each wave has fallen. While
## a teammate faces Death everyone else spectates: they cannot act or be
## touched, foes see only the challenger, and they show pale and translucent.
const WAVES := 3
const WISPS := 7
# Seconds between the bargain and the first foe, while the doors close.
const GRACE := 1.6
const CATCH := 1.05

var game: Node
# The challenger's side.
var wisps: Array = []
var wave := 0
var clock := 0.0
var grace := 0.0
var caught := 0
# Where foes live: what was raised, for whom, and whether its fall is owed.
var foes: Array = []
var foe_peer := -1
var foe_pending := false
# The teammate this device last saw facing Death (0 for none).
var watched := 0

func setup(owner_game: Node) -> void:
	game = owner_game

func kind() -> String:
	return str(Run.trial.get("kind", ""))

func running() -> bool:
	return Run.trial.get("state", "") == "running"

## This player's own trial, fought now, holds Death's room shut.
func seals_room() -> bool:
	return running() and kind() in DeathBargain.AT_ONCE

## Anyone's trial holds the room: the room-clear check and the passage wait.
func holds_room() -> bool:
	return seals_room() or watched != 0

## Watching a teammate's trial: no acting, no harm, no foe's notice.
func spectating() -> bool:
	if seals_room() or not party_on(): return false
	var now: int = game.party.challenger()
	return now != 0 and now != Session.local_peer_id

func party_on() -> bool:
	return game.party != null and game.party.climbing()

## Sets the trial owed for a bargain, holding back its curse.
func begin(trial_kind: String, curse: Dictionary) -> void:
	reset()
	Run.trial = {"kind": trial_kind, "curse": curse.duplicate(), "room": Run.current_room, "state": "waiting"}
	if trial_kind in DeathBargain.AT_ONCE:
		start()
	else:
		game.ui.notify(DeathBargain.trial_name(trial_kind), DeathBargain.trial_text(trial_kind), DeathBargain.COLOR)
	Run.save_run()

func start() -> void:
	Run.trial.state = "running"
	clock = DeathBargain.trial_time(kind())
	grace = GRACE
	wave = 0
	caught = 0
	if kind() == "last_breath":
		# Saved with the trial, so health returns even after a reload.
		Run.trial["hp"] = Run.hp
		Run.hp = minf(Run.hp, 1.0)
		Run.changed.emit()
	game.room.set_open(false)
	Audio.play_sound("door", .55)
	var detail := DeathBargain.trial_text(kind())
	if party_on(): detail += " Your friends watch from the edge of the dark."
	game.ui.notify(DeathBargain.trial_name(kind()), detail, DeathBargain.COLOR)

## The room's foes, wisps and champions arrive once the doors have shut.
func arrive() -> void:
	match kind():
		"waves": next_wave()
		"quarry": ask("champion")
		"harvest":
			scatter_wisps()
			ask("hunters")
		"last_breath": ask("wave")

func update(delta: float) -> void:
	watch_party()
	if not (game.party and game.party.client()): tend_foes()
	if Run.trial.is_empty():
		if not wisps.is_empty(): reset()
		return
	if not running():
		# No dashing waits for the next fight to shut its doors.
		var data: Dictionary = Run.rooms.get(Run.current_room, {})
		if kind() == "no_dash" and not game.room.open and game.deferred_encounter.is_empty() and not data.get("cleared", true) and data.get("type", "") in ["combat", "boss"]:
			Run.trial.state = "running"
			game.ui.notify("No dashing", "The fight begins. Death is watching your feet.", DeathBargain.COLOR)
		return
	if kind() == "no_dash": return
	if grace > 0:
		grace -= delta
		if grace <= 0: arrive()
		return
	if DeathBargain.trial_time(kind()) > 0:
		clock -= delta
		if clock <= 0:
			fail("Time ran out.")
			return
	if kind() == "harvest":
		collect(delta)
		if caught >= WISPS: succeed()

## Everything this trial raised has fallen (sent by whoever runs the foes).
func on_cleared() -> void:
	if not running(): return
	match kind():
		"waves":
			if wave >= WAVES: succeed()
			else: next_wave()
		"quarry", "last_breath": succeed()

func wave_size() -> int:
	return 3 + Run.floor_number / 2

func next_wave() -> void:
	wave += 1
	ask("wave")
	if wave > 1: game.ui.notify("Wave %d of %d" % [wave, WAVES], "Death raises more.", DeathBargain.COLOR)

## Asks for foes (or their end) where foes live: here, or the host.
func ask(op: String) -> void:
	if game.party and game.party.client():
		game.party.acts.append(["trial", [op, kind(), wave]])
	else:
		raise_for(Session.local_peer_id, op, kind(), wave)

# ---------------------------------------------------------------- where foes live

## Raises a trial's foes around its challenger, or sends them back.
func raise_for(peer: int, op: String, trial_kind: String, at_wave: int) -> void:
	if op == "end":
		if peer == foe_peer: banish()
		return
	if foe_peer != peer: banish()
	var body: Node3D = game.party.body_of(peer) if game.party and peer != Session.local_peer_id else game.player
	if not is_instance_valid(body): return
	var center: Vector3 = body.global_position
	var gen := RandomNumberGenerator.new()
	gen.seed = Content.stable_hash("trial:%d:%s:%d:%s:%d" % [Run.seed_value, Run.current_room, peer, trial_kind, at_wave])
	var roster: Array = Foes.roster_for(Run.theme_id(), Run.floor_number, Run.floor_plan).filter(func(entry): return entry[0] != "rootling")
	if game.party: game.party.begin_world()
	foe_peer = peer
	match op:
		"wave", "hunters":
			var count: int = wave_size() if op == "wave" else 2 + Run.floor_number / 2
			for entry in Foes.compose(roster, Foes.elite_chance(Run.floor_number), count, gen):
				var foe: DungeonEnemy = game.spawn_enemy(around(gen, center, 3.5, 6.5), entry.kind, "")
				if entry.elite not in ["", "twinned"]: foe.make_elite(entry.elite)
				Effects.play("death_puff", foe.global_position + Vector3.UP * .5, DeathBargain.COLOR, 10, 1.2)
				foes.append(foe)
		"champion":
			# One foe of this floor, made elite, with far more health.
			var pick: Array = roster[gen.randi_range(0, roster.size() - 1)] if not roster.is_empty() else ["brute"]
			var foe: DungeonEnemy = game.spawn_enemy(around(gen, center, 4.5, 6.5), pick[0], "")
			foe.make_elite(["gilded", "volatile", "warded"][gen.randi_range(0, 2)])
			foe.max_hp *= 2.6 + .3 * Run.floor_number
			foe.hp = foe.max_hp
			Geo.ring(foe, Vector3(0, .05, 0), foe.radius + .5, DeathBargain.COLOR, .05)
			Effects.play("death_puff", foe.global_position + Vector3.UP * .6, DeathBargain.COLOR, 16, 1.6)
			foes.append(foe)
	# Hunters only hunt; a wave or a champion owes its fall to the challenger.
	foe_pending = op != "hunters"
	if game.party: game.party.end_world()

## Each tick where foes live: has the challenger's wave fallen, or have they gone?
func tend_foes() -> void:
	if foe_peer < 0: return
	foes = foes.filter(func(foe): return is_instance_valid(foe) and foe.alive)
	if game.party and game.party.host() and foe_peer != Session.local_peer_id and not game.party.members.has(foe_peer):
		banish()
		return
	if foe_pending and foes.is_empty():
		foe_pending = false
		if foe_peer == Session.local_peer_id or not (game.party and game.party.host()): on_cleared()
		else: game.party.tell(foe_peer, "trial", "cleared")

## Whatever Death raised goes back into the dark.
func banish() -> void:
	if game.party: game.party.begin_world()
	for foe in foes:
		if is_instance_valid(foe) and foe.alive:
			Effects.play("death_puff", foe.global_position + Vector3.UP * .5, DeathBargain.COLOR, 8)
			foe.alive = false
			foe.queue_free()
	if game.party: game.party.end_world()
	game.enemies = game.enemies.filter(func(foe): return is_instance_valid(foe) and foe.alive)
	foes.clear()
	foe_peer = -1
	foe_pending = false

## A point a few steps from the challenger, inside the room.
func around(gen: RandomNumberGenerator, base: Vector3, near: float, far: float) -> Vector3:
	for attempt in 8:
		var p := base + Vector3.FORWARD.rotated(Vector3.UP, gen.randf() * TAU) * gen.randf_range(near, far)
		var safe: Vector2 = game.room.geometry.safe_point(Vector2(p.x, p.z), .7, game.room.blocked_at)
		if safe.distance_to(Vector2(base.x, base.z)) > 2.5: return Vector3(safe.x, base.y, safe.y)
	return base + Vector3(3, 0, 0)

# ---------------------------------------------------------------- spectating

## Follows whether a teammate faces Death: their doors shut for everyone, and
## whoever is not fighting watches until it is done.
func watch_party() -> void:
	var now: int = game.party.challenger() if party_on() else 0
	if now == watched: return
	var before := watched
	watched = now
	if now != 0 and now != Session.local_peer_id:
		game.room.set_open(false)
		if game.ui.mode == "bargain": game.close_reward()
		game.ui.notify("%s faces Death" % Session.name_of(now), "You watch from the edge of the dark, untouched, until it is done.", DeathBargain.COLOR)
	elif now == 0 and before != Session.local_peer_id and is_instance_valid(game.room):
		if Run.rooms.get(Run.current_room, {}).get("cleared", false): game.room.set_open(true)

## The line spectators see: whose trial, and how it stands.
func watching_line() -> String:
	if not spectating(): return ""
	var now: int = game.party.challenger()
	return "WATCHING %s · %s" % [Session.name_of(now).to_upper(), game.party.trial_line(now)]

# ---------------------------------------------------------------- the challenger's side

## Soul-wisps drift through the room until the player walks through them.
func scatter_wisps() -> void:
	var gen := RandomNumberGenerator.new()
	gen.seed = Content.stable_hash("wisps:%d:%s" % [Run.seed_value, Run.current_room])
	var cells: Array = game.room.geometry.cells
	for i in WISPS:
		var center: Vector2 = RoomGeometry.cell_center(cells[i % cells.size()])
		var spot: Vector2 = game.room.geometry.safe_point(center + Vector2(gen.randf_range(-5.5, 5.5), gen.randf_range(-3.6, 3.6)), .8, game.room.blocked_at)
		var wisp := Node3D.new()
		game.scene_root.add_child(wisp)
		var height: float = game.room.floor_height(Vector3(spot.x, 0, spot.y)) if game.first_person else 0.0
		wisp.position = Vector3(spot.x, height + .9, spot.y)
		wisp.set_meta("home", wisp.position)
		wisp.set_meta("phase", gen.randf() * TAU)
		Geo.sphere(wisp, Vector3.ZERO, .1, Color("efe9ff"), 2.6)
		wisp.add_child(DeathFigure.sprite(.7, Color(.8, .72, 1.0, .5)))
		wisps.append(wisp)

func collect(delta: float) -> void:
	var at: Vector3 = game.player.global_position
	for wisp in wisps.duplicate():
		if not is_instance_valid(wisp):
			wisps.erase(wisp)
			continue
		var phase: float = wisp.get_meta("phase") + delta * .9
		wisp.set_meta("phase", phase)
		wisp.position = wisp.get_meta("home") + Vector3(cos(phase) * .7, sin(phase * 1.7) * .15, sin(phase) * .5)
		if Vector2(wisp.position.x - at.x, wisp.position.z - at.z).length() < CATCH:
			caught += 1
			Effects.play("discovery_glint", wisp.global_position, DeathBargain.COLOR)
			Audio.play_sound("coin", 1.3 + caught * .05)
			wisp.queue_free()
			wisps.erase(wisp)

## Last breath, or any trial fought before friends: a fall fails the trial
## instead of ending the run (alone) or leaving the challenger down (co-op).
func catch_fall() -> bool:
	if not running(): return false
	if not (kind() == "last_breath" or (seals_room() and party_on())): return false
	var rekindle := not Run.trial.has("hp")
	fail("You fell.")
	if rekindle: Run.hp = minf(float(Run.stats.max_hp), Party.REVIVE_HP)
	Run.changed.emit()
	game.player.invulnerability = 2.0
	return true

func on_dash() -> void:
	if running() and kind() == "no_dash": fail("You dashed.")

func on_room_cleared() -> void:
	if running() and kind() == "no_dash": succeed()

func succeed() -> void:
	var restore := float(Run.trial.get("hp", -1.0))
	finish()
	if restore > 0: Run.hp = clampf(restore, .5, Run.stats.max_hp)
	Run.changed.emit()
	game.ui.notify("Death keeps its word", "The trial is won. No curse falls.", DeathBargain.COLOR)
	Audio.play_sound("item", .8)
	Run.save_run()

func fail(reason: String) -> void:
	var curse: Dictionary = Run.trial.get("curse", {})
	var restore := float(Run.trial.get("hp", -1.0))
	finish()
	Run.add_curse(curse)
	if restore > 0: Run.hp = clampf(restore, .5, Run.stats.max_hp)
	Run.changed.emit()
	if DeathBargain.known_curse(curse):
		game.ui.notify("The curse falls · %s" % DeathBargain.curse_name(curse), "%s %s" % [reason, DeathBargain.curse_text(curse)], DeathBargain.COLOR)
	Audio.play_sound("hurt", .6)
	game.shake = maxf(game.shake, .15)
	Run.save_run()

## The trial is over: its foes go back into the dark and its doors open.
func finish() -> void:
	var sealed := seals_room()
	if sealed: ask("end")
	Run.trial = {}
	reset()
	if sealed:
		game.room.set_open(true)
		Audio.play_sound("door", 1.1)

func reset() -> void:
	for wisp in wisps:
		if is_instance_valid(wisp): wisp.queue_free()
	wisps.clear()
	wave = 0
	caught = 0
	grace = 0.0
	clock = 0.0

## The trial's line under the top of the screen, or nothing.
func hud_line() -> String:
	var watching := watching_line()
	if watching != "": return watching
	if Run.trial.is_empty(): return ""
	var title := DeathBargain.trial_name(kind()).to_upper()
	if not running(): return "%s · AT YOUR NEXT FIGHT" % title
	if grace > 0: return "%s · DEATH IS WATCHING" % title
	match kind():
		"waves": return "%s · WAVE %d / %d · %d s" % [title, wave, WAVES, ceili(clock)]
		"quarry": return "%s · %d s" % [title, ceili(clock)]
		"harvest": return "%s · %d / %d · %d s" % [title, caught, WISPS, ceili(clock)]
		"no_dash": return "%s · DO NOT DASH" % title
		"last_breath": return "%s · SURVIVE THE WAVE" % title
	return title
