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

var port := DEFAULT_PORT
var join_ip := "127.0.0.1"
var course_seed := 20260816
var backend := Backend.ENET
## Peer id -> seat 0..7, assigned in join order. Host is always seat 0.
var seats: Dictionary = {}
var _active := false
var _hosting := false


func is_active() -> bool:
	return _active


func is_host() -> bool:
	return _active and _hosting


func should_simulate(node: Node) -> bool:
	if not _active:
		return true
	return node.is_multiplayer_authority()


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
func host(p_port: int = DEFAULT_PORT) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p_port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	port = p_port
	_bind_peer(peer, true, Backend.ENET)
	_assign_seat(multiplayer.get_unique_id())
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
	return OK


## Opens a Steam lobby and hosts on it. Steam answers on a callback, so callers
## must await this. The lobby owner is always Godot peer 1.
func host_steam() -> Error:
	close()
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
	backend = Backend.ENET
	peers_changed.emit()


func start_match() -> void:
	if not is_host():
		return
	_begin_match.rpc(course_seed, int(GameSettings.difficulty), seats)


@rpc("authority", "call_local", "reliable")
func _begin_match(seed: int, difficulty: int, p_seats: Dictionary) -> void:
	course_seed = seed
	seats = p_seats.duplicate()
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	GameSettings.difficulty = difficulty as GameSettings.Kind
	match_starting.emit()
	get_tree().change_scene_to_file(MATCH_SCENE)


func quit_to_menu() -> void:
	close()
	GameSettings.reset()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(TITLE_SCENE)


func _bind_peer(peer: MultiplayerPeer, hosting: bool, p_backend: Backend) -> void:
	_hosting = hosting
	_active = true
	backend = p_backend
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not hosting:
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connect_failed)
		multiplayer.server_disconnected.connect(_on_server_lost)


func _on_peer_connected(id: int) -> void:
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
	_active = true
	peers_changed.emit()


func _on_connect_failed() -> void:
	close()
	disconnected.emit("Could not reach the host.")


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
