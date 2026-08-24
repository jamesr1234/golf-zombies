extends GutTest
## PlayerSwim and PlayerMotion keep the pond / walk rules off the Player facade.


func test_throw_velocity_lifts_and_flies_forward() -> void:
	var velocity := PlayerSwim.throw_velocity(Vector3.FORWARD)
	assert_gt(velocity.y, 0.0)
	assert_lt(velocity.z, 0.0, "Godot forward is -Z")
	assert_almost_eq(velocity.length(), PlayerSwim.SWIM_THROW_SPEED, 0.001)


func test_carry_point_sits_ahead_of_the_hands() -> void:
	var held := Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0))
	var at := PlayerSwim.carry_point(held)
	assert_lt(at.z, held.origin.z)
	assert_lt(at.y, held.origin.y)


func test_hit_push_stays_flat() -> void:
	var push := Player.hit_push(Vector3(0.0, 5.0, -2.0), Vector3.ZERO)
	assert_eq(push.y, 0.0)
	assert_gt(push.length(), 0.0)


func test_motion_boost_counts_stack() -> void:
	var motion := PlayerMotion.new()
	assert_eq(motion.boost_count, 0)
	motion.boost_count += 1
	motion.boost_along = Vector3.FORWARD
	assert_eq(motion.boost_count, 1)
	motion.boost_count += 1
	assert_eq(motion.boost_count, 2)
	motion.exit_boost()
	assert_eq(motion.boost_count, 1)
