extends GutTest
## Scorecard rules: stroke limit, wallet payouts, and the double-bogey fine.

var score: GameState


func before_each() -> void:
	score = GameState.new(PackedInt32Array([4, 3, 5]))


func test_starts_on_first_hole() -> void:
	assert_eq(score.hole_index, 0)
	assert_eq(score.par(), 4)
	assert_eq(score.strokes, 0)


func test_double_bogey_is_the_last_allowed_stroke() -> void:
	assert_eq(score.max_strokes(), 6)
	for _i in 5:
		score.add_stroke()
	assert_false(score.at_stroke_limit(), "five strokes on a par four is still playable")
	score.add_stroke()
	assert_true(score.at_stroke_limit(), "six strokes is a pickup double bogey")


func test_par_three_allows_five() -> void:
	score.hole_out()
	assert_eq(score.par(), 3)
	assert_eq(score.max_strokes(), 5)


func test_hole_out_records_and_advances() -> void:
	score.add_stroke(3)
	score.hole_out()
	assert_eq(score.results[0], 3)
	assert_eq(score.hole_index, 1)
	assert_eq(score.strokes, 0)


func test_totals_only_count_finished_holes() -> void:
	score.add_stroke(5)
	score.hole_out()
	score.add_stroke(2)
	assert_eq(score.total_strokes(), 5)
	assert_eq(score.played_par(), 4)
	assert_eq(score.relative_to_par(), 1)


func test_course_completes_on_final_hole() -> void:
	assert_false(score.is_course_complete())
	for _i in 3:
		score.add_stroke(4)
		score.hole_out()
	assert_true(score.is_course_complete())


func test_relative_formatting() -> void:
	assert_eq(GameState.format_relative(0), "E")
	assert_eq(GameState.format_relative(3), "+3")
	assert_eq(GameState.format_relative(-2), "-2")


func test_the_wallet_starts_empty() -> void:
	assert_eq(score.money, 0)


func test_credits_stack_and_ignore_empty_payouts() -> void:
	score.credit(40)
	score.credit(15)
	score.credit(0)
	score.credit(-8)
	assert_eq(score.money, 55)


func test_spending_fails_when_the_wallet_is_short() -> void:
	score.credit(100)
	assert_false(score.try_spend(140))
	assert_eq(score.money, 100)
	assert_true(score.try_spend(40))
	assert_eq(score.money, 60)
	assert_true(score.try_spend(0))
	assert_eq(score.money, 60)


func test_faster_holes_pay_more() -> void:
	assert_eq(GameState.HOLE_SECONDS, 120.0)
	assert_eq(GameState.time_bonus(120.0), 600)
	assert_eq(GameState.time_bonus(60.0), 300)
	assert_eq(GameState.time_bonus(0.0), 0)
	assert_eq(GameState.time_bonus(-4.0), 0)
	assert_gt(GameState.time_bonus(90.0), GameState.time_bonus(30.0))


func test_the_clock_reads_as_minutes_and_seconds() -> void:
	assert_eq(GameState.format_clock(120.0), "2:00")
	assert_eq(GameState.format_clock(61.0), "1:01")
	assert_eq(GameState.format_clock(0.0), "0:00")
	assert_eq(GameState.format_clock(0.2), "0:01")
	assert_eq(GameState.format_money(400), "$400")
	assert_eq(GameState.format_money(-40), "-$40")


func test_penalty_strokes_can_cap_the_hole() -> void:
	score.add_stroke(4)
	score.add_stroke()
	score.add_stroke()
	assert_true(score.at_stroke_limit())
	score.add_stroke()
	score.cap_at_limit()
	assert_eq(score.strokes, 6)


func test_par_and_under_pay_and_a_double_bogey_costs() -> void:
	assert_eq(GameState.score_payout(-3), GameState.PAY_PAR + GameState.PAY_UNDER * 3)
	assert_eq(GameState.score_payout(-1), GameState.PAY_PAR + GameState.PAY_UNDER)
	assert_eq(GameState.score_payout(0), GameState.PAY_PAR)
	assert_eq(GameState.score_payout(1), 0, "bogey does not pay")
	assert_eq(GameState.score_payout(2), GameState.PAY_DOUBLE_BOGEY)
	assert_eq(GameState.score_payout(3), GameState.PAY_DOUBLE_BOGEY)
	assert_eq(GameState.hole_payout(0, 10.0), GameState.PAY_PAR + GameState.time_bonus(10.0))
	assert_eq(GameState.hole_payout(2, 90.0), GameState.PAY_DOUBLE_BOGEY, "speed does not pay a double bogey")


func test_a_payout_can_take_money_but_not_below_zero() -> void:
	score.credit(25)
	assert_eq(score.apply_payout(GameState.PAY_PAR), GameState.PAY_PAR)
	assert_eq(score.money, 75)
	assert_eq(score.apply_payout(GameState.PAY_DOUBLE_BOGEY), GameState.PAY_DOUBLE_BOGEY)
	assert_eq(score.money, 35)
	assert_eq(score.apply_payout(-100), -35)
	assert_eq(score.money, 0)
	assert_eq(score.apply_payout(-10), 0)
	assert_eq(score.apply_payout(0), 0)


func test_barrier_charges_start_empty_and_decrement_on_place() -> void:
	assert_eq(score.barrier_charges, 0)
	assert_false(score.try_place_barrier())
	score.add_barrier_charges(2)
	assert_eq(score.barrier_charges, 2)
	score.add_barrier_charges(0)
	score.add_barrier_charges(-3)
	assert_eq(score.barrier_charges, 2)
	assert_true(score.try_place_barrier())
	assert_eq(score.barrier_charges, 1)
	assert_true(score.try_place_barrier())
	assert_eq(score.barrier_charges, 0)
	assert_false(score.try_place_barrier())
	assert_eq(score.barrier_charges, 0)


func test_barrier_charges_survive_holing_out() -> void:
	score.add_barrier_charges(3)
	score.add_stroke(3)
	score.hole_out()
	assert_eq(score.hole_index, 1)
	assert_eq(score.barrier_charges, 3)


func test_ladder_charges_start_empty_and_decrement_on_place() -> void:
	assert_eq(score.ladder_charges, 0)
	assert_false(score.try_place_ladder())
	score.add_ladder_charges(2)
	assert_eq(score.ladder_charges, 2)
	score.add_ladder_charges(0)
	score.add_ladder_charges(-2)
	assert_eq(score.ladder_charges, 2)
	assert_true(score.try_place_ladder())
	assert_eq(score.ladder_charges, 1)
	assert_true(score.try_place_ladder())
	assert_eq(score.ladder_charges, 0)
	assert_false(score.try_place_ladder())


func test_ladder_charges_survive_holing_out() -> void:
	score.add_ladder_charges(2)
	score.add_stroke(3)
	score.hole_out()
	assert_eq(score.hole_index, 1)
	assert_eq(score.ladder_charges, 2)


func test_club_kits_only_upgrade() -> void:
	assert_eq(score.club_id, ClubKit.STARTER_ID)
	score.equip_club(ClubKit.TOUR_ID)
	assert_eq(score.club_id, ClubKit.TOUR_ID)
	score.equip_club(ClubKit.STARTER_ID)
	assert_eq(score.club_id, ClubKit.TOUR_ID, "you cannot put the starter back")
	assert_eq(score.club_kit().id, ClubKit.TOUR_ID)


func test_bonus_and_freeze_seconds_are_consumed_once() -> void:
	score.add_bonus_seconds(30)
	score.add_freeze_seconds(15.0)
	assert_eq(score.take_bonus_seconds(), 30.0)
	assert_eq(score.bonus_seconds, 0)
	assert_almost_eq(score.take_freeze_seconds(), 15.0, 0.001)
	assert_eq(score.freeze_seconds, 0.0)
	assert_eq(score.take_bonus_seconds(), 0.0)
