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
