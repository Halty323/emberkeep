class_name DeathTrials
extends Node
## Death's trials, owed for a bargain paid with one instead of a curse. What
## was taken is already the player's; the trial only decides whether the
## curse it holds back falls. Run.trial keeps it, so "No dashing" can wait
## across rooms and floors. A trial fought at once seals Death's room, and
## leaving the run in the middle of one counts as failing it (Run.load_run).
const WAVES := 3
const WISPS := 7
# Seconds between the bargain and the first foe, while the doors close.
const GRACE := 1.6
const CATCH := 1.05

var game: Node
var foes: Array = []
var wisps: Array = []
var wave := 0
var clock := 0.0
var grace := 0.0
var caught := 0

func setup(owner_game: Node) -> void:
	game = owner_game

func kind() -> String:
	return str(Run.trial.get("kind", ""))

func running() -> bool:
	return Run.trial.get("state", "") == "running"

## A trial fought now holds Death's room shut; the room-clear check waits.
func seals_room() -> bool:
	return running() and kind() in DeathBargain.AT_ONCE

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
	game.ui.notify(DeathBargain.trial_name(kind()), DeathBargain.trial_text(kind()), DeathBargain.COLOR)

## The room's foes, wisps and champions arrive once the doors have shut.
func arrive() -> void:
	match kind():
		"waves": next_wave()
		"quarry": summon_champion()
		"harvest":
			scatter_wisps()
			raise(2 + Run.floor_number / 2)
		"last_breath": raise(wave_size())

func update(delta: float) -> void:
	if Run.trial.is_empty():
		if not foes.is_empty() or not wisps.is_empty(): reset()
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
	foes = foes.filter(func(foe): return is_instance_valid(foe) and foe.alive)
	if DeathBargain.trial_time(kind()) > 0:
		clock -= delta
		if clock <= 0:
			fail("Time ran out.")
			return
	match kind():
		"waves":
			if foes.is_empty():
				if wave >= WAVES: succeed()
				else: next_wave()
		"quarry", "last_breath":
			if foes.is_empty(): succeed()
		"harvest":
			collect(delta)
			if caught >= WISPS: succeed()

func wave_size() -> int:
	return 3 + Run.floor_number / 2

func next_wave() -> void:
	wave += 1
	raise(wave_size())
	if wave > 1: game.ui.notify("Wave %d of %d" % [wave, WAVES], "Death raises more.", DeathBargain.COLOR)

## Foes Death raises from this floor's own roster. They carry no loot.
func raise(count: int) -> void:
	var gen := RandomNumberGenerator.new()
	gen.seed = Content.stable_hash("trial:%d:%s:%s:%d" % [Run.seed_value, Run.current_room, kind(), wave])
	var roster: Array = Foes.roster_for(Run.theme_id(), Run.floor_number, Run.floor_plan).filter(func(entry): return entry[0] != "rootling")
	for entry in Foes.compose(roster, Foes.elite_chance(Run.floor_number), count, gen):
		var foe: DungeonEnemy = game.spawn_enemy(around(gen, 3.5, 6.5), entry.kind, "")
		if entry.elite not in ["", "twinned"]: foe.make_elite(entry.elite)
		Effects.play("death_puff", foe.global_position + Vector3.UP * .5, DeathBargain.COLOR, 10, 1.2)
		foes.append(foe)

## One champion: a foe of this floor, made elite, with far more health.
func summon_champion() -> void:
	var gen := RandomNumberGenerator.new()
	gen.seed = Content.stable_hash("quarry:%d:%s" % [Run.seed_value, Run.current_room])
	var roster: Array = Foes.roster_for(Run.theme_id(), Run.floor_number, Run.floor_plan).filter(func(entry): return entry[0] != "rootling")
	var pick: Array = roster[gen.randi_range(0, roster.size() - 1)] if not roster.is_empty() else ["brute"]
	var foe: DungeonEnemy = game.spawn_enemy(around(gen, 4.5, 6.5), pick[0], "")
	foe.make_elite(["gilded", "volatile", "warded"][gen.randi_range(0, 2)])
	foe.max_hp *= 2.6 + .3 * Run.floor_number
	foe.hp = foe.max_hp
	Geo.ring(foe, Vector3(0, .05, 0), foe.radius + .5, DeathBargain.COLOR, .05)
	Effects.play("death_puff", foe.global_position + Vector3.UP * .6, DeathBargain.COLOR, 16, 1.6)
	foes.append(foe)

## A point a few steps from the player, inside the room.
func around(gen: RandomNumberGenerator, near: float, far: float) -> Vector3:
	var base: Vector3 = game.player.global_position
	for attempt in 8:
		var p := base + Vector3.FORWARD.rotated(Vector3.UP, gen.randf() * TAU) * gen.randf_range(near, far)
		var safe: Vector2 = game.room.geometry.safe_point(Vector2(p.x, p.z), .7, game.room.blocked_at)
		if safe.distance_to(Vector2(base.x, base.z)) > 2.5: return Vector3(safe.x, base.y, safe.y)
	return base + Vector3(3, 0, 0)

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

## Last breath: a fall in the trial fails it instead of ending the run.
func catch_fall() -> bool:
	if not (running() and kind() == "last_breath"): return false
	fail("Your last breath ran out.")
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

## Whatever Death raised goes back into the dark, and its doors open.
func finish() -> void:
	var sealed := seals_room()
	for foe in foes:
		if is_instance_valid(foe) and foe.alive:
			Effects.play("death_puff", foe.global_position + Vector3.UP * .5, DeathBargain.COLOR, 8)
			foe.alive = false
			foe.queue_free()
	game.enemies = game.enemies.filter(func(foe): return is_instance_valid(foe) and foe.alive)
	Run.trial = {}
	reset()
	if sealed:
		game.room.set_open(true)
		Audio.play_sound("door", 1.1)

func reset() -> void:
	for wisp in wisps:
		if is_instance_valid(wisp): wisp.queue_free()
	wisps.clear()
	foes.clear()
	wave = 0
	caught = 0
	grace = 0.0
	clock = 0.0

## The trial's line under the top of the screen, or nothing.
func hud_line() -> String:
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
