extends GutTest
## Online VS rules that do not need a live ENet session.


func after_each() -> void:
	NetSession.seats.clear()
	GameSettings.reset()


func test_eight_seat_colours_are_distinct() -> void:
	var seen := {}
	for i in Palette.SEATS.size():
		var color := Palette.seat_color(i)
		assert_eq(Palette.SEATS.size(), 8)
		assert_false(seen.has(color), "seat %d reuses a colour" % i)
		seen[color] = true
	assert_eq(Palette.seat_color(8), Palette.SEATS[0], "seats wrap")


func test_a_tinted_ball_matches_its_seat() -> void:
	var ball: GolfBall = preload("res://scenes/golf/ball.tscn").instantiate()
	add_child_autofree(ball)
	var color := Palette.seat_color(3)
	ball.apply_color(color)
	var glow := ball.get_node("Glow") as OmniLight3D
	assert_eq(glow.light_color, color)


func test_only_the_owner_can_claim_a_vs_ball() -> void:
	var ball: GolfBall = preload("res://scenes/golf/ball.tscn").instantiate()
	add_child_autofree(ball)
	ball.owner_peer = 4
	ball.place_at(Vector3.ZERO)
	var owner := _pawn(4, Vector3(1.0, 0.0, 0.0))
	var thief := _pawn(7, Vector3(1.0, 0.0, 0.0))
	assert_true(ball.is_owned_by(owner))
	assert_false(ball.is_owned_by(thief))
	var golf := GolfController.new()
	add_child_autofree(golf)
	golf.setup(ball, Vector3(0.0, 0.0, -20.0))
	assert_true(golf.can_claim(owner))
	assert_false(golf.can_claim(thief), "someone else's ball is not claimable")


func test_local_balls_stay_shared() -> void:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	var pawn := _pawn(0, Vector3.ZERO)
	assert_true(ball.is_owned_by(pawn))


func test_wallets_and_strokes_are_per_player() -> void:
	var cyan := PlayerScore.new()
	var amber := PlayerScore.new()
	cyan.seat = 0
	amber.seat = 1
	cyan.credit(80)
	amber.credit(20)
	cyan.add_stroke(3)
	amber.add_stroke(5)
	assert_eq(cyan.money, 80)
	assert_eq(amber.money, 20)
	assert_eq(cyan.strokes, 3)
	assert_eq(amber.strokes, 5)
	assert_false(cyan.try_spend(100))
	assert_true(amber.try_spend(20))
	assert_eq(amber.money, 0)


func test_clock_out_is_a_double_bogey_pickup() -> void:
	var card := PlayerScore.new(PackedInt32Array([4, 3, 5]))
	card.add_stroke(2)
	card.settle_pickup()
	assert_true(card.done_this_hole)
	assert_eq(card.strokes, 6)
	assert_eq(card.results[0], 6)
	assert_eq(card.hole_index, 0, "finishing does not drag the field on")


func test_the_hole_ends_when_everyone_is_done() -> void:
	var a := PlayerScore.new()
	var b := PlayerScore.new()
	assert_false(PlayerScore.everyone_done([a, b]))
	a.finish_hole()
	assert_false(PlayerScore.everyone_done([a, b]))
	b.settle_pickup()
	assert_true(PlayerScore.everyone_done([a, b]))
	assert_false(PlayerScore.everyone_done([]))


func test_melee_hits_players_in_arc_and_does_not_down_them() -> void:
	var origin := Vector3.ZERO
	var forward := Vector3(0.0, 0.0, -1.0)
	assert_true(Melee.in_arc(origin, forward, Vector3(0.0, 0.0, -2.0), Melee.RANGE, Melee.ARC_DEG))
	assert_false(Melee.in_arc(origin, forward, Vector3(0.0, 0.0, -8.0), Melee.RANGE, Melee.ARC_DEG))
	assert_false(Melee.in_arc(origin, forward, Vector3(4.0, 0.0, 0.0), Melee.RANGE, Melee.ARC_DEG))
	var victim: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(victim)
	victim.global_position = Vector3(0.0, 0.0, -1.5)
	var hp := victim.health.hp
	victim.apply_knockback(origin, 10.0)
	assert_gt(victim.velocity.length(), 1.0)
	assert_eq(victim.health.hp, hp)
	assert_false(victim.health.is_downed())


func test_guns_never_hurt_players() -> void:
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(player)
	assert_false(Weapon.hurts_target(player))
	var zombie: Zombie = preload("res://scenes/zombies/zombie.tscn").instantiate()
	zombie.stats = preload("res://resources/zombies/walker.tres")
	add_child_autofree(zombie)
	assert_true(Weapon.hurts_target(zombie))
	assert_false(Weapon.hurts_target(null))


func test_cart_hijack_needs_the_driver_in_range() -> void:
	var driver: Player = preload("res://scenes/players/player.tscn").instantiate()
	var attacker: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(driver)
	add_child_autofree(attacker)
	assert_false(GolfCart.can_hijack(null, attacker, 1.0))
	assert_false(GolfCart.can_hijack(driver, driver, 1.0))
	assert_false(GolfCart.can_hijack(driver, attacker, Melee.RANGE + 1.0))
	assert_true(GolfCart.can_hijack(driver, attacker, 1.0))
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	driver.spawn_at(cart.global_position, 0.0)
	attacker.spawn_at(cart.global_position + Vector3(1.0, 0.0, 0.0), 0.0)
	cart.board(driver)
	assert_eq(cart.driver, driver)
	assert_true(cart.try_hijack(attacker))
	assert_eq(cart.driver, attacker)
	assert_ne(cart.driver, driver)


func test_seats_fill_in_join_order() -> void:
	NetSession._assign_seat(1)
	NetSession._assign_seat(12)
	NetSession._assign_seat(7)
	assert_eq(NetSession.seat_for(1), 0)
	assert_eq(NetSession.seat_for(12), 1)
	assert_eq(NetSession.seat_for(7), 2)
	assert_eq(NetSession.color_for(1), Palette.CYAN)


func _pawn(peer_id: int, at: Vector3) -> Player:
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	player.peer_id = peer_id
	add_child_autofree(player)
	player.global_position = at
	return player
