extends GutTest
## Launch curve for the one club: putts stay flat, chips stay low, full swings
## still carry the same distance the hole generator plans around.


func test_green_and_fringe_are_the_putting_surfaces() -> void:
	assert_true(Shot.can_putt(Surface.Type.GREEN))
	assert_true(Shot.can_putt(Surface.Type.FRINGE))
	for type in [Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.BUNKER, Surface.Type.TEE]:
		assert_false(Shot.can_putt(type), "%s is a swing, not a putt" % Surface.name_of(type))


func test_a_bright_green_grid_is_a_putting_surface() -> void:
	for type in [
		Surface.Type.ROUGH, Surface.Type.FAIRWAY, Surface.Type.TEE, Surface.Type.FRINGE,
		Surface.Type.BUNKER, Surface.Type.GREEN, Surface.Type.WATER
	]:
		assert_eq(
			Shot.can_putt(type), Surface.looks_like_green(type),
			"%s putting has to match the bright green grid look" % Surface.name_of(type)
		)
	assert_true(Surface.looks_like_green(Surface.Type.GREEN))
	assert_true(Surface.looks_like_green(Surface.Type.FRINGE), "the collar still reads as a putting grid")
	assert_false(Surface.looks_like_green(Surface.Type.FAIRWAY), "the fairway is coarser grass")


func test_a_putt_stays_on_the_ground() -> void:
	for type in [Surface.Type.GREEN, Surface.Type.FRINGE]:
		var launch := Shot.velocity(0.0, 0.0, 0.6, type, true)
		assert_almost_eq(launch.y, 0.0, 0.001, "%s putts have to stay horizontal" % Surface.name_of(type))
		assert_gt(launch.length(), 0.0)


func test_a_max_putt_has_real_pace() -> void:
	var tap := Shot.velocity(0.0, 0.0, 0.0, Surface.Type.GREEN, true)
	var full := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.GREEN, true)
	assert_almost_eq(tap.length(), Shot.PUTT_MIN_SPEED, 0.001)
	assert_almost_eq(full.length(), Shot.putt_max_speed(), 0.001)
	assert_gt(full.length(), tap.length() * 8.0, "a stuffed putt has to cross a big green")


func test_a_max_putt_is_two_point_four_green_spans() -> void:
	assert_almost_eq(Shot.PUTT_SPAN_MULT, 2.4, 0.001)
	assert_almost_eq(
		Shot.putt_run(), Shot.default_green_span() * Shot.PUTT_SPAN_MULT, 0.001
	)
	var wide := 22.0
	assert_almost_eq(Shot.putt_run(null, wide), wide * Shot.PUTT_SPAN_MULT, 0.001)
	var launch := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.GREEN, true, null, wide)
	assert_almost_eq(launch.length(), Shot.putt_max_speed(null, wide), 0.001)
	assert_gt(
		Shot.putt_run(null, 22.0), Shot.putt_run(null, 16.0),
		"a bigger green has to take a longer stuffed putt"
	)


func test_a_full_putt_is_a_roll_not_a_chip() -> void:
	var putt := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.GREEN, true)
	var swing := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false)
	var chip := Shot.velocity(0.0, 0.0, Shot.CHIP_BLEND, Surface.Type.FAIRWAY, false)
	assert_almost_eq(putt.y, 0.0, 0.001)
	assert_lt(putt.length(), swing.length() * 0.65, "a stuffed putt cannot carry like a drive")
	assert_lt(putt.length(), chip.length() * 1.25, "and it still has to stay a roll, not a chip")
	assert_lt(Shot.putt_run(), Shot.max_carry() * 0.5, "green speed is a roll across the green")


func test_the_green_putts_even_if_the_flag_is_wrong() -> void:
	var launch := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.GREEN, false)
	assert_almost_eq(launch.y, 0.0, 0.001)
	assert_almost_eq(launch.length(), Shot.putt_max_speed(), 0.001)
	assert_almost_eq(
		Shot.velocity(0.0, 0.0, 0.4, Surface.Type.FRINGE, false).y, 0.0, 0.001
	)


func test_a_low_power_swing_is_a_chip() -> void:
	var tap := SwingMeter.MIN_POWER
	assert_lt(Shot.launch_deg(tap), 12.0, "a tap should not fly at full loft")
	assert_lt(Shot.swing_speed(tap), Shot.MIN_SPEED, "and it has to be slower than the old floor")


func test_full_power_matches_the_old_full_swing() -> void:
	assert_almost_eq(Shot.launch_deg(1.0), Shot.LAUNCH_DEG, 0.001)
	assert_almost_eq(Shot.swing_speed(1.0), Shot.MAX_SPEED, 0.001)
	var expected := Shot.MAX_SPEED * Shot.MAX_SPEED * sin(2.0 * deg_to_rad(Shot.LAUNCH_DEG)) / Shot.GRAVITY
	assert_almost_eq(Shot.max_carry(), expected, 0.001)
	var play := Shot.MAX_SPEED * sqrt(Shot.DISTANCE_SCALE)
	var vy := play * sin(deg_to_rad(Shot.LAUNCH_DEG))
	assert_almost_eq(Shot.apex_height(), vy * vy / (2.0 * Shot.GRAVITY), 0.001)
	assert_almost_eq(Shot.carry_to_height(0.0), Shot.max_carry() * Shot.DISTANCE_SCALE, 0.001)
	assert_lt(Shot.carry_to_height(Shot.apex_height() * 0.5), Shot.max_carry() * Shot.DISTANCE_SCALE)
	assert_eq(Shot.carry_to_height(Shot.apex_height() + 1.0), 0.0)


func test_the_chip_curve_meets_the_full_swing() -> void:
	var blend := Shot.CHIP_BLEND
	assert_almost_eq(Shot.launch_deg(blend), Shot.LAUNCH_DEG, 0.001)
	assert_almost_eq(
		Shot.swing_speed(blend), lerpf(Shot.MIN_SPEED, Shot.MAX_SPEED, blend), 0.001,
		"no speed jump when a chip becomes a swing"
	)


func test_a_fairway_chip_still_has_some_loft() -> void:
	var launch := Shot.velocity(0.0, 0.0, 0.12, Surface.Type.FAIRWAY, false)
	assert_gt(launch.y, 0.0)
	assert_lt(rad_to_deg(atan2(launch.y, Vector2(launch.x, launch.z).length())), Shot.LAUNCH_DEG)


func test_an_unspecified_kit_is_the_starter() -> void:
	var with_kit := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false, ClubKit.starter())
	var without := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false)
	assert_almost_eq(with_kit.length(), without.length(), 0.001)


func test_loft_bias_raises_and_lowers_launch() -> void:
	var stock := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false)
	var high := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false, null, 0.0, 20.0)
	var low := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false, null, 0.0, -12.0)
	assert_gt(high.y, stock.y)
	assert_lt(low.y, stock.y)
	assert_almost_eq(high.length(), stock.length(), 0.001)
	assert_almost_eq(Shot.launch_deg(1.0, 0.0), Shot.LAUNCH_DEG, 0.001)
	assert_almost_eq(Shot.launch_deg(1.0, -100.0), Shot.MIN_LAUNCH_DEG, 0.001)
	assert_almost_eq(Shot.launch_deg(1.0, 100.0), Shot.MAX_LAUNCH_DEG, 0.001)


func test_swings_carry_three_times_farther_and_putts_do_not() -> void:
	assert_almost_eq(Shot.DISTANCE_SCALE, 3.0, 0.001)
	assert_almost_eq(Shot.carry_to_height(0.0), Shot.max_carry() * 3.0, 0.001)
	var putt := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.GREEN, true)
	assert_almost_eq(putt.length(), Shot.putt_max_speed(), 0.001)
	var swing := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false)
	assert_almost_eq(swing.length(), Shot.MAX_SPEED * sqrt(Shot.DISTANCE_SCALE), 0.001)


func test_max_carry_ignores_the_stick_so_holes_stay_put() -> void:
	var expected := Shot.MAX_SPEED * Shot.MAX_SPEED * sin(2.0 * deg_to_rad(Shot.LAUNCH_DEG)) / Shot.GRAVITY
	assert_almost_eq(Shot.max_carry(), expected, 0.001)
	assert_gt(Shot.apex_height(1.0, 20.0), Shot.apex_height())


func test_a_higher_loft_draws_a_taller_perfect_flight() -> void:
	var low := Shot.flight_points(Vector3.ZERO, 0.0, 1.0, -12.0)
	var high := Shot.flight_points(Vector3.ZERO, 0.0, 1.0, 24.0)
	assert_gt(_peak_y(high), _peak_y(low) + 2.0, "stick up has to show a taller arc")
	for point in high:
		assert_almost_eq(point.x, 0.0, 0.001, "a perfect hit stays on the aim line")


func test_loft_moves_how_far_a_perfect_hit_lands() -> void:
	var punch := Shot.carry_to_height(0.0, 1.0, Shot.LOFT_BIAS_MIN)
	var stock := Shot.carry_to_height(0.0, 1.0, 0.0)
	var flop := Shot.carry_to_height(0.0, 1.0, Shot.LOFT_BIAS_MAX)
	assert_lt(punch, stock - 20.0, "a punch has to land well short of a stock swing")
	assert_gt(flop, stock + 10.0, "more loft toward 45 has to carry further")
	var punch_flight := Shot.flight_points(Vector3.ZERO, 0.0, 1.0, Shot.LOFT_BIAS_MIN)
	var flop_flight := Shot.flight_points(Vector3.ZERO, 0.0, 1.0, Shot.LOFT_BIAS_MAX)
	assert_almost_eq(_carry_xz(punch_flight), punch, 1.5)
	assert_almost_eq(_carry_xz(flop_flight), flop, 1.5)


func test_a_putt_preview_stays_on_the_ground() -> void:
	var origin := Vector3(0.0, 0.15, 0.0)
	var points := Shot.flight_points(origin, 90.0, 1.0, 24.0, true)
	assert_gt(points.size(), 2)
	for point in points:
		assert_almost_eq(point.y, origin.y, 0.001)
		assert_almost_eq(point.z, origin.z, 0.001, "yaw 90 is a roll along +X")


func test_a_putt_preview_without_a_lie_still_uses_green_speed() -> void:
	var implied := Shot.flight_points(Vector3.ZERO, 0.0, 1.0, 0.0, true)
	var green := Shot.flight_points(
		Vector3.ZERO, 0.0, 1.0, 0.0, true, null, 0.0, Surface.Type.GREEN
	)
	assert_almost_eq(_carry_xz(implied), _carry_xz(green), 0.01)


func test_a_fringe_putt_preview_dies_shorter_than_a_green_putt() -> void:
	var green := Shot.flight_points(
		Vector3.ZERO, 0.0, 1.0, 0.0, true, null, 0.0, Surface.Type.GREEN
	)
	var fringe := Shot.flight_points(
		Vector3.ZERO, 0.0, 1.0, 0.0, true, null, 0.0, Surface.Type.FRINGE
	)
	assert_lt(
		_carry_xz(fringe), _carry_xz(green) * 0.8,
		"collar grass has to kill the roll the preview shows"
	)


func test_a_full_swing_loses_speed_in_the_rough_and_sand() -> void:
	var fairway := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false)
	var rough := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.ROUGH, false)
	var bunker := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.BUNKER, false)
	assert_lt(rough.length(), fairway.length())
	assert_lt(bunker.length(), rough.length())
	assert_almost_eq(
		rough.length(), fairway.length() * Surface.POWER_MULT[Surface.Type.ROUGH], 0.001
	)
	assert_almost_eq(
		bunker.length(), fairway.length() * Surface.POWER_MULT[Surface.Type.BUNKER], 0.001
	)
	assert_lt(
		_carry_xz(Shot.flight_points(
			Vector3.ZERO, 0.0, 1.0, 0.0, false, null, 0.0, Surface.Type.ROUGH
		)),
		_carry_xz(Shot.flight_points(Vector3.ZERO, 0.0, 1.0)) * 0.75
	)


func test_a_collar_chip_lands_just_short_of_the_cup() -> void:
	var collar := ChipScale.putting_collar()
	assert_almost_eq(collar, Shot.default_green_span() * 0.5 + ChipScale.COLLAR_FRINGE, 0.001)
	var desired := ChipScale.chip_max_carry(collar)
	assert_almost_eq(desired, collar - ChipScale.CHIP_SHORT, 0.001)
	var carry := _carry_xz(_chip_flight(1.0, 0.0, collar))
	assert_almost_eq(carry, desired, 1.5)
	assert_lt(carry, collar, "a stuffed meter has to die short so it can roll in")
	assert_gt(carry, collar - 2.0)
	var bunker := ChipScale.chip_max_carry(5.0)
	assert_almost_eq(bunker, 5.0 - ChipScale.CHIP_SHORT, 0.001)
	var forged := ChipScale.chip_max_carry(collar, 0.0, ClubKit.by_id(ClubKit.FORGED_ID))
	assert_almost_eq(forged, desired, 0.01, "upgrades cannot stretch a collar chip past the cup")


func test_a_higher_collar_chip_goes_a_little_further() -> void:
	var collar := ChipScale.putting_collar()
	var stock := ChipScale.chip_max_carry(collar)
	var flop := ChipScale.chip_max_carry(collar, Shot.LOFT_BIAS_MAX)
	var punch := ChipScale.chip_max_carry(collar, Shot.LOFT_BIAS_MIN)
	assert_gt(flop, stock, "a high chip has to carry a bit further because it will not roll")
	assert_almost_eq(punch, stock, 0.001, "a punch does not get extra near-hole carry")
	assert_lt(flop, stock * 1.2)
	assert_lt(flop, ClubKit.starter().scaled_carry() * 0.15, "a flop is still a chip, not a drive")
	assert_almost_eq(_carry_xz(_chip_flight(1.0, Shot.LOFT_BIAS_MAX, collar)), flop, 1.5)


func test_a_mid_approach_overshoots_so_the_hole_needs_a_partial() -> void:
	var collar := ChipScale.putting_collar()
	var mid := 50.0
	var max_at_mid := ChipScale.chip_max_carry(mid)
	assert_gt(max_at_mid, mid, "a stuffed meter from mid-range has to fly past the cup")
	var hole_high := mid / max_at_mid
	var collar_high := collar / ChipScale.chip_max_carry(collar)
	assert_lt(hole_high, 1.0)
	assert_lt(hole_high, collar_high, "further back has to take a smaller partial than the collar")
	assert_almost_eq(_carry_xz(_chip_flight(1.0, 0.0, mid)), max_at_mid, 2.0)


func test_a_drive_length_swing_stays_a_full_drive() -> void:
	var far := ClubKit.starter().scaled_carry()
	assert_almost_eq(ChipScale.chip_max_carry(far), Shot.carry_to_height(0.0), 0.01)
	assert_almost_eq(ChipScale.chip_speed_scale(far), 1.0, 0.001)
	var raw := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false)
	var scaled := ChipScale.scale_launch(raw, far)
	assert_almost_eq(scaled.length(), raw.length(), 0.001)


func test_chip_scale_is_linear_with_hole_distance() -> void:
	var collar := ChipScale.putting_collar()
	var far := ClubKit.starter().scaled_carry()
	var mid := (collar + far) * 0.5
	var full := Shot.carry_to_height(0.0)
	assert_almost_eq(ChipScale.chip_max_carry(collar), collar - ChipScale.CHIP_SHORT, 0.001)
	assert_almost_eq(ChipScale.chip_max_carry(far), full, 0.01)
	assert_almost_eq(
		ChipScale.chip_max_carry(mid), lerpf(mid - ChipScale.CHIP_SHORT, full, 0.5), 0.01
	)


func test_chip_scale_leaves_putts_and_unspecified_distance_alone() -> void:
	assert_almost_eq(ChipScale.chip_speed_scale(0.0), 1.0, 0.001)
	var putt := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.GREEN, true)
	assert_almost_eq(putt.length(), Shot.putt_max_speed(), 0.001)
	assert_almost_eq(putt.y, 0.0, 0.001)
	var expected := (
		Shot.MAX_SPEED * Shot.MAX_SPEED * sin(2.0 * deg_to_rad(Shot.LAUNCH_DEG)) / Shot.GRAVITY
	)
	assert_almost_eq(Shot.max_carry(), expected, 0.001)
	var swing := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false)
	assert_almost_eq(swing.length(), Shot.MAX_SPEED * sqrt(Shot.DISTANCE_SCALE), 0.001)
	assert_almost_eq(
		ChipScale.scale_launch(swing, 0.0).length(), swing.length(), 0.001
	)


func test_no_patch_is_the_rough() -> void:
	assert_eq(Surface.dominant([]), Surface.Type.ROUGH)


func _chip_flight(power: float, loft_bias: float, hole_dist: float) -> PackedVector3Array:
	return ChipScale.scale_flight(
		Shot.flight_points(
			Vector3.ZERO, 0.0, power, loft_bias, false, null, 0.0, Surface.Type.FAIRWAY
		),
		hole_dist, loft_bias
	)


func _peak_y(points: PackedVector3Array) -> float:
	var peak := -INF
	for point in points:
		peak = maxf(peak, point.y)
	return peak


func _carry_xz(points: PackedVector3Array) -> float:
	var start: Vector3 = points[0]
	var land: Vector3 = points[points.size() - 1]
	return Vector2(land.x - start.x, land.z - start.z).length()
