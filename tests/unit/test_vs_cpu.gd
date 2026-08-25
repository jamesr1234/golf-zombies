extends GutTest
## The online CPU writes intents onto an InputGhost. It does not possess the pawn.

const PLAYER := preload("res://scenes/players/player.tscn")
const CART := preload("res://scenes/vehicles/golf_cart.tscn")

var _ghost: InputGhost
var _brain: VsCpu
var _player: Player


func before_each() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	InputActions.register_for_mode(GameSettings.Mode.ONLINE_VS)
	_ghost = InputGhost.new()
	_brain = VsCpu.new()
	_player = PLAYER.instantiate()
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_brain.setup(_player, _ghost)


func after_each() -> void:
	if _ghost != null:
		_ghost.release_all()
	GameSettings.mode = GameSettings.Mode.SOLO
	NetSession.seats.clear()


func test_coop_cpu_skips_golf_off_turn() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	NetSession.seats = {1: 0, 2: 1}
	_player.peer_id = 2
	_player.cpu_filled = true
	var flow := VsMatchFlow.new()
	flow.phase = VsMatchFlow.Phase.PLAYING
	var card := TeamScore.new()
	card.team = 0
	flow._team_scores[0] = card
	_player.flow = flow
	var golf := GolfController.new()
	var ball := GolfBall.new()
	add_child_autofree(golf)
	add_child_autofree(ball)
	golf.ball = ball
	_player.golf = golf
	_tick()
	assert_false(_ghost.wants("interact"), "the CPU waits for its turn")
	assert_false(_ghost.wants("swing"))
	flow.free()


func test_prep_near_the_tee_requests_interact() -> void:
	_player.flow = _FakeFlow.new()
	_player.flow.phase = VsMatchFlow.Phase.PREP
	_tick()
	assert_true(_ghost.wants("interact"), "Computer 2 has to start the hole")


func test_a_backswing_at_wanted_power_requests_swing() -> void:
	_player.flow = _FakeFlow.new()
	_player.flow.phase = VsMatchFlow.Phase.PLAYING
	var golf := GolfController.new()
	var ball := GolfBall.new()
	add_child_autofree(golf)
	add_child_autofree(ball)
	golf.ball = ball
	golf.golfer = _player
	golf.meter.state = SwingMeter.State.BACKSWING
	golf.meter.value = 0.95
	_player.golf = golf
	_player.enter_golf_mode()
	_brain._shot_power = CpuBuddy.wanted_power(Vector3.ZERO, Vector3(0.0, 0.0, -120.0))
	_brain._power_slop = 0.0
	_brain._contact_slop = 0.05
	_brain._address_left = 0.0
	_tick()
	assert_true(_ghost.wants("swing"), "click two at the top of the meter")
	assert_false(_ghost.wants("interact"))


func test_off_turn_cpu_walks_to_the_team_ball() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	NetSession.seats = {1: 0, 2: 1}
	_player.peer_id = 2
	_player.cpu_filled = true
	_player.global_position = Vector3.ZERO
	var flow := VsMatchFlow.new()
	flow.phase = VsMatchFlow.Phase.PLAYING
	var card := TeamScore.new()
	card.team = 0
	flow._team_scores[0] = card
	_player.flow = flow
	var golf := GolfController.new()
	var ball := GolfBall.new()
	add_child_autofree(golf)
	add_child_autofree(ball)
	ball.global_position = Vector3(0.0, 0.0, -40.0)
	golf.ball = ball
	_player.golf = golf
	_tick()
	assert_gt(_ghost.move.length(), 0.3, "the partner goes to the shared ball")
	assert_false(_ghost.wants("interact"), "off-turn does not claim")
	assert_false(_ghost.wants("swing"))
	flow.free()


func test_a_long_approach_goes_to_the_cart_first() -> void:
	_player.flow = _CartFlow.new()
	_player.flow.phase = VsMatchFlow.Phase.PLAYING
	_player.global_position = Vector3.ZERO
	var golf := GolfController.new()
	var ball := GolfBall.new()
	add_child_autofree(golf)
	add_child_autofree(ball)
	ball.global_position = Vector3(0.0, 0.0, -80.0)
	golf.ball = ball
	_player.golf = golf
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3(8.0, 0.0, 0.0)
	_player.flow.cart = cart
	_tick()
	assert_gt(_ghost.move.x, 0.3, "walk to the cart, not the far ball")
	assert_true(_ghost.wants("sprint"))
	assert_false(_ghost.wants("interact"), "cart is still out of board range")


func test_driver_hops_out_near_the_ball() -> void:
	_player.flow = _FakeFlow.new()
	_player.flow.phase = VsMatchFlow.Phase.PLAYING
	var golf := GolfController.new()
	var ball := GolfBall.new()
	add_child_autofree(golf)
	add_child_autofree(ball)
	ball.global_position = Vector3(0.0, 0.0, -5.0)
	golf.ball = ball
	_player.golf = golf
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	_player.cart = cart
	cart.driver = _player
	_player.enter_ride()
	_player.global_position = Vector3.ZERO
	_tick()
	assert_true(_ghost.wants("interact"), "hop out when the ball is in walking range")


func test_cpu_takes_a_beat_before_claiming() -> void:
	_player.flow = _FakeFlow.new()
	_player.flow.phase = VsMatchFlow.Phase.PLAYING
	var golf := GolfController.new()
	var ball := GolfBall.new()
	add_child_autofree(golf)
	add_child_autofree(ball)
	ball.global_position = Vector3.ZERO
	golf.ball = ball
	_player.golf = golf
	_player.global_position = Vector3(1.0, 0.0, 0.0)
	_tick()
	assert_false(_ghost.wants("interact"), "read the line first")
	assert_gt(_brain._think_left, 0.0)
	_brain._think_left = 0.0
	_tick()
	assert_true(_ghost.wants("interact"))


func test_address_waits_before_the_first_click() -> void:
	_player.flow = _FakeFlow.new()
	_player.flow.phase = VsMatchFlow.Phase.PLAYING
	var golf := GolfController.new()
	var ball := GolfBall.new()
	add_child_autofree(golf)
	add_child_autofree(ball)
	golf.ball = ball
	golf.golfer = _player
	golf.meter.state = SwingMeter.State.READY
	_player.golf = golf
	_player.enter_golf_mode()
	_brain._address_left = 1.2
	_tick()
	assert_false(_ghost.wants("swing"), "waggle first")
	_brain._address_left = 0.0
	_tick()
	assert_true(_ghost.wants("swing"))


func test_driver_holds_forward_from_the_cart_heading() -> void:
	_player.flow = _FakeFlow.new()
	_player.flow.phase = VsMatchFlow.Phase.PLAYING
	var golf := GolfController.new()
	var ball := GolfBall.new()
	add_child_autofree(golf)
	add_child_autofree(ball)
	ball.global_position = Vector3(0.0, 0.0, -40.0)
	golf.ball = ball
	_player.golf = golf
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3.ZERO
	cart.rotation.y = 0.0
	_player.cart = cart
	cart.driver = _player
	_player.enter_ride()
	_player.global_position = Vector3.ZERO
	_player.rotation.y = PI * 0.5
	_tick()
	assert_lt(_ghost.move.y, -0.5, "drive from the cart nose, not the pawn look")
	assert_almost_eq(_ghost.move.x, 0.0, 0.2, "already facing the ball")
	assert_true(_ghost.wants("shoot"), "boost on a long fairway ride")
	assert_false(_ghost.wants("interact"), "too far to hop out")


func test_cpu_drives_to_the_ball_after_the_shot() -> void:
	_player.flow = _FakeFlow.new()
	_player.flow.phase = VsMatchFlow.Phase.PLAYING
	var golf := GolfController.new()
	var ball := GolfBall.new()
	add_child_autofree(golf)
	add_child_autofree(ball)
	ball.global_position = Vector3(0.0, 0.0, -80.0)
	ball._in_play = true
	golf.ball = ball
	_player.golf = golf
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3.ZERO
	cart.rotation.y = 0.0
	_player.cart = cart
	cart.driver = _player
	_player.enter_ride()
	_player.global_position = Vector3.ZERO
	_tick()
	assert_lt(_ghost.move.y, -0.5, "chase the shot instead of sitting still")
	assert_false(_ghost.wants("interact"), "keep driving until the ball is close")


func test_cpu_treads_out_to_the_ball_before_diving() -> void:
	_wet_ball(Vector3(0.0, -1.0, -12.0))
	_enter_swim()
	_tick()
	assert_false(_ghost.wants("shoot"), "open water is a swim, not an instant dive")
	assert_gt(_ghost.move.length(), 0.3)


func test_treading_cpu_dives_for_a_sunk_ball() -> void:
	var ball := _wet_ball(Vector3(0.0, -1.0, -4.0))
	_enter_swim()
	_tick()
	assert_true(_ghost.wants("shoot"), "R2 from the surface is the dive")
	assert_false(_ghost.wants("grab"), "too far to pick up yet")
	assert_gt(_ghost.move.length(), 0.3, "swim at the ball")
	assert_true(ball.is_submerged())


func test_underwater_cpu_grabs_a_nearby_sunk_ball() -> void:
	_wet_ball(Vector3(0.4, -0.8, 0.0))
	_enter_swim(true)
	_tick()
	assert_true(_ghost.wants("grab"), "Circle picks it up off the pond floor")
	assert_false(_ghost.wants("shoot"))


func test_underwater_cpu_descends_toward_a_deep_ball() -> void:
	_wet_ball(Vector3(0.0, -3.0, -5.0))
	_enter_swim(true)
	_tick()
	assert_true(_ghost.wants("melee"), "L1 is swim-down")
	assert_false(_ghost.wants("grab"), "still out of reach")
	assert_gt(_ghost.move.length(), 0.3)


func test_cpu_surfaces_then_throws_the_ball_at_the_pin() -> void:
	var ball := _wet_ball(Vector3.ZERO)
	ball.pick_up(_player)
	_enter_swim(true)
	_tick()
	assert_true(_ghost.wants("ascend"), "get back to the surface first")
	assert_false(_ghost.wants("shoot"))
	_player.swim.underwater = false
	_player.rotation.y = 0.0
	_tick()
	assert_true(_ghost.wants("shoot"), "R2 on the surface is the toss")
	assert_false(_ghost.wants("grab"), "do not climb out with it")


func test_cpu_swims_the_ball_toward_the_pin_before_throwing() -> void:
	var ball := _wet_ball(Vector3.ZERO)
	ball.pick_up(_player)
	_enter_swim()
	_player.flow.hole = _PondHole.new()
	_tick()
	assert_false(_ghost.wants("shoot"), "do not toss back into the middle of the pond")
	assert_lt(_ghost.move.y, -0.3, "swim the ball toward the pin first")


func test_cpu_walks_into_the_pond_when_the_ball_is_sunk() -> void:
	_wet_ball(Vector3(0.0, -1.0, -10.0))
	_player.global_position = Vector3.ZERO
	_tick()
	assert_gt(absf(_ghost.move.y), 0.3, "walk in, do not address a sunk ball")
	assert_false(_ghost.wants("interact"))
	assert_false(_ghost.wants("swing"))


func test_off_turn_cpu_still_dives_for_the_team_ball() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	NetSession.seats = {1: 0, 2: 1}
	_player.peer_id = 2
	_player.cpu_filled = true
	var flow := VsMatchFlow.new()
	flow.phase = VsMatchFlow.Phase.PLAYING
	var card := TeamScore.new()
	card.team = 0
	flow._team_scores[0] = card
	_player.flow = flow
	var golf := GolfController.new()
	var ball := GolfBall.new()
	add_child_autofree(golf)
	add_child_autofree(ball)
	golf.setup(ball, Vector3(0.0, 0.0, -80.0))
	ball.global_position = Vector3(0.0, -1.0, -4.0)
	ball.enter_surface(Surface.Type.WATER)
	_player.golf = golf
	_enter_swim()
	_tick()
	assert_true(_ghost.wants("shoot"), "anyone on the team can fetch it")
	assert_false(_ghost.wants("interact"))
	flow.free()


func test_cpu_leaves_the_water_once_the_partner_has_the_ball() -> void:
	var ball := _wet_ball(Vector3.ZERO)
	var mate := Node3D.new()
	add_child_autofree(mate)
	ball.pick_up(mate)
	_enter_swim()
	_tick()
	assert_true(_ghost.wants("grab"), "climb out and let them throw")
	assert_false(_ghost.wants("shoot"))


func test_driving_transit_holds_forward() -> void:
	_player.flow = _FakeFlow.new()
	_player.flow.phase = VsMatchFlow.Phase.TRANSIT
	var path := CartPath.new()
	add_child_autofree(path)
	path.heading = Vector3(0.0, 0.0, -1.0)
	path.centerline = [Vector3.ZERO, Vector3(0.0, 0.0, -40.0)]
	path.tee = Vector3(0.0, 0.0, -80.0)
	_player.flow.course = {"cart_path": path, "clubhouse": null}
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3.ZERO
	cart.rotation.y = 0.0
	_player.cart = cart
	cart.driver = _player
	_player.enter_ride()
	_player.global_position = Vector3.ZERO
	_tick()
	assert_lt(_ghost.move.y, -0.5, "drive down the path")
	assert_true(_ghost.wants("shoot"), "boost like a human holding the trigger")


func test_transit_cpu_drifts_a_right_hander() -> void:
	_player.flow = _FakeFlow.new()
	_player.flow.phase = VsMatchFlow.Phase.TRANSIT
	var path := CartPath.new()
	add_child_autofree(path)
	path.heading = Vector3(0.0, 0.0, -1.0)
	path.centerline = [
		Vector3.ZERO,
		Vector3(0.0, 0.0, -20.0),
		Vector3(24.0, 0.0, -20.0),
	]
	path.tee = Vector3(80.0, 0.0, -20.0)
	_player.flow.course = {"cart_path": path, "clubhouse": null}
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3(0.0, 0.0, -18.0)
	cart.rotation.y = 0.0
	_player.cart = cart
	cart.driver = _player
	_player.enter_ride()
	_player.global_position = cart.global_position
	_tick()
	assert_gt(_ghost.move.x, GolfCart.DRIFT_STEER, "steer into the corner")
	assert_true(_ghost.wants("shoot"), "boost plus steer is the drift")
	assert_lt(_ghost.move.y, -0.9, "stay on the pedal through the slide")


func _wet_ball(at: Vector3) -> GolfBall:
	_player.flow = _FakeFlow.new()
	_player.flow.phase = VsMatchFlow.Phase.PLAYING
	var golf := GolfController.new()
	var ball := GolfBall.new()
	add_child_autofree(golf)
	add_child_autofree(ball)
	golf.setup(ball, Vector3(0.0, 0.0, -80.0))
	ball.global_position = at
	ball.enter_surface(Surface.Type.WATER)
	_player.golf = golf
	_player.global_position = Vector3.ZERO
	return ball


func _enter_swim(underwater := false) -> void:
	_player.state = Player.State.SWIMMING
	_player.swim.underwater = underwater


func _tick() -> void:
	_ghost.begin_frame()
	_brain.tick(0.016)
	_ghost.apply()


class _FakeFlow:
	var phase := VsMatchFlow.Phase.PREP
	var hole
	var course

	func can_start_play(_who: Node3D) -> bool:
		return phase == VsMatchFlow.Phase.PREP

	func is_practice() -> bool:
		return phase == VsMatchFlow.Phase.PREP or phase == VsMatchFlow.Phase.SHOP

	func can_strike(_who: Node3D) -> bool:
		return true


class _PondHole:
	func water_depth_at(at: Vector3) -> float:
		return 0.0 if at.z < -20.0 else 6.0


class _CartFlow:
	var phase := VsMatchFlow.Phase.PLAYING
	var hole
	var course
	var cart: GolfCart

	func can_start_play(_who: Node3D) -> bool:
		return false

	func is_practice() -> bool:
		return false

	func can_strike(_who: Node3D) -> bool:
		return true

	func cart_for(_who: Node3D) -> GolfCart:
		return cart
