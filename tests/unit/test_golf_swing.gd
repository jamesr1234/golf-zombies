extends GutTest
## The swing pose and the stance the golfer takes. Both are pure maths so they can
## be checked without standing a world up.


func test_address_puts_the_club_on_the_ball() -> void:
	assert_eq(GolfClub.swing_angle_deg(0.0), 0.0)


func test_the_club_goes_further_back_as_the_meter_rises() -> void:
	var quarter := GolfClub.swing_angle_deg(0.25)
	var half := GolfClub.swing_angle_deg(0.5)
	assert_lt(quarter, 0.0, "the backswing is behind the golfer")
	assert_lt(half, quarter)
	assert_almost_eq(GolfClub.swing_angle_deg(1.0), -GolfClub.BACKSWING_ARC, 0.01)


func test_a_late_click_never_drags_the_club_back_past_the_ball() -> void:
	# The meter dips below zero when contact is missed low.
	assert_eq(GolfClub.swing_angle_deg(-0.2), 0.0)


func test_the_follow_through_carries_past_the_ball() -> void:
	assert_eq(GolfClub.follow_angle_deg(0.0), 0.0)
	assert_gt(GolfClub.follow_angle_deg(0.5), 0.0)
	assert_almost_eq(GolfClub.follow_angle_deg(1.0), GolfClub.FOLLOW_THROUGH_ARC, 0.01)


func test_the_follow_through_eases_to_a_stop() -> void:
	var early := GolfClub.follow_angle_deg(0.5) - GolfClub.follow_angle_deg(0.25)
	var late := GolfClub.follow_angle_deg(1.0) - GolfClub.follow_angle_deg(0.75)
	assert_lt(late, early, "the finish should decelerate, not snap")


func test_a_putt_is_a_short_stroke() -> void:
	assert_lt(GolfClub.PUTT_BACKSWING_ARC, GolfClub.BACKSWING_ARC * 0.4)
	assert_almost_eq(
		GolfClub.swing_angle_deg(1.0, true), -GolfClub.PUTT_BACKSWING_ARC, 0.01
	)
	assert_almost_eq(
		GolfClub.follow_angle_deg(1.0, true), GolfClub.PUTT_FOLLOW_THROUGH_ARC, 0.01
	)
	assert_gt(
		absf(GolfClub.swing_angle_deg(1.0)), absf(GolfClub.swing_angle_deg(1.0, true)),
		"a full meter on the green is still a putt, not a chip swing"
	)


func test_the_golfer_stands_beside_the_ball_at_ground_level() -> void:
	var ball_position := Vector3(4.0, GolfBall.RADIUS, -2.0)
	var spot := GolfClub.stance_point(ball_position, 0.0)
	assert_almost_eq(spot.y, 0.0, 0.001, "feet on the ground, not on top of the ball")
	var offset := spot - ball_position
	offset.y = 0.0
	assert_almost_eq(offset.length(), GolfClub.SIDE, 0.001)
	var forward := Shot.aim_direction(0.0, 0.0)
	assert_almost_eq(
		offset.normalized().dot(forward), 0.0, 0.001, "beside the ball, not in front of it"
	)


func test_the_stance_swings_around_with_the_aim() -> void:
	var north := GolfClub.stance_point(Vector3.ZERO, 0.0)
	var east := GolfClub.stance_point(Vector3.ZERO, 90.0)
	assert_gt(north.distance_to(east), 0.5, "aiming somewhere else moves the golfer")
	assert_almost_eq(north.length(), east.length(), 0.001, "always the same step to the side")


## The shaft is built from this gap, so if the grip drifts off the stance the head
## stops meeting the ball.
func test_the_grip_sits_above_the_golfer() -> void:
	var lie := Vector3(-3.0, GolfBall.RADIUS, 7.0)
	var hands := GolfClub.hands_point(lie, 25.0)
	var feet := GolfClub.stance_point(lie, 25.0)
	assert_almost_eq(hands.y - feet.y, GolfClub.HAND_HEIGHT, 0.001)
	assert_almost_eq(Vector2(hands.x, hands.z).distance_to(Vector2(feet.x, feet.z)), 0.0, 0.001)
