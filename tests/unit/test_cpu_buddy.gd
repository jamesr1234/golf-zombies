extends GutTest
## The test CPU writes onto a fake pad and aims with the same look convention
## the player already uses. It is not wired up in these unit tests' world.


func test_the_cpu_pad_ignores_the_keyboard() -> void:
	var pad := CpuInput.new("p1", false)
	pad.hold("shoot")
	pad.tap("reload")
	pad.move = Vector2(0.0, -1.0)
	assert_true(pad.pressed("shoot"))
	assert_true(pad.just_pressed("reload"))
	assert_eq(pad.move_vector(), Vector2(0.0, -1.0))
	assert_false(pad.pressed("jump"), "unset buttons stay up")
	pad.begin_frame()
	assert_false(pad.pressed("shoot"), "a new frame starts from rest")
	assert_false(pad.just_pressed("reload"))
	pad.release("interact")
	assert_true(pad.just_released("interact"))
	assert_false(pad.pressed("interact"))


func test_local_move_forward_is_negative_stick_y() -> void:
	var stick := CpuBuddy.local_move(Basis.IDENTITY, Vector3(0.0, 0.0, -1.0))
	assert_almost_eq(stick.x, 0.0, 0.001)
	assert_almost_eq(stick.y, -1.0, 0.001, "local -Z is how the player walks forward")


func test_local_move_right_is_positive_stick_x() -> void:
	var stick := CpuBuddy.local_move(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0))
	assert_almost_eq(stick.x, 1.0, 0.001)
	assert_almost_eq(stick.y, 0.0, 0.001)


func test_cart_move_holds_forward_when_the_nose_faces_the_ball() -> void:
	var stick := CpuBuddy.cart_move(0.0, Vector3(0.0, 0.0, -12.0))
	assert_almost_eq(stick.x, 0.0, 0.05)
	assert_lt(stick.y, -0.9, "forward throttle is negative stick Y")


func test_cart_move_steers_right_when_the_ball_is_to_the_right() -> void:
	var stick := CpuBuddy.cart_move(0.0, Vector3(10.0, 0.0, 0.0))
	assert_gt(stick.x, 0.5, "positive steer yaws the cart toward +X")
	assert_lt(stick.y, 0.0, "still on the pedal while turning")


func test_race_move_keeps_the_pedal_down_in_a_tight_corner() -> void:
	var stick := CpuBuddy.race_move(0.0, Vector3(12.0, 0.0, -2.0))
	assert_gt(stick.x, GolfCart.DRIFT_STEER, "enough steer to slide")
	assert_almost_eq(stick.y, -1.0, 0.001, "a racer does not lift in the corner")


func test_looking_right_needs_a_positive_look_x() -> void:
	# Yaw 0 faces -Z. A point to the right is +X, which is a negative yaw change,
	# and the player subtracts look.x from yaw, so the stick must go right.
	var error := CpuBuddy.yaw_error(0.0, Vector3.ZERO, Vector3(4.0, 0.0, 0.0))
	assert_lt(error, -80.0)
	var stick := CpuBuddy.look_stick(error, 0.0)
	assert_gt(stick.x, 0.5, "right stick look turns the body right")


func test_looking_up_needs_a_negative_look_y() -> void:
	var error := CpuBuddy.pitch_error(0.0, Vector3.ZERO, Vector3(0.0, 4.0, -4.0))
	assert_gt(error, 20.0)
	var stick := CpuBuddy.look_stick(0.0, error)
	assert_lt(stick.y, -0.5, "the player subtracts look.y from pitch")


func test_the_cpu_shoots_enemies() -> void:
	assert_true(CpuBuddy.SHOOT_ENEMIES)


func test_a_long_approach_wants_more_power_than_a_chip() -> void:
	var drive := CpuBuddy.wanted_power(
		Vector3.ZERO, Vector3(0.0, 0.0, -ClubKit.starter().scaled_carry() * 0.85)
	)
	var chip := CpuBuddy.wanted_power(Vector3.ZERO, Vector3(0.0, 0.0, -8.0))
	assert_gt(drive, 0.7)
	assert_lt(chip, 0.3)
	assert_gt(drive, chip)


func test_a_short_putt_wants_less_power_than_a_long_one() -> void:
	var short := CpuBuddy.wanted_power(Vector3.ZERO, Vector3(0.0, 0.0, -3.0), true)
	var long := CpuBuddy.wanted_power(Vector3.ZERO, Vector3(0.0, 0.0, -12.0), true)
	assert_lt(short, long)
	var across := CpuBuddy.wanted_power(
		Vector3.ZERO, Vector3(0.0, 0.0, -Shot.putt_run()), true
	)
	assert_gt(across, 0.7, "a stuffed putt is what crosses the green")


func test_holding_interact_sends_the_cpu_to_the_ball() -> void:
	var cpu: Player = preload("res://scenes/players/player.tscn").instantiate()
	var human: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(cpu)
	add_child_autofree(human)
	cpu.possess_cpu()
	cpu.partner = human
	human.partner = cpu
	human.input = CpuInput.new("p2", false)
	human.set_physics_process(false)
	cpu.set_physics_process(false)
	var pad := human.input as CpuInput
	pad.begin_frame()
	pad.hold("interact")
	human._tick_cpu_shot_command(0.2)
	assert_false(cpu.brain.shot_requested, "a tap must not order the shot")
	human._tick_cpu_shot_command(0.3)
	assert_true(cpu.brain.shot_requested)
	assert_true(cpu.brain.is_taking_shot())


func test_a_tap_hops_out_of_the_cart_without_climbing_back_in() -> void:
	var cpu: Player = preload("res://scenes/players/player.tscn").instantiate()
	var human: Player = preload("res://scenes/players/player.tscn").instantiate()
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cpu)
	add_child_autofree(human)
	add_child_autofree(cart)
	cpu.possess_cpu()
	cpu.partner = human
	human.partner = cpu
	human.cart = cart
	cpu.cart = cart
	human.input = CpuInput.new("p2", false)
	human.set_physics_process(false)
	cpu.set_physics_process(false)
	cart.set_physics_process(false)
	cart.global_position = Vector3.ZERO
	cart.board(human)
	assert_true(human.is_riding())
	var pad := human.input as CpuInput
	pad.begin_frame()
	pad.tap("interact")
	human._tick_cpu_shot_command(0.016)
	assert_false(human.is_riding(), "press hops out")
	pad.begin_frame()
	pad.release("interact")
	human._tick_cpu_shot_command(0.016)
	assert_false(human.is_riding(), "the release must not board again")
	assert_false(cpu.brain.shot_requested, "hopping out is not a CPU golf order")


func test_driving_holds_forward() -> void:
	var cpu: Player = preload("res://scenes/players/player.tscn").instantiate()
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cpu)
	add_child_autofree(cart)
	cpu.possess_cpu()
	cpu.cart = cart
	cart.set_physics_process(false)
	cart.global_position = Vector3.ZERO
	cart.board(cpu)
	cpu.set_physics_process(false)
	assert_eq(cart.passenger, cpu, "the buddy rides shotgun")
	assert_null(cart.driver)
	cpu.brain.tick(0.016)
	var pad := cpu.input as CpuInput
	assert_false(cpu.is_driving(), "they never take the wheel")
	assert_eq(pad.move.y, 0.0, "shotgun does not throttle")


func test_the_cpu_does_not_golf_until_asked() -> void:
	var cpu: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(cpu)
	cpu.possess_cpu()
	cpu.set_physics_process(false)
	var pad := cpu.input as CpuInput
	cpu.brain.tick(0.016)
	assert_false(cpu.brain.shot_requested)
	assert_false(pad.just_pressed("interact"))
	assert_false(pad.just_pressed("swing"))


func test_cover_stands_between_the_partner_and_the_sniper() -> void:
	var cover := CpuBuddy.cover_point(Vector3.ZERO, Vector3(0.0, 14.0, -80.0))
	assert_almost_eq(cover.x, 0.0, 0.001)
	assert_almost_eq(cover.z, -CpuBuddy.COVER_STANDOFF, 0.001)


func test_the_cpu_plants_a_shield_after_a_sniper_hit() -> void:
	var pair := _cover_pair()
	var cpu: Player = pair[0]
	var human: Player = pair[1]
	human.wants_cover = true
	cpu.brain.tick(0.016)
	var pad := cpu.input as CpuInput
	assert_true(pad.pressed("shield"), "the buddy should plant after a sniper connects")
	assert_eq(pad.move, Vector2.ZERO)


func test_the_cpu_plants_a_shield_when_the_partner_draws_the_sniper() -> void:
	var pair := _cover_pair()
	var cpu: Player = pair[0]
	var human: Player = pair[1]
	assert_true(human.weapon.add_gun(preload("res://resources/weapons/sniper.tres")))
	assert_true(human.is_holding_sniper())
	cpu.brain.tick(0.016)
	var pad := cpu.input as CpuInput
	assert_true(pad.pressed("shield"), "drawing the sniper should put the buddy on cover")
	assert_eq(pad.move, Vector2.ZERO)


func test_the_cpu_warps_when_the_partner_walks_out_of_reach() -> void:
	var cpu: Player = preload("res://scenes/players/player.tscn").instantiate()
	var human: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(cpu)
	add_child_autofree(human)
	cpu.possess_cpu()
	cpu.partner = human
	human.partner = cpu
	cpu.set_physics_process(false)
	human.set_physics_process(false)
	human.global_position = Vector3(0.0, 1.2, 0.0)
	cpu.global_position = Vector3(0.0, 1.2, 40.0)
	cpu.brain.tick(0.016)
	assert_lt(
		cpu.global_position.distance_to(human.global_position), 4.0,
		"a doorway or a long walk cannot strand the buddy"
	)


func test_the_cpu_warps_onto_the_cart_when_the_partner_drives_off() -> void:
	var cpu: Player = preload("res://scenes/players/player.tscn").instantiate()
	var human: Player = preload("res://scenes/players/player.tscn").instantiate()
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cpu)
	add_child_autofree(human)
	add_child_autofree(cart)
	cpu.possess_cpu()
	cpu.partner = human
	human.partner = cpu
	cpu.cart = cart
	human.cart = cart
	cpu.set_physics_process(false)
	human.set_physics_process(false)
	cart.set_physics_process(false)
	cart.global_position = Vector3.ZERO
	cart.board(human)
	cpu.global_position = Vector3(0.0, 1.2, 40.0)
	cpu.brain.tick(0.016)
	assert_true(cpu.is_riding(), "the buddy has to catch the cart instead of jogging after it")
	assert_eq(cart.passenger, cpu)


func _cover_pair() -> Array:
	var cpu: Player = preload("res://scenes/players/player.tscn").instantiate()
	var human: Player = preload("res://scenes/players/player.tscn").instantiate()
	var sniper: Zombie = preload("res://scenes/zombies/zombie.tscn").instantiate()
	add_child_autofree(cpu)
	add_child_autofree(human)
	sniper.stats = preload("res://resources/zombies/sniper.tres")
	add_child_autofree(sniper)
	cpu.possess_cpu()
	cpu.partner = human
	human.partner = cpu
	cpu.set_physics_process(false)
	human.set_physics_process(false)
	sniper.set_physics_process(false)
	human.global_position = Vector3.ZERO
	sniper.global_position = Vector3(0.0, 0.0, -80.0)
	cpu.global_position = CpuBuddy.cover_point(human.global_position, sniper.global_position)
	return [cpu, human, sniper]


class FlowStub:
	var hole: HoleData
	var phase := 0


func test_the_cpu_walks_to_a_gun_in_the_arena() -> void:
	var cpu: Player = preload("res://scenes/players/player.tscn").instantiate()
	var pickup: GunPickup = preload("res://scenes/course/props/gun_pickup.tscn").instantiate()
	add_child_autofree(cpu)
	add_child_autofree(pickup)
	cpu.possess_cpu()
	cpu.set_physics_process(false)
	var hole := HoleData.new()
	hole.index = ArenaHole.INDEX
	var flow := FlowStub.new()
	flow.hole = hole
	cpu.flow = flow
	cpu.global_position = Vector3(0.0, 1.2, 0.0)
	pickup.global_position = Vector3(8.0, 1.0, 0.0)
	cpu.brain.tick(0.016)
	var pad := cpu.input as CpuInput
	assert_gt(pad.move.length(), 0.2, "unarmed, the buddy has to walk to a pickup")
	assert_false(cpu.weapon.has_weapon())
