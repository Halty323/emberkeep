extends Node
## Offline transport boundary. No credentials, accounts or fake online scores.
## Gameplay state has one authority; a future ENet transport can supply commands
## here and replicate snapshots. Save data is versioned separately from transport.
signal command_received(peer_id: int, command: Dictionary)
signal snapshot_ready(snapshot: Dictionary)
const PROTOCOL_VERSION := 1
var local_peer_id = 1
var online = false
var tick = 0

func is_authority() -> bool:
	return not online or multiplayer.is_server()

func submit(command: Dictionary) -> void:
	command_received.emit(local_peer_id, command)

func publish(snapshot: Dictionary) -> void:
	if is_authority():
		tick += 1
		snapshot["protocol"] = PROTOCOL_VERSION
		snapshot["tick"] = tick
		snapshot_ready.emit(snapshot)
