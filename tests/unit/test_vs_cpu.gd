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
	add_child_autofree(flow)
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
	_tick()
	assert_true(_ghost.wants("swing"), "click two at the top of the meter")
	assert_false(_ghost.wants("interact"))


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
	_player.cart = cart
	cart.driver = _player
	_player.enter_ride()
	_player.global_position = Vector3.ZERO
	_tick()
	assert_lt(_ghost.move.y, -0.5, "drive down the path")
	assert_true(_ghost.wants("shoot"), "boost like a human holding the trigger")


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
