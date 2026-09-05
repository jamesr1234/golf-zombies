extends GutTest
## Hole 11 is Test Hole 2: a four-thousand-yard par 5 that runs like a circuit.

const _RaceLane := preload("res://scripts/course/race_lane.gd")


func test_test_hole_two_is_a_four_thousand_yard_par_five() -> void:
	var hole := HoleGenerator.generate(RaceHole.INDEX, 20260816)
	assert_true(RaceHole.applies(hole))
	assert_eq(hole.par, RaceHole.PAR)
	assert_almost_eq(hole.length(), RaceHole.LENGTH, 0.2)
	assert_eq(hole.yardage(), RaceHole.YARDS)
	assert_eq(hole.yardage_label(), "4000 yd")
	assert_eq(hole.label(), "Test Hole 2  Par 5")
	assert_eq(hole.banner_title(), "Test Hole 2   Par 5")
	assert_eq(hole.sign_text(), "TEST HOLE 2\n4000 yd")
	assert_almost_eq(
		HoleGenerator.fairway_width(hole.par, hole.index),
		RaceHole.WIDTH,
		0.01
	)
	var band := HoleGenerator.length_range(hole.par)
	assert_gt(hole.length(), band.y, "4000 yards is past a normal par 5")
	assert_true(RaceHole.WARMUP.begins_with("Four thousand yards"))


func test_the_fairway_is_a_wide_circuit() -> void:
	var hole := HoleGenerator.generate(RaceHole.INDEX, 20260816)
	assert_eq(RaceHole.FOLDS, 3)
	assert_gt(RaceHole.WIDTH, 44.0, "the strip is several cart-lanes wide")
	assert_gt(
		RaceHole.TURN_R,
		RaceHole.WIDTH * 0.5 + 8.0,
		"U-turns sit outside the strip so the return is real rough, not more fairway"
	)
	assert_gt(RaceHole.infield_gap(), 70.0, "neighbouring strips do not paint together")
	assert_eq(_RaceLane.wrong_side_count(hole), 0, "rails stay on their own side of the strip")
	var along := hole.along_tee()
	assert_almost_eq(along.x, 0.0, 0.02)
	assert_lt(along.z, -0.9, "the start faces down the front straight")
	add_child_autofree(_RaceLane.create(hole))


func test_the_corners_are_a_few_sweeping_u_turns() -> void:
	var angles := RaceHole.turn_angles()
	assert_eq(angles.size(), RaceHole.FOLDS, "a handful of U-turns, not a hairpin stack")
	for angle in angles:
		assert_almost_eq(absf(angle), 180.0, 1.5, "sweeping 180s, not chicanes")


func test_the_strip_has_speed_pads_and_ramps() -> void:
	var data := HoleGenerator.generate(RaceHole.INDEX, 20260816)
	assert_gte(data.boosts.size(), 24, "speed rectangles tile the straights")
	assert_gte(data.jumps.size(), 3, "ramps on the long stretches")
	for boost in data.boosts:
		assert_gt(float(boost["width"]), CartPathBoost.WIDTH, "race pads are rectangles, not stripes")
		assert_gt(
			boost["from"].distance_to(boost["to"]),
			RaceHole.BOOST_LEN * 0.8
		)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	assert_gte(get_tree().get_nodes_in_group("transit_boost").size(), 24)
	assert_gte(root.find_children("*", "JumpRamp", true, false).size(), 3)
	var track_car := root.find_child("TrackRaceCar", true, false) as GolfCart
	assert_not_null(track_car, "a race car waits on the tee")
	assert_true(track_car.is_in_group("golf_carts"))
	assert_lt(
		track_car.position.distance_to(data.tee),
		6.0,
		"the race car starts on the tee, not down the strip"
	)
	assert_lt(
		HoleGenerator.distance_to_centerline(data, track_car.position),
		RaceHole.WIDTH * 0.5,
		"the race car parks on the driveable strip, not the paddock"
	)
	assert_not_null(root.find_child("DropRaceCar", true, false))


func test_the_built_hole_keeps_a_cup_and_a_hoop() -> void:
	var data := HoleGenerator.generate(RaceHole.INDEX, 20260816)
	assert_true(data.has_race_hoop())
	assert_lt(
		data.tee.distance_to(data.race_hoop),
		Shot.max_carry(),
		"the hoop has to be a drive, not a lay-up"
	)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	assert_gt(root.find_children("*", "Cup", true, false).size(), 0)
	assert_null(root.find_child("SoccerGoal", true, false))
	assert_not_null(root.find_child("RaceHoop", true, false))
	var lane := root.find_child("RaceLane", true, false)
	assert_not_null(lane)
	assert_false(lane.is_lit(), "the rails stay dark until the hoop")
	assert_false(lane.visible)
	lane.ignite()
	assert_true(lane.is_lit())
	assert_true(lane.visible)
	var signs := get_tree().get_nodes_in_group("hole_signs")
	assert_eq(signs.size(), 1)
	var yard := signs[0].get_node("YardCopy") as Label3D
	assert_eq(yard.text, "4000 yd")


func test_the_drop_lands_about_five_hundred_yards_from_the_cup() -> void:
	var hole := HoleGenerator.generate(RaceHole.INDEX, 20260816)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260816
	var remain_m := float(RaceHole.DROP_YARDS) * RaceHole.METRE
	for _i in 12:
		var at := RaceHole.drop_point(hole, rng)
		assert_almost_eq(RaceHole.remaining(hole, at), remain_m, RaceHole.DROP_ALONG + 8.0)
		assert_lt(
			HoleGenerator.distance_to_centerline(hole, at),
			RaceHole.WIDTH * 0.5,
			"the drop stays on the strip"
		)


func test_a_ball_through_the_hoop_jumps_down_the_hole() -> void:
	var data := HoleGenerator.generate(RaceHole.INDEX, 20260816)
	var hoop := RaceHoop.create(data)
	add_child_autofree(hoop)
	var lane = _RaceLane.new()
	lane.name = "RaceLane"
	add_child_autofree(lane)
	assert_false(lane.is_lit())
	var ball := preload("res://scenes/golf/ball.tscn").instantiate() as GolfBall
	add_child_autofree(ball)
	var from := hoop.to_global(Vector3(0.0, RaceHoop.OUTER, -1.6))
	var into := hoop.global_transform.basis * Vector3(0.0, 0.0, 22.0)
	ball.toss(from, into)
	await wait_physics_frames(16)
	assert_false(ball.is_holed(), "the hoop is a gate, not the cup")
	var remain_m := float(RaceHole.DROP_YARDS) * RaceHole.METRE
	assert_almost_eq(
		RaceHole.remaining(data, ball.global_position),
		remain_m,
		RaceHole.DROP_ALONG + 12.0
	)
	assert_gt(ball.global_position.distance_to(hoop.global_position), 200.0)
	assert_true(lane.is_lit(), "the hoop lights the driveable rails")


func test_the_overlay_dresses_the_start_finish() -> void:
	var packed := load("res://scenes/course/holes/hole_11.tscn") as PackedScene
	assert_not_null(packed)
	var root: Node3D = packed.instantiate()
	add_child_autofree(root)
	assert_eq(root.get("hole_index"), RaceHole.INDEX)
	assert_not_null(root.get_node_or_null("Grandstand"))
	assert_not_null(root.get_node_or_null("Colonnade"))
	assert_not_null(root.get_node_or_null("RaceCar"))
	assert_not_null(HoleOverlay.packed_for(RaceHole.INDEX))
