class_name BallDrop
extends RefCounted
## Unplayable-lie relief. Stand over a resting ball, press L3 / Shift to pick
## it up, run a short way, and place it. The drop is a stroke.

const GRAB_RANGE := 1.4
const GRAB_HEIGHT := 1.8
const CARRY_LIMIT := 8.0

var origin := Vector3.ZERO
var active := false


func tick(player: Player) -> void:
	if active:
		if not player.is_carrying_ball():
			cancel()
			return
		if past_limit(player) or player.input.just_pressed("sprint"):
			place(player)
		return
	if player.input.just_pressed("sprint") and can_pick_up(player):
		pick_up(player)


func can_pick_up(player: Player) -> bool:
	if active or player == null or not player.health.is_alive():
		return false
	if player.shopping or player.talking or player.is_celebrating():
		return false
	if player.is_swimming() or player.is_riding() or player.is_in_mech():
		return false
	if player.is_climbing() or player.is_grappling() or player.is_ziplining():
		return false
	if player.is_placing() or player.is_milling() or player.is_poker_seated():
		return false
	if player.state != Player.State.NORMAL and player.state != Player.State.GOLFING:
		return false
	var golf := player.golf
	if golf == null or golf.ball == null:
		return false
	if golf.golfer != null and golf.golfer != player:
		return false
	var ball: GolfBall = golf.ball
	if not ball.is_owned_by(player):
		return false
	if ball.is_in_play() or ball.is_carried() or ball.is_holed() or ball.is_stowed():
		return false
	if ball.is_closed() or ball.is_submerged() or ball.is_sinking():
		return false
	return _over_ball(player, ball)


func pick_up(player: Player) -> void:
	if not can_pick_up(player):
		return
	var golf := player.golf
	var lie := golf.ball.global_position
	if golf.golfer == player:
		golf.release()
	golf.ball.pick_up(player)
	if not player.is_carrying_ball():
		return
	origin = Vector3(lie.x, player.global_position.y, lie.z)
	active = true
	Sfx.play("grab_ball", player)


func place(player: Player) -> void:
	if not active:
		return
	var golf := player.golf
	active = false
	if golf == null or golf.ball == null:
		return
	golf.take_drop(drop_point(player))
	Sfx.play("grab_ball", player)


func cancel() -> void:
	active = false
	origin = Vector3.ZERO


func drop_point(player: Player) -> Vector3:
	var at := player.global_position
	var offset := at - origin
	offset.y = 0.0
	if offset.length() > CARRY_LIMIT:
		offset = offset.limit_length(CARRY_LIMIT)
		at = Vector3(origin.x + offset.x, at.y, origin.z + offset.z)
	return at


func past_limit(player: Player) -> bool:
	return _flat_from_origin(player) >= CARRY_LIMIT


func _over_ball(player: Player, ball: GolfBall) -> bool:
	var offset := ball.global_position - player.global_position
	if absf(offset.y) > GRAB_HEIGHT:
		return false
	offset.y = 0.0
	return offset.length() <= GRAB_RANGE


func _flat_from_origin(player: Player) -> float:
	var offset := player.global_position - origin
	offset.y = 0.0
	return offset.length()
