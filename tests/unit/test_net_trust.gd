extends GutTest
## Who an `any_peer` request is allowed to speak for, and what the host is
## allowed to believe about it.
##
## A request that names a peer arrives over a wire that already knows who sent
## it. Trusting the name instead of the sender is how one client ends up driving
## another player's cart, and trusting a number instead of bounding it is how a
## swing carries further than any club can hit. A direct call from a test reports
## sender 0, which speaks for nobody, so it stands in for a peer naming a seat
## that is not its own.

const PLAYER := preload("res://scenes/players/player.tscn")
const CART := preload("res://scenes/vehicles/golf_cart.tscn")
const MECH := preload("res://scenes/course/items/mech_suit.tscn")
const STEP := 1.0 / 60.0


func after_each() -> void:
	NetSession.close()
	NetSession.seats.clear()
	GameSettings.reset()


func test_a_request_only_speaks_for_the_peer_that_sent_it() -> void:
	assert_true(NetSession.rpc_speaks_for(4, 4), "your own seat is yours to drive")
	assert_false(NetSession.rpc_speaks_for(4, 5), "peer 4 must not act as peer 5")
	assert_false(NetSession.rpc_speaks_for(1, 5), "not even the host puppets a peer this way")


## Sender 0 is a local call and peer 0 is nobody. Neither names a peer, so
## neither may stand in for one.
func test_an_unnamed_peer_speaks_for_nobody() -> void:
	assert_false(NetSession.rpc_speaks_for(0, 0))
	assert_false(NetSession.rpc_speaks_for(0, 3))
	assert_false(NetSession.rpc_speaks_for(3, 0))
	assert_false(NetSession.rpc_speaks_for(-1, -1), "a junk id is still not a seat")


func test_only_peer_one_counts_as_the_host() -> void:
	assert_true(NetSession.rpc_from_host(1))
	assert_false(NetSession.rpc_from_host(2), "a client must not deal out knockback")
	assert_false(NetSession.rpc_from_host(0))


func test_a_client_cannot_board_or_eject_another_player() -> void:
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	var victim: Player = PLAYER.instantiate()
	add_child_autofree(victim)
	await wait_physics_frames(2)
	victim.peer_id = 5
	victim.spawn_at(cart.global_position + Vector3(1.0, 0.0, 0.0), 0.0)
	cart._request_board(5)
	assert_null(cart.driver, "a peer must not seat a player who did not ask")
	assert_false(victim.is_riding())
	cart._do_board(victim)
	assert_eq(cart.driver, victim, "the player's own board still reaches the seat")
	cart._request_eject(5)
	assert_eq(cart.driver, victim, "a peer must not turn another player out of the cart")
	assert_true(victim.is_riding())


func test_a_client_cannot_shut_another_player_into_a_mech() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)
	var suit: MechSuit = MECH.instantiate()
	add_child_autofree(suit)
	var victim: Player = PLAYER.instantiate()
	add_child_autofree(victim)
	await wait_physics_frames(2)
	suit.global_position = Vector3.ZERO
	victim.peer_id = 5
	victim.global_position = suit.get_node("Cockpit").global_position
	suit.bind_owner(victim)
	suit._request_close(5)
	assert_null(suit.pilot, "the suit only closes on the peer that asked")
	assert_false(suit.is_closed())
	suit.try_close(victim)
	assert_eq(suit.pilot, victim, "the player's own reach into the cockpit still seals it")


func test_a_client_cannot_steer_a_mill_it_is_not_standing_at() -> void:
	var mill := CartPathWindmill.create(Vector3(6.0, 0.0, 0.0), Vector3.FORWARD)
	add_child_autofree(mill)
	var desk := WindmillControl.create({"position": Vector3(0.0, 0.0, 2.0), "yaw": 0.0})
	add_child_autofree(desk)
	var operator: Player = PLAYER.instantiate()
	add_child_autofree(operator)
	await wait_physics_frames(2)
	operator.peer_id = 5
	operator.global_position = desk.stand_at()
	desk.try_toggle(operator)
	assert_true(operator.is_milling(), "somebody is legitimately at the desk")
	var held := mill.rotor_rad()
	# The first stick out of the deadzone only latches, so it takes a second one
	# to turn the blades. Both are sent, or the latch would hide the guard.
	desk._report_stick(Vector2(1.0, 0.0))
	desk._report_stick(Vector2(0.0, -1.0))
	assert_almost_eq(mill.rotor_rad(), held, 0.0001, "only the peer at the desk turns the blades")
	desk._steer(Vector2(1.0, 0.0))
	desk._steer(Vector2(0.0, -1.0))
	assert_ne(mill.rotor_rad(), held, "the same stick from the operator does turn them")
	desk._request_toggle(5)
	assert_eq(desk.operator, operator, "and nobody else may take the desk off them")


func test_a_wire_swing_cannot_carry_further_than_a_full_backswing() -> void:
	var meter := SwingMeter.new()
	meter.accept_remote(50.0, 0.0)
	assert_eq(meter.power, 1.0, "no club hits harder than a topped-out meter")
	meter.accept_remote(-3.0, 0.0)
	assert_eq(meter.power, SwingMeter.MIN_POWER, "and none hits backwards")
	meter.accept_remote(0.62, 0.0)
	assert_almost_eq(meter.power, 0.62, 0.0001, "a real swing arrives untouched")


func test_a_wire_swing_cannot_bend_further_than_a_shank() -> void:
	var meter := SwingMeter.new()
	meter.accept_remote(1.0, 900.0)
	assert_eq(meter.deviation_deg, SwingMeter.MISS_DEVIATION_DEG)
	meter.accept_remote(1.0, -900.0)
	assert_eq(meter.deviation_deg, -SwingMeter.MISS_DEVIATION_DEG)
	meter.accept_remote(1.0, -4.5)
	assert_almost_eq(meter.deviation_deg, -4.5, 0.0001, "a real mishit arrives untouched")


## A NaN power reaches the ball as a NaN velocity and parks it off the world
## where no stroke can reach it, which ends the run with no way to finish.
func test_a_junk_wire_swing_falls_back_to_a_legal_one() -> void:
	var meter := SwingMeter.new()
	meter.accept_remote(NAN, NAN)
	assert_eq(meter.power, SwingMeter.MIN_POWER)
	assert_eq(meter.deviation_deg, 0.0)
	meter.accept_remote(INF, -INF)
	assert_eq(meter.power, SwingMeter.MIN_POWER)
	assert_eq(meter.deviation_deg, 0.0)


## The clubhouse doors are the gate the phase RPCs now re-check on the host, so
## a sender who is not standing there gets nowhere. Without it any peer could
## reset a live hole to prep for everyone.
func test_the_clubhouse_only_opens_for_someone_standing_at_it() -> void:
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	await wait_physics_frames(2)
	assert_false(house.can_open_doors(null), "an unknown sender is not at the door")
	assert_false(house.can_open_exit(null))
	var far: Player = PLAYER.instantiate()
	add_child_autofree(far)
	await wait_physics_frames(1)
	far.global_position = house.door_point() + Vector3(0.0, 0.0, 400.0)
	assert_false(house.can_open_doors(far), "still out on the hole, not at the door")
	var near: Player = PLAYER.instantiate()
	add_child_autofree(near)
	await wait_physics_frames(1)
	near.global_position = house.door_point()
	assert_true(house.can_open_doors(near), "walking up to it still works")
