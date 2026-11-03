extends Node
## The transport boundary. Alone, commands go straight to the game and nothing
## leaves the device. In co-op one player hosts a party on the local network
## (ENet) and up to three others join it; the host runs the foes and the shared
## world, and every player keeps their own hero, health, wallet and loot.
## Every message carries a kind and a payload; the host checks who sent it.
signal command_received(peer_id: int, command: Dictionary)
signal snapshot_ready(snapshot: Dictionary)
signal roster_changed
signal message_received(from: int, kind: String, data)
signal session_ended(reason: String)
signal parties_changed
# 2: LAN co-op. A different protocol or content revision cannot join.
const PROTOCOL_VERSION := 2
const GAME_PORT := 47620
const MAX_PLAYERS := 4
const SLOT_COLORS := [Color("ffcf86"), Color("8fd6ff"), Color("b6f0a0"), Color("f2a6e6")]
var local_peer_id = 1
var online = false
var hosting = false
var tick = 0
# peer id -> {"name", "slot", "weapon"}; the host is always slot 0.
var roster: Dictionary = {}
var local_name := ""
var local_weapon := ""
# Host: the climb has begun, so the party is closed to newcomers.
var started := false
# "connecting" while a join is pending, "party" once in a party.
var status := ""
var host_address := ""
var discovery := LanDiscovery.new()
# Parties heard on the network: "ip" -> {"name", "count", "max", "open", "address", "port", "seen"}.
var parties: Dictionary = {}
var peer: ENetMultiplayerPeer
var refusals: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)

func _exit_tree() -> void:
	discovery.stop()
	if online: close_peer()

func is_authority() -> bool:
	return not online or hosting

func submit(command: Dictionary) -> void:
	command_received.emit(local_peer_id, command)

func publish(snapshot: Dictionary) -> void:
	if is_authority():
		tick += 1
		snapshot["protocol"] = PROTOCOL_VERSION
		snapshot["tick"] = tick
		snapshot_ready.emit(snapshot)

## Opens a party on this device. Returns an empty string or why it failed.
func host_party(player_name: String, weapon: String, port := GAME_PORT) -> String:
	leave_party()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		peer = null
		return "Could not open a party on port %d" % port
	multiplayer.multiplayer_peer = peer
	online = true
	hosting = true
	started = false
	status = "party"
	local_peer_id = 1
	local_name = clean_name(player_name)
	local_weapon = weapon
	roster = {1: {"name": local_name, "slot": 0, "weapon": weapon}}
	host_address = ""
	discovery.start_host(announcement)
	roster_changed.emit()
	return ""

## Joins a party by address. The answer comes back as roster_changed (in)
## or session_ended (refused, unreachable).
func join_party(address: String, player_name: String, weapon: String, port := GAME_PORT) -> String:
	leave_party()
	address = address.strip_edges()
	if address.is_empty(): return "Enter the host's address"
	if ":" in address and address.count(":") == 1:
		port = int(address.get_slice(":", 1))
		address = address.get_slice(":", 0)
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		peer = null
		return "Could not reach %s" % address
	multiplayer.multiplayer_peer = peer
	online = true
	hosting = false
	status = "connecting"
	local_name = clean_name(player_name)
	local_weapon = weapon
	host_address = address
	roster = {}
	return ""

## Leaves (or, as host, closes) the party. Safe to call when offline.
func leave_party(reason := "") -> void:
	discovery.stop()
	var was_online: bool = online
	if online: close_peer()
	online = false
	hosting = false
	started = false
	status = ""
	roster = {}
	local_peer_id = 1
	if was_online and reason != "": session_ended.emit(reason)

func close_peer() -> void:
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer = null

func clean_name(value: String) -> String:
	value = value.strip_edges().replace("\n", " ")
	if value.is_empty(): value = "Little light"
	return value.substr(0, 18)

func slot_of(peer_id: int) -> int:
	return int(roster.get(peer_id, {}).get("slot", -1))

func local_slot() -> int:
	return maxi(0, slot_of(local_peer_id))

func name_of(peer_id: int) -> String:
	return str(roster.get(peer_id, {}).get("name", "A little light"))

func color_of(peer_id: int) -> Color:
	return SLOT_COLORS[posmod(slot_of(peer_id), SLOT_COLORS.size())]

## Every player in the party, the host first.
func peers() -> Array:
	var ids: Array = roster.keys()
	ids.sort_custom(func(a, b): return slot_of(a) < slot_of(b))
	return ids

func others() -> Array:
	return peers().filter(func(id): return id != local_peer_id)

## Reliable, ordered delivery. `to` is a peer id, or 0 for everyone else.
func send(to: int, kind: String, data = null) -> void:
	if not online or peer == null: return
	if to == 0: _deliver.rpc(kind, data)
	elif to != local_peer_id: _deliver.rpc_id(to, kind, data)

## Frequent state that the next update replaces: unreliable and ordered.
func stream(to: int, kind: String, data = null) -> void:
	if not online or peer == null: return
	if to == 0: _stream.rpc(kind, data)
	elif to != local_peer_id: _stream.rpc_id(to, kind, data)

@rpc("any_peer", "call_remote", "reliable", 0)
func _deliver(kind: String, data) -> void:
	receive(multiplayer.get_remote_sender_id(), kind, data)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _stream(kind: String, data) -> void:
	receive(multiplayer.get_remote_sender_id(), kind, data)

func receive(from: int, kind: String, data) -> void:
	if not online: return
	# A guest takes orders from the host only.
	if not hosting and from != 1: return
	match kind:
		"hello": if hosting: welcome(from, data)
		"roster": if not hosting: take_roster(data)
		"refused": if not hosting: leave_party(str(data))
		"weapon":
			if hosting and roster.has(from) and data is String:
				roster[from].weapon = data
				share_roster()
		_:
			# The host only hears guests who have been let in.
			if hosting and not roster.has(from): return
			message_received.emit(from, kind, data)

## The handshake: protocol and content revision must match, and the party
## must have room and not have started climbing.
func welcome(from: int, data) -> void:
	var problem := admission(data)
	if problem != "":
		refuse(from, problem)
		return
	var used: Array = roster.values().map(func(entry): return int(entry.slot))
	var slot := 1
	while slot in used: slot += 1
	roster[from] = {"name": clean_name(str(data.get("name", ""))), "slot": slot, "weapon": str(data.get("weapon", ""))}
	share_roster()

## Why a guest with this hello may not join, or an empty string.
func admission(data) -> String:
	if not data is Dictionary: return "That is not an Emberkeep party"
	if int(data.get("protocol", -1)) != PROTOCOL_VERSION: return "This party plays a different version of Emberkeep"
	if str(data.get("revision", "")) != Content.revision: return "This party's tower was built from different content"
	if started: return "This party is already climbing"
	if roster.size() >= MAX_PLAYERS: return "This party is full"
	return ""

func refuse(from: int, reason: String) -> void:
	send(from, "refused", reason)
	refusals[from] = Time.get_ticks_msec() + 400

func share_roster() -> void:
	send(0, "roster", roster)
	roster_changed.emit()

func take_roster(data) -> void:
	if not data is Dictionary: return
	roster = {}
	for id in data: roster[int(id)] = data[id]
	if status == "connecting" and roster.has(local_peer_id): status = "party"
	roster_changed.emit()

func _on_peer_connected(id: int) -> void:
	if not hosting and id == 1:
		local_peer_id = multiplayer.get_unique_id()
		send(1, "hello", {"protocol": PROTOCOL_VERSION, "revision": Content.revision, "name": local_name, "weapon": local_weapon})

func _on_connected() -> void:
	local_peer_id = multiplayer.get_unique_id()

func _on_peer_disconnected(id: int) -> void:
	if hosting and roster.has(id):
		var who := name_of(id)
		roster.erase(id)
		share_roster()
		message_received.emit(id, "left", who)

func _on_connection_failed() -> void:
	leave_party("Could not reach that party")

func _on_server_gone() -> void:
	leave_party("The host closed the party")

## The host's line in the network's list of parties.
func announcement() -> Dictionary:
	return {"name": local_name, "count": roster.size(), "max": MAX_PLAYERS, "open": not started, "port": GAME_PORT,
		"protocol": PROTOCOL_VERSION, "revision": Content.revision}

func look_for_parties() -> void:
	parties = {}
	discovery.start_seek()

func stop_looking() -> void:
	if not hosting: discovery.stop()

## This device's addresses on the local network, for others to type in.
func local_addresses() -> Array:
	var result: Array = []
	for address in IP.get_local_addresses():
		if LanDiscovery.private_ipv4(address) and address not in result: result.append(address)
	return result

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for id in refusals.keys():
		if now >= refusals[id]:
			refusals.erase(id)
			if peer and hosting: peer.disconnect_peer(id)
	var found := discovery.poll(delta)
	if found.is_empty() and not discovery.seeking: return
	var changed := false
	for entry in found:
		if int(entry.get("protocol", -1)) != PROTOCOL_VERSION: continue
		var key := "%s:%d" % [entry.address, int(entry.port)]
		var before: Dictionary = parties.get(key, {})
		changed = changed or before.is_empty() or before.get("count") != entry.get("count") or before.get("open") != entry.get("open") or before.get("name") != entry.get("name")
		entry["seen"] = now
		entry["same_content"] = str(entry.get("revision", "")) == Content.revision
		parties[key] = entry
	for key in parties.keys():
		if now - int(parties[key].seen) > 4500:
			parties.erase(key)
			changed = true
	# Rebuilt only when the list itself changes, never while someone types.
	if changed: parties_changed.emit()
