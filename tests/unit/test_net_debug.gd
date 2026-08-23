extends GutTest
## The F3 overlay dumps the same lines to the Output log so a hitch can be
## copied after the match.


func _overlay() -> NetDebug:
	var debug := NetDebug.new()
	add_child_autofree(debug)
	return debug


func test_a_long_frame_counts_as_a_spike() -> void:
	var debug := _overlay()
	assert_false(debug._track_frame(0.016), "a 60 Hz frame is on time")
	assert_true(debug._track_frame(0.05), "30 ms and up is a hitch")
	var body := debug.report(0.016)
	assert_true(body.contains("spikes 1"), body)


func test_dump_prints_the_same_lines_as_the_overlay() -> void:
	var debug := _overlay()
	debug._track_frame(0.05)
	var body := debug.dump(0.016)
	assert_eq(body, debug.report(0.016))
	assert_true(body.contains("spikes 1"), body)
	assert_true(body.contains("no remote puppets"), body)


func test_hiding_the_overlay_dumps_one_last_reading() -> void:
	var debug := _overlay()
	debug.toggle()
	debug._last_delta = 0.016
	debug._track_frame(0.04)
	var body := debug.toggle()
	assert_false(debug.visible)
	assert_true(body.contains("spikes 1"), body)


func test_line_for_a_puppet_reports_gap_and_stall() -> void:
	var interp := NetInterp.new()
	interp.nominal = 0.05
	interp.arrive(Transform3D.IDENTITY, Transform3D.IDENTITY)
	interp.arrive(Transform3D(Basis(), Vector3(1.0, 0.0, 0.0)), Transform3D.IDENTITY)
	interp.sample(0.2)
	interp.arrive(
		Transform3D(Basis(), Vector3(2.0, 0.0, 0.0)),
		Transform3D(Basis(), Vector3(1.0, 0.0, 0.0))
	)
	var line := NetDebug.line_for("p2", interp)
	assert_true(line.contains("p2"), line)
	assert_true(line.contains("stall"), line)
	assert_gt(interp.stalls, 0)
