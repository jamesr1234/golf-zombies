extends GutTest
## A floor fan holds you and the ball in a gentle hover and keeps the speed
## you jumped in with.

const STEP := 0.2
const _Fan := preload("res://scripts/course/fan.gd")


func test_a_fall_climbs_toward_a_hover() -> void:
	var next := _Fan.next_vertical(-18.0, STEP)
	assert_gt(next, -18.0)
	assert_lt(next, _Fan.HOVER_VY)


func test_a_ramp_launch_settles_instead_of_climbing() -> void:
	var next := _Fan.next_vertical(14.0, STEP)
	assert_lt(next, 14.0)
	assert_gt(next, _Fan.HOVER_VY)


func test_horizontal_speed_survives_a_steer() -> void:
	var held := _Fan.hold_horizontal(Vector3(0.0, 2.0, -22.0), Vector3(-1.0, 0.0, 0.0), STEP)
	assert_almost_eq(Vector3(held.x, 0.0, held.z).length(), 22.0, 0.05)
	assert_almost_eq(held.y, 2.0, 0.001)
	assert_lt(held.x, 0.0)


func test_a_placed_fan_spins_a_rotor_over_a_lift_column() -> void:
	var fan := _Fan.new()
	add_child_autofree(fan)
	assert_true(fan.is_in_group("fans"))
	assert_eq(fan.collision_layer, 0)
	assert_eq(fan.collision_mask, Layers.PLAYER | Layers.VEHICLE | Layers.BALL)
	assert_not_null(fan.get_node_or_null("Model"))
	var rotor := fan.find_child("Rotor", true, false) as Node3D
	assert_not_null(rotor)
	var yaw := rotor.rotation.y
	fan._physics_process(STEP)
	assert_ne(rotor.rotation.y, yaw)


func test_the_ball_keeps_its_run_while_it_lifts() -> void:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	ball.linear_velocity = Vector3(6.0, -12.0, -9.0)
	var fan := _Fan.new()
	add_child_autofree(fan)
	fan._lift_ball(ball, STEP)
	assert_gt(ball.linear_velocity.y, -12.0)
	assert_almost_eq(ball.linear_velocity.x, 6.0, 0.001)
	assert_almost_eq(ball.linear_velocity.z, -9.0, 0.001)
