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


## Online the session is a child of the ball, so leftover flight spin has to be
## ignored or the arrow peels off the line the golfer is facing.
func test_the_aim_arrow_follows_world_yaw_when_the_parent_has_spun() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	parent.rotation = Vector3(0.6, 1.3, -0.9)
	var golf := GolfController.new()
	parent.add_child(golf)
	golf.aim_yaw = 90.0
	golf._lie = Vector3(2.0, 0.15, -5.0)
	golf._pose_arrow()
	var facing := -golf._arrow.global_transform.basis.z
	assert_almost_eq(
		facing.angle_to(Shot.aim_direction(90.0, 0.0)), 0.0, 0.01,
		"the arrow has to stay on the aim line, not the ball's leftover spin"
	)
	assert_almost_eq(golf._arrow.global_position.distance_to(golf._lie), 0.0, 0.01)


func test_the_stick_raises_shot_height_until_the_swing_starts() -> void:
	var golf := GolfController.new()
	add_child_autofree(golf)
	golf.golfer = Node.new()
	add_child_autofree(golf.golfer)
	golf.aim_height_by(12.0)
	assert_almost_eq(golf.aim_loft, 12.0, 0.01)
	golf.aim_height_by(100.0)
	assert_almost_eq(golf.aim_loft, Shot.LOFT_BIAS_MAX, 0.01)
	golf.meter.state = SwingMeter.State.BACKSWING
	golf.aim_height_by(-8.0)
	assert_almost_eq(golf.aim_loft, Shot.LOFT_BIAS_MAX, 0.01, "height locks once the meter is moving")


func test_putting_ignores_shot_height() -> void:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	ball.enter_surface(Surface.Type.GREEN)
	var golf := GolfController.new()
	add_child_autofree(golf)
	golf.ball = ball
	golf.golfer = Node.new()
	add_child_autofree(golf.golfer)
	golf.aim_height_by(20.0)
	assert_almost_eq(golf.aim_loft, 0.0, 0.01)


func test_the_white_line_follows_a_perfect_hit() -> void:
	var golf := GolfController.new()
	add_child_autofree(golf)
	await get_tree().process_frame
	golf.golfer = Node.new()
	add_child_autofree(golf.golfer)
	golf._lie = Vector3(1.0, 0.15, -2.0)
	golf.aim_yaw = 0.0
	golf.aim_loft = 20.0
	golf._pose_preview()
	assert_true(golf._preview.visible)
	var expected := Shot.flight_points(golf._lie, 0.0, 1.0, 20.0)
	var drawn := _preview_points(golf._preview)
	assert_eq(drawn.size(), expected.size())
	assert_almost_eq(drawn[0].distance_to(expected[0]), 0.0, 0.01)
	assert_gt(_peak_y(drawn), golf._lie.y + 4.0)
	assert_gt(
		golf._preview.landing.distance_to(golf._lie), 40.0,
		"the landing mark has to sit out at the carry, not on the ball"
	)


func test_the_landing_mark_moves_when_loft_changes() -> void:
	var golf := GolfController.new()
	add_child_autofree(golf)
	await get_tree().process_frame
	golf.golfer = Node.new()
	add_child_autofree(golf.golfer)
	golf._lie = Vector3.ZERO
	golf.aim_yaw = 0.0
	golf.aim_loft = Shot.LOFT_BIAS_MIN
	golf._pose_preview()
	var punch := golf._preview.landing.distance_to(golf._lie)
	golf.aim_loft = Shot.LOFT_BIAS_MAX
	golf._pose_preview()
	var flop := golf._preview.landing.distance_to(golf._lie)
	assert_gt(flop, punch + 20.0, "raising loft has to push the landing farther out")
	assert_true(golf._preview.spot_visible())


func test_the_camera_looks_farther_for_a_longer_carry() -> void:
	var golf := GolfController.new()
	add_child_autofree(golf)
	var ball := GolfBall.new()
	add_child_autofree(ball)
	golf.ball = ball
	golf.golfer = Node.new()
	add_child_autofree(golf.golfer)
	ball.global_position = Vector3.ZERO
	golf.aim_yaw = 0.0
	golf.aim_loft = Shot.LOFT_BIAS_MIN
	var punch_look := golf.get_camera_transform().origin.distance_to(Vector3.ZERO)
	golf.aim_loft = Shot.LOFT_BIAS_MAX
	var flop_look := golf.get_camera_transform().origin.distance_to(Vector3.ZERO)
	assert_gt(flop_look, punch_look, "a longer carry has to pull the camera back to show the landing")


func _preview_points(preview: ShotPreview) -> PackedVector3Array:
	var immediate := preview.mesh as ImmediateMesh
	var arrays := immediate.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var points := PackedVector3Array()
	var i := 0
	while i < verts.size():
		points.append((verts[i] + verts[i + 1]) * 0.5)
		i += 2
	return points


func _peak_y(points: PackedVector3Array) -> float:
	var peak := -INF
	for point in points:
		peak = maxf(peak, point.y)
	return peak


## The shaft is built from this gap, so if the grip drifts off the stance the head
## stops meeting the ball.
func test_the_grip_sits_above_the_golfer() -> void:
	var lie := Vector3(-3.0, GolfBall.RADIUS, 7.0)
	var hands := GolfClub.hands_point(lie, 25.0)
	var feet := GolfClub.stance_point(lie, 25.0)
	assert_almost_eq(hands.y - feet.y, GolfClub.HAND_HEIGHT, 0.001)
	assert_almost_eq(Vector2(hands.x, hands.z).distance_to(Vector2(feet.x, feet.z)), 0.0, 0.001)
