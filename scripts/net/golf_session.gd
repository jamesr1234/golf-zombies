class_name GolfSession
extends GolfController
## Per-ball golf for online VS. Claim and strike are host-validated; the swing
## meter still runs on the golfer's machine. Live aim is sent from that machine
## so the other screens can turn the pink arrow and white flight line with them.

var _sent_aim_yaw := INF
var _sent_aim_loft := INF


func can_claim(player: Node) -> bool:
	if not _coop_may_play(player):
		return false
	if ball != null and not ball.is_owned_by(player):
		return false
	return super.can_claim(player)


func _coop_may_play(player: Node) -> bool:
	if not GameSettings.is_coop_vs():
		return true
	if ball != null and not ball.is_owned_by(player):
		return false
	var pawn := player as Player
	if pawn == null or pawn.flow == null:
		return true
	if pawn.flow.has_method("is_practice") and pawn.flow.is_practice():
		return true
	if pawn.flow.has_method("can_strike"):
		return pawn.flow.can_strike(pawn)
	return true


func try_toggle(player: Node) -> void:
	if NetSession.is_active() and not multiplayer.is_server():
		_request_toggle.rpc_id(1)
		return
	super.try_toggle(player)
	if NetSession.is_active() and golfer == player:
		_replicate_golfer.rpc(_peer_of(player))
	elif NetSession.is_active() and golfer == null:
		_replicate_golfer.rpc(0)


func _strike() -> void:
	if NetSession.is_active() and not multiplayer.is_server():
		_request_strike.rpc_id(1, aim_yaw, meter.deviation_deg, meter.power, aim_loft)
		_finish_local_swing()
		return
	super._strike()


func cancel_swing() -> void:
	super.cancel_swing()
	if golfer != null and golfer.has_method("exit_golf_mode"):
		release()


func _process(delta: float) -> void:
	if golfer == null:
		return
	if NetSession.is_active() and golfer is Node and not (golfer as Node).is_multiplayer_authority():
		_show_club(delta)
		return
	super._process(delta)
	_publish_aim()


func _show_club(delta: float) -> void:
	_refresh_lie()
	_pose_arrow()
	_pose_preview()
	_club.pose(_lie, aim_yaw, meter.value, delta, _is_putting())


func apply_remote_aim(peer_id: int, yaw: float, loft := 0.0) -> void:
	if golfer == null or _peer_of(golfer) != peer_id:
		return
	aim_yaw = yaw
	aim_loft = loft


func _publish_aim() -> void:
	if not NetSession.is_active():
		return
	if is_equal_approx(aim_yaw, _sent_aim_yaw) and is_equal_approx(aim_loft, _sent_aim_loft):
		return
	_sent_aim_yaw = aim_yaw
	_sent_aim_loft = aim_loft
	_replicate_aim.rpc(aim_yaw, aim_loft)


func _finish_local_swing() -> void:
	_lock_lie()
	meter.reset()
	_arrow.visible = false
	if _preview != null:
		_preview.visible = false
	_club.start_follow_through()
	Sfx.play("putt" if _is_putting() else "club_hit", self)


func _peer_of(player: Node) -> int:
	if player == null:
		return 0
	return int(player.get("peer_id"))


@rpc("any_peer", "reliable")
func _request_toggle() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var player := _player_for(sender)
	if player == null:
		return
	super.try_toggle(player)
	_replicate_golfer.rpc(_peer_of(golfer) if golfer != null else 0)


@rpc("any_peer", "reliable")
func _request_strike(yaw: float, deviation: float, power: float, loft := 0.0) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var player := _player_for(sender)
	if GameSettings.is_coop_vs():
		if not _coop_may_play(player):
			return
	elif ball == null or ball.owner_peer != sender:
		return
	if golfer == null or _peer_of(golfer) != sender:
		return
	aim_yaw = yaw
	aim_loft = loft
	meter.deviation_deg = deviation
	meter.power = power
	super._strike()


@rpc("any_peer", "unreliable_ordered")
func _replicate_aim(yaw: float, loft := 0.0) -> void:
	apply_remote_aim(multiplayer.get_remote_sender_id(), yaw, loft)


@rpc("authority", "call_local", "reliable")
func _replicate_golfer(peer_id: int) -> void:
	if multiplayer.is_server():
		return
	if peer_id == 0:
		if golfer != null:
			super.release()
		return
	var player := _player_for(peer_id)
	if player != null and golfer != player:
		_claim(player)


func _player_for(peer_id: int) -> Player:
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player != null and player.peer_id == peer_id:
			return player
	return null
