extends GutTest
## Three-click timing: the power bar oscillates until click two, then contact.

var meter: SwingMeter


func before_each() -> void:
	meter = SwingMeter.new()


func test_starts_ready_and_idle() -> void:
	assert_eq(meter.state, SwingMeter.State.READY)
	assert_false(meter.is_swinging())
	assert_eq(meter.power, 0.0)


func test_first_click_starts_the_backswing() -> void:
	meter.click()
	assert_eq(meter.state, SwingMeter.State.BACKSWING)
	assert_true(meter.is_swinging())


func test_backswing_rises_over_time() -> void:
	meter.click()
	meter.tick(0.25)
	assert_almost_eq(meter.value, SwingMeter.BACKSWING_SPEED * 0.25, 0.001)


func test_second_click_locks_power() -> void:
	meter.click()
	meter.value = 0.62
	meter.click()
	assert_eq(meter.state, SwingMeter.State.DOWNSWING)
	assert_almost_eq(meter.power, 0.62, 0.001)


func test_quick_tap_is_a_short_shot() -> void:
	meter.click()
	meter.tick(0.06)
	meter.click()
	assert_lt(meter.power, 0.2, "a fast tap has to produce a short shot")


func test_waiting_through_the_top_does_not_lock_power() -> void:
	meter.click()
	meter.tick(2.0)
	assert_eq(meter.state, SwingMeter.State.BACKSWING)
	assert_eq(meter.power, 0.0)


func test_backswing_bounces_at_the_top() -> void:
	meter.click()
	meter.value = 0.99
	meter.tick(0.1)
	assert_eq(meter.state, SwingMeter.State.BACKSWING)
	assert_almost_eq(meter.value, 1.0, 0.001)
	meter.tick(0.1)
	assert_almost_eq(meter.value, 1.0 - SwingMeter.BACKSWING_SPEED * 0.1, 0.001)


func test_backswing_bounces_at_the_bottom() -> void:
	meter.click()
	meter.value = 0.99
	meter.tick(0.1)
	meter.value = 0.01
	meter.tick(0.1)
	assert_eq(meter.state, SwingMeter.State.BACKSWING)
	assert_almost_eq(meter.value, 0.0, 0.001)
	meter.tick(0.1)
	assert_almost_eq(meter.value, SwingMeter.BACKSWING_SPEED * 0.1, 0.001)


func test_clicking_at_the_top_locks_full_power() -> void:
	meter.click()
	meter.value = 1.0
	meter.click()
	assert_eq(meter.state, SwingMeter.State.DOWNSWING)
	assert_eq(meter.power, 1.0)


func test_clicking_in_the_power_sweet_spot_is_full_power() -> void:
	meter.click()
	meter.value = 1.0 - SwingMeter.POWER_SWEET * 0.4
	meter.click()
	assert_eq(meter.power, 1.0)


func test_clicking_below_the_power_sweet_spot_keeps_that_power() -> void:
	meter.click()
	meter.value = 0.62
	meter.click()
	assert_almost_eq(meter.power, 0.62, 0.001)


func test_perfect_contact_keeps_power_and_aim() -> void:
	meter.click()
	meter.value = 0.9
	meter.click()
	meter.value = 0.0
	meter.click()
	assert_true(meter.is_done())
	assert_almost_eq(meter.deviation_deg, 0.0, 0.001)
	assert_almost_eq(meter.power, 0.9, 0.001)
	assert_false(meter.mishit)
	assert_true(meter.sweet)


func test_early_contact_slices_right_and_loses_power() -> void:
	meter.click()
	meter.value = 0.8
	meter.click()
	meter.value = SwingMeter.CONTACT_WINDOW
	meter.click()
	assert_almost_eq(meter.deviation_deg, SwingMeter.MAX_DEVIATION_DEG, 0.001)
	assert_lt(meter.power, 0.8)


func test_contact_sweet_spot_is_a_pure_strike() -> void:
	meter.click()
	meter.value = 0.7
	meter.click()
	meter.value = SwingMeter.CONTACT_SWEET * 0.5
	meter.click()
	assert_true(meter.sweet)
	assert_almost_eq(meter.deviation_deg, 0.0, 0.001)
	assert_false(meter.mishit)


func test_outside_the_contact_sweet_spot_still_has_error() -> void:
	meter.click()
	meter.value = 0.7
	meter.click()
	meter.value = SwingMeter.CONTACT_SWEET + 0.03
	meter.click()
	assert_false(meter.sweet)
	assert_gt(meter.deviation_deg, 0.0)


func test_late_contact_hooks_left() -> void:
	meter.click()
	meter.value = 0.8
	meter.click()
	meter.value = -SwingMeter.CONTACT_WINDOW * 0.5
	meter.click()
	assert_lt(meter.deviation_deg, 0.0)


func test_way_early_contact_is_a_mishit() -> void:
	meter.click()
	meter.value = 1.0
	meter.click()
	meter.click()
	assert_true(meter.mishit)
	assert_almost_eq(meter.deviation_deg, SwingMeter.MAX_DEVIATION_DEG * 2.0, 0.001)


func test_never_clicking_misses_the_ball_badly() -> void:
	meter.click()
	meter.value = 0.7
	meter.click()
	meter.tick(2.0)
	assert_true(meter.is_done())
	assert_true(meter.mishit)
	assert_almost_eq(meter.deviation_deg, SwingMeter.MISS_DEVIATION_DEG, 0.001)
	assert_lt(meter.power, 0.7)


func test_power_never_reaches_zero() -> void:
	meter.click()
	meter.value = 0.0
	meter.click()
	meter.value = 0.0
	meter.click()
	assert_gt(meter.power, 0.0)


func test_reset_returns_to_ready() -> void:
	meter.click()
	meter.tick(0.4)
	meter.reset()
	assert_eq(meter.state, SwingMeter.State.READY)
	assert_eq(meter.value, 0.0)
