extends GutTest
## The beverage wagon parks, presents the cooler, and sells beers.

const PLAYER := preload("res://scenes/players/player.tscn")

func test_she_stops_when_she_reaches_you() -> void:
	assert_eq(CartGirl.wanted_speed(12.0), CartGirl.CRUISE_SPEED)
	assert_eq(CartGirl.wanted_speed(CartGirl.STOP_RANGE), 0.0)
	assert_eq(CartGirl.wanted_speed(CartGirl.STOP_RANGE - 1.0), 0.0)


func test_once_parked_she_does_not_creep_after_a_few_steps() -> void:
	assert_eq(CartGirl.wanted_speed(8.0, true), 0.0)
	assert_eq(CartGirl.wanted_speed(CartGirl.FOLLOW_RANGE + 1.0, true), CartGirl.CRUISE_SPEED)


func test_driving_points_the_nose_at_the_player() -> void:
	var yaw := CartGirl.drive_yaw(Vector3(0.0, 0.0, -8.0))
	assert_almost_eq(yaw, 0.0, 0.001)
	var right := CartGirl.drive_yaw(Vector3(-8.0, 0.0, 0.0))
	assert_almost_eq(right, PI * 0.5, 0.001)
	var to_player := Vector3(4.0, 0.0, -3.0)
	var nose := CartGirl.nose_at(CartGirl.drive_yaw(to_player))
	assert_gt(
		nose.dot(to_player.normalized()), 0.99,
		"the wagon has to roll toward the player, not away"
	)


func test_parking_swings_the_cooler_toward_the_player() -> void:
	var yaw := CartGirl.cooler_yaw(Vector3(0.0, 0.0, -8.0))
	assert_almost_eq(absf(yaw), PI, 0.001)
	var drive := CartGirl.drive_yaw(Vector3(0.0, 0.0, -8.0))
	assert_almost_eq(absf(wrapf(yaw - drive, -PI, PI)), PI, 0.001)


func test_cooler_cans_say_beer() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	var copies := girl.find_children("BeerCopy", "Label3D", true, false)
	assert_eq(copies.size(), 6, "each can in the ice has the print")
	for copy in copies:
		assert_eq((copy as Label3D).text, "beer")


func test_the_cooler_starts_shut() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	assert_false(girl.cooler_open)
	girl.open_cooler()
	assert_true(girl.cooler_open)


func test_a_sale_takes_thirty_and_hands_over_a_beer() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var score := GameState.new(PackedInt32Array([4]))
	assert_false(girl.sell_to(player, score), "empty pockets")
	assert_eq(player.buzz.held, 0)
	score.credit(90)
	assert_true(girl.sell_to(player, score))
	assert_eq(score.money, 60)
	assert_eq(player.buzz.held, 1)
	assert_false(player.is_holding_beer(), "buying puts it in items, not in hand")
	assert_true(girl.sell_to(player, score))
	assert_true(girl.sell_to(player, score))
	assert_false(girl.sell_to(player, score))
	assert_eq(player.buzz.held, 3)


func test_she_spawns_down_the_hole_so_she_can_roll_in_from_afar() -> void:
	assert_eq(CartGirl.spawn_along(160.0), CartGirl.SPAWN_ALONG)
	assert_lt(CartGirl.spawn_along(50.0), 50.0, "a short hole cannot put her past the green")
	assert_gt(CartGirl.spawn_along(50.0), 20.0)
	var hole := HoleGenerator.generate(0, 20260816)
	var girl := CartGirl.spawn_at_hole(hole)
	add_child_autofree(girl)
	var to_tee := girl.position - hole.tee
	to_tee.y = 0.0
	assert_gt(to_tee.length(), 40.0, "she has to appear from down the hole, not beside the tee")
	assert_gt(
		to_tee.dot((hole.cup - hole.tee).normalized()), 0.0,
		"the first look after a shot is down the fairway"
	)
	assert_eq(girl.name, "CartGirl")
	assert_eq(girl.visit, CartGirl.Visit.WAITING)
	assert_false(girl.visible, "she is not sitting on the hole during warmup")
	assert_eq(girl.collision_layer, 0)
	assert_eq(girl.collision_mask, Layers.WORLD, "hidden still has to sit on the ground")
	var toward_tee := hole.tee - girl.position
	toward_tee.y = 0.0
	assert_gt(
		CartGirl.nose_at(girl.rotation.y).dot(toward_tee.normalized()), 0.7,
		"she should spawn facing the tee so the first roll is toward the players"
	)


func test_a_hidden_wait_does_not_drop_her_through_the_map() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	girl.position = Vector3(0.0, 2.0, 0.0)
	var y := girl.global_position.y
	girl._drive(0.5)
	assert_almost_eq(girl.global_position.y, y, 0.001, "warmup gravity cannot bury her")
	assert_eq(girl.velocity.y, 0.0)
	assert_eq(girl.collision_mask, Layers.WORLD)


func test_she_idles_until_the_first_shot() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	assert_eq(girl.visit, CartGirl.Visit.WAITING)
	assert_false(girl.visible)
	girl.begin_approach()
	assert_eq(girl.visit, CartGirl.Visit.APPROACHING)
	assert_true(girl.visible, "the first stroke is when she appears down the hole")
	assert_eq(girl.collision_layer, Layers.VEHICLE)
	girl.begin_approach()
	assert_eq(girl.visit, CartGirl.Visit.APPROACHING, "a later call does not restart her")


func test_fifteen_seconds_with_no_sale_sends_her_away() -> void:
	assert_false(CartGirl.linger_expired(14.9))
	assert_true(CartGirl.linger_expired(CartGirl.LINGER_SECONDS))
	var girl := CartGirl.new()
	add_child_autofree(girl)
	girl.begin_approach()
	girl.begin_service()
	assert_eq(girl.visit, CartGirl.Visit.SERVING)
	girl.wait_out(CartGirl.LINGER_SECONDS - 0.1)
	assert_eq(girl.visit, CartGirl.Visit.SERVING)
	girl.wait_out(0.2)
	assert_eq(girl.visit, CartGirl.Visit.LEAVING)


func test_flipping_the_cooler_buys_another_fifteen() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	girl.begin_approach()
	girl.begin_service()
	girl.wait_out(14.0)
	girl.open_cooler()
	girl.wait_out(5.0)
	assert_eq(girl.visit, CartGirl.Visit.SERVING, "opening the cooler is enough to keep her")
	girl.wait_out(CartGirl.LINGER_SECONDS)
	assert_eq(girl.visit, CartGirl.Visit.LEAVING)


func test_a_beer_keeps_her_for_thirty_more_seconds() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var score := GameState.new(PackedInt32Array([4]))
	score.credit(90)
	girl.begin_approach()
	girl.begin_service()
	girl.open_cooler()
	assert_true(girl.sell_to(player, score))
	assert_eq(girl.visit, CartGirl.Visit.SERVING, "one beer is not closing time")
	assert_true(girl.cooler_open)
	girl.wait_out(CartGirl.SALE_LINGER_SECONDS - 0.2)
	assert_eq(girl.visit, CartGirl.Visit.SERVING)
	assert_true(girl.sell_to(player, score), "there is time to grab another")
	girl.wait_out(20.0)
	assert_eq(girl.visit, CartGirl.Visit.SERVING, "each beer restarts the thirty")
	girl.wait_out(CartGirl.SALE_LINGER_SECONDS)
	assert_eq(girl.visit, CartGirl.Visit.LEAVING)


func test_once_she_leaves_she_does_not_come_back() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	girl.begin_approach()
	girl.begin_service()
	girl.depart()
	girl.vanish()
	girl.begin_approach()
	assert_eq(girl.visit, CartGirl.Visit.GONE)


func test_you_cannot_buy_while_she_is_still_waiting() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.global_position = girl.cooler_point()
	assert_false(girl.can_use(player), "she is not selling until she parks")
	girl.begin_approach()
	assert_false(girl.can_use(player), "not while she is still rolling in")
	girl.begin_service()
	assert_true(girl.can_use(player))


func test_she_hops_out_when_you_flip_the_cooler() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	girl.begin_approach()
	girl.begin_service()
	assert_false(girl.tending)
	assert_lt(girl.attendant().position.distance_to(CartGirl.SEAT), 0.05)
	girl.open_cooler()
	assert_true(girl.tending)
	assert_gt(
		girl.attendant().position.distance_to(CartGirl.SEAT), 1.0,
		"she has to leave the seat and stand by the cooler"
	)
	assert_gt(girl.attendant().position.z, 1.4)
	girl._animate(0.05)
	assert_gt(
		girl.attendant().hips.position.y, 0.7,
		"standing beside the cooler, not folded into the seat"
	)


func test_opening_the_cooler_plants_the_wagon() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	girl.begin_approach()
	girl.begin_service()
	girl.rotation.y = 0.8
	girl.open_cooler()
	var yaw := girl.rotation.y
	var at := girl.position
	girl._drive(0.2)
	assert_almost_eq(girl.rotation.y, yaw, 0.001)
	assert_almost_eq(girl.position.x, at.x, 0.001)
	assert_almost_eq(girl.position.z, at.z, 0.001)


func test_the_wagon_is_lime_not_pink() -> void:
	assert_ne(Palette.BEER_CART, Palette.HOT_PINK)
	assert_gt(Palette.BEER_CART.g, Palette.BEER_CART.r, "the body has to read as lime from afar")
	assert_gt(Palette.BEER_CART.g, Palette.BEER_CART.b)


func test_she_says_enjoy_for_every_beer() -> void:
	var girl := CartGirl.new()
	add_child_autofree(girl)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var score := GameState.new(PackedInt32Array([4]))
	score.credit(90)
	girl.begin_approach()
	girl.begin_service()
	girl.open_cooler()
	assert_true(girl.sell_to(player, score))
	var cheer := girl.find_child("Cheer", true, false) as Label3D
	assert_not_null(cheer)
	assert_eq(cheer.text, "enjoy!")
	assert_eq(cheer.modulate, Palette.BEER_INK)
	assert_gt(cheer.position.y, 1.8, "the line sits over her head")
	assert_true(girl.sell_to(player, score))
	cheer = girl.find_child("Cheer", true, false) as Label3D
	assert_not_null(cheer)
	assert_eq(cheer.text, "enjoy!")
