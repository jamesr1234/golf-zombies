extends GutTest
## Only the ball you own breathes. A foreign lie stays a steady glow.

const PLAYER_SCENE := preload("res://scenes/players/player.tscn")


func test_a_shared_ball_pulses_for_any_viewer() -> void:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	var viewer := _viewer(1)
	assert_true(BallPulse.should_pulse(ball, viewer))


func test_a_foreign_ball_does_not_pulse() -> void:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	ball.owner_peer = 2
	assert_false(BallPulse.should_pulse(ball, _viewer(1)))


func test_the_owner_ball_pulses() -> void:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	ball.owner_peer = 2
	assert_true(BallPulse.should_pulse(ball, _viewer(2)))


func test_a_holed_ball_does_not_pulse() -> void:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	ball._holed = true
	assert_false(BallPulse.should_pulse(ball, _viewer(1)))


func test_a_stowed_ball_does_not_pulse() -> void:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	ball.stow()
	assert_false(BallPulse.should_pulse(ball, _viewer(1)))


func test_a_carried_ball_does_not_pulse() -> void:
	var ball := GolfBall.new()
	var viewer := _viewer(1)
	add_child_autofree(ball)
	ball.pick_up(viewer)
	assert_false(BallPulse.should_pulse(ball, viewer))


func test_a_closed_ball_does_not_pulse() -> void:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	ball.close_for_pickup()
	assert_false(BallPulse.should_pulse(ball, _viewer(1)))


func test_the_pulse_energy_oscillates_above_rest() -> void:
	assert_almost_eq(BallPulse.energy_at(0.25), Palette.GLOW_STRONG, 0.001)
	assert_almost_eq(BallPulse.energy_at(0.75), Palette.GLOW_MEDIUM, 0.001)
	assert_gt(BallPulse.energy_at(0.125), Palette.GLOW_MEDIUM)
	assert_lt(BallPulse.energy_at(0.125), Palette.GLOW_STRONG)


func test_the_pulse_reach_is_three_times_the_rest_glow() -> void:
	assert_almost_eq(BallPulse.PULSE_RANGE, BallPulse.REST_RANGE * 3.0, 0.001)
	assert_almost_eq(BallPulse.range_at(0.25), BallPulse.PULSE_RANGE, 0.001)
	assert_almost_eq(BallPulse.range_at(0.75), BallPulse.REST_RANGE, 0.001)
	assert_gt(BallPulse.range_at(0.125), BallPulse.REST_RANGE)


func test_only_a_local_owner_in_the_viewer_list_pulses() -> void:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	ball.owner_peer = 4
	assert_false(BallPulse.should_pulse_for_viewers(ball, [_viewer(1)]))
	assert_true(BallPulse.should_pulse_for_viewers(ball, [_viewer(1), _viewer(4)]))


func _viewer(peer_id: int) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.peer_id = peer_id
	return player
