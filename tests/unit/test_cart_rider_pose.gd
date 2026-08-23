extends GutTest
## A rider's pose has one owner: the cart it sits in. If the pawn also chased its
## own replicated transform, the two would fight and the body would snap between
## the seat and whatever the rider last reported.

const PLAYER := preload("res://scenes/players/player.tscn")
const CART := preload("res://scenes/vehicles/golf_cart.tscn")


func after_each() -> void:
	NetSession.close()
	NetSession.seats.clear()
	GameSettings.reset()


func _cart_with_driver() -> Array:
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_frames(1)
	cart.board(player)
	return [cart, player]


func test_a_rider_is_marked_as_carried_by_its_cart() -> void:
	var pair := await _cart_with_driver()
	var cart: GolfCart = pair[0]
	var player: Player = pair[1]
	assert_true(player.carried_by_cart(), "the cart places a rider, not the network")
	cart.eject(player)
	assert_false(player.carried_by_cart(), "on foot again, the pawn owns its own pose")


func test_a_pawn_on_foot_is_not_carried() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_frames(1)
	assert_false(player.carried_by_cart())


## The bug this guards: a watching peer glided the cart but never re-seated the
## rider, so the body was left at whatever the driver last reported.
func test_a_watching_peer_re_seats_riders_after_gliding_the_cart() -> void:
	var pair := await _cart_with_driver()
	var cart: GolfCart = pair[0]
	var player: Player = pair[1]
	cart.global_position = Vector3(40.0, 0.0, 0.0)
	player.global_position = Vector3.ZERO
	cart._seat_riders()
	assert_almost_eq(
		player.global_position.distance_to(cart.seats[0].global_position), 0.0, 0.01,
		"the rider sits in the seat, not where the network last put it"
	)


func test_a_carried_rider_ignores_a_stale_replicated_transform() -> void:
	var pair := await _cart_with_driver()
	var cart: GolfCart = pair[0]
	var player: Player = pair[1]
	cart.global_position = Vector3(40.0, 0.0, 0.0)
	cart._seat_riders()
	var seated := player.global_position
	player.sync_xform = Transform3D(Basis(), Vector3.ZERO)
	assert_almost_eq(
		player.global_position.distance_to(seated), 0.0, 0.01,
		"a stale snapshot must not drag the rider out of the seat"
	)
	assert_eq(player.net_interp().snaps, 0, "and must not be logged as a teleport")


## Prediction is for the peer that owns the stick and does not own the cart. On
## the host, and in solo, the cart is simulated for real and there is nothing to
## predict against.
func test_a_cart_it_already_simulates_is_never_predicted() -> void:
	var pair := await _cart_with_driver()
	assert_false((pair[0] as GolfCart).predicts_locally())


func test_an_empty_cart_is_only_ever_watched() -> void:
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	await wait_frames(1)
	assert_false(cart.predicts_locally(), "with no one at the wheel there is no stick to read")
