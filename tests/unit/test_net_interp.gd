extends GutTest
## Client visual interpolation: reach the snapshot at the send interval, snap
## teleports, and restart a lerp from the current pose.


func test_a_sample_reaches_the_target_at_the_interval() -> void:
	var interp := NetInterp.new()
	interp.interval = 0.05
	interp.push(Transform3D.IDENTITY, Transform3D.IDENTITY)
	var dest := Transform3D(Basis(), Vector3(2.0, 0.0, 0.0))
	interp.push(dest, Transform3D.IDENTITY)
	var mid := interp.sample(0.025)
	assert_almost_eq(mid.origin.x, 1.0, 0.01)
	var end := interp.sample(0.025)
	assert_almost_eq(end.origin.x, 2.0, 0.01)


func test_a_large_jump_snaps() -> void:
	var interp := NetInterp.new()
	interp.interval = 0.05
	interp.push(Transform3D.IDENTITY, Transform3D.IDENTITY)
	var far := Transform3D(Basis(), Vector3(20.0, 0.0, 0.0))
	interp.push(far, Transform3D.IDENTITY)
	var now := interp.sample(0.0)
	assert_almost_eq(now.origin.x, 20.0, 0.01, "a spawn or seat change must not slide")


func test_a_mid_lerp_update_starts_from_the_current_pose() -> void:
	var interp := NetInterp.new()
	interp.interval = 0.05
	interp.push(Transform3D.IDENTITY, Transform3D.IDENTITY)
	interp.push(Transform3D(Basis(), Vector3(2.0, 0.0, 0.0)), Transform3D.IDENTITY)
	var mid := interp.sample(0.025)
	interp.push(Transform3D(Basis(), Vector3(2.0, 0.0, 2.0)), mid)
	var again := interp.sample(0.0)
	assert_almost_eq(again.origin.x, mid.origin.x, 0.01)
	assert_almost_eq(again.origin.z, 0.0, 0.01)
	var end := interp.sample(0.05)
	assert_almost_eq(end.origin.z, 2.0, 0.01)


func test_follow_writes_the_sampled_pose() -> void:
	var node := Node3D.new()
	add_child_autofree(node)
	var interp := NetInterp.new()
	interp.follow(node, Transform3D.IDENTITY, 0.0, 0.05)
	var dest := Transform3D(Basis(), Vector3(2.0, 0.0, 0.0))
	interp.follow(node, dest, 0.025, 0.05)
	assert_almost_eq(node.global_position.x, 1.0, 0.01)
