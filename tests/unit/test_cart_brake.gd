extends GutTest
## L2 slams the cart dead and throws shotgun through the windshield.

const CART := preload("res://scenes/vehicles/golf_cart.tscn")
const PLAYER := preload("res://scenes/players/player.tscn")


func test_travel_follows_the_nose() -> void:
	var cart := GolfCart.new()
	cart.rotation.y = 0.0
	cart.velocity = Vector3.ZERO
	var forward := CartBrake.travel_dir(cart, 12.0)
	assert_almost_eq(forward.x, 0.0, 0.01)
	assert_almost_eq(forward.z, -1.0, 0.01)
	var reverse := CartBrake.travel_dir(cart, -12.0)
	assert_almost_eq(reverse.z, 1.0, 0.01)
	cart.free()


func test_a_crawl_does_not_throw_anyone() -> void:
	assert_false(CartBrake.should_toss(2.0))
	assert_true(CartBrake.should_toss(CartBrake.YEET_MIN))
	assert_almost_eq(CartBrake.toss_speed(GolfCart.MAX_SPEED), GolfCart.MAX_SPEED, 0.01)


func test_max_speed_throws_about_thirty_metres() -> void:
	var at_max := CartBrake.throw_range(GolfCart.MAX_SPEED)
	assert_almost_eq(at_max, CartBrake.RANGE_AT_MAX, 1.5)
	assert_gt(CartBrake.throw_range(CartPathBoost.SPEED), at_max, "the stripe throws farther")


func test_the_pedal_bleeds_speed_instead_of_snapping() -> void:
	var next := CartBrake.next_speed(22.0, 0.016)
	assert_lt(next, 22.0)
	assert_gt(next, 20.0, "one frame is a bite, not a wall")
	var left := 22.0
	for _i in 12:
		left = CartBrake.next_speed(left, 0.016)
	assert_gt(left, 0.0, "a fifth of a second later it is still rolling")
	assert_lt(left, 16.0, "but it has shed a lot")
	assert_almost_eq(CartBrake.next_speed(0.4, 0.05), 0.0, 0.001)


func test_the_cabin_nods_then_whips_back() -> void:
	var pose := CartBrake.kick_pitch(0.0, 0.0, GolfCart.MAX_SPEED)
	assert_lt(pose.y, 0.0, "the slam throws the nose down")
	for _i in 10:
		pose = CartBrake.next_pitch(pose.x, pose.y, true, GolfCart.MAX_SPEED, 0.016)
	assert_lt(pose.x, -0.08, "the cabin slants forward")
	var nose := CartWobble.body_basis(0.0, 0.0, pose.x) * Vector3(0.0, 0.0, -1.0)
	assert_lt(nose.y, 0.0, "negative pitch drops the cart's nose")
	var whipped := false
	for _i in 45:
		pose = CartBrake.next_pitch(pose.x, pose.y, false, 0.0, 0.016)
		if pose.x > 0.04:
			whipped = true
	assert_true(whipped, "letting go rocks the nose back past level")


func test_l2_slants_the_cabin_forward() -> void:
	var packed := _ride()
	var driver: Player = packed[0]
	var cart: GolfCart = packed[2]
	cart.drive_speed = GolfCart.MAX_SPEED
	(driver.input as CpuInput).hold("aim")
	cart._drive(0.016)
	assert_lt(cart._brake_pitch_vel, 0.0)
	for _i in 8:
		cart._drive(0.016)
	assert_lt(cart._brake_pitch, -0.06, "the body nods onto the nose")


func test_l2_takes_a_beat_to_stop() -> void:
	var packed := _ride()
	var driver: Player = packed[0]
	var cart: GolfCart = packed[2]
	cart.drive_speed = 22.0
	cart.velocity = Vector3(0.0, 0.0, -22.0)
	(driver.input as CpuInput).hold("aim")
	cart._drive(0.016)
	assert_gt(cart.drive_speed, 18.0, "it does not die on the first frame")
	assert_lt(cart.drive_speed, 22.0)
	assert_eq(cart.driver, driver, "the driver stays on the brake")
	for _i in 90:
		cart._drive(1.0 / 60.0)
	assert_almost_eq(cart.drive_speed, 0.0, 0.01, "held long enough, it does stop")


func test_the_passenger_flies_forward_limp() -> void:
	var packed := _ride()
	var driver: Player = packed[0]
	var passenger: Player = packed[1]
	var cart: GolfCart = packed[2]
	cart.drive_speed = GolfCart.MAX_SPEED
	cart.velocity = Vector3(0.0, 0.0, -GolfCart.MAX_SPEED)
	(driver.input as CpuInput).hold("aim")
	cart._drive(0.016)
	assert_null(cart.passenger)
	assert_false(passenger.is_riding())
	assert_true(passenger.body.is_limp(), "they ragdoll out of the seat")
	assert_true(passenger.is_floored())
	assert_almost_eq(passenger.velocity.z, -GolfCart.MAX_SPEED, 0.2)
	assert_almost_eq(passenger.velocity.y, CartBrake.YEET_LIFT, 0.2)


func test_a_slow_brake_keeps_shotgun_seated() -> void:
	var packed := _ride()
	var driver: Player = packed[0]
	var passenger: Player = packed[1]
	var cart: GolfCart = packed[2]
	cart.drive_speed = 3.0
	(driver.input as CpuInput).hold("aim")
	cart._drive(0.016)
	assert_lt(cart.drive_speed, 3.0)
	assert_gt(cart.drive_speed, 0.0)
	assert_eq(cart.passenger, passenger)
	assert_true(passenger.is_riding())
	assert_false(passenger.body.is_limp())


func test_holding_the_brake_does_not_throw_twice() -> void:
	var packed := _ride()
	var driver: Player = packed[0]
	var passenger: Player = packed[1]
	var cart: GolfCart = packed[2]
	cart.drive_speed = 18.0
	(driver.input as CpuInput).hold("aim")
	cart._drive(0.016)
	assert_null(cart.passenger)
	cart.passenger = passenger
	passenger.enter_ride()
	passenger.cart = cart
	cart.drive_speed = 18.0
	cart._drive(0.016)
	assert_eq(cart.passenger, passenger, "a held trigger is one slam")


func test_the_buddy_does_not_hop_back_in_mid_flight() -> void:
	var packed := _ride()
	var driver: Player = packed[0]
	var passenger: Player = packed[1]
	var cart: GolfCart = packed[2]
	passenger.possess_cpu()
	passenger.partner = driver
	driver.partner = passenger
	cart.drive_speed = GolfCart.MAX_SPEED
	(driver.input as CpuInput).hold("aim")
	cart._drive(0.016)
	assert_false(passenger.is_riding())
	assert_false(cart.can_board(passenger), "the cart will not take a ragdoll")
	passenger.brain.tick(0.016)
	assert_false(passenger.is_riding(), "they finish the flight before boarding")


func test_the_drive_prompt_names_the_brake() -> void:
	var packed := _ride()
	var text: String = packed[0].get_prompt().to_lower()
	assert_string_contains(text, "brake")


func _ride() -> Array:
	var cart: GolfCart = CART.instantiate()
	var driver: Player = PLAYER.instantiate()
	var passenger: Player = PLAYER.instantiate()
	add_child_autofree(cart)
	add_child_autofree(driver)
	add_child_autofree(passenger)
	cart.set_physics_process(false)
	driver.set_physics_process(false)
	driver.set_process(false)
	passenger.set_physics_process(false)
	passenger.set_process(false)
	var pad := CpuInput.new("p1", false)
	driver.input = pad
	cart.global_position = Vector3(0.0, 0.4, 0.0)
	driver.global_position = Vector3(1.0, 0.0, 0.0)
	passenger.global_position = Vector3(-1.0, 0.0, 0.0)
	cart.board(driver)
	cart.board(passenger)
	return [driver, passenger, cart]
