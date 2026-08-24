extends GutTest
## The Steam session layer. These run with Steam closed, so every case here is
## the offline path: nothing may crash, and the ENet backend must stay default.

const STEAM_OWNER := "res://scripts/net/steam_lobby.gd"
const FREE_PORT := 47771


func after_each() -> void:
	NetSession.close()
	NetSession.seats.clear()
	SteamLobby.pending_invite = 0
	GameSettings.reset()


func test_a_lobby_id_is_only_digits() -> void:
	assert_eq(SteamLobby.parse_lobby_id(""), 0)
	assert_eq(SteamLobby.parse_lobby_id("192.168.4.85"), 0, "a LAN IP is not a lobby")
	assert_eq(SteamLobby.parse_lobby_id(" 109775241 "), 109775241)


func test_an_invite_survives_until_a_screen_picks_it_up() -> void:
	assert_eq(SteamLobby.take_pending_invite(), 0, "nothing is waiting by default")
	SteamLobby.pending_invite = 99
	assert_eq(SteamLobby.take_pending_invite(), 99, "a cold-start invite is not lost")
	assert_eq(SteamLobby.take_pending_invite(), 0, "and it is only handed out once")


func test_a_session_starts_on_enet() -> void:
	assert_eq(NetSession.backend, NetSession.Backend.ENET)
	assert_true(
		(NetSession.get_script() as GDScript).is_tool(),
		"@tool course props must be able to call is_active in the editor"
	)
	assert_false(NetSession.is_steam())
	assert_false(NetSession.is_active())


func test_closing_resets_the_whole_session() -> void:
	NetSession.seats[1] = 0
	NetSession.seats[7] = 1
	NetSession.backend = NetSession.Backend.STEAM
	NetSession.close()
	assert_eq(NetSession.seats.size(), 0)
	assert_false(NetSession.is_active())
	assert_false(NetSession.is_host())
	assert_eq(NetSession.backend, NetSession.Backend.ENET, "close falls back to ENet")
	assert_is(multiplayer.multiplayer_peer, OfflineMultiplayerPeer)


func test_steam_queries_are_safe_while_offline() -> void:
	if SteamLobby.is_online():
		pass_test("Steam is running, offline guards do not apply.")
		return
	assert_eq(SteamLobby.steam_id(), 0)
	assert_eq(SteamLobby.lobby_owner_id(), 0)
	assert_false(SteamLobby.is_lobby_owner())
	assert_eq(SteamLobby.members().size(), 0)
	assert_null(SteamLobby.create_host_peer())
	assert_null(SteamLobby.create_client_peer())
	SteamLobby.leave_lobby()
	assert_eq(SteamLobby.open_invite_overlay(), "Host on Steam first.")
	assert_eq(SteamLobby.invite_online_friends().size(), 0)
	assert_eq(SteamLobby.online_friend_names().size(), 0)
	assert_eq(SteamLobby.friend_count(), 0)
	assert_eq(SteamLobby.lobby_id, 0)


func test_hosting_on_steam_refuses_when_steam_is_down() -> void:
	if SteamLobby.is_online() or SteamLobby.is_client_running():
		pass_test("Steam is running, so hosting is expected to work.")
		return
	var err: Error = await NetSession.host_steam()
	assert_eq(err, ERR_UNAVAILABLE)
	assert_false(NetSession.is_active())
	assert_eq(NetSession.backend, NetSession.Backend.ENET)


func test_joining_on_steam_refuses_when_steam_is_down() -> void:
	if SteamLobby.is_online() or SteamLobby.is_client_running():
		pass_test("Steam is running, so joining is expected to work.")
		return
	var err: Error = await NetSession.join_steam(12345)
	assert_eq(err, ERR_UNAVAILABLE)
	assert_false(NetSession.is_active())


func test_play_does_not_init_steam() -> void:
	assert_false(SteamLobby.is_online(), "Play must not init Steam on boot")
	assert_eq(SteamLobby.can_host(), SteamLobby.is_available())


func test_lan_addresses_skip_loopback() -> void:
	for address in NetSession.lan_addresses():
		assert_false(address.begins_with("127."), address)
		assert_false(address.contains(":"), address)


func test_a_watching_mac_stays_awake_but_headless_does_not() -> void:
	assert_true(NetSession.holds_system_awake("macOS", "macos", true))
	assert_false(NetSession.holds_system_awake("macOS", "headless", true), "GUT must not spawn caffeinate")
	assert_false(NetSession.holds_system_awake("Windows", "windows", true))
	assert_false(NetSession.holds_system_awake("macOS", "macos", false), "the menu may nap")


func test_a_live_session_does_not_sleep() -> void:
	var err := NetSession.host(FREE_PORT)
	assert_eq(err, OK)
	assert_false(OS.low_processor_usage_mode, "Computer 2 froze after a stretch of no input")
	NetSession.close()
	assert_true(OS.low_processor_usage_mode, "the title screen can sleep again")


func test_a_lan_host_keeps_the_enet_backend() -> void:
	var err := NetSession.host(FREE_PORT)
	assert_eq(err, OK, "the LAN path still works alongside Steam")
	assert_true(NetSession.is_host())
	assert_false(NetSession.is_steam())
	assert_eq(NetSession.seat_for(multiplayer.get_unique_id()), 0, "the host takes seat 0")
	assert_eq(NetSession.wire_count(), 1, "a host with no remotes is only on the wire alone")


func test_a_join_is_not_connected_until_the_handshake() -> void:
	var err := NetSession.join("127.0.0.1", FREE_PORT + 1)
	assert_eq(err, OK)
	assert_true(NetSession.is_connecting(), "create_client is not a finished join")
	assert_false(NetSession.is_active())
	assert_false(NetSession.is_host())
	NetSession.close()
	assert_false(NetSession.is_connecting())


## The handoff contract: Steam stays behind one door so the gameplay phase can
## never wire a second transport by accident. Matches real calls only, so prose
## like "Hosting on Steam." in UI copy does not trip it.
func test_only_steam_lobby_touches_the_steam_api() -> void:
	var api := RegEx.new()
	api.compile("\\bSteam\\.[A-Za-z_]|\\bSteamMultiplayerPeer\\b")
	var strays: PackedStringArray = []
	for path in _scripts_under("res://scripts"):
		if path == STEAM_OWNER:
			continue
		if api.search(FileAccess.get_file_as_string(path)) != null:
			strays.append(path)
	assert_eq(
		"  ".join(strays), "", "only steam_lobby.gd may call Steam directly"
	)


func test_only_net_session_binds_a_peer() -> void:
	var strays: PackedStringArray = []
	for path in _scripts_under("res://scripts"):
		var body := FileAccess.get_file_as_string(path)
		if body.contains("multiplayer_peer =") and not path.ends_with("net_session.gd"):
			strays.append(path)
	assert_eq("  ".join(strays), "", "only net_session.gd may bind a peer")


func _scripts_under(root: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := "%s/%s" % [root, entry]
		if dir.current_is_dir():
			found.append_array(_scripts_under(path))
		elif entry.ends_with(".gd"):
			found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
