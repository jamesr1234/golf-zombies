extends GutTest
## Hole 12 is a soccer goal five hundred yards out. First ball in the net wins.


func test_hole_twelve_is_a_five_hundred_yard_goal() -> void:
	var hole := HoleGenerator.generate(SoccerHole.INDEX, 20260816)
	assert_true(hole.has_soccer_goal())
	assert_eq(hole.par, SoccerHole.PAR)
	assert_almost_eq(hole.length(), SoccerHole.LENGTH, 0.01)
	assert_eq(hole.yardage(), SoccerHole.YARDS)
	assert_eq(hole.yardage_label(), "500 yd")
	assert_eq(hole.label(), "Hole 12  Soccer Goal")
	assert_eq(hole.banner_title(), "Hole 12   Soccer Goal")
	assert_eq(hole.sign_text(), "HOLE 12\n500 yd")
	assert_almost_eq(
		HoleGenerator.fairway_width(hole.par, hole.index),
		HoleGenerator.fairway_width(5) * 2.0,
		0.01
	)


func test_the_built_hole_has_a_goal_instead_of_a_cup() -> void:
	var data := HoleGenerator.generate(SoccerHole.INDEX, 20260816)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	assert_not_null(root.find_child("SoccerGoal", true, false))
	assert_null(root.get_node_or_null("Cup"), "the pin cup is the goal, not a hole")
	var signs := get_tree().get_nodes_in_group("hole_signs")
	assert_eq(signs.size(), 1)
	var yard := signs[0].get_node("YardCopy") as Label3D
	assert_eq(yard.text, "500 yd")


func test_a_fast_ball_scores_in_the_goal() -> void:
	var goal := SoccerGoal.place(Vector3.ZERO, Vector3.FORWARD)
	add_child_autofree(goal)
	var ball := _play_ball()
	watch_signals(ball)
	ball.toss(Vector3(0.0, SoccerGoal.HEIGHT * 0.5, -0.4), Vector3(0.0, 0.0, 18.0))
	await wait_physics_frames(12)
	assert_true(ball.is_holed(), "a drive through the mouth has to count")
	assert_signal_emitted(ball, "holed")


func test_try_score_goal_ignores_speed() -> void:
	var ball := _play_ball()
	watch_signals(ball)
	ball.toss(Vector3.ZERO, Vector3(0.0, 0.0, 30.0))
	ball.try_score_goal()
	assert_true(ball.is_holed())
	assert_signal_emitted(ball, "holed")


func test_a_miss_beside_the_post_does_not_score() -> void:
	var goal := SoccerGoal.place(Vector3.ZERO, Vector3.FORWARD)
	add_child_autofree(goal)
	var ball := _play_ball()
	ball.toss(
		Vector3(SoccerGoal.WIDTH * 0.5 + 2.0, SoccerGoal.HEIGHT * 0.5, -0.4),
		Vector3(0.0, 0.0, 18.0)
	)
	await wait_physics_frames(12)
	assert_false(ball.is_holed())


func _play_ball() -> GolfBall:
	var ball := preload("res://scenes/golf/ball.tscn").instantiate() as GolfBall
	add_child_autofree(ball)
	return ball
