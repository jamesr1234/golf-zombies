extends Node
## Listen-server session for online VS. Survives scene changes so the peer stays
## up from the lobby into the match. Steam is the shipping transport; ENet stays
## for LAN and solo testing. Peer construction lives in SteamLobby for Steam and
## here for ENet; everything past _bind_peer() is transport-agnostic.

signal peers_changed()
signal match_starting()
signal disconnected(reason: String)

enum Backend { ENET, STEAM }

const MAX_PLAYERS := 8
const DEFAULT_PORT := 7777
const MATCH_SCENE := "res://scenes/net/online_main.tscn"
const TITLE_SCENE := "res://scenes/ui/main_menu.tscn"
const JOIN_SECONDS := 25.0

var port := DEFAULT_PORT
var join_ip := "127.0.0.1"
var course_seed := 20260816
var backend := Backend.ENET
## Peer id -> seat 0..7, assigned in join order. Host is always seat 0.
var seats: Dictionary = {}
var _active := false
var _hosting := false
var _connecting := false


func is_active() -> bool:
	return _active


func is_connecting() -> bool:
	return _connecting


func wire_count() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	if is_host():
		return 1 + multiplayer.get_peers().size()
	return 1 if _active else 0


func is_host() -> bool:
	return _active and _hosting


func should_simulate(node: Node) -> bool:
	if not _active:
		return true
	return node.is_multiplayer_authority()


## World effects (damage, projectiles, the hole clock) run on the host.
func defers_world() -> bool:
	return should_defer_world(_active, multiplayer.is_server())


static func should_defer_world(active: bool, is_server: bool) -> bool:
	return active and not is_server


func peer_ids() -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array(seats.keys())
	ids.sort()
	return ids


func player_count() -> int:
	return seats.size()


func seat_for(peer_id: int) -> int:
	return int(seats.get(peer_id, -1))


func color_for(peer_id: int) -> Color:
	return Palette.seat_color(seat_for(peer_id))


func is_steam() -> bool:
	return backend == Backend.STEAM


## LAN and solo testing. Steam cannot easily run two clients on one machine.
func _nudge_local_network() -> void:
	var udp := PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	udp.set_dest_address("255.255.255.255", port)
	udp.put_packet("golf-zombies".to_utf8_buffer())
	udp.close()


func lan_addresses() -> PackedStringArray:
	var found: PackedStringArray = []
	for address in IP.get_local_addresses():
		if address.contains(":"):
			continue
		if address.begins_with("127.") or address.begins_with("169.254."):
			continue
		found.append(address)
	return found


func host(p_port: int = DEFAULT_PORT) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	## macOS turns "*" into an IPv6-only socket. Computer 2 joins with
	## 192.168.4.x (IPv4), so the host has to listen on IPv4.
	peer.set_bind_ip("0.0.0.0")
	var err := peer.create_server(p_port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	port = p_port
	_bind_peer(peer, true, Backend.ENET)
	_assign_seat(multiplayer.get_unique_id())
	_nudge_local_network()
	print("[net] hosting on 0.0.0.0:%d  join at %s" % [port, "  ".join(lan_addresses())])
	return OK


func join(ip: String, p_port: int = DEFAULT_PORT) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, p_port)
	if err != OK:
		return err
	join_ip = ip
	port = p_port
	_bind_peer(peer, false, Backend.ENET)
	_nudge_local_network()
	print("[net] joining %s:%d" % [join_ip, port])
	get_tree().create_timer(JOIN_SECONDS).timeout.connect(_on_join_timeout)
	return OK


## Opens a Steam lobby and hosts on it. Steam answers on a callback, so callers
## must await this. The lobby owner is always Godot peer 1.
func host_steam() -> Error:
	close()
	if not SteamLobby.can_host():
		return ERR_UNAVAILABLE
	if not SteamLobby.start_up():
		return ERR_UNAVAILABLE
	if not SteamLobby.is_online():
		return ERR_UNAVAILABLE
	if await SteamLobby.create_lobby(MAX_PLAYERS) == 0:
		return ERR_CANT_CREATE
	var peer := SteamLobby.create_host_peer()
	if peer == null:
		SteamLobby.leave_lobby()
		return ERR_CANT_CREATE
	_bind_peer(peer, true, Backend.STEAM)
	_assign_seat(multiplayer.get_unique_id())
	return OK


## Joins someone else's Steam lobby and connects to its owner. Must be awaited.
func join_steam(lobby_id: int) -> Error:
	close()
	if not SteamLobby.can_host():
		return ERR_UNAVAILABLE
	if not SteamLobby.start_up():
		return ERR_UNAVAILABLE
	if not SteamLobby.is_online():
		return ERR_UNAVAILABLE
	if await SteamLobby.join_lobby(lobby_id) == 0:
		return ERR_CANT_CONNECT
	var peer := SteamLobby.create_client_peer()
	if peer == null:
		SteamLobby.leave_lobby()
		return ERR_CANT_CONNECT
	_bind_peer(peer, false, Backend.STEAM)
	return OK


func close() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.disconnect(_on_connected)
	if multiplayer.connection_failed.is_connected(_on_connect_failed):
		multiplayer.connection_failed.disconnect(_on_connect_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_lost):
		multiplayer.server_disconnected.disconnect(_on_server_lost)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	SteamLobby.leave_lobby()
	seats.clear()
	_active = false
	_hosting = false
	_connecting = false
	backend = Backend.ENET
	OS.low_processor_usage_mode = true
	peers_changed.emit()


func start_match() -> void:
	if not is_host():
		return
	_seat_wired_peers()
	print("[net] start_match seats=%d wire=%d remotes=%s" % [
		seats.size(), wire_count(), multiplayer.get_peers()
	])
	var ids := PackedInt32Array()
	var seat_list := PackedInt32Array()
	for peer_id in peer_ids():
		ids.append(peer_id)
		seat_list.append(seat_for(peer_id))
	## Send each remote a packet, then run locally. Broadcast+call_local can
	## still lose the start if the host is the only one on the wire.
	for peer_id in multiplayer.get_peers():
		_begin_match.rpc_id(peer_id, course_seed, int(GameSettings.difficulty), ids, seat_list)
	_begin_match(course_seed, int(GameSettings.difficulty), ids, seat_list)


@rpc("authority", "call_local", "reliable")
func _begin_match(
	seed: int, difficulty: int, ids: PackedInt32Array, seat_list: PackedInt32Array
) -> void:
	course_seed = seed
	seats.clear()
	for i in ids.size():
		seats[ids[i]] = seat_list[i] if i < seat_list.size() else i
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	GameSettings.difficulty = difficulty as GameSettings.Kind
	match_starting.emit()
	## Changing scenes in this same call drops the outgoing start packet on the
	## host, so the joiner never leaves the lobby.
	call_deferred("_enter_match")


func _enter_match() -> void:
	if not _active:
		return
	get_tree().change_scene_to_file(MATCH_SCENE)


func quit_to_menu() -> void:
	close()
	GameSettings.reset()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(TITLE_SCENE)


func _bind_peer(peer: MultiplayerPeer, hosting: bool, p_backend: Backend) -> void:
	_hosting = hosting
	_active = hosting
	_connecting = not hosting
	backend = p_backend
	OS.low_processor_usage_mode = false
	get_tree().get_multiplayer().multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not hosting:
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connect_failed)
		multiplayer.server_disconnected.connect(_on_server_lost)
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_on_connected()


func _on_peer_connected(id: int) -> void:
	print("[net] peer %d connected  seats=%d wire=%d" % [id, seats.size(), wire_count()])
	if is_host():
		if seats.size() >= MAX_PLAYERS:
			multiplayer.multiplayer_peer.disconnect_peer(id)
			return
		_assign_seat(id)
		_sync_seats.rpc(seats)
	peers_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	seats.erase(id)
	if is_host():
		_sync_seats.rpc(seats)
	peers_changed.emit()


func _on_connected() -> void:
	_connecting = false
	_active = true
	print("[net] connected to host as peer %d" % multiplayer.get_unique_id())
	peers_changed.emit()


## Silence and a refusal mean different things, so they must not read the same.
## Nothing at all points outside the game: macOS or the router ate the packets.
func _on_join_timeout() -> void:
	if _connecting:
		_fail("No reply from %s.  UDP is being blocked." % join_ip)


func _seat_wired_peers() -> void:
	_assign_seat(multiplayer.get_unique_id())
	for peer_id in multiplayer.get_peers():
		_assign_seat(peer_id)


func _on_connect_failed() -> void:
	_fail("The host refused the connection.")


func _fail(reason: String) -> void:
	print("[net] join failed: %s" % reason)
	close()
	disconnected.emit(reason)


func _on_server_lost() -> void:
	close()
	disconnected.emit("Host left.")
	get_tree().change_scene_to_file(TITLE_SCENE)


func _assign_seat(peer_id: int) -> void:
	if seats.has(peer_id):
		return
	var used: Array = seats.values()
	for seat in MAX_PLAYERS:
		if not used.has(seat):
			seats[peer_id] = seat
			return


@rpc("authority", "call_remote", "reliable")
func _sync_seats(p_seats: Dictionary) -> void:
	seats = p_seats.duplicate()
	peers_changed.emit()
