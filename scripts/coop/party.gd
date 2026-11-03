class_name Party
extends Node
## Co-op on the local network, two to four little lights in one tower.
##
## Every player's own device runs their own hero exactly as a lone climb does:
## movement, casting, health, wallet, relics, spellbook, pickups, chests and
## every reward. Loot is personal: each player sees and collects only their
## own drops, and takes their own pick at every reliquary and shop.
##
## The host runs everything the party shares: foes, the spells in flight,
## the residue on the floor, hazards, bombs, breakable props, doors and
## lanterns. Guests send what they do (where they are, what they cast and
## hit) and the host sends back what happens: foes and spells to draw,
## effects, sounds, blows to take, and the world's changes. A foe chases the
## nearest teammate still standing.
##
## A player whose last heart goes falls instead of dying; a teammate standing
## beside them for a few seconds rekindles them on one heart. The climb ends
## only when everyone is down at once. Rooms change only when the whole party
## is in the passage, and the stair is climbed together.
static var current: Party
const STATE_RATE := 1.0 / 30.0
const SNAPSHOT_RATE := 1.0 / 20.0
# Every so many snapshots, foes and telegraphs are sent whole, not as changes.
const KEYFRAME := 10
const REVIVE_TIME := 3.0
const REVIVE_REACH := 1.7
const REVIVE_HP := 2.0
# A room's fight starts once everyone is in, or this long after the first.
const SEAL_GRACE := 3.0
const PULL_SPACING := .75
# Foes keep their quarry unless another teammate is clearly closer.
const TARGET_STICKINESS := 1.5
# The cosmetic flight of a spell needs only these of its traits.
const SHOT_KEYS := ["returning", "homing", "wave", "accel", "linger", "grow", "size", "range", "bounce", "pierce"]
# Sounds a guest hears from the host's world; the rest are each player's own.
const SHARED_SOUNDS := ["hit", "kill"]
# Sights and sounds: sent unreliably, since a lost one is only a missed spark
# and must never hold up the world's changes behind it.
const LOOSE := ["fx", "snd", "dmg", "word"]
const LOOSE_PER_TICK := 48
var game
var figures: Node3D
# Other players' figures, by peer id.
var members: Dictionary = {}
# The latest report from each player (the host's own included, on the host).
var states: Dictionary = {}
# Host: what everyone hears this tick, and what one player alone hears.
var outbox: Array = []
var loose: Array = []
var direct: Dictionary = {}
var pushes: Dictionary = {}
# Guest: what this player did this tick, for the host.
var acts: Array = []
var fire_stats: Array = []
# Host: inside the shared world's simulation, effects, sounds and telegraphs
# are recorded for the guests.
var recording := 0
var geo_paused := 0
# Host: whose spell is being cast or simulated (0: this device's own).
var shot_owner := 0
var pending_net_id := 0
var pending_predicted := false
# Spells known by network id (host: the real ones; guest: drawn copies).
var net_shots: Dictionary = {}
# Guest: the host's foes, drawn here.
var puppets: Dictionary = {}
# Telegraph geometry foes make while fighting, by network id.
var geo_nodes: Dictionary = {}
var geo_counter := 0
var geo_sent: Dictionary = {}
var foe_sent: Dictionary = {}
var shot_counter := 0
var downed := false
# Host: rekindling progress per fallen player (0..1); everyone sees it.
var revive: Dictionary = {}
var at_stair: Dictionary = {}
var waiting_at_stair := false
# Room handoffs and floors so far: a report from before one is shifted or
# ignored, so a figure never jumps across the origin change.
var epoch := 0
var last_shift := Vector3.ZERO
var state_timer := 0.0
var snap_timer := 0.0
var snap_tick := 0
var first_inside := -1.0
var clock := 0.0
# When each teammate's casting was last heard, so a volley is one sound.
var heard_cast: Dictionary = {}
var notice := ""
# Host: foes are taking their turn, so a blow can catch a teammate nearby.
var foe_turn := false
var splashing := false

func setup(owner_game) -> void:
	game = owner_game
	current = self
	NetHooks.recorder = self
	name = "Party"
	figures = Node3D.new()
	figures.name = "PartyFigures"
	game.add_child(figures)
	Session.message_received.connect(on_message)
	Session.roster_changed.connect(on_roster)
	Session.session_ended.connect(on_session_ended)
	Session.parties_changed.connect(func():
		if is_instance_valid(game.ui) and game.ui.mode == "coop": game.ui.show_screen("coop"))

func _exit_tree() -> void:
	if current == self: current = null

## In a party (lobby or climb). Co-op is first person only.
func online() -> bool:
	return Session.online and Session.status == "party" and game.first_person

func host() -> bool:
	return online() and Session.hosting

func client() -> bool:
	return online() and not Session.hosting

func climbing() -> bool:
	return online() and Run.active and not game.in_menu

## The run is over for everyone, or this player left: forget the party's world.
func reset() -> void:
	for id in members.keys(): remove_member(id)
	states.clear()
	outbox.clear()
	loose.clear()
	direct.clear()
	pushes.clear()
	acts.clear()
	fire_stats.clear()
	net_shots.clear()
	puppets.clear()
	geo_nodes.clear()
	geo_sent.clear()
	foe_sent.clear()
	revive.clear()
	at_stair.clear()
	recording = 0
	geo_paused = 0
	shot_owner = 0
	downed = false
	waiting_at_stair = false
	epoch = 0
	first_inside = -1.0
	notice = ""

# ---------------------------------------------------------------- lobby

## The host sets off: everyone starts the same tower from the same seed.
func begin(seed_value: int) -> void:
	if not host(): return
	Session.started = true
	Run.generator_version = FloorGenerator.VERSION
	var floor_data: Dictionary = Run.floor_data_for(seed_value, 1)
	var packed := pack(floor_data)
	Session.send(0, "start", {"seed": seed_value, "floor": packed})
	start_local(seed_value, floor_data)

func start_local(seed_value: int, floor_data: Dictionary) -> void:
	reset()
	Run.incoming_floor = floor_data
	game.start_run(Session.local_weapon, seed_value, false)
	for id in Session.others(): ensure_member(id)
	game.ui.notify("The party sets out", "%d little lights climb together." % Session.roster.size(), Color("f1cc8a"))

## Each player's own offers at a reliquary or shop differ from the others'.
func loot_salt() -> int:
	return Session.local_slot() * 7919 if online() else 0

## The climb is over (won or everyone fell): the party stays together.
func ended() -> void:
	downed = false
	waiting_at_stair = false
	for id in members.keys(): remove_member(id)
	if host(): Session.started = false

## Host: back to the lobby for another climb with the same party.
func regroup() -> void:
	if not Session.hosting: return
	Session.started = false
	Session.send(0, "lobby")
	reset()
	Run.active = false
	game.show_title_room()
	game.ui.show_screen("lobby")

static func pack(value) -> PackedByteArray:
	var raw := var_to_bytes(value)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, raw.size())
	return header + packed

static func unpack(bytes) -> Variant:
	if not bytes is PackedByteArray or bytes.size() < 4: return null
	var size: int = bytes.decode_u32(0)
	if size <= 0 or size > 64 * 1024 * 1024: return null
	var raw: PackedByteArray = bytes.slice(4).decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size: return null
	return bytes_to_var(raw)

func on_roster() -> void:
	if not climbing():
		if is_instance_valid(game.ui) and game.in_menu and game.ui.mode in ["coop", "lobby"] and Session.status == "party":
			game.ui.show_screen("lobby")
		return
	for id in members.keys():
		if not Session.roster.has(id): remove_member(id)
	for id in Session.others(): ensure_member(id)

func ensure_member(peer_id: int) -> PartyMember:
	if members.has(peer_id) and is_instance_valid(members[peer_id]): return members[peer_id]
	var member := PartyMember.new()
	figures.add_child(member)
	member.setup_member(game, peer_id, Session.name_of(peer_id), Session.color_of(peer_id), Session.hosting)
	member.position = game.player.position if is_instance_valid(game.player) else Vector3.ZERO
	member.target = member.position
	members[peer_id] = member
	return member

func remove_member(peer_id: int) -> void:
	if members.has(peer_id) and is_instance_valid(members[peer_id]): members[peer_id].queue_free()
	members.erase(peer_id)
	states.erase(peer_id)
	revive.erase(peer_id)
	at_stair.erase(peer_id)

func on_session_ended(reason: String) -> void:
	if Run.active and not game.in_menu:
		# A climb without its party is over; it is not saved.
		Run.active = false
		reset()
		game.show_title_room()
		game.ui.show_screen("menu")
	else:
		reset()
		if is_instance_valid(game.ui) and game.ui.mode in ["coop", "lobby"]: game.ui.show_screen("coop")
	if reason != "" and is_instance_valid(game.ui): game.ui.notify(reason, "", Color("e8c39a"))

# ---------------------------------------------------------------- bodies

## Everyone foes can strike: this device's player and, on the host, the
## figures standing in for the others. Fallen players are left out.
func bodies() -> Array:
	var result: Array = []
	if is_instance_valid(game.player) and not downed: result.append(game.player)
	if host():
		for member in members.values():
			if is_instance_valid(member) and not member.downed: result.append(member)
	return result

func body_of(peer_id: int) -> Node3D:
	if peer_id == 0 or peer_id == Session.local_peer_id: return game.player
	return members.get(peer_id) if is_instance_valid(members.get(peer_id)) else game.player

## The teammate a foe goes after: the nearest standing, kept unless another
## is clearly closer.
func quarry(enemy: Node3D) -> Node3D:
	var standing := bodies()
	if standing.is_empty(): return game.player
	var held = enemy.get_meta("quarry") if enemy.has_meta("quarry") else null
	var best: Node3D = null
	var best_distance := INF
	for body in standing:
		var distance: float = body.global_position.distance_to(enemy.global_position)
		if body == held: distance -= TARGET_STICKINESS
		if distance < best_distance:
			best_distance = distance
			best = body
	enemy.set_meta("quarry", best)
	return best

## Runs every foe for one tick, each chasing its own quarry.
func run_foes(delta: float) -> void:
	var own = game.player
	begin_world()
	foe_turn = true
	for enemy in game.enemies.duplicate():
		if not is_instance_valid(enemy) or not enemy.alive or not game.sim_live(): continue
		game.player = quarry(enemy)
		enemy.update_sim(delta)
		game.player = own
	foe_turn = false
	game.player = own
	end_world()

## A blow meant for the quarry also lands on any teammate at least as close
## to where it came from (a slam, a burst, a body in contact).
func splash(struck: Node3D, amount: float, source: Vector3) -> void:
	if splashing or not foe_turn: return
	splashing = true
	var reach: float = Vector2(struck.global_position.x - source.x, struck.global_position.z - source.z).length() + .25
	for body in bodies():
		if body == struck: continue
		if Vector2(body.global_position.x - source.x, body.global_position.z - source.z).length() <= reach and absf(body.global_position.y - struck.global_position.y) < 1.2:
			if body is PartyMember: strike(body, amount, source, false)
			else: body.hurt(amount, source)
	splashing = false

## A figure struck on the host: the blow goes to its player's own device.
func strike(member: PartyMember, amount: float, source: Vector3, spread := true) -> void:
	if spread: splash(member, amount, source)
	if member.downed or member.invulnerable: return
	tell(member.owner_peer_id, "hurt", [amount, source])
	# Until its player's device says otherwise, as the player's own would be.
	member.invulnerable = true

func send_push(peer_id: int, value: Vector3) -> void:
	if host(): pushes[peer_id] = value

# ---------------------------------------------------------------- recording

func begin_world() -> void:
	if host(): recording += 1

func end_world() -> void:
	recording = maxi(0, recording - 1)

func share(kind: String, data = null, except := 0) -> void:
	if not host(): return
	if kind in LOOSE:
		if loose.size() < LOOSE_PER_TICK: loose.append([kind, data])
	else: outbox.append([kind, data, except])

## One player alone hears this (a blow, a heal, a hit marker).
func tell(peer_id: int, kind: String, data = null) -> void:
	if not host(): return
	if peer_id == Session.local_peer_id:
		on_private(kind, data)
		return
	if not direct.has(peer_id): direct[peer_id] = []
	direct[peer_id].append([kind, data])

func shared_sound(id: String, pitch: float, at = null) -> void:
	if at != null or id in SHARED_SOUNDS: share("snd", [id, pitch, at])

## Telegraph geometry a foe makes while it fights is made on every device.
func note_geo(node: Node3D, method: String, args: Array) -> void:
	if recording <= 0 or geo_paused > 0: return
	var key: Array = geo_parent(node.get_parent())
	if key.is_empty(): return
	geo_counter += 1
	node.set_meta("net_geo", geo_counter)
	geo_nodes[geo_counter] = node
	share("geo", [geo_counter, method, key, args])

func geo_parent(parent: Node) -> Array:
	if parent == game.scene_root: return ["r"]
	if parent is DungeonEnemy and not parent.puppet: return ["e", parent.entity_id]
	if parent and parent.get_parent() is DungeonEnemy and parent == parent.get_parent().visual: return ["v", parent.get_parent().entity_id]
	if parent and parent.has_meta("net_geo"): return ["g", int(parent.get_meta("net_geo"))]
	return []

func resolve_parent(key: Array) -> Node3D:
	match str(key[0]):
		"r": return game.scene_root
		"e":
			var foe = puppets.get(int(key[1]))
			return foe if is_instance_valid(foe) else null
		"v":
			var foe = puppets.get(int(key[1]))
			return foe.visual if is_instance_valid(foe) else null
		"g":
			var node = geo_nodes.get(int(key[1]))
			return node if is_instance_valid(node) else null
	return null

# ---------------------------------------------------------------- foes

## Host: a foe has entered the fight; guests draw it.
func foe_spawned(enemy: DungeonEnemy) -> void:
	if not host(): return
	mark_parts(enemy)
	share("foe", {"id": enemy.entity_id, "kind": enemy.kind, "p": enemy.position, "src": enemy.source, "t": snap_tick})

func foe_elite(enemy: DungeonEnemy, twist: String, partner: DungeonEnemy) -> void:
	if not host() or enemy.puppet: return
	mark_parts(enemy)
	if is_instance_valid(partner): mark_parts(partner)
	share("elite", [enemy.entity_id, twist, partner.entity_id if is_instance_valid(partner) else 0])

## A guest builds the same foe in the same pose, so only what moves from
## here on is ever sent.
func mark_parts(enemy: DungeonEnemy) -> void:
	var parts := parts_of(enemy)
	enemy.set_meta("net_parts", parts)
	var baseline := {}
	for i in parts.size(): baseline[i] = [parts[i].transform, parts[i].visible]
	foe_sent[enemy.entity_id] = baseline
	enemy.set_meta("net_moved", {})

## The parts of a foe that may move as it fights: its body and what hangs on
## it. Both devices build a foe the same way, so the lists line up.
static func parts_of(enemy: DungeonEnemy) -> Array:
	var result: Array = [enemy.visual]
	for child in enemy.get_children():
		if child is Node3D and child != enemy.visual and not child.has_meta("net_geo"): result.append(child)
	for child in enemy.visual.get_children():
		if child is Node3D and not child.has_meta("net_geo"): result.append(child)
	return result

func foe_killed(enemy: DungeonEnemy, event: Dictionary) -> void:
	if not host(): return
	var shared := event.duplicate()
	shared["id"] = enemy.entity_id
	share("kill", shared)

## A loot drop for everyone: each player gets their own copy.
func loot(at: Vector3, pickup_id: String) -> void:
	share("loot", [pickup_id, at])

## Guest: a spell or blast struck the host's foe here; the host applies it.
func foe_hit(enemy: DungeonEnemy, damage: float, impulse: Vector3, critical: bool, dot: bool, cause: String) -> void:
	if client(): acts.append(["hit", [enemy.entity_id, damage, impulse, critical, dot, cause]])

func foe_status(enemy: DungeonEnemy, stats: Dictionary) -> void:
	var status := {}
	# Statuses, the elements they carry, and the combinations riding on them.
	for key in ["burn", "chill", "poison", "chain", "wet", "waxen", "resonance", "hit", "keg", "jelly", "freeze", "northern"]:
		if float(stats.get(key, 0)) > 0: status[key] = float(stats[key])
	if str(stats.get("element", "")) != "": status["element"] = str(stats.element)
	if client() and not status.is_empty(): acts.append(["status", [enemy.entity_id, status]])

func foe_slow(enemy: DungeonEnemy, duration: float, factor: float) -> void:
	if client(): acts.append(["slow", [enemy.entity_id, duration, factor]])

func foe_shove(enemy: DungeonEnemy, force: Vector3) -> void:
	if client(): acts.append(["shove", [enemy.entity_id, force]])

func foe_dashed(enemy: DungeonEnemy) -> void:
	if client(): acts.append(["dash", enemy.entity_id])

func host_foe(id) -> DungeonEnemy:
	for enemy in game.enemies:
		if is_instance_valid(enemy) and enemy.alive and enemy.entity_id == int(id): return enemy
	return null

# ---------------------------------------------------------------- spells

## Guest: this player's own spell. It is drawn at once and the host casts the
## real one; whatever it strikes is the host's to decide.
func predict_shot(at: Vector3, direction: Vector3, damage: float, speed: float, stats: Dictionary, color: Color) -> EmberShot:
	var shot: EmberShot = game.make_shot(at, direction, damage, speed, flight(stats), color, true)
	if shot == null: return null
	shot_counter += 1
	shot.cosmetic = true
	shot.net_id = Session.local_slot() * 4194304 + shot_counter
	shot.owner_peer = Session.local_peer_id
	net_shots[shot.net_id] = shot
	var index := -1
	for i in fire_stats.size():
		if fire_stats[i][0] == stats:
			index = i
			break
	if index < 0:
		fire_stats.append([stats, stats.duplicate()])
		index = fire_stats.size() - 1
	acts.append(["fire", [shot.net_id, at, direction, damage, speed, index, color]])
	return shot

static func flight(stats: Dictionary) -> Dictionary:
	var result := {}
	for key in SHOT_KEYS:
		if stats.has(key) and float(stats[key]) != 0: result[key] = float(stats[key])
	return result

## Host: a real spell exists; the guests draw it (its caster drew it already).
func shot_spawned(shot: EmberShot) -> void:
	if not host(): return
	shot.owner_peer = shot_owner if shot_owner != 0 else Session.local_peer_id
	shot.net_id = pending_net_id if pending_net_id != 0 else shot.entity_id
	pending_net_id = 0
	net_shots[shot.net_id] = shot
	share("shot", [shot.net_id, shot.position, shot.direction, shot.speed, shot.tint, shot.friendly, flight(shot.stats), shot.owner_peer],
		shot.owner_peer if pending_predicted else 0)
	pending_predicted = false

func shot_gone(shot: EmberShot) -> void:
	if shot.net_id == 0: return
	if host() and net_shots.has(shot.net_id): share("shot_end", shot.net_id)
	net_shots.erase(shot.net_id)

## Guest: a hostile spell this player caught or blew away never reaches them.
func dispel(shot: EmberShot) -> void:
	if client() and shot.net_id != 0: acts.append(["dispel", shot.net_id])

func spell_owner_local(shot: EmberShot) -> bool:
	return shot.owner_peer == 0 or shot.owner_peer == Session.local_peer_id

# ---------------------------------------------------------------- the world

func world_noise(at: Vector3, loudness: float) -> void:
	if client(): acts.append(["noise", [at, loudness]])

func place_bomb(at: Vector3, height: float) -> void:
	if client(): acts.append(["bomb", [at, height]])

func at_the_stair() -> Dictionary:
	if not online(): return {}
	waiting_at_stair = true
	if host(): at_stair[Session.local_peer_id] = true
	else: acts.append(["stair", true])
	Audio.play_sound("door", 1.1)
	return GameActions.result(true)

## Guest: a residue change from the host.
func apply_residue(data) -> void:
	if not data is Array or not is_instance_valid(game.residue): return
	game.residue.apply_net(data)

# ---------------------------------------------------------------- the tick

## Once per physics tick, after everything else has moved.
func tick(delta: float) -> void:
	if not climbing(): return
	clock += delta
	# Walking away from the stair stops waiting at it.
	if waiting_at_stair and (not is_instance_valid(game.stairs) or game.player.global_position.distance_to(game.stairs.approach_point()) > 3.5):
		waiting_at_stair = false
		at_stair.erase(Session.local_peer_id)
	state_timer -= delta
	if state_timer <= 0:
		state_timer = STATE_RATE
		var mine := local_state()
		if host(): states[Session.local_peer_id] = mine
		else: Session.stream(1, "state", mine)
	if host():
		host_rules(delta)
		if not climbing(): return
		if is_instance_valid(game.residue):
			var changes: Dictionary = game.residue.take_changes()
			if not changes.is_empty(): share("res", changes)
		snap_timer -= delta
		if snap_timer <= 0:
			snap_timer = SNAPSHOT_RATE
			send_snapshot()
		flush_host()
	else:
		if not acts.is_empty():
			var stats_list: Array = fire_stats.map(func(entry): return entry[1])
			Session.send(1, "act", {"acts": acts, "stats": stats_list, "ep": epoch})
			acts = []
			fire_stats = []
	update_notice()

func local_state() -> Dictionary:
	var player = game.player
	var state := {"p": player.global_position, "y": game.fps.yaw, "v": player.velocity, "hp": Run.hp, "mhp": float(Run.stats.max_hp),
		"inv": player.invulnerability > 0 or Run.has_flag("invulnerable"), "down": downed, "w": Color(Run.weapon().color),
		"room": Run.current_room, "ep": epoch, "stair": waiting_at_stair}
	var corridors: CorridorTransit = game.corridors
	var point := Vector2(player.position.x, player.position.z)
	state["in"] = is_instance_valid(game.room) and game.room.geometry.contains(point, .1)
	if is_instance_valid(corridors.active):
		var local := point - Vector2(corridors.active.position.x, corridors.active.position.z)
		state["cor"] = corridors.portal_id
		state["al"] = CorridorPlan.project(corridors.active.path, local)
		state["walk"] = corridors.walking()
		state["from"] = corridors.source_room
	return state

func flush_host() -> void:
	for peer_id in Session.others():
		var events: Array = []
		for entry in outbox:
			if int(entry[2]) != peer_id: events.append([entry[0], entry[1]])
		if not events.is_empty(): Session.send(peer_id, "ev", events)
		if direct.has(peer_id) and not direct[peer_id].is_empty(): Session.send(peer_id, "me", direct[peer_id])
		if pushes.has(peer_id): Session.stream(peer_id, "push", pushes[peer_id])
	# A few at a time, so each piece fits one network packet.
	for start in range(0, loose.size(), 14): Session.stream(0, "sights", loose.slice(start, start + 14))
	loose.clear()
	outbox.clear()
	direct.clear()
	pushes.clear()

## Host: what everyone draws: players, foes and the telegraphs foes made.
func send_snapshot() -> void:
	snap_tick += 1
	var keyframe := snap_tick % KEYFRAME == 0
	var players := {}
	for id in states:
		var s: Dictionary = states[id]
		players[id] = {"p": s.get("p"), "y": s.get("y", 0.0), "v": s.get("v"), "inv": s.get("inv", false), "down": s.get("down", false),
			"hp": s.get("hp", 0.0), "mhp": s.get("mhp", 6.0), "w": s.get("w"), "stair": s.get("stair", false)}
	var foes: Array = []
	var ids := PackedInt32Array()
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or not enemy.alive: continue
		ids.append(enemy.entity_id)
		# Each foe repeats its moved parts on its own beat, so a lost packet
		# heals and no snapshot carries every foe's.
		foes.append(foe_frame(enemy, (snap_tick + enemy.entity_id) % KEYFRAME == 0))
	var telegraphs: Array = []
	for nid in geo_nodes.keys():
		var node = geo_nodes[nid]
		if not is_instance_valid(node) or not node.is_inside_tree():
			geo_nodes.erase(nid)
			geo_sent.erase(nid)
			share("geo_gone", nid)
			continue
		var frame := [node.transform, node.visible]
		if keyframe or geo_sent.get(nid) != frame:
			geo_sent[nid] = frame
			telegraphs.append([nid, node.transform, node.visible])
	# Split to fit network packets: the first piece names every foe alive.
	var chunks: Array = [{"t": snap_tick, "ep": epoch, "room": Run.current_room, "pl": players, "rv": revive, "g": telegraphs, "ids": ids, "en": []}]
	var size := 160 + players.size() * 140 + telegraphs.size() * 72 + ids.size() * 4
	for entry in foes:
		var cost: int = 64 + entry[6].size() * 68
		if size + cost > 1100 and not chunks.back().en.is_empty():
			chunks.append({"t": snap_tick, "ep": epoch, "room": Run.current_room, "en": []})
			size = 60
		chunks.back().en.append(entry)
		size += cost
	for chunk in chunks: Session.stream(0, "snap", chunk)

func foe_frame(enemy: DungeonEnemy, keyframe: bool) -> Array:
	var flags := (1 if enemy.targetable else 0) | (2 if enemy.inert else 0) | (4 if enemy.shrouded else 0) | (8 if enemy.ward_up else 0) \
		| (enemy.mark_bits() << 4) | (4096 if enemy.frozen > 0 else 0)
	var changes: Array = []
	var parts: Array = enemy.get_meta("net_parts", [])
	var sent: Dictionary = foe_sent.get(enemy.entity_id, {})
	var moved: Dictionary = enemy.get_meta("net_moved", {})
	for i in parts.size():
		var part = parts[i]
		if not is_instance_valid(part):
			if sent.get(i) != null:
				sent[i] = null
				changes.append([i])
			continue
		var frame := [part.transform, part.visible]
		if sent.get(i) != frame or (keyframe and moved.has(i)):
			sent[i] = frame
			moved[i] = true
			changes.append([i, part.transform, part.visible])
	enemy.set_meta("net_moved", moved)
	foe_sent[enemy.entity_id] = sent
	return [enemy.entity_id, enemy.position, enemy.hp, enemy.max_hp, flags, enemy.flash, changes]

## Host: rekindling, the passage, the fight's start, the stair, the end.
func host_rules(delta: float) -> void:
	# Rekindling: a standing teammate beside a fallen one.
	var everyone := {Session.local_peer_id: game.player}
	for id in members: everyone[id] = members[id]
	var fallen := []
	for id in everyone:
		if is_down(id): fallen.append(id)
	for id in fallen:
		var body: Node3D = everyone[id]
		if not is_instance_valid(body): continue
		var tended := false
		for other in everyone:
			if other == id or is_down(other) or not is_instance_valid(everyone[other]): continue
			var gap := Vector2(everyone[other].global_position.x - body.global_position.x, everyone[other].global_position.z - body.global_position.z).length()
			if gap <= REVIVE_REACH and absf(everyone[other].global_position.y - body.global_position.y) < 1.5: tended = true
		var progress: float = revive.get(id, 0.0)
		progress = clampf(progress + (delta / REVIVE_TIME if tended else -delta / (REVIVE_TIME * 2.0)), 0.0, 1.0)
		if progress >= 1.0:
			revive.erase(id)
			tell(id, "revive")
			if members.has(id):
				members[id].downed = false
				members[id].pose()
			share("notify", ["%s is rekindled" % Session.name_of(id), "Back on one heart.", Color("ffd28d")])
		elif progress > 0: revive[id] = progress
		else: revive.erase(id)
	for id in revive.keys():
		if id not in fallen: revive.erase(id)
	for id in members:
		if is_instance_valid(members[id]): members[id].show_revive(float(revive.get(id, 0.0)))
	# Everyone down at once: the climb is over.
	if not everyone.is_empty() and fallen.size() == everyone.size():
		share("wipe")
		flush_host()
		game.end_run(false)
		return
	gather()
	seal_when_inside()
	climb_when_ready()

func is_down(peer_id: int) -> bool:
	if peer_id == Session.local_peer_id: return downed
	return bool(states.get(peer_id, {}).get("down", false))

func standing_peers() -> Array:
	return Session.peers().filter(func(id): return not is_down(id))

## The next room loads only once everyone standing is in the same passage
## and someone has reached its turn; whoever lags is pulled along.
func gather() -> void:
	if not is_instance_valid(game.room) or not game.room.open: return
	var portal := ""
	for id in standing_peers():
		var s: Dictionary = states.get(id, {})
		if int(s.get("ep", -1)) != epoch or str(s.get("cor", "")) == "" or str(s.get("from", "")) != Run.current_room: continue
		if not Run.portals.has(str(s.cor)) or str(s.cor) not in Run.rooms[Run.current_room].get("portals", []): continue
		var plan: Dictionary = CorridorPlan.ensure(Run.portals[s.cor], Run.rooms)
		var turn: float = float(plan.handoff) if Run.current_room == Run.portals[s.cor].a.room else float(plan.length) - float(plan.handoff)
		if float(s.get("al", 0.0)) >= turn - .05: portal = s.cor
	if portal == "": return
	for id in standing_peers():
		var s: Dictionary = states.get(id, {})
		if int(s.get("ep", -1)) != epoch or str(s.get("cor", "")) != portal or not bool(s.get("walk", false)): return
	var destination: String = Run.other_room(portal, Run.current_room)
	share("handoff", {"portal": portal, "from": Run.current_room, "to": destination})
	flush_host()
	handoff(portal, Run.current_room, destination)

## Everyone moves through the passage's turn together. Whoever is behind is
## placed just past it, spaced by party slot.
func handoff(portal: String, from: String, to: String) -> void:
	var corridors: CorridorTransit = game.corridors
	if Run.current_room != from or not Run.portals.has(portal): return
	if corridors.portal_id != portal or not is_instance_valid(corridors.active):
		corridors.arm(portal)
	if not is_instance_valid(corridors.active): return
	var player = game.player
	var local := Vector2(player.position.x, player.position.z) - Vector2(corridors.active.position.x, corridors.active.position.z)
	var along := CorridorPlan.project(corridors.active.path, local)
	var past: float = corridors.handoff + .3 + Session.local_slot() * PULL_SPACING
	if along < corridors.handoff + .26 or not corridors.walking():
		var spot: Dictionary = CorridorPlan.sample(corridors.active.path, past)
		var at: Vector2 = spot.at + Vector2(corridors.active.position.x, corridors.active.position.z)
		player.position = Vector3(at.x, .03, at.y)
		player.last_valid = player.position
		player.velocity = Vector3.ZERO
		game.fps.yaw = atan2(-spot.direction.x, -spot.direction.y)
	var shift := Vector3(corridors.destination_offset.x, 0, corridors.destination_offset.y)
	corridors.rebase(to, corridors.destination_offset)
	moved_origin(shift)
	waiting_at_stair = false

## Every position known in the old room's frame moves with the origin.
func moved_origin(shift: Vector3) -> void:
	epoch += 1
	last_shift = shift
	for member in members.values():
		if not is_instance_valid(member): continue
		member.position -= shift
		member.target -= shift
	for id in states:
		if states[id].get("p") is Vector3: states[id].p -= shift
	first_inside = -1.0

## Host: a fight starts once the whole party is through the door (or a few
## seconds after the first); anyone still in the passage is pulled in.
func seal_when_inside() -> void:
	if game.deferred_encounter.is_empty(): return
	var inside := 0
	var standing := standing_peers()
	for id in standing:
		if id == Session.local_peer_id:
			if game.room.geometry.contains(Vector2(game.player.position.x, game.player.position.z), 1.05): inside += 1
		elif int(states.get(id, {}).get("ep", -1)) == epoch and bool(states.get(id, {}).get("in", false)): inside += 1
	if inside == 0: return
	if first_inside < 0: first_inside = clock
	if inside < standing.size() and clock - first_inside < SEAL_GRACE: return
	share("seal", Run.current_room)
	seal(Run.current_room)

func seal(room_id: String) -> void:
	if Run.current_room != room_id: return
	pull_inside()
	game.corridors.reset()
	if host(): game.activate_corridor_encounter()
	else:
		game.deferred_encounter = {}
		game.room.set_open(false)

## Brings this player through the door they came in by, if still outside.
func pull_inside() -> void:
	var player = game.player
	var point := Vector2(player.position.x, player.position.z)
	if game.room.geometry.contains(point, .3): return
	var portal: String = game.room.entry_portal
	var spot := Vector2.ZERO
	if portal != "" and Run.portals.has(portal):
		var side: Dictionary = Run.portal_side(portal, Run.current_room)
		spot = RoomGeometry.entry_point(side.cell, side.dir) - Vector2(side.dir) * (.8 + Session.local_slot() * .5)
	spot = game.room.geometry.safe_point(spot, .5, game.room.blocked_at)
	var at := Vector3(spot.x, 0, spot.y)
	at.y = game.room.floor_height(at) + .03
	player.position = at
	player.last_valid = at
	player.velocity = Vector3.ZERO

## Host: the stair is climbed when everyone standing waits at it.
func climb_when_ready() -> void:
	var waiting := 0
	var standing := standing_peers()
	for id in standing:
		if id == Session.local_peer_id:
			if waiting_at_stair: waiting += 1
		elif bool(states.get(id, {}).get("stair", false)) or at_stair.has(id): waiting += 1
	if waiting == 0 or waiting < standing.size(): return
	at_stair.clear()
	var next := {}
	if not Run.last_floor(): next = Run.floor_data_for(Run.seed_value, Run.floor_number + 1)
	var message := {"floor": Run.floor_number + 1, "data": pack(next) if not next.is_empty() else PackedByteArray()}
	share("climb", message)
	flush_host()
	climb(message)

func climb(message: Dictionary) -> void:
	waiting_at_stair = false
	var next = unpack(message.get("data")) if message.get("data") is PackedByteArray and not message.data.is_empty() else null
	if next is Dictionary: Run.incoming_floor = next
	if downed: rise(true)
	if not is_instance_valid(game.stairs): game.raise_stairs(false)
	game.begin_climb()

## The new floor opens in a fresh frame of reference.
func floor_changed() -> void:
	epoch += 1
	last_shift = Vector3.ZERO
	at_stair.clear()
	waiting_at_stair = false
	first_inside = -1.0
	for member in members.values():
		if is_instance_valid(member):
			member.position = game.player.position
			member.target = member.position

## A new room's tree: what pointed into the old one is gone.
func room_changed() -> void:
	puppets.clear()
	geo_nodes.clear()
	geo_sent.clear()
	foe_sent.clear()
	for id in net_shots.keys():
		if not is_instance_valid(net_shots[id]): net_shots.erase(id)

# ---------------------------------------------------------------- falling

## This player's last heart is gone: they fall where they stand.
func fall() -> void:
	if downed: return
	downed = true
	waiting_at_stair = false
	Run.hp = 0.0
	game.player.velocity = Vector3.ZERO
	game.request_dash = false
	Audio.play_sound("hurt", .7)
	Run.changed.emit()
	if host(): share("notify", ["%s has fallen" % Session.name_of(Session.local_peer_id), "Stand beside them to rekindle them.", Color("e0a18b")])
	else: acts.append(["fell", true])

## Rekindled by a teammate (or carried up the stair): back on one heart.
func rise(quietly := false) -> void:
	if not downed: return
	downed = false
	Run.hp = minf(float(Run.stats.max_hp), REVIVE_HP)
	game.player.invulnerability = 1.5
	Run.changed.emit()
	if not quietly:
		Effects.ring_burst(game.scene_root, game.player.global_position, Color("ffd28d"), 1.6)
		Audio.play_sound("item", 1.2)
		game.ui.notify("Rekindled", "A friend's warmth brings you back.", Color("ffd28d"))

# ---------------------------------------------------------------- messages

func on_message(from: int, kind: String, data) -> void:
	if not online(): return
	if Session.hosting:
		match kind:
			"state": take_state(from, data)
			"act": take_acts(from, data)
			"left": guest_left(from, str(data))
		return
	match kind:
		"start":
			var floor_data = unpack(data.get("floor")) if data is Dictionary else null
			if floor_data is Dictionary: start_local(int(data.seed), floor_data)
		"ev", "sights": if climbing() and data is Array: for entry in data: on_event(str(entry[0]), entry[1])
		"me": if climbing() and data is Array: for entry in data: on_private(str(entry[0]), entry[1])
		"snap": if climbing() and data is Dictionary: take_snapshot(data)
		"push": if climbing() and data is Vector3 and is_instance_valid(game.player): game.player.push = data
		"lobby":
			# Back to the lobby for another climb, from a climb or its end.
			Run.active = false
			reset()
			if not game.in_menu: game.show_title_room()
			game.ui.show_screen("lobby")

func take_state(from: int, data) -> void:
	if not data is Dictionary or not data.get("p") is Vector3: return
	var ep := int(data.get("ep", -1))
	if ep == epoch - 1:
		data.p -= last_shift
		data.erase("cor")
		data["ep"] = epoch
	elif ep != epoch: return
	var was_down := is_down(from)
	states[from] = data
	if not bool(data.get("stair", false)): at_stair.erase(from)
	var member: PartyMember = ensure_member(from) if climbing() else null
	if member: member.show_state(data)
	if was_down and not bool(data.get("down", false)): revive.erase(from)

func take_acts(from: int, data) -> void:
	if not climbing() or not data is Dictionary or not data.get("acts") is Array: return
	var same_frame := int(data.get("ep", -1)) == epoch
	var stats_list: Array = data.get("stats", []) if data.get("stats") is Array else []
	var member: Node3D = body_of(from)
	var own = game.player
	begin_world()
	for entry in data.acts:
		if not entry is Array or entry.size() < 2: continue
		var value = entry[1]
		match str(entry[0]):
			"fire":
				if not same_frame or not value is Array or value.size() < 7 or not value[1] is Vector3 or not value[2] is Vector3 or not value[6] is Color: continue
				var stats: Dictionary = stats_list[int(value[5])] if int(value[5]) >= 0 and int(value[5]) < stats_list.size() and stats_list[int(value[5])] is Dictionary else {}
				cast_heard(from, value[1])
				shot_owner = from
				pending_net_id = int(value[0])
				pending_predicted = true
				game.spawn_shot(value[1], value[2], float(value[3]), float(value[4]), stats, value[6], true)
				pending_net_id = 0
				pending_predicted = false
				shot_owner = 0
			"hit":
				var foe: DungeonEnemy = host_foe(value[0]) if value is Array and value.size() >= 6 else null
				if foe:
					game.player = member
					foe.take_hit(float(value[1]), value[2] if value[2] is Vector3 else Vector3.ZERO, bool(value[3]), bool(value[4]), str(value[5]))
					game.player = own
			"status":
				var foe: DungeonEnemy = host_foe(value[0]) if value is Array and value.size() >= 2 else null
				if foe and value[1] is Dictionary:
					value[1]["owner"] = from
					foe.apply_status(value[1])
			"slow":
				var foe: DungeonEnemy = host_foe(value[0]) if value is Array and value.size() >= 3 else null
				if foe: foe.slow(float(value[1]), float(value[2]))
			"shove":
				var foe: DungeonEnemy = host_foe(value[0]) if value is Array and value.size() >= 2 else null
				if foe and value[1] is Vector3: foe.shove(value[1])
			"dash":
				var foe: DungeonEnemy = host_foe(value)
				if foe: foe.dashed_through()
			"dispel":
				var shot = net_shots.get(int(value))
				if is_instance_valid(shot) and not shot.friendly: shot.remove()
			"noise":
				if value is Array and value.size() >= 2 and value[0] is Vector3 and same_frame: game.make_noise(value[0], float(value[1]))
			"bomb":
				if value is Array and value.size() >= 2 and value[0] is Vector3 and same_frame: game.actions.place_guest_bomb(from, value[0], float(value[1]))
			"stair": at_stair[from] = true
			"fell":
				if members.has(from):
					members[from].downed = true
					members[from].pose()
				share("notify", ["%s has fallen" % Session.name_of(from), "Stand beside them to rekindle them.", Color("e0a18b")])
				game.ui.notify("%s has fallen" % Session.name_of(from), "Stand beside them to rekindle them.", Color("e0a18b"))
	end_world()
	game.player = own

func guest_left(peer_id: int, who: String) -> void:
	remove_member(peer_id)
	if climbing():
		share("notify", ["%s has gone home" % who, "", Color("e8c39a")])
		game.ui.notify("%s has gone home" % who, "", Color("e8c39a"))

## Guest: the host's world, as it happens.
func on_event(kind: String, data) -> void:
	match kind:
		"foe": if data is Dictionary: make_puppet(data)
		"elite":
			var foe = puppets.get(int(data[0]))
			if is_instance_valid(foe):
				var partner = puppets.get(int(data[2]))
				geo_paused += 1
				foe.make_elite(str(data[1]), partner if is_instance_valid(partner) else null)
				geo_paused -= 1
				foe.set_meta("net_parts", parts_of(foe))
				if is_instance_valid(partner): partner.set_meta("net_parts", parts_of(partner))
		"kill":
			var foe = puppets.get(int(data.get("id", 0)))
			if is_instance_valid(foe): drop_puppet(foe)
			game.award_kill(data)
		"loot":
			if is_instance_valid(game.room) and data[1] is Vector3: game.spawn_pickup(data[1], str(data[0]))
		"fx": replay_fx(str(data[0]), data[1])
		"snd":
			if data[2] is Vector3: Audio.play_at(str(data[0]), game, data[2], float(data[1]))
			else: Audio.play_sound(str(data[0]), float(data[1]))
		"dmg": if data[0] is Vector3: game.damage_number(data[0], float(data[1]), bool(data[2]))
		"word": if data is Array and data.size() >= 2 and data[0] is Vector3: game.reaction_word(data[0], str(data[1]))
		"shot": draw_shot(data)
		"shot_end":
			var shot = net_shots.get(int(data))
			if is_instance_valid(shot): shot.remove()
			net_shots.erase(int(data))
		"geo": make_geo(data)
		"geo_gone":
			var node = geo_nodes.get(int(data))
			if is_instance_valid(node): node.queue_free()
			geo_nodes.erase(int(data))
		"clear":
			if str(data) == Run.current_room:
				for foe in puppets.values():
					if is_instance_valid(foe): drop_puppet(foe)
				game.clear_room()
		"seal": seal(str(data))
		"prop":
			var room_id := str(data[0])
			if Run.rooms.has(room_id):
				var record: Dictionary = GameActions.find_record(Run.rooms[room_id].get("props", []), str(data[1]))
				if not record.is_empty(): game.destroy_prop(room_id, record, room_id == Run.current_room and is_instance_valid(game.room))
		"portal":
			if Run.portals.has(str(data[0])) and Run.portals[str(data[0])].state == "concealed":
				Run.portals[str(data[0])].state = "revealed"
				if is_instance_valid(game.room) and str(data[0]) in Run.rooms[Run.current_room].get("portals", []):
					game.room.reveal_socket(str(data[0]))
					game.ui.notify("A hidden passage", "The old wall gives way.", Color("d7c3e8"))
					Audio.play_sound("door", .7)
		"lamp":
			if is_instance_valid(game.room):
				if bool(data[1]): game.relight(int(data[0]))
				else: game.snuff(int(data[0]))
		"res": apply_residue(data)
		"bomb": if data is Dictionary and str(data.get("room", "")) == Run.current_room: game.spawn_bomb_view(data)
		"bomb_gone":
			var view = game.bomb_views.get(str(data))
			if is_instance_valid(view): view.queue_free()
			game.bomb_views.erase(str(data))
		"notify": game.ui.notify(str(data[0]), str(data[1]), data[2] if data[2] is Color else Color("f1cc8a"))
		"handoff": if data is Dictionary: handoff(str(data.portal), str(data["from"]), str(data.to))
		"climb": if data is Dictionary: climb(data)
		"wipe": game.end_run(false)

## What happens to this player alone.
func on_private(kind: String, data) -> void:
	match kind:
		"hurt":
			if data is Array and data.size() >= 2 and is_instance_valid(game.player):
				game.player.hurt(float(data[0]), data[1] if data[1] is Vector3 else game.player.global_position)
		"heal": Run.heal(float(data))
		"hitmark": game.fps.hit_time = .13
		"revive": rise()
		"haste": if is_instance_valid(game.player): game.player.haste_time = 2.0

func replay_fx(method: String, args) -> void:
	if not args is Array: return
	match method:
		"play": if args.size() >= 6: Effects.play(str(args[0]), args[1], args[2], int(args[3]), float(args[4]), args[5])
		"ring": if args.size() >= 3: Effects.ring_burst(game.scene_root, args[0], args[1], float(args[2]))
		"beam": if args.size() >= 3: Effects.beam(game.scene_root, args[0], args[1], args[2])

func make_puppet(data: Dictionary) -> void:
	var id := int(data.id)
	if puppets.has(id) and is_instance_valid(puppets[id]): return
	if not data.get("p") is Vector3 or not is_instance_valid(game.room): return
	var foe: DungeonEnemy = Foes.create(str(data.kind))
	foe.puppet = true
	game.scene_root.add_child(foe)
	geo_paused += 1
	foe.setup(game, str(data.kind), id)
	geo_paused -= 1
	foe.source = str(data.get("src", ""))
	foe.place(data.p)
	foe.set_meta("born", int(data.get("t", 0)))
	foe.set_meta("goal", data.p)
	foe.set_meta("net_parts", parts_of(foe))
	puppets[id] = foe
	game.enemies.append(foe)

func drop_puppet(foe: DungeonEnemy) -> void:
	puppets.erase(foe.entity_id)
	foe.alive = false
	foe.collision_layer = 0
	if is_instance_valid(foe.thread): foe.thread.queue_free()
	foe.queue_free()

func take_snapshot(data: Dictionary) -> void:
	if int(data.get("ep", -1)) != epoch or str(data.get("room", "")) != Run.current_room: return
	var tick := int(data.get("t", 0))
	if data.get("pl") is Dictionary:
		for id in data.pl:
			var peer_id := int(id)
			var s = data.pl[id]
			if peer_id == Session.local_peer_id or not s is Dictionary: continue
			states[peer_id] = s
			var member := ensure_member(peer_id)
			member.show_state(s)
	if data.has("rv"):
		revive = data.rv if data.get("rv") is Dictionary else {}
		for id in members:
			members[id].show_revive(float(revive.get(id, 0.0)))
	if data.get("en") is Array:
		for entry in data.en:
			if not entry is Array or entry.size() < 7: continue
			var foe = puppets.get(int(entry[0]))
			if not is_instance_valid(foe): continue
			foe.set_meta("goal", entry[1])
			foe.hp = float(entry[2])
			foe.max_hp = float(entry[3])
			var flags := int(entry[4])
			foe.targetable = flags & 1 != 0
			foe.inert = flags & 2 != 0
			foe.ward_up = flags & 8 != 0
			foe.show_mark_bits((flags >> 4) & 255)
			foe.show_ice(flags & 4096 != 0)
			if is_instance_valid(foe.ward_mesh): foe.ward_mesh.visible = foe.ward_up
			foe.flash = maxf(foe.flash, float(entry[5]))
			var parts: Array = foe.get_meta("net_parts", [])
			for change in entry[6]:
				var index := int(change[0])
				if index < 0 or index >= parts.size() or not is_instance_valid(parts[index]): continue
				if change.size() < 3:
					parts[index].queue_free()
					continue
				parts[index].transform = change[1]
				parts[index].visible = bool(change[2])
	if data.get("ids") is PackedInt32Array:
		var alive := {}
		for id in data.ids: alive[id] = true
		for id in puppets.keys():
			var foe = puppets[id]
			if not is_instance_valid(foe):
				puppets.erase(id)
			elif not alive.has(id) and int(foe.get_meta("born", 0)) < tick:
				drop_puppet(foe)
	if data.get("g") is Array:
		for entry in data.g:
			var node = geo_nodes.get(int(entry[0]))
			if not is_instance_valid(node): continue
			node.transform = entry[1]
			node.visible = bool(entry[2])

## Guest: the host's foes glide to where the host has them.
func update_puppets(delta: float) -> void:
	for foe in puppets.values():
		if not is_instance_valid(foe) or not foe.alive: continue
		var goal = foe.get_meta("goal", foe.position)
		if goal is Vector3:
			foe.position = goal if foe.position.distance_to(goal) > 5.0 else foe.position.lerp(goal, 1.0 - exp(-18.0 * delta))
		foe.show_flash(delta)
		foe.orbital_cooldown -= delta
		if is_instance_valid(foe.thread) and is_instance_valid(foe.twin) and foe.twin.alive:
			DungeonEnemy.stretch(foe.thread, foe.global_position + Vector3.UP * .6, foe.twin.global_position + Vector3.UP * .6)
	game.enemies = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive)

func draw_shot(data) -> void:
	if not data is Array or data.size() < 8 or not data[1] is Vector3 or not data[2] is Vector3: return
	var id := int(data[0])
	if net_shots.has(id) and is_instance_valid(net_shots[id]): return
	var stats: Dictionary = data[6] if data[6] is Dictionary else {}
	var shot: EmberShot = game.make_shot(data[1], data[2], 0.0, float(data[3]), stats, data[4] if data[4] is Color else Color.WHITE, bool(data[5]))
	if shot == null: return
	if bool(data[5]): cast_heard(int(data[7]), data[1])
	shot.cosmetic = true
	shot.net_id = id
	shot.owner_peer = int(data[7])
	net_shots[id] = shot

## A teammate's casting, heard where they stand: once per volley.
func cast_heard(peer_id: int, at: Vector3) -> void:
	if peer_id == Session.local_peer_id or clock - float(heard_cast.get(peer_id, -1.0)) < .09: return
	heard_cast[peer_id] = clock
	# Each device hears its own; this sound is never relayed.
	var was := recording
	recording = 0
	Audio.play_at("shoot", game, at, 1.05)
	recording = was

func make_geo(data) -> void:
	if not data is Array or data.size() < 4 or not data[2] is Array or not data[3] is Array: return
	var parent := resolve_parent(data[2])
	if parent == null: return
	var args: Array = data[3]
	var node: Node3D
	geo_paused += 1
	match str(data[1]):
		"box": node = Geo.box(parent, args[0], args[1], args[2], float(args[3]))
		"sphere": node = Geo.sphere(parent, args[0], float(args[1]), args[2], float(args[3]))
		"cylinder": node = Geo.cylinder(parent, args[0], float(args[1]), float(args[2]), args[3], float(args[4]), float(args[5]))
		"ring": node = Geo.ring(parent, args[0], float(args[1]), args[2], float(args[3]))
		"halo": node = Geo.halo(parent, args[0], float(args[1]), args[2])
		"glow_box": node = Geo.glow_box(parent, args[0], args[1], args[2])
		"light": node = Geo.light(parent, args[0], args[1], float(args[2]), float(args[3]), bool(args[4]))
	geo_paused -= 1
	if node:
		node.set_meta("net_geo", int(data[0]))
		geo_nodes[int(data[0])] = node

# ---------------------------------------------------------------- the HUD

func update_notice() -> void:
	notice = ""
	if downed:
		notice = "You have fallen · a friend can rekindle you"
		return
	var corridors: CorridorTransit = game.corridors
	if waiting_at_stair:
		var standing := standing_peers()
		var ready := standing.filter(func(id): return id == Session.local_peer_id or bool(states.get(id, {}).get("stair", false)) or at_stair.has(id)).size()
		notice = "Waiting at the stair · %d / %d" % [ready, standing.size()]
	elif corridors.coop_held:
		var names: Array = []
		for id in standing_peers():
			if id == Session.local_peer_id: continue
			var s: Dictionary = states.get(id, {})
			if str(s.get("cor", "")) != corridors.portal_id or not bool(s.get("walk", false)): names.append(Session.name_of(id))
		notice = "Waiting for %s" % ", ".join(names) if not names.is_empty() else "The party gathers"
