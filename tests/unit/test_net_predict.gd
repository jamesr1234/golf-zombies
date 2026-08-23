extends GutTest
## Reconciling a body that ran the host's input against the host's account of
## where that input took it.


func _line(steps := 40, step := 0.25) -> PackedVector3Array:
	var track: PackedVector3Array = []
	for i in steps:
		track.append(Vector3(float(i) * step, 0.0, 0.0))
	return track


func _body(at: Vector3) -> Node3D:
	var node := Node3D.new()
	add_child_autofree(node)
	node.global_position = at
	return node


func _walked(predict: NetPredict, track: PackedVector3Array) -> void:
	for point in track:
		predict.remember(point)


## The whole point of matching against the path rather than the position: a body
## running the host's input is always ahead of the host's account of it, because
## that account crossed the network to get here. Read as error, that head start
## would drag it backwards on every snapshot.
func test_a_body_ahead_of_the_hosts_account_has_not_drifted() -> void:
	var behind := Vector3(4.0, 0.0, 0.0)
	assert_almost_eq(
		NetPredict.nearest(_line(), behind).distance_to(behind), 0.0, 0.001,
		"the host is describing a place the body really did pass through"
	)


func test_a_body_shoved_off_its_line_reports_the_whole_gap() -> void:
	var shoved := Vector3(4.0, 0.0, 6.0)
	assert_almost_eq(
		NetPredict.nearest(_line(), shoved).distance_to(shoved), 6.0, 0.001,
		"nothing on the path went near there, so it is a real disagreement"
	)
	assert_gt(6.0, NetPredict.SNAP, "and far enough to hand the body back")


func test_running_the_hosts_line_late_is_left_alone() -> void:
	var predict := NetPredict.new()
	_walked(predict, _line())
	var body := _body(Vector3(9.75, 0.0, 0.0))
	var handed := predict.correct(body, Transform3D(Basis(), Vector3(4.0, 0.0, 0.0)), 1.0 / 60.0)
	assert_false(handed, "being late is not being wrong")
	assert_almost_eq(
		body.global_position.x, 9.75, 0.001, "and must not be dragged back down the line"
	)


func test_a_small_disagreement_is_closed_gently() -> void:
	var predict := NetPredict.new()
	_walked(predict, _line())
	var body := _body(Vector3(9.75, 0.0, 0.0))
	var off := NetPredict.SLACK * 8.0
	predict.correct(body, Transform3D(Basis(), Vector3(4.0, 0.0, off)), 1.0 / 60.0)
	assert_gt(body.global_position.z, 0.0, "it does move toward the host")
	assert_lt(body.global_position.z, off * 0.5, "but nothing like all the way in one frame")


func test_a_real_divergence_hands_the_body_straight_back() -> void:
	var predict := NetPredict.new()
	_walked(predict, _line())
	var body := _body(Vector3(9.75, 0.0, 0.0))
	var host := Transform3D(Basis(), Vector3(4.0, 0.0, NetPredict.SNAP + 1.0))
	assert_true(predict.correct(body, host, 1.0 / 60.0))
	assert_almost_eq(body.global_position.distance_to(host.origin), 0.0, 0.001)


## Nothing to match against yet is not the same as agreeing, and guessing either
## way would move a body that has not been anywhere.
func test_a_body_with_no_path_yet_is_not_touched() -> void:
	var body := _body(Vector3(9.75, 0.0, 0.0))
	var predict := NetPredict.new()
	assert_false(predict.correct(body, Transform3D(Basis(), Vector3.ZERO), 1.0 / 60.0))
	assert_almost_eq(body.global_position.x, 9.75, 0.001)


func test_the_path_does_not_grow_without_end() -> void:
	var predict := NetPredict.new()
	_walked(predict, _line(600, 0.05))
	var far_behind := Vector3(0.0, 0.0, 0.0)
	assert_gt(
		NetPredict.nearest(_line(600, 0.05), far_behind).distance_to(far_behind), -1.0,
		"the helper still answers"
	)
	var body := _body(Vector3(30.0, 0.0, 0.0))
	# Only the last stretch is kept, so the start of a long walk is forgotten and
	# the host claiming the body is back there reads as divergence, not lateness.
	assert_true(predict.correct(body, Transform3D(Basis(), far_behind), 1.0 / 60.0))
