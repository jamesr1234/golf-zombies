extends GutTest
## Bought clubs forgive mishits, carry farther, and putt softer. Hole length
## still plans around the unscaled starter carry.


func test_starter_matches_the_old_club() -> void:
	var kit := ClubKit.starter()
	assert_eq(kit.id, ClubKit.STARTER_ID)
	assert_eq(kit.deviation_scale, 1.0)
	assert_eq(kit.speed_scale, 1.0)
	assert_eq(kit.putt_speed_scale, 1.0)
	assert_almost_eq(kit.scaled_carry(), Shot.max_carry() * Shot.DISTANCE_SCALE, 0.001)


func test_better_sets_forgive_more_and_hit_farther() -> void:
	var starter := ClubKit.starter()
	var tour := ClubKit.by_id(ClubKit.TOUR_ID)
	var forged := ClubKit.by_id(ClubKit.FORGED_ID)
	assert_lt(tour.deviation_scale, starter.deviation_scale)
	assert_gt(tour.contact_scale, starter.contact_scale)
	assert_gt(tour.speed_scale, starter.speed_scale)
	assert_lt(tour.putt_speed_scale, starter.putt_speed_scale)
	assert_lt(forged.deviation_scale, tour.deviation_scale)
	assert_gt(forged.speed_scale, tour.speed_scale)
	assert_lt(forged.putt_speed_scale, tour.putt_speed_scale)
	assert_gt(forged.tier(), tour.tier())


func test_max_carry_stays_on_the_starter_so_holes_do_not_grow() -> void:
	var expected := Shot.MAX_SPEED * Shot.MAX_SPEED * sin(2.0 * deg_to_rad(Shot.LAUNCH_DEG)) / Shot.GRAVITY
	assert_almost_eq(Shot.max_carry(), expected, 0.001)
	var forged := ClubKit.by_id(ClubKit.FORGED_ID)
	assert_gt(forged.scaled_carry(), Shot.max_carry())
	assert_almost_eq(Shot.max_carry(), expected, 0.001)


func test_a_forged_mishit_hooks_less_than_a_starter_mishit() -> void:
	var starter := _miss(ClubKit.starter())
	var forged := _miss(ClubKit.by_id(ClubKit.FORGED_ID))
	assert_lt(absf(forged.deviation_deg), absf(starter.deviation_deg))
	assert_gt(forged.power, starter.power)


func test_a_beer_boost_hits_the_ball_harder() -> void:
	var starter := ClubKit.starter()
	var drunk := starter.boosted(1.24)
	assert_gt(drunk.speed_scale, starter.speed_scale)
	assert_eq(starter.speed_scale, 1.0, "the bag itself does not change")
	var sober := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false, starter)
	var smashed := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false, drunk)
	assert_gt(smashed.length(), sober.length())


func test_the_mech_kit_is_straighter_and_longer_than_forged() -> void:
	var forged := ClubKit.by_id(ClubKit.FORGED_ID)
	var mech := ClubKit.mech()
	assert_lt(mech.deviation_scale, forged.deviation_scale)
	assert_gt(mech.contact_scale, forged.contact_scale)
	assert_gt(mech.speed_scale, forged.speed_scale)
	var forged_ball := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false, forged)
	var mech_ball := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false, mech)
	assert_gt(mech_ball.length(), forged_ball.length())


func test_forged_swings_launch_faster() -> void:
	var fairway := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false)
	var forged := Shot.velocity(
		0.0, 0.0, 1.0, Surface.Type.FAIRWAY, false, ClubKit.by_id(ClubKit.FORGED_ID)
	)
	assert_gt(forged.length(), fairway.length())


func test_better_putts_run_out_less() -> void:
	var starter := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.GREEN, true)
	var forged := Shot.velocity(
		0.0, 0.0, 1.0, Surface.Type.GREEN, true, ClubKit.by_id(ClubKit.FORGED_ID)
	)
	assert_lt(forged.length(), starter.length())
	assert_almost_eq(forged.y, 0.0, 0.001)


func _miss(kit: ClubKit) -> SwingMeter:
	var meter := SwingMeter.new()
	meter.kit = kit
	meter.click()
	meter.value = 0.7
	meter.click()
	meter.tick(2.0)
	return meter
