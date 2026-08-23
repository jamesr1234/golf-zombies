extends GutTest
## Client visual interpolation: hold arriving snapshots and draw the puppet a
## fixed step behind the newest one, so a clump of late packets still has
## something queued to move across. Teleports skip the queue.

const NOMINAL := 0.05
const DELAY := 0.1


func _started() -> NetInterp:
	var interp := NetInterp.new()
	interp.nominal = NOMINAL
	interp.delay = DELAY
	interp.arrive(Transform3D.IDENTITY)
	return interp


func _at(x: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, 0.0, 0.0))


func _step(interp: NetInterp, seconds: float, step := 1.0 / 60.0) -> Transform3D:
	var pose := interp.sample(0.0)
	var left := seconds
	while left > 0.0:
		pose = interp.sample(minf(step, left))
		left -= step
	return pose


## Feed snapshots at the send rate for a while, so the queue is in the steady
## state a match actually runs in rather than the one it starts in.
func _stream(interp: NetInterp, from_x: float, count: int, every := NOMINAL) -> float:
	var x := from_x
	for _i in count:
		_step(interp, every)
		x += 1.0
		interp.arrive(_at(x))
	return x


func test_the_puppet_is_drawn_behind_the_newest_snapshot() -> void:
	var interp := _started()
	var x := _stream(interp, 0.0, 8)
	var drawn := interp.sample(0.0).origin.x
	assert_lt(drawn, x, "it is deliberately behind the newest pose")
	assert_almost_eq(
		drawn, x - DELAY / NOMINAL, 0.35,
		"by the delay, which at this send rate is two snapshots back"
	)


func test_a_clump_of_late_packets_keeps_the_puppet_moving() -> void:
	var interp := _started()
	var x := _stream(interp, 0.0, 8)
	# Nothing arrives for two send intervals, the shape jitter takes on the wire.
	var before := interp.sample(0.0).origin.x
	var during := _step(interp, NOMINAL * 2.0).origin.x
	assert_gt(during, before, "the queue carried it through the silence")
	assert_lte(during, x, "without running past what it was told")


func test_the_puppet_parks_only_once_the_queue_is_spent() -> void:
	var interp := _started()
	_stream(interp, 0.0, 8)
	var run_dry := _step(interp, DELAY + NOMINAL * 3.0)
	var still := _step(interp, NOMINAL * 2.0)
	assert_almost_eq(still.origin.x, run_dry.origin.x, 0.001, "nothing left to draw from")


## A packet landing after the queue ran dry used to throw the puppet to wherever
## the timeline said it should already have got to, so a long gap read as a
## freeze and then a teleport. The draw keeping its own pace is what fixes it.
func test_a_very_late_packet_does_not_jump_the_puppet_forward() -> void:
	var interp := _started()
	var x := _stream(interp, 0.0, 8)
	var parked := _step(interp, DELAY + NOMINAL * 4.0).origin.x
	interp.arrive(_at(x + 1.0))
	var resumed := interp.sample(1.0 / 60.0).origin.x
	assert_gt(resumed, parked, "it does start moving again")
	assert_lt(resumed - parked, 0.5, "but carries on from where it stopped, not from the clock")


func test_the_queue_deepens_when_the_link_makes_gaps_it_cannot_cover() -> void:
	var interp := _started()
	var x := _stream(interp, 0.0, 6)
	assert_almost_eq(interp.depth, DELAY, 0.01, "a clean link sits at what was asked for")
	for _i in 4:
		_step(interp, DELAY * 2.5)
		x += 1.0
		interp.arrive(_at(x))
	assert_gt(interp.depth, DELAY, "gaps this wide need more queue than that")
	assert_lte(interp.depth, NetInterp.MAX_DEPTH, "though only so much is worth holding")


func test_a_link_that_settles_earns_its_responsiveness_back() -> void:
	var interp := _started()
	var x := _stream(interp, 0.0, 4)
	for _i in 3:
		_step(interp, DELAY * 2.5)
		x += 1.0
		interp.arrive(_at(x))
	var deep := interp.depth
	assert_gt(deep, DELAY, "the bad patch bought depth")
	_stream(interp, x, 400)
	assert_lt(interp.depth, deep, "and clean play hands it back")


func test_a_snapshot_after_the_queue_ran_dry_counts_a_stall() -> void:
	var interp := _started()
	var x := _stream(interp, 0.0, 8)
	assert_eq(interp.stalls, 0, "a stream arriving on time never parks")
	_step(interp, DELAY + NOMINAL * 4.0)
	interp.arrive(_at(x + 1.0))
	assert_eq(interp.stalls, 1, "the puppet sat on its last pose before this one landed")
	assert_gt(interp.worst_gap, NOMINAL * 3.0, "the gap it waited out is reported")


func test_a_steady_stream_reports_no_stalls() -> void:
	var interp := _started()
	_stream(interp, 0.0, 40)
	assert_gt(interp.arrivals, 30, "the moves were counted")
	assert_eq(interp.stalls, 0, "a link this clean has nothing to report")
	assert_eq(interp.stall_percent(), 0.0)


func test_a_large_jump_snaps() -> void:
	var interp := _started()
	interp.arrive(_at(20.0))
	assert_almost_eq(
		interp.sample(0.0).origin.x, 20.0, 0.01, "a spawn or seat change must not slide"
	)


func test_a_teleport_counts_as_a_snap_not_a_stall() -> void:
	var interp := _started()
	interp.arrive(_at(20.0))
	assert_eq(interp.snaps, 1, "a spawn or seat change is reported on its own")
	assert_eq(interp.stalls, 0, "and never blamed on the connection")


## The drawn pose trails the newest snapshot on purpose, so measuring a teleport
## against it would read a fast cart as one and snap every frame.
func test_a_fast_mover_is_not_mistaken_for_a_teleport() -> void:
	var interp := _started()
	var x := 0.0
	for _i in 20:
		_step(interp, NOMINAL)
		x += 1.5
		interp.arrive(_at(x))
	assert_eq(interp.snaps, 0, "steady ground covered at speed is still just moving")


func test_a_puppet_standing_still_reports_no_gap() -> void:
	var interp := _started()
	for _i in 20:
		_step(interp, NOMINAL)
		interp.arrive(Transform3D.IDENTITY)
	assert_eq(interp.arrivals, 0, "silence from a parked puppet is not a late packet")
	assert_eq(interp.stalls, 0)
	assert_eq(interp.worst_gap, 0.0)


func test_the_worst_gap_fades_so_one_bad_moment_does_not_stand_all_match() -> void:
	var interp := _started()
	var x := _stream(interp, 0.0, 4)
	_step(interp, NOMINAL * 5.0)
	x += 1.0
	interp.arrive(_at(x))
	var bad := interp.worst_gap
	assert_gt(bad, NOMINAL * 4.0, "the hiccup is on the board")
	_stream(interp, x, int(NetInterp.WORST_HOLD / NOMINAL) + 2)
	assert_lt(interp.worst_gap, bad, "a clean run since then takes it back down")


func test_reset_stats_clears_the_readout_without_disturbing_the_draw() -> void:
	var interp := _started()
	var x := _stream(interp, 0.0, 8)
	var drawn := interp.sample(0.0)
	interp.reset_stats()
	assert_eq(interp.arrivals, 0)
	assert_eq(interp.worst_gap, 0.0)
	assert_eq(interp.stall_percent(), 0.0)
	assert_almost_eq(interp.sample(0.0).origin.x, drawn.origin.x, 0.01, "still mid draw")
	_step(interp, DELAY + NOMINAL * 3.0)
	assert_almost_eq(interp.sample(0.0).origin.x, x, 0.01, "and still reaches its snapshot")


func test_follow_writes_the_sampled_pose() -> void:
	var node := Node3D.new()
	add_child_autofree(node)
	var interp := NetInterp.new()
	interp.follow(node, Transform3D.IDENTITY, 0.0, NOMINAL, DELAY)
	interp.follow(node, _at(2.0), DELAY + NOMINAL, NOMINAL, DELAY)
	assert_almost_eq(node.global_position.x, 2.0, 0.01)


## Nothing can be drawn between two snapshots until both have arrived, so asking
## for less delay than the send rate cannot be honoured.
func test_the_queue_is_never_shorter_than_the_gap_between_sends() -> void:
	var node := Node3D.new()
	add_child_autofree(node)
	var interp := NetInterp.new()
	interp.follow(node, Transform3D.IDENTITY, 0.0, NOMINAL, 0.0)
	assert_eq(interp.delay, NOMINAL)


func test_follow_still_catches_a_snapshot_that_skipped_the_setter() -> void:
	var node := Node3D.new()
	add_child_autofree(node)
	var interp := NetInterp.new()
	interp.follow(node, Transform3D.IDENTITY, 0.0, NOMINAL, DELAY)
	interp.follow(node, _at(1.0), 0.0, NOMINAL, DELAY)
	assert_eq(interp.arrivals, 1, "the snapshot was picked up without the setter")
