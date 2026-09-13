extends GutTest
## HoleData.shift moves every world-space point with the height field.

const SEED := 20260816


func test_shift_moves_tee_bounds_and_height_together() -> void:
	var hole := HoleGenerator.generate(0, SEED)
	var before_tee := hole.tee
	var before_cup := hole.cup
	var before_practice := hole.practice_tee
	var before_bounds := hole.bounds
	var tee_height := hole.height.height_at(before_tee.x, before_tee.z)
	var cup_height := hole.height.height_at(before_cup.x, before_cup.z)
	var offset := Vector3(24.0, 0.0, -18.0)
	hole.shift(offset)
	assert_almost_eq(hole.tee.x, before_tee.x + offset.x, 0.001)
	assert_almost_eq(hole.tee.z, before_tee.z + offset.z, 0.001)
	assert_almost_eq(hole.cup.x, before_cup.x + offset.x, 0.001)
	assert_almost_eq(hole.practice_tee.x, before_practice.x + offset.x, 0.001)
	assert_almost_eq(hole.bounds.position.x, before_bounds.position.x + offset.x, 0.001)
	assert_almost_eq(hole.bounds.position.y, before_bounds.position.y + offset.z, 0.001)
	assert_almost_eq(hole.height.height_at(hole.tee.x, hole.tee.z), tee_height, 0.15)
	assert_almost_eq(hole.height.height_at(hole.cup.x, hole.cup.z), cup_height, 0.15)


func test_a_zero_shift_leaves_the_hole_alone() -> void:
	var hole := HoleGenerator.generate(0, SEED)
	var tee := hole.tee
	hole.shift(Vector3.ZERO)
	assert_eq(hole.tee, tee)


func test_rotate_y_turns_the_fairway_and_keeps_the_deck() -> void:
	var hole := HoleGenerator.generate(0, SEED)
	var before_tee := hole.tee
	var before_cup := hole.cup
	var before_along := hole.along_tee()
	var before_yaw := float(hole.patches[0]["yaw"])
	var tee_height := hole.height.height_at(before_tee.x, before_tee.z)
	var cup_height := hole.height.height_at(before_cup.x, before_cup.z)
	var yaw := deg_to_rad(90.0)
	hole.rotate_y(yaw)
	var spun_tee := before_tee.rotated(Vector3.UP, yaw)
	var spun_cup := before_cup.rotated(Vector3.UP, yaw)
	assert_almost_eq(hole.tee.x, spun_tee.x, 0.001)
	assert_almost_eq(hole.tee.z, spun_tee.z, 0.001)
	assert_almost_eq(hole.cup.x, spun_cup.x, 0.001)
	assert_almost_eq(hole.cup.z, spun_cup.z, 0.001)
	assert_almost_eq(float(hole.patches[0]["yaw"]), before_yaw + 90.0, 0.01)
	assert_almost_eq(
		hole.height.height_at(hole.tee.x, hole.tee.z), tee_height, 0.15
	)
	assert_almost_eq(
		hole.height.height_at(hole.cup.x, hole.cup.z), cup_height, 0.15
	)
	assert_almost_eq(hole.height.height_at(hole.tee.x, hole.tee.z), HeightField.DECK, 0.15)
	var expected := before_along.rotated(Vector3.UP, yaw)
	assert_almost_eq(hole.along_tee().x, expected.x, 0.08)
	assert_almost_eq(hole.along_tee().z, expected.z, 0.08)


func test_pave_for_path_then_face_keeps_the_lane_flat() -> void:
	var hole := HoleGenerator.generate(1, SEED)
	var incoming := Vector3.RIGHT
	var target := Vector3(40.0, 0.0, 80.0)
	var start := target - incoming * 40.0
	var line: Array[Vector3] = [start, target]
	hole.pave_for_path(line, incoming, target)
	var node := Node3D.new()
	add_child_autofree(node)
	hole.face_arrival(node, incoming, target)
	assert_gt(hole.along_tee().dot(incoming), 0.95)
	assert_almost_eq(hole.arrival_point().x, target.x, 0.05)
	assert_almost_eq(hole.arrival_point().z, target.z, 0.05)
	var mid := start.lerp(target, 0.5)
	assert_almost_eq(
		hole.height.height_at(mid.x, mid.z), HeightField.DECK, 0.35,
		"the incoming lane is deck after the hole is rotated into place"
	)
	var behind := hole.arrival_point() - hole.along_tee() * 12.0
	assert_almost_eq(
		hole.height.height_at(behind.x, behind.z), HeightField.DECK, 0.35,
		"the apron behind the arrival stays flat"
	)


func test_the_mech_stands_left_of_the_play_tee() -> void:
	var hole := HoleGenerator.generate(0, SEED)
	var stand := hole.mech_stand()
	assert_lt(stand.distance_to(hole.tee), 10.0)
	assert_gt(stand.distance_to(hole.practice_tee), 15.0)
	var left := Vector3.UP.cross(hole.along_tee()).normalized()
	assert_gt((stand - hole.tee).dot(left), 5.0)
	assert_gt((stand - hole.tee).dot(hole.along_tee()), 0.0, "slightly toward the hole")
