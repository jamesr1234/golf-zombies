class_name LanProbe
extends Node
## Raw UDP round trip, deliberately kept away from ENet. It answers one question:
## can these two machines pass a UDP packet at all? A silent probe while the
## firewall already allows Godot means the packets die outside the game, so no
## netcode change will help. It listens one port above the game so a running
## match is never disturbed.

signal answered(from_ip: String)
signal gave_up()

const PROBE := "gz-ping"
const REPLY := "gz-pong"

## Shortened by tests so the give-up case does not stall a run.
var wait_seconds := 3.0
var _server: PacketPeerUDP
var _client: PacketPeerUDP
var _waited := 0.0


static func probe_port(port: int) -> int:
	return port + 1


func _exit_tree() -> void:
	stop_serving()
	_stop_client()


func _process(delta: float) -> void:
	_pump_server()
	_pump_client(delta)


func is_serving() -> bool:
	return _server != null


func is_probing() -> bool:
	return _client != null


## Hosts answer probes for as long as they hold the lobby.
func serve(port: int) -> Error:
	stop_serving()
	var socket := PacketPeerUDP.new()
	var err := socket.bind(probe_port(port), "0.0.0.0")
	if err != OK:
		return err
	_server = socket
	return OK


func stop_serving() -> void:
	if _server != null:
		_server.close()
		_server = null


## Joiners fire one packet and wait. Answers arrive on answered, silence on gave_up.
func probe(ip: String, port: int) -> Error:
	_stop_client()
	var socket := PacketPeerUDP.new()
	var err := socket.bind(0, "0.0.0.0")
	if err != OK:
		return err
	socket.set_dest_address(ip, probe_port(port))
	err = socket.put_packet(PROBE.to_utf8_buffer())
	if err != OK:
		socket.close()
		return err
	_client = socket
	_waited = 0.0
	return OK


func _stop_client() -> void:
	if _client != null:
		_client.close()
		_client = null


func _pump_server() -> void:
	if _server == null:
		return
	while _server.get_available_packet_count() > 0:
		var body := _server.get_packet().get_string_from_utf8()
		if body != PROBE:
			continue
		_server.set_dest_address(_server.get_packet_ip(), _server.get_packet_port())
		_server.put_packet(REPLY.to_utf8_buffer())


func _pump_client(delta: float) -> void:
	if _client == null:
		return
	while _client.get_available_packet_count() > 0:
		var body := _client.get_packet().get_string_from_utf8()
		var from := _client.get_packet_ip()
		if body != REPLY:
			continue
		_stop_client()
		answered.emit(from)
		return
	_waited += delta
	if _waited < wait_seconds:
		return
	_stop_client()
	gave_up.emit()
