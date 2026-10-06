extends GutTest
## L3 / Shift picks up a resting ball you are standing over, you can carry it a
## short way, and placing it is a dropped-ball stroke.

const PLAYER := preload("res://scenes/players/player.tscn")
const STEP := 1.0 / 60.0


func test_l3_picks_up_a_resting_ball_you_are_over() -> void:
	var setup := _setup()
	var pad: CpuInput = setup.pad
	pad.tap("sprint")
	setup.player._fight(STEP)
	assert_true(setup.player.is_carrying_ball())
	assert_true(setup.player.is_dropping_ball())
	assert_eq(setup.ball.carrier(), setup.player)


func test_a_ball_too_far_away_stays_on_the_ground() -> void:
	var setup := _setup()
	setup.ball.global_position = Vector3(0.0, GolfBall.RADIUS, 3.0)
	var pad: CpuInput = setup.pad
	pad.tap("sprint")
	setup.player._fight(STEP)
	assert_false(setup.player.is_carrying_ball())
	assert_false(setup.ball.is_carried())


func test_a_rolling_ball_cannot_be_picked_up() -> void:
	var setup := _setup()
	setup.ball.toss(setup.ball.global_position, Vector3(0.0, 2.0, -4.0))
	assert_true(setup.ball.is_in_play())
	var pad: CpuInput = setup.pad
	pad.tap("sprint")
	setup.player._fight(STEP)
	assert_false(setup.player.is_carrying_ball(), "wait for it to stop")


func test_a_sunk_ball_stays_a_swim_grab() -> void:
	var setup := _setup()
	setup.ball.enter_surface(Surface.Type.WATER)
	assert_true(setup.ball.is_submerged())
	assert_false(setup.player.ball_drop.can_pick_up(setup.player))


func test_l3_places_the_carried_ball_as_a_stroke() -> void:
	var setup := _setup()
	watch_signals(setup.golf)
	setup.player.ball_drop.pick_up(setup.player)
	assert_true(setup.player.is_dropping_ball())
	setup.player.global_position = Vector3(2.0, 0.0, -1.5)
	var pad: CpuInput = setup.pad
	pad.tap("sprint")
	setup.player._fight(STEP)
	assert_false(setup.player.is_carrying_ball())
	assert_false(setup.player.is_dropping_ball())
	assert_false(setup.ball.is_in_play(), "a drop sits, it does not fly")
	assert_almost_eq(setup.ball.global_position.x, 2.0, 0.2)
	assert_almost_eq(setup.ball.global_position.z, -1.5, 0.2)
	assert_signal_emitted(setup.golf, "stroke_taken")


func test_running_past_the_limit_auto_drops() -> void:
	var setup := _setup()
	watch_signals(setup.golf)
	setup.player.ball_drop.pick_up(setup.player)
	setup.player.global_position = Vector3(0.0, 0.0, -(BallDrop.CARRY_LIMIT + 0.4))
	setup.player._fight(STEP)
	assert_false(setup.player.is_carrying_ball(), "the carry ends at the limit")
	assert_signal_emitted(setup.golf, "stroke_taken")
	var flat: Vector3 = setup.ball.global_position - setup.player.ball_drop.origin
	flat.y = 0.0
	assert_almost_eq(flat.length(), BallDrop.CARRY_LIMIT, 0.15)


func test_r2_does_not_throw_a_relief_carry() -> void:
	var setup := _setup()
	setup.player.ball_drop.pick_up(setup.player)
	var pad: CpuInput = setup.pad
	pad.tap("shoot")
	setup.player._fight(STEP)
	assert_true(setup.player.is_carrying_ball(), "relief is a drop, not a toss")
	assert_false(setup.ball.is_in_play())


func test_a_swim_carry_still_throws() -> void:
	var setup := _setup()
	setup.ball.pick_up(setup.player)
	assert_true(setup.player.is_carrying_ball())
	assert_false(setup.player.is_dropping_ball())
	var pad: CpuInput = setup.pad
	pad.tap("shoot")
	setup.player._fight(STEP)
	assert_false(setup.player.is_carrying_ball())
	assert_true(setup.ball.is_in_play())


func test_pickup_leaves_golf_mode() -> void:
	var setup := _setup()
	setup.golf.setup(setup.ball, Vector3(0.0, 0.0, -20.0))
	setup.golf.try_toggle(setup.player)
	assert_true(setup.golf.is_golfing(setup.player))
	var pad: CpuInput = setup.pad
	pad.tap("sprint")
	setup.player._fight(STEP)
	assert_false(setup.golf.is_golfing(setup.player))
	assert_true(setup.player.is_carrying_ball())


func test_a_closed_ball_is_retrieved_not_dropped() -> void:
	var setup := _setup()
	setup.ball.close_for_pickup()
	assert_false(setup.player.ball_drop.can_pick_up(setup.player))


func test_the_prompt_offers_pickup_when_you_are_over_the_ball() -> void:
	var setup := _setup()
	setup.golf.setup(setup.ball, Vector3(0.0, 0.0, -20.0))
	var text: String = setup.player.get_prompt().to_lower()
	assert_true(text.contains("pick up"), text)
	assert_true(text.contains("play the ball"), text)
	setup.player.ball_drop.pick_up(setup.player)
	assert_true(setup.player.get_prompt().to_lower().contains("drop the ball"))


func test_take_drop_places_and_counts_a_stroke() -> void:
	var golf := GolfController.new()
	var ball := GolfBall.new()
	add_child_autofree(golf)
	add_child_autofree(ball)
	golf.ball = ball
	watch_signals(golf)
	golf.take_drop(Vector3(4.0, 0.0, -3.0))
	assert_almost_eq(ball.global_position.x, 4.0, 0.2)
	assert_almost_eq(ball.global_position.z, -3.0, 0.2)
	assert_false(ball.is_in_play())
	assert_signal_emitted(golf, "stroke_taken")


func test_r3_still_zooms_when_you_are_over_the_ball() -> void:
	var setup := _setup()
	var sniper: WeaponStats = preload("res://resources/weapons/sniper.tres")
	if not setup.player.weapon.has_gun(sniper):
		setup.player.weapon.add_gun(sniper)
	setup.player.weapon.index = setup.player.weapon.loadout.find(sniper)
	var pad: CpuInput = setup.pad
	pad.tap("zoom")
	setup.player._fight(STEP)
	assert_false(setup.player.is_carrying_ball(), "R3 is zoom, not the pickup")
	assert_almost_eq(setup.player.weapon.zoom_mult(), 2.0, 0.001)


func _setup() -> Dictionary:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = Vector3.ZERO
	var ball := GolfBall.new()
	var golf := GolfController.new()
	add_child_autofree(ball)
	add_child_autofree(golf)
	golf.ball = ball
	player.golf = golf
	ball.global_position = Vector3(0.0, GolfBall.RADIUS, 0.4)
	var pad := CpuInput.new("p1", true)
	player.input = pad
	return {"player": player, "ball": ball, "golf": golf, "pad": pad}
