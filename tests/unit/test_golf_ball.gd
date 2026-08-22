extends GutTest
## Green strikes have to stay on the turf. Bounce is what turned a putt into a
## chip even when the launch itself was already flat.


func test_a_green_strike_rolls_instead_of_launching() -> void:
	var ball := _ball_on(Surface.Type.GREEN)
	ball.strike(0.0, 0.0, 1.0)
	assert_almost_eq(ball.linear_velocity.y, 0.0, 0.001)
	assert_almost_eq(ball.physics_material_override.bounce, 0.0, 0.001)
	assert_true(ball.is_putting())
	assert_true(ball.is_on_green())
	assert_lt(
		ball.linear_velocity.length(), Shot.MAX_SPEED * 0.65,
		"a stuffed green stroke cannot fly like a drive"
	)


func test_a_fairway_strike_still_has_loft_and_bounce() -> void:
	var ball := _ball_on(Surface.Type.FAIRWAY)
	ball.strike(0.0, 0.0, 1.0)
	assert_gt(ball.linear_velocity.y, 0.0)
	assert_almost_eq(ball.physics_material_override.bounce, GolfBall.FLIGHT_BOUNCE, 0.001)
	assert_false(ball.is_putting())
	assert_false(ball.is_on_green())


func test_a_fringe_strike_is_a_putt_too() -> void:
	var ball := _ball_on(Surface.Type.FRINGE)
	ball.strike(0.0, 0.0, 0.5)
	assert_almost_eq(ball.linear_velocity.y, 0.0, 0.001)
	assert_almost_eq(ball.physics_material_override.bounce, 0.0, 0.001)
	assert_true(ball.is_putting())
	assert_true(ball.is_on_green(), "the collar still reads as a putting grid")


func test_a_slow_ball_drops_into_the_cup() -> void:
	var cup := Cup.create(Vector3(0.0, 2.0, 0.0))
	add_child_autofree(cup)
	var ball := GolfBall.new()
	add_child_autofree(ball)
	var lip := cup.global_position + Vector3.UP * GolfBall.RADIUS
	ball.toss(lip, Vector3.ZERO)
	ball.try_hole_out(cup)
	assert_true(ball.is_sinking(), "a slow ball over the cup should drop")
	for _frame in 150:
		if ball.is_holed():
			break
		await wait_physics_frames(1)
	assert_true(ball.is_holed())
	assert_lt(
		ball.global_position.y, cup.global_position.y - GolfBall.RADIUS,
		"it has to sit down in the well, not on the green"
	)


func test_a_fast_ball_rattles_over_the_cup() -> void:
	var cup := Cup.create(Vector3(0.0, 2.0, 0.0))
	add_child_autofree(cup)
	var ball := GolfBall.new()
	add_child_autofree(ball)
	ball.toss(cup.global_position + Vector3.UP * GolfBall.RADIUS, Vector3(8.0, 0.0, 0.0))
	await wait_physics_frames(3)
	assert_false(ball.is_sinking())
	assert_false(ball.is_holed())


func _ball_on(type: Surface.Type) -> GolfBall:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	ball.enter_surface(type)
	return ball
