extends GutTest
## The cart's driving model and how hard it hits, without needing a world.

const WALKER := preload("res://resources/zombies/walker.tres")
const RUNNER := preload("res://resources/zombies/runner.tres")
const BRUTE := preload("res://resources/zombies/brute.tres")
const _Boost := preload("res://scripts/course/cart_path_boost.gd")


func test_full_throttle_is_faster_going_forwards_than_back() -> void:
	assert_eq(GolfCart.target_speed(1.0), GolfCart.MAX_SPEED)
	assert_eq(GolfCart.target_speed(-1.0), -GolfCart.REVERSE_SPEED)
	assert_eq(GolfCart.target_speed(0.0), 0.0)


func test_the_trigger_gives_a_little_extra_speed() -> void:
	assert_gt(GolfCart.target_speed(1.0, true), GolfCart.MAX_SPEED)
	assert_lt(GolfCart.target_speed(1.0, true), GolfCart.MAX_SPEED * 1.35, "a nudge, not a rocket")
	assert_eq(GolfCart.target_speed(-1.0, true), -GolfCart.REVERSE_SPEED, "no boost in reverse")


func test_boost_and_steer_at_speed_is_a_drift() -> void:
	assert_true(GolfCart.is_drifting(true, 0.8, 10.0))
	assert_false(GolfCart.is_drifting(true, 0.0, 10.0), "straight boost still tracks the nose")
	assert_false(GolfCart.is_drifting(true, 1.0, 2.0), "too slow to slide")
	assert_false(GolfCart.is_drifting(false, 1.0, 12.0), "without the trigger it grips")


func test_a_fresh_drift_is_fully_sideways() -> void:
	assert_eq(GolfCart.next_drift(0.0, true, 0.016), 1.0)


func test_the_slide_takes_a_second_to_grip_after_you_let_go() -> void:
	assert_almost_eq(GolfCart.next_drift(1.0, false, 0.25), 0.75, 0.01)
	assert_gt(GolfCart.next_drift(1.0, false, 0.99), 0.0, "still sliding just before a second is up")
	assert_almost_eq(GolfCart.next_drift(1.0, false, GolfCart.DRIFT_RECOVER), 0.0, 0.01)


func test_grip_returns_gradually_instead_of_snapping() -> void:
	var delta := 1.0 / 60.0
	var sliding := GolfCart.velocity_slip(1.0, delta)
	var recovering := GolfCart.velocity_slip(0.5, delta)
	var gripped := GolfCart.velocity_slip(0.0, delta)
	assert_lt(sliding, recovering)
	assert_lt(recovering, gripped)
	assert_almost_eq(gripped, 1.0, 0.001)
	assert_lt(sliding, 0.04, "the nose does not yank the cart around mid-slide")


func test_drifting_yaws_harder_than_gripping() -> void:
	assert_gt(GolfCart.drift_turn_scale(1.0), GolfCart.drift_turn_scale(0.0))
	assert_almost_eq(GolfCart.drift_turn_scale(0.0), 1.0, 0.001)
	assert_gt(GolfCart.drift_turn_scale(1.0), 1.7, "a little more yaw than a normal turn")


func test_a_sideways_slide_is_a_full_drift_angle() -> void:
	assert_almost_eq(GolfCart.slip_amount(Vector3.FORWARD, Vector3.FORWARD * 10.0), 0.0, 0.01)
	assert_almost_eq(GolfCart.slip_amount(Vector3.FORWARD, Vector3.RIGHT * 10.0), 1.0, 0.01)
	var half := GolfCart.slip_amount(
		Vector3.FORWARD, (Vector3.FORWARD + Vector3.RIGHT).normalized() * 10.0
	)
	assert_almost_eq(half, 0.5, 0.05)


func test_a_bigger_drift_angle_adds_more_speed() -> void:
	assert_eq(GolfCart.drift_bonus(0.0, 1.0), 0.0, "straight still caps at the boost")
	assert_eq(GolfCart.drift_bonus(1.0, 0.0), 0.0, "no bonus without a slide")
	assert_gt(GolfCart.drift_bonus(1.0, 1.0), GolfCart.drift_bonus(0.4, 1.0))
	assert_gt(
		GolfCart.target_speed(1.0, true) + GolfCart.drift_bonus(1.0, 1.0),
		GolfCart.target_speed(1.0, true),
		"a big angle has to outrun a straight boost"
	)


func test_only_a_moving_slide_on_the_ground_leaves_rubber() -> void:
	assert_true(GolfCart.is_leaving_rubber(1.0, true, 10.0))
	assert_false(GolfCart.is_leaving_rubber(0.0, true, 10.0), "gripping tires stay clean")
	assert_false(GolfCart.is_leaving_rubber(1.0, false, 10.0), "no marks in the air")
	assert_false(GolfCart.is_leaving_rubber(1.0, true, 1.0), "a crawl is not a skid")


func test_throttle_is_proportional_and_clamped() -> void:
	assert_almost_eq(GolfCart.target_speed(0.5), GolfCart.MAX_SPEED * 0.5, 0.01)
	assert_eq(GolfCart.target_speed(4.0), GolfCart.MAX_SPEED, "a stick cannot ask for more")


func test_a_windmill_fling_kills_drive_and_throws_the_cart() -> void:
	var cart := GolfCart.new()
	cart.drive_speed = 16.0
	cart.fling(Vector3.RIGHT, 34.0, 14.0, 1.0)
	assert_true(cart.is_flung())
	assert_eq(cart.drive_speed, 0.0)
	assert_almost_eq(cart.velocity.x, 34.0, 0.01)
	assert_almost_eq(cart.velocity.y, 14.0, 0.01)
	cart.recover_at(Vector3.ZERO, 0.0)
	assert_false(cart.is_flung())
	assert_eq(cart.velocity, Vector3.ZERO)
	cart.free()


func test_recovering_on_the_path_kills_all_speed() -> void:
	var cart := GolfCart.new()
	cart.drive_speed = 14.0
	cart.velocity = Vector3(3.0, 1.0, -2.0)
	cart.recover_at(Vector3(4.0, 0.4, -8.0), 90.0)
	assert_eq(cart.drive_speed, 0.0)
	assert_eq(cart.velocity, Vector3.ZERO)
	assert_almost_eq(cart.position.x, 4.0, 0.001)
	assert_almost_eq(cart.position.z, -8.0, 0.001)
	cart.free()


func test_a_parked_cart_cannot_spin_on_the_spot() -> void:
	assert_eq(GolfCart.turn_rate_deg(0.0, 1.0), 0.0)


func test_steering_bites_harder_the_faster_you_go() -> void:
	var slow := absf(GolfCart.turn_rate_deg(3.0, 1.0))
	var fast := absf(GolfCart.turn_rate_deg(GolfCart.MAX_SPEED, 1.0))
	assert_gt(fast, slow)
	assert_almost_eq(fast, GolfCart.TURN_DEG_PER_SEC, 0.01)


func test_steering_flips_in_reverse_like_a_real_cart() -> void:
	var forwards := GolfCart.turn_rate_deg(8.0, 1.0)
	var backwards := GolfCart.turn_rate_deg(-8.0, 1.0)
	assert_lt(forwards, 0.0, "steering right turns the cart clockwise")
	assert_almost_eq(backwards, -forwards, 0.01)


func test_rolling_slowly_does_not_run_anybody_over() -> void:
	assert_eq(GolfCart.crush_damage(GolfCart.CRUSH_MIN_SPEED - 0.5), 0.0)
	assert_eq(GolfCart.crush_damage(0.0), 0.0)


func test_cruising_speed_flattens_the_smaller_zombies() -> void:
	var damage := GolfCart.crush_damage(8.0)
	assert_gt(damage, WALKER.max_hp, "a walker should not survive being driven into")
	assert_gt(damage, RUNNER.max_hp)


func test_full_speed_flattens_a_brute() -> void:
	var damage := GolfCart.crush_damage(GolfCart.MAX_SPEED)
	assert_gt(damage, BRUTE.max_hp, "at this speed a brute does not survive the hit")


func test_reversing_over_something_hurts_just_as_much() -> void:
	assert_eq(GolfCart.crush_damage(-9.0), GolfCart.crush_damage(9.0))


func test_bodies_are_not_solid_to_the_cart() -> void:
	assert_eq(
		Layers.VEHICLE_MASK & Layers.ZOMBIE, 0,
		"you drive through zombies rather than bumping to a halt on them"
	)
	assert_eq(Layers.VEHICLE_MASK & Layers.PLAYER, 0, "and never shove your partner around")
	assert_gt(Layers.VEHICLE_MASK & Layers.PROP, 0, "trees still stop the cart")


func test_the_wheel_follows_the_stick() -> void:
	assert_eq(SteeringWheel.angle_for_steer(0.0), 0.0)
	assert_eq(SteeringWheel.angle_for_steer(1.0), -SteeringWheel.MAX_TURN_DEG)
	assert_eq(SteeringWheel.angle_for_steer(-1.0), SteeringWheel.MAX_TURN_DEG)
	assert_eq(SteeringWheel.angle_for_steer(4.0), -SteeringWheel.MAX_TURN_DEG, "a stick cannot crank it further")


func test_the_wheel_turns_toward_the_stick() -> void:
	var wheel := SteeringWheel.new()
	add_child_autofree(wheel)
	wheel.turn(1.0, 1.0)
	assert_lt(wheel.angle_deg(), -90.0, "a right turn cranks the wheel clockwise from the seat")
	assert_false(wheel.has_hands_on(), "nobody is driving yet")


func test_the_rim_faces_the_driver_not_the_sky() -> void:
	var wheel := SteeringWheel.new()
	add_child_autofree(wheel)
	assert_almost_eq(
		wheel.rim_pitch_deg(), 90.0, 0.1,
		"Godot's torus is a doughnut around Y; without this it is a bar from the seat"
	)


func test_a_ramp_sends_the_cart_up_instead_of_flattening_the_velocity() -> void:
	var floor_n := Vector3(0.0, cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0)))
	var along := GolfCart.slope_velocity(Vector3.FORWARD, floor_n, 30.0)
	assert_gt(along.y, 8.0, "the lip has to throw the cart up")
	assert_lt(along.z, 0.0, "and keep sending it the way the nose is pointing")
	assert_almost_eq(along.length(), 30.0, 0.01)


func test_flat_ground_stays_horizontal() -> void:
	var along := GolfCart.slope_velocity(Vector3.FORWARD, Vector3.UP, 20.0)
	assert_almost_eq(along.y, 0.0, 0.001)
	assert_almost_eq(along.z, -20.0, 0.001)


func test_the_cart_lets_go_of_the_ground_on_a_fast_climb() -> void:
	var floor_n := Vector3(0.0, cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0)))
	assert_eq(GolfCart.snap_length(floor_n, Vector3.FORWARD, 20.0), 0.0)
	assert_eq(
		GolfCart.snap_length(Vector3.UP, Vector3.FORWARD, 30.0), GolfCart.FLOOR_SNAP,
		"flat ground still sticks"
	)
	assert_eq(
		GolfCart.snap_length(floor_n, Vector3.FORWARD, 2.0), GolfCart.FLOOR_SNAP,
		"crawling up a slope is not a jump"
	)


func test_going_down_a_ramp_still_sticks_to_the_ground() -> void:
	var floor_n := Vector3(0.0, cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0)))
	assert_eq(
		GolfCart.snap_length(floor_n, -Vector3.FORWARD, 20.0), GolfCart.FLOOR_SNAP,
		"downhill has to follow the slope, not fly off the back"
	)


func test_a_full_speed_launch_still_carries_over_water() -> void:
	var range := JumpRamp.flight_distance(
		GolfCart.MAX_SPEED, JumpRamp.ANGLE_DEG, JumpRamp.lip_height()
	)
	assert_gt(range, HoleGenerator.WATER_MIN_SPAN, "the jump still carries you over a swimming pond")


func test_air_gravity_is_much_heavier_than_the_world() -> void:
	assert_gt(GolfCart.AIR_GRAVITY, 20.0)
	var heavy := JumpRamp.flight_distance(
		GolfCart.MAX_SPEED, JumpRamp.ANGLE_DEG, JumpRamp.lip_height(), GolfCart.AIR_GRAVITY
	)
	var floaty := JumpRamp.flight_distance(
		GolfCart.MAX_SPEED, JumpRamp.ANGLE_DEG, JumpRamp.lip_height(), 9.8
	)
	assert_lt(heavy, floaty * 0.55, "the jump has to dump you, not hang")


func test_turbo_raises_top_speed() -> void:
	var cart := GolfCart.new()
	assert_eq(cart.max_drive_speed(), GolfCart.MAX_SPEED)
	cart.install_turbo()
	assert_gt(cart.max_drive_speed(), GolfCart.MAX_SPEED)
	assert_almost_eq(
		GolfCart.target_speed(1.0, false, cart.max_drive_speed()),
		GolfCart.MAX_SPEED * GolfCart.TURBO_MULT,
		0.01
	)
	cart.free()


func test_a_ram_plate_hits_harder() -> void:
	var base := GolfCart.crush_damage(10.0)
	var ram := GolfCart.crush_damage(10.0, GolfCart.RAM_MULT)
	assert_gt(ram, base)
	var cart := GolfCart.new()
	cart.install_ram()
	assert_almost_eq(cart.ram_mult(), GolfCart.RAM_MULT, 0.001)
	cart.free()


func test_a_boost_stripe_outpaces_the_trigger() -> void:
	assert_gt(_Boost.SPEED, GolfCart.BOOST_SPEED * 2.0)
	var from_cruise := _Boost.cart_speed(GolfCart.MAX_SPEED, 0.5)
	assert_gt(from_cruise, GolfCart.BOOST_SPEED)
	assert_gt(from_cruise, GolfCart.MAX_SPEED * 1.5)
	var from_stop := _Boost.cart_speed(0.0, 1.0)
	assert_gt(from_stop, GolfCart.MAX_SPEED)
	var cart := GolfCart.new()
	assert_false(cart.on_boost_pad())
	cart.enter_boost(Vector3.FORWARD)
	assert_true(cart.on_boost_pad())
	cart.exit_boost()
	assert_false(cart.on_boost_pad())
	cart.free()
	var pad = _Boost.create(Vector3.ZERO, Vector3(0.0, 0.0, -6.0))
	assert_true(pad.is_in_group("transit_boost"))
	assert_almost_eq(pad.along.z, -1.0, 0.01)
	pad.free()


func test_a_boost_stripe_hurls_a_player_down_the_lane() -> void:
	var next := _Boost.player_velocity(Vector3.ZERO, Vector3.FORWARD, 0.5)
	assert_lt(next.z, 0.0, "Godot forward is -Z")
	assert_gt(absf(next.z), Player.SPRINT_SPEED)


func test_the_drop_off_sits_on_the_ground_not_inside_it() -> void:
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	assert_true(cart.is_in_group("golf_carts"), "nailer proximity looks up this group")
	cart.global_position = Vector3(0.0, 0.5, 0.0)
	var floor := StaticBody3D.new()
	floor.collision_layer = Layers.WORLD
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 0.4, 30.0)
	col.shape = box
	floor.add_child(col)
	add_child_autofree(floor)
	floor.global_position = Vector3(0.0, 3.0, 0.0)
	await wait_physics_frames(2)
	var at := cart.exit_point(1.0)
	assert_almost_eq(
		at.y, 3.2 + GolfCart.EXIT_LIFT, 0.15,
		"the bank is higher than the cart; feet have to land on it"
	)


func test_chase_camera_sits_behind_and_above_the_cart() -> void:
	var origin := Vector3(0.0, 1.0, 0.0)
	var view := GolfCart.chase_cam(origin, 0.0)
	assert_gt(view.origin.z, origin.z, "facing -Z, the camera sits on +Z")
	assert_gt(view.origin.y, origin.y + 3.0, "high enough to see the cart")
	assert_gt(view.origin.distance_to(origin), 8.0, "zoomed out past the cabin")
	assert_gt((-view.basis.z).dot(Vector3.FORWARD), 0.7, "looking the way the cart faces")


func test_chase_camera_orbits_when_the_cart_turns() -> void:
	var view := GolfCart.chase_cam(Vector3.ZERO, PI * 0.5)
	assert_gt(view.origin.x, 6.0, "yaw 90 faces -X, so the camera is on +X")


func test_a_forward_stick_reads_as_forward_throttle() -> void:
	assert_almost_eq(GolfCart.stick_drive(Vector2(0.0, -1.0)).y, 1.0, 0.001, "up the screen")
	assert_almost_eq(GolfCart.stick_drive(Vector2(0.0, 1.0)).y, -1.0, 0.001, "and back is reverse")
	assert_almost_eq(GolfCart.stick_drive(Vector2(0.5, 0.0)).x, 0.5, 0.001, "steer rides as given")
