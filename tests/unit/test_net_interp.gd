extends GutTest
## Client visual interpolation: glide across the measured gap between snapshots
## rather than the nominal send rate, and snap teleports.

const NOMINAL := 0.05


func _started(nominal := NOMINAL) -> NetInterp:
	var interp := NetInterp.new()
	interp.nominal = nominal
	interp.arrive(Transform3D.IDENTITY, Transform3D.IDENTITY)
	return interp


func _step(interp: NetInterp, seconds: float, step := 1.0 / 60.0) -> Transform3D:
	var pose := interp.sample(0.0)
	var left := seconds
	while left > 0.0:
		pose = interp.sample(minf(step, left))
		left -= step
	return pose


func test_a_glide_outlasts_the_gap_so_the_puppet_never_parks() -> void:
	var interp := _started()
	interp.arrive(Transform3D(Basis(), Vector3(2.0, 0.0, 0.0)), Transform3D.IDENTITY)
	var at_gap := interp.sample(NOMINAL)
	assert_lt(
		at_gap.origin.x, 2.0,
		"still moving when the next snapshot is due, instead of sitting frozen"
	)
	var done := interp.sample(NOMINAL * NetInterp.STRETCH)
	assert_almost_eq(done.origin.x, 2.0, 0.01, "it still lands on the snapshot")


func test_a_late_arrival_stretches_the_next_glide() -> void:
	var interp := _started()
	var late := NOMINAL * 1.6
	var x := 0.0
	for i in 12:
		x += 1.0
		interp.arrive(Transform3D(Basis(), Vector3(x, 0.0, 0.0)), interp.sample(0.0))
		_step(interp, late)
	assert_gt(
		interp.window, NOMINAL * 1.2,
		"a peer that keeps arriving late should be given a longer glide"
	)
	assert_lt(interp.window, late * 1.1, "but not longer than the gap it measured")


func test_a_long_silence_does_not_slow_the_next_move() -> void:
	var interp := _started()
	interp.arrive(Transform3D(Basis(), Vector3(1.0, 0.0, 0.0)), Transform3D.IDENTITY)
	_step(interp, 2.0)
	interp.arrive(Transform3D(Basis(), Vector3(2.0, 0.0, 0.0)), interp.sample(0.0))
	assert_lte(
		interp.window, NOMINAL * NetInterp.WINDOW_MAX_SCALE,
		"a puppet that held still must not crawl when it moves again"
	)
	var done := interp.sample(NOMINAL * NetInterp.WINDOW_MAX_SCALE * NetInterp.STRETCH)
	assert_almost_eq(done.origin.x, 2.0, 0.01)


func test_a_large_jump_snaps() -> void:
	var interp := _started()
	var far := Transform3D(Basis(), Vector3(20.0, 0.0, 0.0))
	interp.arrive(far, Transform3D.IDENTITY)
	var now := interp.sample(0.0)
	assert_almost_eq(now.origin.x, 20.0, 0.01, "a spawn or seat change must not slide")


func test_a_mid_glide_update_starts_from_the_current_pose() -> void:
	var interp := _started()
	interp.arrive(Transform3D(Basis(), Vector3(2.0, 0.0, 0.0)), Transform3D.IDENTITY)
	var mid := interp.sample(0.025)
	interp.arrive(Transform3D(Basis(), Vector3(2.0, 0.0, 2.0)), mid)
	var again := interp.sample(0.0)
	assert_almost_eq(again.origin.x, mid.origin.x, 0.01)
	assert_almost_eq(again.origin.z, 0.0, 0.01)
	var end := interp.sample(NOMINAL * NetInterp.STRETCH)
	assert_almost_eq(end.origin.z, 2.0, 0.01)


func test_follow_writes_the_sampled_pose() -> void:
	var node := Node3D.new()
	add_child_autofree(node)
	var interp := NetInterp.new()
	interp.follow(node, Transform3D.IDENTITY, 0.0, NOMINAL)
	var dest := Transform3D(Basis(), Vector3(2.0, 0.0, 0.0))
	interp.follow(node, dest, NOMINAL * NetInterp.STRETCH, NOMINAL)
	assert_almost_eq(node.global_position.x, 2.0, 0.01)


func test_a_snapshot_that_lands_mid_glide_is_not_a_stall() -> void:
	var interp := _started()
	interp.arrive(Transform3D(Basis(), Vector3(1.0, 0.0, 0.0)), Transform3D.IDENTITY)
	var mid := _step(interp, NOMINAL * 0.5)
	interp.arrive(Transform3D(Basis(), Vector3(2.0, 0.0, 0.0)), mid)
	assert_eq(interp.arrivals, 2, "both moves counted")
	assert_eq(interp.stalls, 0, "arriving while the puppet is still gliding is on time")


func test_a_snapshot_that_lands_after_the_glide_counts_a_stall() -> void:
	var interp := _started()
	interp.arrive(Transform3D(Basis(), Vector3(1.0, 0.0, 0.0)), Transform3D.IDENTITY)
	var parked := _step(interp, NOMINAL * 4.0)
	interp.arrive(Transform3D(Basis(), Vector3(2.0, 0.0, 0.0)), parked)
	assert_eq(interp.stalls, 1, "the puppet sat on its last pose before this one landed")
	assert_almost_eq(interp.stall_percent(), 50.0, 0.01, "one of the two moves stalled")
	assert_gt(interp.worst_gap, NOMINAL * 3.0, "the gap it waited out is reported")


func test_a_puppet_standing_still_reports_no_gap() -> void:
	var interp := _started()
	_step(interp, 3.0)
	interp.arrive(Transform3D.IDENTITY, Transform3D.IDENTITY)
	assert_eq(interp.arrivals, 0, "silence from a parked puppet is not a late packet")
	assert_eq(interp.stalls, 0)
	assert_eq(interp.worst_gap, 0.0)


func test_a_teleport_counts_as_a_snap_not_a_stall() -> void:
	var interp := _started()
	interp.arrive(Transform3D(Basis(), Vector3(20.0, 0.0, 0.0)), Transform3D.IDENTITY)
	assert_eq(interp.snaps, 1, "a spawn or seat change is reported on its own")
	assert_eq(interp.stalls, 0, "and never blamed on the connection")


func test_reset_stats_clears_the_readout_without_disturbing_the_glide() -> void:
	var interp := _started()
	interp.arrive(Transform3D(Basis(), Vector3(1.0, 0.0, 0.0)), Transform3D.IDENTITY)
	_step(interp, NOMINAL * 4.0)
	interp.arrive(Transform3D(Basis(), Vector3(2.0, 0.0, 0.0)), interp.sample(0.0))
	interp.reset_stats()
	assert_eq(interp.stalls, 0)
	assert_eq(interp.arrivals, 0)
	assert_eq(interp.worst_gap, 0.0)
	assert_eq(interp.stall_percent(), 0.0)
	var done := interp.sample(NOMINAL * NetInterp.WINDOW_MAX_SCALE * NetInterp.STRETCH)
	assert_almost_eq(done.origin.x, 2.0, 0.01, "the puppet still reaches its snapshot")


func test_follow_still_catches_a_snapshot_that_skipped_the_setter() -> void:
	var node := Node3D.new()
	add_child_autofree(node)
	var interp := NetInterp.new()
	interp.follow(node, Transform3D.IDENTITY, 0.0, NOMINAL)
	interp.follow(node, Transform3D(Basis(), Vector3(1.0, 0.0, 0.0)), 0.0, NOMINAL)
	assert_almost_eq(interp.to.origin.x, 1.0, 0.01)
