class_name LobbyUi
extends Control
## Host or join an 8-player listen-server, then wait for the host to start.

const _Music := preload("res://scripts/fx/music.gd")

var _ip: LineEdit
var _port: LineEdit
var _status: Label
var _list: Label
var _host_btn: Button
var _join_btn: Button
var _steam_btn: Button
var _invite_btn: Button
var _start_btn: Button
var _back_btn: Button
var _test_btn: Button
var _diff: OptionButton
var _probe: LanProbe
var _busy := false
## Holds a failure message so the next _refresh() does not overwrite it.
var _notice := ""


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_probe = LanProbe.new()
	_probe.answered.connect(_on_probe_answered)
	_probe.gave_up.connect(_on_probe_silent)
	add_child(_probe)
	NetSession.peers_changed.connect(_refresh)
	NetSession.disconnected.connect(_on_lost)
	SteamLobby.invite_accepted.connect(_on_invite)
	SteamLobby.lobby_error.connect(_on_lost)
	_Music.play_lounge()
	_refresh()
	_consume_invite()


func _exit_tree() -> void:
	if NetSession.peers_changed.is_connected(_refresh):
		NetSession.peers_changed.disconnect(_refresh)
	if NetSession.disconnected.is_connected(_on_lost):
		NetSession.disconnected.disconnect(_on_lost)
	if SteamLobby.invite_accepted.is_connected(_on_invite):
		SteamLobby.invite_accepted.disconnect(_on_invite)
	if SteamLobby.lobby_error.is_connected(_on_lost):
		SteamLobby.lobby_error.disconnect(_on_lost)


func _host() -> void:
	if _busy:
		return
	_busy = true
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	GameSettings.difficulty = _diff.selected as GameSettings.Kind
	var err := NetSession.host(_port_value())
	_busy = false
	if err == OK:
		_probe.serve(_port_value())
	_settle(err, "Could not host on that port.")


func _join() -> void:
	if _busy:
		return
	_busy = true
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	var err := NetSession.join(_ip.text.strip_edges(), _port_value())
	_busy = false
	_settle(err, "Could not join.")


func _host_steam() -> void:
	if _busy:
		return
	_busy = true
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	GameSettings.difficulty = _diff.selected as GameSettings.Kind
	_status.text = HudStyle.chrome("Opening a Steam lobby...")
	_refresh()
	var err: Error = await NetSession.host_steam()
	_busy = false
	_settle(err, "Steam would not open a lobby.")


func _on_invite(_lobby_id: int) -> void:
	_consume_invite()


## Handles both invite routes: one accepted while we sit here, and one that
## launched the game and has been waiting for a screen to pick it up.
func _consume_invite() -> void:
	if _busy or NetSession.is_active():
		return
	var lobby_id := SteamLobby.take_pending_invite()
	if lobby_id == 0:
		return
	_busy = true
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	_status.text = HudStyle.chrome("Joining your friend's lobby...")
	_refresh()
	var err: Error = await NetSession.join_steam(lobby_id)
	_busy = false
	_settle(err, "Could not join that lobby.")


func _invite() -> void:
	Sfx.play("ui_confirm", self)
	SteamLobby.open_invite_overlay()


func _settle(err: Error, complaint: String) -> void:
	_notice = complaint if err != OK else ""
	Sfx.play("ui_deny" if err != OK else "ui_confirm", self)
	_refresh()


func _start() -> void:
	if not NetSession.is_host():
		return
	GameSettings.difficulty = _diff.selected as GameSettings.Kind
	Sfx.play("ui_confirm", self)
	NetSession.start_match()


func _back() -> void:
	Sfx.play("ui_back", self)
	NetSession.quit_to_menu()


## Answers "can these two machines pass a UDP packet at all", without ENet in
## the way. A silent probe means the packets die outside the game.
func _test_lan() -> void:
	Sfx.play("ui_confirm", self)
	var err := _probe.probe(_ip.text.strip_edges(), _port_value())
	_notice = "" if err == OK else "Could not send a probe."
	_refresh()


func _on_probe_answered(from_ip: String) -> void:
	_notice = "LAN reaches %s.  UDP is open." % from_ip
	_refresh()


func _on_probe_silent() -> void:
	_notice = "No probe reply from %s.  UDP is blocked." % _ip.text.strip_edges()
	_refresh()


func _port_value() -> int:
	return clampi(_port.text.to_int(), 1, 65535)


func _on_lost(reason: String) -> void:
	_notice = reason
	_refresh()


func _refresh() -> void:
	var active := NetSession.is_active()
	var connecting := NetSession.is_connecting()
	var can_act := not active and not connecting and not _busy
	var hosting := NetSession.is_host()
	_host_btn.disabled = not can_act
	_join_btn.disabled = not can_act
	_test_btn.disabled = _probe.is_probing()
	_steam_btn.visible = SteamLobby.can_host()
	_steam_btn.disabled = not can_act or not SteamLobby.can_host()
	_invite_btn.visible = SteamLobby.can_host()
	_invite_btn.disabled = not (hosting and NetSession.is_steam())
	_ip.editable = can_act
	_port.editable = can_act
	_diff.disabled = active and not hosting
	_start_btn.visible = hosting
	_start_btn.disabled = not hosting
	_list.text = HudStyle.chrome(_roster()) if active else ""
	if not _busy:
		_status.text = HudStyle.chrome(_notice if _notice != "" else _status_copy(active))


func _status_copy(active: bool) -> String:
	if _probe.is_probing():
		return "Testing %s..." % _ip.text.strip_edges()
	if NetSession.is_connecting():
		return "Connecting to %s..." % NetSession.join_ip
	if not active:
		if SteamLobby.can_host():
			return "Host on Steam and invite friends, or play over LAN."
		return "Host or join over LAN.  Type the host IP below."
	if not NetSession.is_host():
		return "Connected. Waiting for the host to start."
	var seated := NetSession.player_count()
	var wired := NetSession.wire_count()
	var count := "%d / %d" % [seated, NetSession.MAX_PLAYERS]
	if wired != seated:
		count += "   wire %d" % wired
	if NetSession.is_steam():
		return "Hosting on Steam.  %s   Invite friends to fill seats." % count
	var ips := "  ".join(NetSession.lan_addresses())
	if ips == "":
		ips = "this Mac"
	return "Join at %s : %d.  %s" % [ips, NetSession.port, count]


func _roster() -> String:
	var lines: PackedStringArray = []
	for peer_id in NetSession.peer_ids():
		var seat := NetSession.seat_for(peer_id)
		var tag := "you" if peer_id == multiplayer.get_unique_id() else "peer %d" % peer_id
		if peer_id == 1:
			tag += "  host"
		lines.append("%s   %s" % [_seat_name(seat), tag])
	return "\n".join(lines)


func _seat_name(seat: int) -> String:
	var names: PackedStringArray = [
		"Cyan", "Amber", "Magenta", "Lime", "Violet", "Pink", "Blue", "Ice",
	]
	if seat < 0 or seat >= names.size():
		return "Seat"
	return names[seat]


func _build() -> void:
	var night := ColorRect.new()
	night.set_anchors_preset(Control.PRESET_FULL_RECT)
	night.color = Palette.NIGHT
	night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(night)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 120.0
	root.offset_top = 70.0
	root.offset_right = -120.0
	root.offset_bottom = -70.0
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.label_settings = HudStyle.banner(Palette.MAGENTA, 52)
	title.text = HudStyle.chrome("Online VS")
	root.add_child(title)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.label_settings = HudStyle.readout(Palette.CYAN, 16)
	root.add_child(_status)
	root.add_child(_fields())
	_list = Label.new()
	_list.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.label_settings = HudStyle.readout(Palette.ICE, 16)
	root.add_child(_list)
	_start_btn = LobbyChrome.button("Start match")
	_start_btn.pressed.connect(_start)
	root.add_child(_start_btn)
	_back_btn = LobbyChrome.button("Back")
	_back_btn.pressed.connect(_back)
	root.add_child(_back_btn)


func _fields() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_diff = OptionButton.new()
	_diff.custom_minimum_size = Vector2(360.0, 36.0)
	for label in GameSettings.LABELS:
		_diff.add_item(label)
	_diff.selected = int(GameSettings.difficulty)
	box.add_child(_diff)
	_steam_btn = LobbyChrome.button("Host on Steam")
	_steam_btn.pressed.connect(_host_steam)
	_invite_btn = LobbyChrome.button("Invite friends")
	_invite_btn.pressed.connect(_invite)
	box.add_child(LobbyChrome.row([_steam_btn, _invite_btn]))
	box.add_child(LobbyChrome.heading("LAN  ·  testing"))
	_ip = LineEdit.new()
	_ip.placeholder_text = "Host IP"
	_ip.text = NetSession.join_ip
	_ip.custom_minimum_size = Vector2(360.0, 36.0)
	_ip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_ip)
	_port = LineEdit.new()
	_port.placeholder_text = "Port"
	_port.text = str(NetSession.DEFAULT_PORT)
	_port.custom_minimum_size = Vector2(360.0, 36.0)
	_port.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_port)
	_host_btn = LobbyChrome.button("Host")
	_host_btn.pressed.connect(_host)
	_join_btn = LobbyChrome.button("Join")
	_join_btn.pressed.connect(_join)
	_test_btn = LobbyChrome.button("Test LAN")
	_test_btn.pressed.connect(_test_lan)
	box.add_child(LobbyChrome.row([_host_btn, _join_btn, _test_btn]))
	return box


