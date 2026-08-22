extends Node
## The only file that talks to Steam. Owns init, callbacks, lobby membership,
## and Steam-backed peers. NetSession drives it; nothing else should touch it.

signal lobby_error(reason: String)
signal members_changed()
signal invite_accepted(lobby_id: int)
## Fires once per create/join attempt, from either a callback or the timeout.
signal _settled(lobby_id: int)

## Valve's public test app. Real builds pass their own id to start_up().
const DEV_APP_ID := 480
## Steam answers createLobby/joinLobby on a callback, so every wait is bounded.
const SETTLE_SECONDS := 10.0
const SEAT_KEY := "golf_zombies"

var lobby_id := 0
var app_id := DEV_APP_ID
## Set when Steam launched us straight into an invite, before any UI exists.
var pending_invite := 0
var _started := false
var _pending := false
var _callbacks_hooked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not is_available():
		return
	## Do not init Steam on boot. App 480 makes the Mac Steam client exit as
	## soon as it finishes login. Invites still start Steam because they cannot
	## work without it.
	_join_from_command_line()
	if pending_invite != 0:
		start_up()


func _process(_delta: float) -> void:
	if _started:
		Steam.run_callbacks()


## True when the GodotSteam extension is present at all.
func is_available() -> bool:
	return ClassDB.class_exists("SteamMultiplayerPeer") and Engine.has_singleton("Steam")


## True when Steam is present, running, and initialised. Guards every call.
func is_online() -> bool:
	return _started


## Spacewar (480) can still bounce the Mac Steam client. We still offer Steam
## hosting so two machines can try invites; LAN stays the fallback.
func can_host() -> bool:
	return is_available()


## True when the Steam process is up. Used so tests never call steamInit.
func is_client_running() -> bool:
	return is_available() and Steam.has_method("isSteamRunning") and Steam.isSteamRunning()


func start_up(p_app_id: int = DEV_APP_ID) -> bool:
	if _started:
		return true
	if not is_available():
		return false
	app_id = p_app_id
	OS.set_environment("SteamAppId", str(app_id))
	OS.set_environment("SteamGameId", str(app_id))
	if Steam.has_method("isSteamRunning") and not Steam.isSteamRunning():
		push_warning("Steam init skipped: the Steam client is not running.")
		return false
	## Do not pass the app id into steamInitEx — some builds call
	## RestartAppIfNecessary, which closes Steam when Spacewar cannot launch.
	var result: Dictionary = Steam.steamInitEx()
	if int(result.get("status", -1)) != Steam.STEAM_API_INIT_RESULT_OK:
		push_warning("Steam init failed: %s" % result.get("verbal", "unknown"))
		return false
	_started = true
	_connect_callbacks()
	print("[steam] ready as %s (%d)" % [Steam.getPersonaName(), Steam.getSteamID()])
	return true


func steam_id() -> int:
	if not _started:
		return 0
	return Steam.getSteamID()


func lobby_owner_id() -> int:
	if not _started or lobby_id == 0:
		return 0
	return Steam.getLobbyOwner(lobby_id)


func is_lobby_owner() -> bool:
	var owner := lobby_owner_id()
	return owner != 0 and owner == steam_id()


func members() -> PackedInt64Array:
	var ids: PackedInt64Array = PackedInt64Array()
	if not _started or lobby_id == 0:
		return ids
	for index in Steam.getNumLobbyMembers(lobby_id):
		ids.append(Steam.getLobbyMemberByIndex(lobby_id, index))
	return ids


## Creates a friends-only lobby. Returns the id, or 0 if it did not happen.
func create_lobby(max_players: int) -> int:
	if not _await_ready():
		return 0
	print("[steam] creating friends lobby")
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, maxi(max_players, 2))
	var id: int = await _settle_wait()
	if id != 0:
		Steam.setLobbyData(id, SEAT_KEY, "1")
		print("[steam] lobby %d open" % id)
	return id


## Joins an existing lobby. Returns the id, or 0 if it did not happen.
func join_lobby(id: int) -> int:
	if not _await_ready():
		return 0
	if id == 0:
		lobby_error.emit("That lobby is no longer open.")
		return 0
	Steam.joinLobby(id)
	return await _settle_wait()


func leave_lobby() -> void:
	if _started and lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0


func open_invite_overlay() -> void:
	if _started and lobby_id != 0:
		Steam.activateGameOverlayInviteDialog(lobby_id)


func _await_ready() -> bool:
	if not _started:
		lobby_error.emit("Steam is not running.")
		return false
	if _pending:
		lobby_error.emit("Still waiting on Steam.")
		return false
	leave_lobby()
	return true


## Waits for the matching Steam callback, but never longer than SETTLE_SECONDS.
func _settle_wait() -> int:
	_pending = true
	get_tree().create_timer(SETTLE_SECONDS).timeout.connect(_on_settle_timeout)
	return await _settled


func _settle(id: int, reason: String) -> void:
	if not _pending:
		return
	_pending = false
	lobby_id = id
	if id == 0:
		lobby_error.emit(reason)
	_settled.emit(id)


func _on_settle_timeout() -> void:
	_settle(0, "Steam did not answer in time.")


func _connect_callbacks() -> void:
	if _callbacks_hooked or not is_available():
		return
	_callbacks_hooked = true
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.join_requested.connect(_on_join_requested)


func _on_lobby_created(connect_result: int, id: int) -> void:
	if connect_result != 1:
		_settle(0, "Steam could not open a lobby.")
		return
	_settle(id, "")


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_settle(0, "Could not enter that lobby.")
		return
	_settle(id, "")


func _on_lobby_chat_update(id: int, _changed: int, _by: int, _state: int) -> void:
	if id == lobby_id:
		members_changed.emit()


func _on_join_requested(id: int, _friend_id: int) -> void:
	_offer_invite(id)


## Steam launches the game with +connect_lobby <id> when an invite is accepted
## while the game is closed.
func _join_from_command_line() -> void:
	var args := OS.get_cmdline_args()
	var slot := args.find("+connect_lobby")
	if slot == -1 or slot + 1 >= args.size():
		return
	_offer_invite(args[slot + 1].to_int())


## Parks the invite as well as announcing it, because a cold start lands here
## before any menu exists to hear the signal.
func _offer_invite(id: int) -> void:
	if id == 0:
		return
	pending_invite = id
	invite_accepted.emit(id)


## Hands back a waiting invite once, then forgets it.
func take_pending_invite() -> int:
	var id := pending_invite
	pending_invite = 0
	return id


## Builds the host peer. Returns null when Steam cannot supply one.
func create_host_peer() -> MultiplayerPeer:
	if not _started or lobby_id == 0:
		return null
	print("[steam] opening host peer")
	var peer := SteamMultiplayerPeer.new()
	if peer.create_host(0) != OK:
		push_warning("Steam host peer failed")
		return null
	peer.server_relay = true
	return peer


## Builds a client peer aimed at the lobby owner. Refuses when we are the owner,
## since that would put two hosts on one lobby.
func create_client_peer() -> MultiplayerPeer:
	var owner := lobby_owner_id()
	if not _started or owner == 0 or owner == steam_id():
		return null
	var peer := SteamMultiplayerPeer.new()
	if peer.create_client(owner, 0) != OK:
		return null
	peer.server_relay = true
	return peer
