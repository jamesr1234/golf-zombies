extends GutTest
## The cart's driving model and how hard it hits, without needing a world.

const WALKER := preload("res://resources/zombies/walker.tres")
const RUNNER := preload("res://resources/zombies/runner.tres")
const BRUTE := preload("res://resources/zombies/brute.tres")
const _Boost := preload("res://scripts/course/cart_path_boost.gd")
const _Stance := preload("res://scripts/vehicles/cart_stance.gd")
const _Wobble := preload("res://scripts/vehicles/cart_wobble.gd")


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
	assert_false(GolfCart.is_leaving_rubber(0.5, true, 10.0), "the recover is not a skid")
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


func test_axle_heights_pitch_the_nose_to_span_the_wheelbase() -> void:
	assert_almost_eq(_Stance.pitch_from_axles(4.0, 4.0), 0.0, 0.001)
	var rise := _Stance.WHEELBASE * tan(deg_to_rad(20.0))
	assert_almost_eq(
		_Stance.pitch_from_axles(rise, 0.0), deg_to_rad(20.0), 0.001,
		"front higher than rear is a climb"
	)
	assert_lt(_Stance.pitch_from_axles(0.0, rise), 0.0, "and the other way is a descent")


func test_the_cart_rides_halfway_between_the_axles() -> void:
	assert_almost_eq(_Stance.ride_height(1.4, 0.2), 0.8, 0.001)


func test_a_small_lip_is_a_step_and_a_wall_is_not() -> void:
	assert_true(_Stance.can_step(0.0, {"position": Vector3(0.0, 0.14, 0.0)}), "tarmac curb")
	assert_true(_Stance.can_step(0.0, {"position": Vector3(0.0, 0.85, 0.0)}), "a sizeable ridge")
	assert_false(_Stance.can_step(0.0, {"position": Vector3(0.0, 0.01, 0.0)}), "already on it")
	assert_false(_Stance.can_step(0.0, {"position": Vector3(0.0, 2.2, 0.0)}), "a wall is not a ridge")
	assert_false(_Stance.can_step(1.0, {}), "no ground ahead")


func test_the_step_looks_past_the_nose() -> void:
	assert_lt(_Stance.look_z(CartVisuals.WHEEL_Z), -CartVisuals.WHEEL_Z)
	assert_lt(_Stance.look_z(CartVisuals.WHEEL_Z), -1.1, "past the box front")
	assert_gt(_Stance.look_z(CartVisuals.WHEEL_Z, true), CartVisuals.WHEEL_Z)


func test_a_wheel_is_planted_until_it_leaves_the_ground() -> void:
	assert_true(_Stance.is_planted(1.0, {"position": Vector3(0.0, 1.0, 0.0)}))
	assert_true(_Stance.is_planted(1.0, {"position": Vector3(0.0, 1.4, 0.0)}), "climbing into a ramp")
	assert_false(_Stance.is_planted(2.0, {"position": Vector3(0.0, 0.2, 0.0)}), "airborne")
	assert_false(_Stance.is_planted(1.0, {}), "no ground under the tire")


func test_a_launch_holds_the_nose_up() -> void:
	assert_true(_Stance.holds_air_pitch(deg_to_rad(20.0), false), "airborne after the lip")
	assert_true(
		_Stance.holds_air_pitch(deg_to_rad(20.0), true, true),
		"still on the lip, already climbing off"
	)
	assert_false(_Stance.holds_air_pitch(0.0, false), "a flat hop has nothing to hold")
	assert_false(
		_Stance.holds_air_pitch(deg_to_rad(20.0), true, false),
		"back on the ground the axles take over"
	)


func test_the_nose_stays_up_after_leaving_the_ramp() -> void:
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3(0.0, 8.0, 0.0)
	cart.rotation = Vector3(deg_to_rad(20.0), 0.0, 0.0)
	cart.drive_speed = GolfCart.MAX_SPEED
	cart.velocity = Vector3(0.0, 6.0, -16.0)
	await wait_physics_frames(2)
	for _i in 20:
		cart._drive(1.0 / 60.0)
	assert_almost_eq(
		cart.rotation.x, deg_to_rad(20.0), 0.02,
		"takeoff tilt has to hold, not follow the fall"
	)


func test_a_soft_landing_does_not_bounce() -> void:
	assert_eq(_Stance.land_strength(2.0), 0.0)
	assert_gt(_Stance.land_strength(8.0), 0.3)
	assert_eq(_Stance.land_strength(20.0), 1.0)


func test_a_landing_squashes_then_springs_back() -> void:
	var impact := _Stance.bounce_offset(1.0, 0.0)
	assert_lt(impact.x, -0.1, "the chassis compresses")
	assert_lt(impact.y, -0.05, "and the nose nods down")
	var rebound := _Stance.bounce_offset(1.0, 0.5 / _Stance.LAND_HZ)
	assert_gt(rebound.x, 0.05, "then the springs throw it back up")
	assert_eq(_Stance.bounce_offset(1.0, 2.5), Vector2.ZERO, "and it settles")


func test_landing_from_a_jump_starts_the_spring() -> void:
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	var floor := StaticBody3D.new()
	floor.collision_layer = Layers.WORLD
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.4, 20)
	col.shape = box
	floor.add_child(col)
	floor.position = Vector3(0.0, -0.2, 0.0)
	add_child_autofree(floor)
	cart.global_position = Vector3(0.0, 2.2, 0.0)
	cart.velocity = Vector3(0.0, -16.0, 0.0)
	cart.drive_speed = 8.0
	await wait_physics_frames(2)
	var landed := false
	for _i in 24:
		cart._drive(1.0 / 60.0)
		if cart._land_age >= 0.0:
			landed = true
			break
	assert_true(landed, "the landing has to wind the springs")
	var bounce := _Stance.bounce_offset(cart._land_strength, cart._land_age)
	assert_lt(bounce.x, 0.0, "and the first beat is a squat")


func test_uneven_axles_blend_into_a_shallower_slope() -> void:
	var ramp := Vector3(0.0, cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0)))
	var blended := _Stance.blend_normal(ramp, Vector3.UP)
	assert_gt(blended.y, ramp.y, "the rear still on the flat softens the climb")
	assert_lt(blended.z, ramp.z)


func test_both_axles_sit_on_a_ramp() -> void:
	var ramp := JumpRamp.create({
		"position": Vector3(0.0, 0.0, 0.0),
		"yaw": 0.0,
		"width": 8.0,
		"length": 16.0,
		"angle_deg": 20.0,
		"role": "takeoff",
	})
	add_child_autofree(ramp)
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	var rise := JumpRamp.lip_height(16.0, 20.0)
	cart.global_position = Vector3(0.0, rise * 0.5 + 0.2, 0.0)
	cart.rotation = Vector3.ZERO
	cart.drive_speed = 8.0
	await wait_physics_frames(2)
	for _i in 24:
		cart._drive(1.0 / 60.0)
	assert_gt(cart.rotation.x, deg_to_rad(12.0), "the nose has to follow the slope")
	assert_lt(
		_wheel_gap(cart, -CartVisuals.WHEEL_Z), 0.18,
		"front tires sit on the ramp, not buried in it"
	)
	assert_lt(
		_wheel_gap(cart, CartVisuals.WHEEL_Z), 0.18,
		"and the rear tires stay planted too"
	)


func test_the_cart_climbs_a_sizeable_ridge() -> void:
	_flat_world(Vector3(0.0, -0.2, 0.0), Vector3(24.0, 0.4, 40.0))
	_curb(Vector3(0.0, 0.4, -6.0), Vector3(8.0, 0.8, 8.0))
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3(0.0, 0.12, 2.0)
	cart.rotation = Vector3.ZERO
	cart.drive_speed = 14.0
	await wait_physics_frames(2)
	var on_top := false
	for _i in 90:
		cart._drive(1.0 / 60.0)
		cart._bleed_speed_on_impact(1.0 / 60.0)
		if cart.global_position.z < -3.0 and cart.global_position.y > 0.45:
			on_top = true
			break
	assert_true(on_top, "over the lip and riding the top, not stuck on the face")


func test_a_wall_still_stops_the_cart() -> void:
	_flat_world(Vector3(0.0, -0.2, 4.0), Vector3(20.0, 0.4, 20.0))
	_curb(Vector3(0.0, 1.2, -3.0), Vector3(8.0, 2.4, 1.2))
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3(0.0, 0.12, 1.5)
	cart.rotation = Vector3.ZERO
	cart.drive_speed = 12.0
	await wait_physics_frames(2)
	for _i in 50:
		cart._drive(1.0 / 60.0)
		cart._bleed_speed_on_impact(1.0 / 60.0)
	assert_gt(cart.global_position.z, -2.2, "a wall is not a ridge")
	assert_lt(absf(cart.drive_speed), 4.0, "and the hit still dumps speed")


func test_only_the_part_of_the_drive_heading_into_a_wall_is_charged_for() -> void:
	var head_on := GolfCart.head_on_amount(Vector3.FORWARD, Vector3.BACK)
	assert_almost_eq(head_on, 1.0, 0.001, "straight into it costs everything")
	assert_eq(
		GolfCart.head_on_amount(Vector3.FORWARD, Vector3.RIGHT), 0.0, "a graze costs nothing"
	)
	assert_eq(
		GolfCart.head_on_amount(Vector3.BACK, Vector3.BACK),
		0.0,
		"backing off a wall already in contact is free"
	)
	var shallow := GolfCart.head_on_amount(
		Vector3(sin(deg_to_rad(5.0)), 0.0, -cos(deg_to_rad(5.0))), Vector3.LEFT
	)
	assert_eq(shallow, 0.0, "running along a lip is not a hit")


func test_running_along_a_wall_does_not_cost_the_cart_its_speed() -> void:
	_flat_world(Vector3(0.0, -0.2, -10.0), Vector3(20.0, 0.4, 60.0))
	_curb(Vector3(1.4, 1.2, -10.0), Vector3(1.0, 2.4, 60.0))
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3(0.0, 0.12, 8.0)
	# Nose turned a few degrees into the wall, so the rub keeps being reported.
	cart.rotation = Vector3(0.0, deg_to_rad(-5.0), 0.0)
	_cpu_driver(cart, Vector2(0.0, -1.0))
	await wait_physics_frames(2)
	var rubbed := false
	for _i in 90:
		cart._drive(1.0 / 60.0)
		cart._bleed_speed_on_impact(1.0 / 60.0)
		rubbed = rubbed or cart.is_on_wall()
	assert_true(rubbed, "the run has to actually rub the wall")
	assert_gt(cart.drive_speed, 15.0, "grinding the lip cannot drain the throttle")


func test_reverse_backs_the_cart_off_a_wall_it_is_pinned_against() -> void:
	_flat_world(Vector3(0.0, -0.2, 4.0), Vector3(20.0, 0.4, 30.0))
	_curb(Vector3(0.0, 1.2, -3.0), Vector3(8.0, 2.4, 1.2))
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3(0.0, 0.12, 0.0)
	cart.rotation = Vector3.ZERO
	var driver := _cpu_driver(cart, Vector2(0.0, -1.0))
	await wait_physics_frames(2)
	for _i in 45:
		cart._drive(1.0 / 60.0)
		cart._bleed_speed_on_impact(1.0 / 60.0)
	var pinned := cart.global_position.z
	assert_true(cart._blocked_by_lip(), "the cart has to be genuinely up against the wall")
	assert_lt(absf(cart.drive_speed), 2.0, "nose into the wall still dumps the speed")
	(driver.input as CpuInput).move = Vector2(0.0, 1.0)
	for _i in 30:
		cart._drive(1.0 / 60.0)
		cart._bleed_speed_on_impact(1.0 / 60.0)
	assert_lt(cart.drive_speed, -3.0, "reverse builds instead of being wiped every frame")
	assert_gt(cart.global_position.z, pinned + 0.5, "and the cart actually gets away")


func test_a_cart_with_nowhere_to_go_is_pushed_free() -> void:
	_flat_world(Vector3(0.0, -0.2, 4.0), Vector3(20.0, 0.4, 30.0))
	_curb(Vector3(0.0, 1.2, -3.0), Vector3(8.0, 2.4, 1.2))
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3(0.0, 0.12, 0.0)
	cart.rotation = Vector3.ZERO
	_cpu_driver(cart, Vector2(0.0, -1.0))
	await wait_physics_frames(2)
	for _i in 60:
		cart._drive(1.0 / 60.0)
		cart._bleed_speed_on_impact(1.0 / 60.0)
	var pinned := cart.global_position.z
	assert_true(cart._blocked_by_lip(), "the cart has to be genuinely up against the wall")
	var freed := pinned
	for _i in 150:
		cart._drive(1.0 / 60.0)
		cart._bleed_speed_on_impact(1.0 / 60.0)
		freed = maxf(freed, cart.global_position.z)
	assert_gt(freed, pinned + 0.5, "a second of asking has to buy a nudge off the wall")


func test_a_parked_cart_is_never_pushed_around() -> void:
	_flat_world(Vector3(0.0, -0.2, 4.0), Vector3(20.0, 0.4, 30.0))
	_curb(Vector3(0.0, 1.2, -3.0), Vector3(8.0, 2.4, 1.2))
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3(0.0, 0.12, -1.2)
	cart.rotation = Vector3.ZERO
	await wait_physics_frames(2)
	var parked := cart.global_position
	for _i in 150:
		cart._drive(1.0 / 60.0)
		cart._bleed_speed_on_impact(1.0 / 60.0)
	assert_almost_eq(
		cart.global_position.z, parked.z, 0.3, "an empty cart resting on a wall stays put"
	)


func test_the_rear_tires_stay_down_when_the_front_climbs() -> void:
	var floor := StaticBody3D.new()
	floor.collision_layer = Layers.WORLD
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.4, 20)
	col.shape = box
	floor.add_child(col)
	floor.position = Vector3(0.0, -0.2, 10.0)
	add_child_autofree(floor)
	var ramp := JumpRamp.create({
		"position": Vector3(0.0, 0.0, 0.0),
		"yaw": 0.0,
		"width": 8.0,
		"length": 16.0,
		"angle_deg": 20.0,
		"role": "takeoff",
	})
	add_child_autofree(ramp)
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3(0.0, 0.12, JumpRamp.ground_run(16.0, 20.0) * 0.5)
	cart.rotation = Vector3.ZERO
	cart.drive_speed = 4.0
	await wait_physics_frames(2)
	for _i in 10:
		cart._drive(1.0 / 60.0)
	assert_gt(cart.rotation.x, deg_to_rad(5.0), "the nose lifts as the front axle climbs")
	assert_lt(_wheel_gap(cart, -CartVisuals.WHEEL_Z), 0.2, "front tires on the slope")
	assert_lt(_wheel_gap(cart, CartVisuals.WHEEL_Z), 0.2, "rear tires still on the ground")


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


func test_a_crawl_or_a_parked_cart_does_not_lean() -> void:
	var motion := Vector2.ZERO
	var dt := 1.0 / 60.0
	for _i in 30:
		motion = _Wobble.next_state(motion.x, motion.y, 1.0, 1.0, 0.0, dt)
	assert_almost_eq(motion.x, 0.0, 0.02, "too slow to tip onto two wheels")
	motion = Vector2.ZERO
	for _i in 30:
		motion = _Wobble.next_state(motion.x, motion.y, 0.0, GolfCart.MAX_SPEED, 0.0, dt)
	assert_almost_eq(motion.x, 0.0, 0.02, "no steer, no lean")


func test_a_hard_turn_at_speed_leans_into_the_corner() -> void:
	var lean := _Wobble.next_state(0.0, 0.0, 1.0, GolfCart.MAX_SPEED, 0.0, 0.2).x
	assert_gt(lean, 0.3, "the cabin has to tip into the turn")
	assert_lt(_Wobble.next_state(0.0, 0.0, -1.0, GolfCart.MAX_SPEED, 0.0, 0.2).x, -0.3)


func test_letting_go_of_the_stick_saves_the_lean() -> void:
	var held := _Wobble.next_state(0.6, 0.0, 1.0, GolfCart.MAX_SPEED, 0.0, 0.2).x
	var saved := _Wobble.next_state(0.6, 0.0, 0.0, GolfCart.MAX_SPEED, 0.0, 0.2).x
	assert_lt(saved, 0.6, "easing off pulls it back")
	assert_lt(saved, held, "and faster than holding the crank")


func test_the_cabin_rocks_past_center_when_you_let_go() -> void:
	var motion := Vector2(0.8, 0.0)
	var dt := 1.0 / 60.0
	var crossed := false
	for _i in 90:
		motion = _Wobble.next_state(motion.x, motion.y, 0.0, GolfCart.MAX_SPEED, 0.0, dt)
		if motion.x < 0.0:
			crossed = true
			break
	assert_true(crossed, "a floppy cabin has to overshoot upright")


func test_the_canopy_lags_behind_the_lean() -> void:
	var canopy := _Wobble.next_follow(0.0, 0.0, 0.8, 0.05)
	assert_gt(canopy.x, 0.0)
	assert_lt(canopy.x, 0.8, "the roof is still catching up")


func test_counter_steer_from_the_edge_pulls_it_back() -> void:
	var lean := 0.85
	var hold := _Wobble.next_tip_hold(0.1, lean, -1.0, 0.05)
	assert_eq(hold, 0.0, "opposite lock cancels a tip")
	var saved := _Wobble.next_state(lean, 0.0, -1.0, GolfCart.MAX_SPEED, 0.0, 0.15).x
	assert_lt(saved, lean, "and the cabin comes back instead of falling")
	assert_false(_Wobble.should_charge_tip(saved, -1.0))


func test_a_normal_hard_turn_does_not_tip() -> void:
	var motion := Vector2.ZERO
	var hold := 0.0
	var dt := 1.0 / 60.0
	for _i in 120:
		motion = _Wobble.next_state(motion.x, motion.y, 0.7, GolfCart.MAX_SPEED, 0.0, dt)
		hold = _Wobble.next_tip_hold(hold, motion.x, 0.7, dt, 0.0, GolfCart.MAX_SPEED)
	assert_false(_Wobble.should_tip(hold), "a hard corner still has to stay up")


func test_holding_a_hard_turn_tips_the_cart() -> void:
	var motion := Vector2.ZERO
	var hold := 0.0
	var dt := 1.0 / 60.0
	var tipped := false
	for _i in 180:
		motion = _Wobble.next_state(motion.x, motion.y, 1.0, GolfCart.MAX_SPEED, 0.0, dt)
		hold = _Wobble.next_tip_hold(hold, motion.x, 1.0, dt)
		if _Wobble.should_tip(hold):
			tipped = true
			break
	assert_true(tipped, "keep cranking and the cart goes over")
	assert_gte(motion.x, _Wobble.TIP)


func test_a_drift_leans_harder_than_a_grip_turn() -> void:
	var grip := _Wobble.next_state(0.0, 0.0, 1.0, GolfCart.MAX_SPEED, 0.0, 0.2).x
	var slide := _Wobble.next_state(0.0, 0.0, 1.0, GolfCart.MAX_SPEED, 1.0, 0.2).x
	assert_gt(slide, grip)
	assert_gt(_Wobble.demand(1.0, GolfCart.MAX_SPEED, 1.0), _Wobble.demand(1.0, GolfCart.MAX_SPEED, 0.0))


func test_the_cabin_skews_when_it_leans() -> void:
	var flat := _Wobble.body_basis(0.0, 0.0)
	assert_true(flat.is_equal_approx(Basis.IDENTITY), "a still cart sits square")
	var pose := _Wobble.body_basis(1.0, 1.0)
	assert_lt(pose.get_euler().z, -deg_to_rad(20.0), "a right lean drops the right side")
	assert_gt(absf(pose.y.dot(pose.x)), 0.15, "and the up axis shears, not a clean roll")
	assert_gt(_Wobble.body_basis(-1.0, -1.0).get_euler().z, deg_to_rad(20.0), "left steer leans left")


func test_a_short_drift_does_not_tip() -> void:
	var motion := Vector2.ZERO
	var hold := 0.0
	var dt := 1.0 / 60.0
	for _i in 18:
		motion = _Wobble.next_state(motion.x, motion.y, 1.0, GolfCart.MAX_SPEED, 1.0, dt)
		hold = _Wobble.next_tip_hold(hold, motion.x, 1.0, dt, 1.0)
	assert_false(_Wobble.should_tip(hold, 1.0), "a flick of a slide still holds")


func test_holding_a_drift_lock_tips() -> void:
	var motion := Vector2.ZERO
	var hold := 0.0
	var dt := 1.0 / 60.0
	var tipped := false
	for _i in 180:
		motion = _Wobble.next_state(motion.x, motion.y, 1.0, GolfCart.MAX_SPEED, 1.0, dt)
		hold = _Wobble.next_tip_hold(hold, motion.x, 1.0, dt, 1.0)
		if _Wobble.should_tip(hold, 1.0):
			tipped = true
			break
	assert_true(tipped, "keep a drift cranked and it still goes over")


func test_a_straight_drive_does_not_wobble() -> void:
	var motion := _Wobble.next_state(0.0, 0.0, 0.0, GolfCart.MAX_SPEED, 0.0, 0.2)
	assert_almost_eq(motion.x, 0.0, 0.001)
	assert_almost_eq(motion.y, 0.0, 0.001)
	assert_ne(_Wobble.pitch_from_vel(4.0), 0.0, "a flick still nods the nose")


func test_a_tipped_cart_stays_down() -> void:
	assert_true(_Wobble.is_tipped(0.0))
	assert_true(_Wobble.is_tipped(4.0), "it stays on its side until someone rights it")
	assert_false(_Wobble.is_righting(-1.0))
	assert_true(_Wobble.is_righting(0.2))
	assert_false(_Wobble.is_righting(_Wobble.RIGHT_TIME))


func test_righting_the_cart_wobbles_upright() -> void:
	var start := _Wobble.right_basis(0.0, 1.0)
	assert_lt(start.get_euler().z, -deg_to_rad(40.0), "it starts on its side")
	var done := _Wobble.right_basis(_Wobble.RIGHT_TIME, 1.0)
	assert_almost_eq(done.get_euler().z, 0.0, 0.08)
	var flop := _Wobble.right_basis(0.28, 1.0)
	assert_gt(absf(flop.get_euler().z - start.get_euler().z), 0.1, "and heaves on the way up")


func test_a_tipped_cart_has_to_be_flipped() -> void:
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.set_process(false)
	await wait_physics_frames(1)
	cart.global_position = Vector3.ZERO
	player.global_position = Vector3(1.0, 0.0, 0.0)
	cart._begin_tip()
	assert_true(cart.is_overturned())
	assert_false(cart.can_board(player), "you cannot hop a cart that is on its side")
	assert_true(cart.can_right(player))
	cart.try_right(player)
	assert_true(cart.is_righting())
	assert_false(cart.can_right(player), "leave it alone while it wobbles up")
	cart._right_age = _Wobble.RIGHT_TIME - 0.01
	cart._drive(0.02)
	assert_false(cart.is_overturned())
	assert_false(cart.is_righting())
	assert_true(cart.can_board(player))


func test_recovering_clears_the_wobble() -> void:
	var cart := GolfCart.new()
	cart._lean = 0.9
	cart._lean_vel = 2.0
	cart._shear = 0.4
	cart._tip_hold = 0.3
	cart._tip_age = 0.4
	cart._right_age = 0.2
	cart._tip_sign = -1.0
	cart.sync_tipped = true
	cart.recover_at(Vector3.ZERO, 0.0)
	assert_eq(cart._lean, 0.0)
	assert_eq(cart._lean_vel, 0.0)
	assert_eq(cart._shear, 0.0)
	assert_eq(cart._tip_hold, 0.0)
	assert_eq(cart._tip_age, -1.0)
	assert_eq(cart._right_age, -1.0)
	assert_false(cart.sync_tipped)
	cart.free()


func test_you_can_board_a_cart_placed_on_the_hole() -> void:
	var assigned: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	var placed: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(assigned)
	add_child_autofree(placed)
	add_child_autofree(player)
	assigned.set_physics_process(false)
	placed.set_physics_process(false)
	player.set_physics_process(false)
	player.set_process(false)
	await wait_physics_frames(1)
	assigned.global_position = Vector3(80.0, 0.0, 0.0)
	placed.global_position = Vector3.ZERO
	player.global_position = Vector3(1.0, 0.0, 0.0)
	player.cart = assigned
	assert_eq(player.active_cart(), placed, "interact talks to the cart you are next to")
	assert_true(placed.can_board(player))
	assert_false(assigned.can_board(player), "the assigned tee cart is across the hole")
	placed.board(player)
	assert_true(placed.is_riding(player))
	assert_eq(player.cart, placed)


func test_the_cpu_buddy_cannot_take_the_wheel() -> void:
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	var human: Player = preload("res://scenes/players/player.tscn").instantiate()
	var cpu: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(cart)
	add_child_autofree(human)
	add_child_autofree(cpu)
	cart.set_physics_process(false)
	human.set_physics_process(false)
	cpu.set_physics_process(false)
	cpu.possess_cpu()
	cart.global_position = Vector3.ZERO
	human.global_position = Vector3(1.0, 0.0, 0.0)
	cpu.global_position = Vector3(-1.0, 0.0, 0.0)
	cart.board(cpu)
	assert_eq(cart.passenger, cpu, "the buddy sits shotgun")
	assert_null(cart.driver, "an empty cart does not hand the buddy the wheel")
	cart.board(human)
	assert_eq(cart.driver, human)
	assert_eq(cart.passenger, cpu)
	assert_false(cart.can_board(cpu), "no second seat, and they still cannot drive")


func test_a_host_cpu_driver_throttles_from_its_own_stick() -> void:
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	var driver: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(driver)
	driver.set_physics_process(false)
	driver.set_process(false)
	driver.net_driven = true
	driver.peer_id = -1
	driver.cpu_filled = true
	var pad := CpuInput.new("p1", false)
	pad.move = Vector2(0.0, -1.0)
	driver.input = pad
	cart.global_position = Vector3(0.0, 0.4, 0.0)
	cart.rotation = Vector3.ZERO
	cart.driver = driver
	driver.cart = cart
	driver.enter_ride()
	for _i in 12:
		cart._drive(0.05)
	assert_gt(cart.drive_speed, 2.0, "a host CPU at the wheel has to roll")
	assert_gt(cart.sync_stick.y, 0.5, "and publish that throttle for watchers")


func _cpu_driver(cart: GolfCart, move: Vector2) -> Player:
	var driver: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(driver)
	driver.set_physics_process(false)
	driver.set_process(false)
	var pad := CpuInput.new("p1", false)
	pad.move = move
	driver.input = pad
	cart.driver = driver
	driver.cart = cart
	driver.enter_ride()
	return driver


func _flat_world(at: Vector3, size: Vector3) -> void:
	var floor := StaticBody3D.new()
	floor.collision_layer = Layers.WORLD
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	floor.add_child(col)
	floor.position = at
	add_child_autofree(floor)


func _curb(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	body.position = at
	add_child_autofree(body)


func _wheel_gap(cart: GolfCart, local_z: float) -> float:
	var wheel := cart.to_global(Vector3(0.0, 0.0, local_z))
	var space := cart.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		wheel + Vector3.UP * 2.0, wheel + Vector3.DOWN * 2.0
	)
	query.collision_mask = Layers.WORLD
	query.exclude = [cart.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return 99.0
	return absf(wheel.y - hit.position.y)
