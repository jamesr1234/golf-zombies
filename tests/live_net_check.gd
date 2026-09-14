extends SceneTree
## Live two-process online check. Not a GUT test: it needs a real ENet peer on
## both sides, so it runs as its own headless process.
##
##   godot --headless -s res://tests/live_net_check.gd -- role=host mode=vs peers=1
##   godot --headless -s res://tests/live_net_check.gd -- role=client mode=vs
##
## Every line it prints starts with CHECK/OK/BAD/INFO so the caller can grep.
##
## Nothing here may name a game class or an autoload at parse time. A main-loop
## script is compiled before the autoloads are registered, so a reference to
## Player or GameSettings would drag the whole project through a compile where
## NetSession does not exist yet and every script that uses it fails. Everything
## from the project is fetched with load() or off the tree, untyped, at runtime.

const MODE_ONLINE_VS := 2
const MODE_ONLINE_COOP_VS := 3

var role := "host"
var mode := "vs"
var peers := 1
var port := 7801
var seat := -1
var hold := 12.0
var expect_drop := false
var fails := 0
## A lambda captures locals by value, so the reason has to land on the instance.
var drop_reason := ""
var net
var settings


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var bits := arg.split("=")
		if bits.size() != 2:
			continue
		match bits[0]:
			"role":
				role = bits[1]
			"mode":
				mode = bits[1]
			"peers":
				peers = bits[1].to_int()
			"port":
				port = bits[1].to_int()
			"seat":
				seat = bits[1].to_int()
			"hold":
				hold = bits[1].to_float()
			"expect_drop":
				expect_drop = bits[1] == "1"
	# The autoload is parented to root before root is handed its tree, so an
	# early grab yields a node whose get_tree() is still null.
	while net == null or not net.is_inside_tree():
		net = root.get_node_or_null("NetSession")
		await process_frame
	settings = load("res://scripts/core/game_settings.gd")
	settings.set("mode", MODE_ONLINE_COOP_VS if mode == "coop" else MODE_ONLINE_VS)
	print("INFO %s starting mode=%s port=%d" % [role, mode, port])
	if role == "host":
		await _run_host()
	elif role == "nohost":
		await _run_nohost()
	elif role == "steamhost":
		await _run_steam_host()
	else:
		await _run_client()
	print("DONE %s fails=%d" % [role, fails])
	quit(1 if fails > 0 else 0)


func _ok(pass_now: bool, what: String, detail: String = "") -> bool:
	if pass_now:
		print("OK   %s %s" % [what, detail])
	else:
		fails += 1
		print("BAD  %s %s" % [what, detail])
	return pass_now


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## Polls a condition instead of sleeping a fixed time, so a slow load does not
## read as a failure and a fast one does not cost the whole budget.
func _until(cond: Callable, seconds: float, label: String) -> bool:
	var waited := 0.0
	while waited < seconds:
		if cond.call():
			print("INFO %s after %.1fs" % [label, waited])
			return true
		await create_timer(0.1).timeout
		waited += 0.1
	print("INFO %s TIMED OUT after %.1fs" % [label, seconds])
	return false


func _uid() -> int:
	return get_multiplayer().get_unique_id()


## Coop VS is always a full field of 16: every seat a human does not take is
## filled with a CPU on start. Free-for-all seats only the humans present.
func _want_pawns() -> int:
	return 16 if mode == "coop" else peers + 1


func _run_host() -> void:
	var err: int = net.host(port)
	if not _ok(err == OK, "host_opens", "err=%d" % err):
		return
	_ok(net.is_host(), "is_host")
	_ok(net.is_active(), "session_active")
	_ok(not net.is_steam(), "backend_is_enet")
	_ok(net.seat_for(1) == 0, "host_takes_seat_0", "seat=%d seats=%s" % [
		net.seat_for(1), str(net.seats)
	])

	var joined := await _until(
		func() -> bool: return get_multiplayer().get_peers().size() >= peers, 20.0, "peers_joined"
	)
	if not _ok(joined, "clients_connect", "wire=%d" % net.wire_count()):
		return
	_ok(
		net.player_count() == peers + 1,
		"seats_assigned",
		"seated=%d" % net.player_count()
	)
	# Let a client claim its coop seat before the roster is frozen.
	await _wait(1.5)
	print("INFO host seats=%s" % str(net.seats))

	net.start_match()
	var loaded := await _until(func() -> bool: return _world() != null, 25.0, "world_loaded")
	if not _ok(loaded, "match_scene_loads"):
		return
	await _report_world("host")
	_talk_forever()
	await _hear_someone("host")
	await _drive_match()
	# Judged while the client is still known to be alive; it exits first.
	await _wait(4.0)
	_ok(
		get_multiplayer().get_peers().size() >= peers,
		"host_keeps_the_client_through_the_match",
		"wire=%d" % net.wire_count()
	)
	print("INFO host mid-match seats=%s wire=%d" % [str(net.seats), net.wire_count()])
	# Stay up long enough for the client to finish its own checks, then prove the
	# host survives the client walking out.
	await _wait(hold)
	_ok(net.is_active() and net.is_host(), "host_survives_a_client_leaving",
		"wire=%d seats=%s" % [net.wire_count(), str(net.seats)])


func _run_client() -> void:
	var err: int = net.join("127.0.0.1", port)
	if not _ok(err == OK, "join_starts", "err=%d" % err):
		return
	var up := await _until(func() -> bool: return net.is_active(), 20.0, "handshake")
	if not _ok(up, "client_connects"):
		return
	_ok(not net.is_host(), "client_is_not_host")
	_ok(_uid() != 1, "client_has_own_id", "id=%d" % _uid())
	var got_seats := await _until(
		func() -> bool: return net.player_count() >= 2, 10.0, "seat_sync"
	)
	_ok(got_seats, "seats_replicate", "seen=%d seats=%s" % [net.player_count(), str(net.seats)])
	_ok(net.seat_for(_uid()) >= 0, "client_has_a_seat", "seat=%d" % net.seat_for(_uid()))
	if seat >= 0:
		net.request_seat(seat)
		var claimed := await _until(
			func() -> bool: return net.seat_for(_uid()) == seat, 6.0, "seat_claim"
		)
		_ok(claimed, "client_claims_requested_seat", "want=%d got=%d" % [seat, net.seat_for(_uid())])

	var loaded := await _until(func() -> bool: return _world() != null, 40.0, "world_loaded")
	if not _ok(loaded, "client_enters_match"):
		return
	await _report_world("client")
	_talk_forever()
	if expect_drop:
		await _survive_host_leaving()
		return
	await _check_sync()
	await _hear_someone("client")
	await _follow_match()
	# Outlast the host's own checks so its roster is not judged on our exit.
	await _wait(hold)
	_ok(net.is_active(), "client_stays_connected_through_the_match")


## There is no host migration by design: when the host goes, the match ends. The
## client has to notice, tear the session down, and land on the title screen
## rather than sit in a dead world or take the whole process out.
func _survive_host_leaving() -> void:
	var dropped := await _until(
		func() -> bool: return not net.is_active(), 40.0, "host_drop_seen"
	)
	if not _ok(dropped, "client_notices_the_host_left"):
		return
	_ok(net.wire_count() == 0, "client_tears_the_session_down", "wire=%d" % net.wire_count())
	_ok(net.seats.is_empty(), "client_clears_the_roster", "seats=%s" % str(net.seats))
	var home := await _until(
		func() -> bool:
			return current_scene != null and current_scene.scene_file_path.ends_with("main_menu.tscn"),
		15.0,
		"back_to_title"
	)
	_ok(home, "client_returns_to_the_title_screen", "scene=%s" % (
		current_scene.scene_file_path if current_scene != null else "none"
	))


## Typing the wrong IP is the single most likely thing to go wrong on the night.
## It must end in a stated reason and a session that can be retried, not a screen
## that says "Connecting..." forever.
func _run_nohost() -> void:
	net.disconnected.connect(_on_drop)
	var err: int = net.join("127.0.0.1", port)
	_ok(err == OK, "join_to_a_dead_port_is_accepted", "err=%d" % err)
	_ok(net.is_connecting(), "session_reports_connecting")
	var gave_up := await _until(
		func() -> bool: return drop_reason != "", net.JOIN_SECONDS + 10.0, "join_timeout"
	)
	if not _ok(gave_up, "a_dead_join_gives_up"):
		return
	_ok(drop_reason != "", "the_failure_states_a_reason", "reason=%s" % drop_reason)
	_ok(not net.is_connecting(), "session_stops_connecting")
	_ok(not net.is_active(), "no_session_is_left_behind")
	_ok(net.seats.is_empty(), "no_seats_are_left_behind", "seats=%s" % str(net.seats))


## Steam is the shipping transport, and everything past _bind_peer is shared with
## ENet, so this only has to prove the Steam-specific half: a lobby opens, a real
## peer is built on it, and the host is seated. The joining half needs a second
## Steam account on a second machine, so it cannot run here.
func _run_steam_host() -> void:
	var lobby = root.get_node_or_null("SteamLobby")
	if not _ok(lobby != null, "steam_autoload_exists"):
		return
	_ok(lobby.can_host(), "steam_is_available", "class+singleton present")
	var err: int = await net.host_steam()
	if not _ok(err == OK, "steam_lobby_opens", "err=%d" % err):
		print("INFO steam host failed; online=%s lobby=%d" % [
			str(lobby.is_online()), lobby.lobby_id
		])
		return
	_ok(lobby.lobby_id != 0, "lobby_has_an_id", "lobby=%d" % lobby.lobby_id)
	_ok(net.is_active() and net.is_host(), "steam_session_is_hosting")
	_ok(net.is_steam(), "backend_switched_to_steam")
	_ok(net.seat_for(1) == 0, "steam_host_takes_seat_0", "seats=%s" % str(net.seats))
	_ok(
		lobby.parse_lobby_id(str(lobby.lobby_id)) == lobby.lobby_id,
		"the_id_a_friend_pastes_round_trips"
	)
	print("INFO steam lobby %d open; friends online: %s" % [
		lobby.lobby_id, str(lobby.online_friend_names())
	])
	net.close()
	_ok(not net.is_active(), "leaving_the_steam_lobby_clears_the_session")


func _on_drop(why: String) -> void:
	drop_reason = why
	print("INFO disconnected reason=%s" % why)


func _world():
	var scene := current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("Screen/Viewport/World")


func _players() -> Array:
	return get_nodes_in_group("players")


func _report_world(side: String) -> void:
	var world = _world()
	var flow = world.get_node_or_null("VsMatchFlow")
	if not _ok(flow != null, "%s_has_match_flow" % side):
		return
	# The host bakes the hole and spawns, then the client receives it; give the
	# spawner a moment either way.
	var want := _want_pawns()
	var spawned := await _until(
		func() -> bool: return _players().size() >= want, 30.0, "%s_pawns" % side
	)
	var players := _players()
	_ok(spawned, "%s_sees_every_pawn" % side, "players=%d want=%d" % [players.size(), want])

	var balls = world.get_node_or_null("Balls")
	var ball_count := 0
	if balls != null:
		for child in balls.get_children():
			if "owner_peer" in child:
				ball_count += 1
	# Coop is one ball per team of two; free-for-all is one each.
	var want_balls := 8 if mode == "coop" else peers + 1
	_ok(
		ball_count == want_balls,
		"%s_has_one_ball_per_side" % side,
		"balls=%d want=%d" % [ball_count, want_balls]
	)

	var built := await _until(
		func() -> bool: return flow.course != null and flow.course.hole != null,
		15.0,
		"%s_hole_bake" % side
	)
	_ok(built, "%s_hole_is_built" % side)

	var mine = _local_player()
	_ok(mine != null, "%s_finds_its_own_pawn" % side)
	if mine != null:
		_ok(
			mine.is_multiplayer_authority(),
			"%s_owns_its_pawn" % side,
			"auth=%d" % mine.get_multiplayer_authority()
		)
		_ok(
			mine.global_position.length() > 0.01,
			"%s_pawn_is_placed" % side,
			"at=%v" % mine.global_position
		)
	var names: PackedStringArray = []
	for p in players:
		names.append("%s(peer=%d,auth=%d,cpu=%s)" % [
			p.name, p.peer_id, p.get_multiplayer_authority(), str(p.cpu_filled)
		])
	print("INFO %s pawns: %s" % [side, "  ".join(names)])
	print("INFO %s balls=%d seats=%s" % [side, ball_count, str(net.seats)])


func _voice():
	return root.get_node_or_null("VoiceChat")


## Headless cannot open a mic, but the wire does not care: pack a tone and push
## it through the same try_send/_hear path a real headset would use. Prefs are
## pointed at the test file first so a live session never rewrites the player's
## own mic settings.
func _talk_forever() -> void:
	var voice = _voice()
	var codec = load("res://scripts/net/voice_codec.gd")
	if voice == null:
		_ok(false, "voice_autoload_exists")
		return
	voice.config_path = codec.TEST_PATH
	voice.muted = false
	var frames = codec.tone(codec.PACKET_FRAMES, 0.4)
	var sent := false
	for i in 400:
		if not net.is_active():
			break
		if voice.try_send(frames, true):
			sent = true
		await _wait(0.05)
	if sent:
		print("INFO client pushed %d voice packets" % voice.send_count)


## The receiving half. A packet that never arrives shows up here as a peer the
## other side never hears, which is the failure people report as "voice is dead"
## even though the sender thinks it sent. Checked both ways.
func _hear_someone(side: String) -> void:
	var voice = _voice()
	if not _ok(voice != null, "voice_autoload_exists"):
		return
	var me := _uid()
	var heard := await _until(
		func() -> bool:
			for peer_id in voice.speaking.keys():
				if int(peer_id) != me and voice.is_speaking(int(peer_id)):
					return true
			return false,
		15.0,
		"%s_voice_in" % side
	)
	_ok(heard, "%s_hears_the_other_side" % side, "speaking=%s" % str(voice.speaking))


## VsMatchFlow.Phase, which cannot be named at parse time from here.
const PHASE_PREP := 0
const PHASE_PLAYING := 1
const PHASE_SHOP := 4


func _flow():
	var world = _world()
	if world == null:
		return null
	return world.get_node_or_null("VsMatchFlow")


## The match opens in the clubhouse. Walk the host through to a live hole and
## make sure each step lands, since the client only ever sees the replicated
## phase and a stall here is a session that never tees off.
func _drive_match() -> void:
	var flow = _flow()
	print("INFO host phase at start=%d" % flow.phase)
	_ok(flow.phase == PHASE_SHOP, "match_opens_in_the_clubhouse", "phase=%d" % flow.phase)
	flow.leave_clubhouse()
	var left := await _until(
		func() -> bool: return flow.phase != PHASE_SHOP, 10.0, "host_leaves_clubhouse"
	)
	_ok(left, "clubhouse_lets_the_field_out", "phase=%d" % flow.phase)
	flow.arrive_at_next_tee()
	var at_tee := await _until(
		func() -> bool: return flow.phase == PHASE_PREP, 10.0, "host_reaches_tee"
	)
	_ok(at_tee, "field_arrives_at_the_tee", "phase=%d" % flow.phase)
	flow.start_play()
	var playing := await _until(
		func() -> bool: return flow.phase == PHASE_PLAYING, 10.0, "host_starts_play"
	)
	_ok(playing, "host_opens_the_hole_for_play", "phase=%d" % flow.phase)


## The client drives none of this; it must arrive at PLAYING purely on replicated
## events. A client stuck in the clubhouse while the host plays is the worst
## version of this bug, so it is worth an explicit case.
func _follow_match() -> void:
	var flow = _flow()
	var followed := await _until(
		func() -> bool: return flow.phase == PHASE_PLAYING, 25.0, "client_follows_to_playing"
	)
	_ok(followed, "client_follows_the_host_into_play", "phase=%d" % flow.phase)


func _local_player():
	var id := _uid()
	for node in _players():
		if node.peer_id == id:
			return node
	return null


## The point of a listen server: the host's simulation has to reach the client.
## Walk the local pawn and prove both the input and the replicated pose land.
func _check_sync() -> void:
	var remote = null
	for node in _players():
		if not node.is_multiplayer_authority():
			remote = node
			break
	if not _ok(remote != null, "client_sees_a_remote_pawn"):
		return
	var before = remote.global_position
	var mine = _local_player()
	var my_before := Vector3.ZERO
	if mine != null:
		my_before = mine.global_position
	Input.action_press("p1_move_forward")
	await _wait(3.0)
	Input.action_release("p1_move_forward")
	await _wait(0.5)
	if mine != null:
		_ok(
			mine.global_position.distance_to(my_before) > 0.2,
			"client_input_moves_its_pawn",
			"moved=%.2f" % mine.global_position.distance_to(my_before)
		)
	print("INFO remote pawn was %v now %v" % [before, remote.global_position])
	_ok(
		remote.sync_xform.origin.length() > 0.01,
		"remote_pawn_carries_a_synced_pose",
		"sync=%v" % remote.sync_xform.origin
	)
