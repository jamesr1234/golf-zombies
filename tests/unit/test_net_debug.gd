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


## Godot counts drawing and the vsync wait inside its process timer, so that
## number only ever restates the frame time. The card's own time is the one that
## tells a fill-rate problem from a code one.
func test_the_overlay_reports_the_card_time_not_the_process_timer() -> void:
	var body := _overlay().report(0.016)
	assert_true(body.contains("gpu"), body)
	assert_false(body.contains("process"), "the process timer cannot separate cpu from gpu")


## A hitch on a steady beat is the signature of something on a timer, so the
## readout has to say how long the beat is rather than only that it happened.
func test_the_overlay_times_the_gap_between_two_hitches() -> void:
	var debug := _overlay()
	debug._track_frame(0.05)
	for _i in 30:
		debug._track_frame(1.0 / 60.0)
	debug._track_frame(0.05)
	assert_almost_eq(debug._spike_period, 0.55, 0.01, "half a second of good frames, then a hitch")
	assert_true(debug.report(0.016).contains("hitch every 0.55 s"), debug.report(0.016))


func test_a_hitch_reports_the_nodes_that_arrived_on_it() -> void:
	var debug := _overlay()
	debug._nodes_seen = NetDebug.node_count() - 40
	debug._track_frame(0.05)
	assert_eq(debug._spike_grew, 40, "the spawn that caused the hitch shows up as nodes")
	assert_true(debug.report(0.016).contains("+40 nodes"), debug.report(0.016))


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


## The trap this guards: on a machine slow enough that every frame is a spike, an
## unthrottled dump prints every frame and becomes its own bottleneck.
func test_a_constant_spike_cannot_log_every_frame() -> void:
	assert_false(
		NetDebug.due_to_log(true, 1.0 / 15.0),
		"a spiking frame right after a dump must wait"
	)
	assert_true(NetDebug.due_to_log(true, NetDebug.LOG_MIN_GAP), "but not wait forever")


func test_a_quiet_run_still_logs_on_the_slow_tick() -> void:
	assert_false(NetDebug.due_to_log(false, NetDebug.LOG_MIN_GAP), "no spike, no early dump")
	assert_true(NetDebug.due_to_log(false, NetDebug.LOG_EVERY))


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
