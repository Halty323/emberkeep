class_name LanDiscovery
extends RefCounted
## Finding parties on the local network without typing an address. A host
## answers queries on QUERY_PORT and also announces itself on ANNOUNCE_PORT
## every second; a guest listens for announcements and asks with a broadcast
## query, which the host answers directly. Phones often filter broadcasts
## they receive, so the direct answer is what usually finds a phone's host;
## when neither gets through, the guest types the host's address instead.
const QUERY_PORT := 47621
const ANNOUNCE_PORT := 47622
const MAGIC := "emberkeep"
const INTERVAL := 1.0
var listener: PacketPeerUDP
var seeker: PacketPeerUDP
var info: Callable
var hosting := false
var seeking := false
var timer := 0.0

func start_host(describe: Callable) -> void:
	stop()
	info = describe
	hosting = true
	listener = PacketPeerUDP.new()
	listener.set_broadcast_enabled(true)
	# Another program, or a second copy of the game, may hold the port; the
	# party still works by address.
	if listener.bind(QUERY_PORT) != OK:
		listener = PacketPeerUDP.new()
		listener.set_broadcast_enabled(true)
		listener.bind(0)
	timer = 0.0

func start_seek() -> void:
	stop()
	seeking = true
	seeker = PacketPeerUDP.new()
	seeker.set_broadcast_enabled(true)
	if seeker.bind(ANNOUNCE_PORT) != OK:
		seeker = PacketPeerUDP.new()
		seeker.set_broadcast_enabled(true)
		seeker.bind(0)
	timer = 0.0

func stop() -> void:
	if listener: listener.close()
	if seeker: seeker.close()
	listener = null
	seeker = null
	hosting = false
	seeking = false

## Called every frame; returns the parties heard since the last call.
func poll(delta: float) -> Array:
	var found: Array = []
	timer -= delta
	if hosting and listener:
		while listener.get_available_packet_count() > 0:
			var packet := listener.get_packet()
			var ip := listener.get_packet_ip()
			var port := listener.get_packet_port()
			var asked = parse(packet)
			if asked is Dictionary and asked.has("query") and ip != "":
				listener.set_dest_address(ip, port)
				listener.put_packet(encode(info.call()))
		if timer <= 0:
			timer = INTERVAL
			var payload := encode(info.call())
			for address in broadcast_addresses():
				listener.set_dest_address(address, ANNOUNCE_PORT)
				listener.put_packet(payload)
	if seeking and seeker:
		if timer <= 0:
			timer = INTERVAL
			var query := ("%s\n%s" % [MAGIC, JSON.stringify({"query": true})]).to_utf8_buffer()
			for address in broadcast_addresses() + ["127.0.0.1"]:
				seeker.set_dest_address(address, QUERY_PORT)
				seeker.put_packet(query)
		while seeker.get_available_packet_count() > 0:
			var packet := seeker.get_packet()
			var ip := seeker.get_packet_ip()
			var heard = parse(packet)
			if heard is Dictionary and heard.has("name") and ip != "":
				heard["address"] = ip
				found.append(heard)
	return found

static func encode(value: Dictionary) -> PackedByteArray:
	return ("%s\n%s" % [MAGIC, JSON.stringify(value)]).to_utf8_buffer()

static func parse(packet: PackedByteArray):
	if packet.size() > 2048: return null
	var text := packet.get_string_from_utf8()
	if not text.begins_with(MAGIC + "\n"): return null
	return JSON.parse_string(text.substr(MAGIC.length() + 1))

## The limited broadcast address, and each local network's own (assumed /24,
## as home routers hand out).
static func broadcast_addresses() -> Array:
	var result: Array = ["255.255.255.255"]
	for address in IP.get_local_addresses():
		if not private_ipv4(address): continue
		var parts := address.split(".")
		var directed := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if directed not in result: result.append(directed)
	return result

static func private_ipv4(address: String) -> bool:
	var parts := address.split(".")
	if parts.size() != 4: return false
	var a := int(parts[0])
	var b := int(parts[1])
	return a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168)
