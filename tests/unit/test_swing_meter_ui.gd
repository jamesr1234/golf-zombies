extends GutTest
## The bar has to show both timing targets: max power up top, perfect contact
## down at the ball.

var ui: SwingMeterUi


func before_each() -> void:
	ui = SwingMeterUi.new()
	ui.size = Vector2(44.0, 220.0)
	add_child_autofree(ui)


func test_the_power_sweet_spot_sits_above_contact() -> void:
	assert_lt(ui.power_sweet_y(), ui.contact_sweet_y(), "max power is the top notch")


func test_perfect_contact_sits_above_a_late_miss() -> void:
	assert_lt(
		ui.contact_sweet_y(), ui._to_y(-SwingMeter.CONTACT_WINDOW),
		"the accuracy notch is the middle of the contact window"
	)


func test_the_power_sweet_spot_sits_inside_the_bar() -> void:
	assert_gt(ui.power_sweet_y(), 0.0, "headroom keeps the top notch off the frame")
	assert_lt(ui.power_sweet_y(), ui.size.y * 0.25)


func test_a_forgiving_kit_widens_the_contact_window() -> void:
	ui.meter = SwingMeter.new()
	var starter := ui._contact_window()
	ui.meter.kit = ClubKit.by_id(ClubKit.FORGED_ID)
	assert_gt(ui._contact_window(), starter)


func test_the_sweet_bands_are_a_real_range() -> void:
	var power_span := ui._to_y(1.0 - SwingMeter.POWER_SWEET) - ui.power_sweet_y()
	var contact_span := ui._to_y(-SwingMeter.CONTACT_SWEET) - ui._to_y(SwingMeter.CONTACT_SWEET)
	assert_gt(power_span, 10.0, "the top sweet spot has to be a band, not a hairline")
	assert_gt(contact_span, 10.0, "the contact sweet spot has to be a band, not a hairline")


func test_heat_is_full_on_the_target() -> void:
	ui.meter = SwingMeter.new()
	ui.meter.state = SwingMeter.State.BACKSWING
	ui.meter.value = 1.0
	assert_almost_eq(ui.heat_at(1.0, 0.1), 1.0, 0.001)


func test_heat_falls_off_away_from_the_target() -> void:
	ui.meter = SwingMeter.new()
	ui.meter.state = SwingMeter.State.BACKSWING
	ui.meter.value = 0.0
	assert_almost_eq(ui.heat_at(1.0, 0.1), 0.0, 0.001)
	ui.meter.value = 0.95
	assert_almost_eq(ui.heat_at(1.0, 0.1), 0.5, 0.001)


func test_address_does_not_heat_the_contact_band() -> void:
	ui.meter = SwingMeter.new()
	assert_eq(ui.heat_at(0.0, 0.1), 0.0, "idle address stays still")


func test_backswing_fill_warms_toward_amber() -> void:
	ui.meter = SwingMeter.new()
	ui.meter.state = SwingMeter.State.BACKSWING
	ui.meter.value = 0.0
	var cold := ui.fill_tint()
	ui.meter.value = 1.0
	var hot := ui.fill_tint()
	assert_gt(hot.r, cold.r, "full power reads warmer")
	assert_lt(hot.b, cold.b, "cyan falls away at the top")


func test_downswing_fill_cools_toward_lime() -> void:
	ui.meter = SwingMeter.new()
	ui.meter.state = SwingMeter.State.DOWNSWING
	ui.meter.value = 1.0
	var from_power := ui.fill_tint()
	ui.meter.value = 0.0
	var at_contact := ui.fill_tint()
	assert_gt(at_contact.g, from_power.g, "contact reads greener")


func test_putting_stays_lime() -> void:
	ui.putting = true
	ui.meter = SwingMeter.new()
	ui.meter.state = SwingMeter.State.BACKSWING
	ui.meter.value = 1.0
	assert_eq(ui.fill_tint(), Palette.LIME)


func test_pulse_stays_in_unit_range() -> void:
	for _i in 4:
		var beat := ui.pulse(2.0)
		assert_between(beat, 0.0, 1.0)
