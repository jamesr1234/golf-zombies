extends GutTest
## Held beers, chug timers, and how hard a buzz hits before the view goes.

var buzz: Buzz


func before_each() -> void:
	buzz = Buzz.new()


func test_tossing_a_beer_spends_it_without_a_sip() -> void:
	buzz.take(2)
	assert_true(buzz.spend())
	assert_eq(buzz.held, 1)
	assert_eq(buzz.active(), 0)
	assert_true(buzz.spend())
	assert_eq(buzz.held, 0)
	assert_false(buzz.spend())


func test_a_grabbed_beer_sits_in_the_hand_until_you_chug() -> void:
	assert_eq(buzz.held, 0)
	assert_false(buzz.chug())
	buzz.take()
	buzz.take()
	assert_eq(buzz.held, 2)
	assert_true(buzz.chug())
	assert_eq(buzz.held, 1)
	assert_eq(buzz.active(), 1)


func test_each_sip_lasts_half_a_minute() -> void:
	buzz.take()
	buzz.chug()
	buzz.tick(Buzz.DURATION * 0.5)
	assert_eq(buzz.active(), 1)
	buzz.tick(Buzz.DURATION * 0.5)
	assert_eq(buzz.active(), 0)


func test_sips_stack_instead_of_refreshing() -> void:
	buzz.take(3)
	buzz.chug()
	buzz.tick(10.0)
	buzz.chug()
	assert_eq(buzz.active(), 2)
	buzz.tick(20.0)
	assert_eq(buzz.active(), 1, "the first beer wears off on its own clock")
	buzz.tick(10.0)
	assert_eq(buzz.active(), 0)


func test_more_beers_make_you_stronger() -> void:
	assert_almost_eq(Buzz.boost_from(0), 1.0, 0.001)
	assert_gt(Buzz.boost_from(1), 1.0)
	assert_gt(Buzz.boost_from(3), Buzz.boost_from(1))
	buzz.take(2)
	buzz.chug()
	buzz.chug()
	assert_almost_eq(buzz.strength_mult(), Buzz.boost_from(2), 0.001)
	assert_almost_eq(buzz.weapon_mult(), buzz.strength_mult(), 0.001)
	assert_almost_eq(buzz.cart_mult(), buzz.strength_mult(), 0.001)


func test_the_view_stays_clean_through_three_beers() -> void:
	assert_eq(Buzz.extra_from(0), 0)
	assert_eq(Buzz.extra_from(3), 0)
	assert_eq(buzz.split_amount(), 0.0)
	assert_eq(buzz.blur_amount(), 0.0)
	buzz.take(3)
	for _i in 3:
		buzz.chug()
	assert_eq(buzz.extra_beers(), 0)
	assert_eq(buzz.split_amount(), 0.0)


func test_the_fourth_beer_starts_the_double_vision() -> void:
	assert_eq(Buzz.extra_from(4), 1)
	assert_gt(Buzz.extra_from(6), Buzz.extra_from(4))
	buzz.take(5)
	for _i in 5:
		buzz.chug()
	assert_eq(buzz.extra_beers(), 2)
	assert_gt(buzz.split_amount(), 0.0)
	assert_gt(buzz.blur_amount(), 0.0)
	assert_gt(buzz.sway_amount(), 0.0)
	assert_gt(buzz.fov_bump(), 0.0)


func test_a_beer_costs_thirty() -> void:
	assert_eq(Buzz.PRICE, 30)
	assert_false(Buzz.can_afford(29))
	assert_true(Buzz.can_afford(30))
	var score := GameState.new(PackedInt32Array([4]))
	score.credit(90)
	assert_true(score.try_spend(Buzz.PRICE))
	assert_eq(score.money, 60)
	assert_true(score.try_spend(Buzz.PRICE))
	assert_true(score.try_spend(Buzz.PRICE))
	assert_false(score.try_spend(Buzz.PRICE))
