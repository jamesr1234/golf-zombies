extends GutTest
## Heads-up blinds, folds, all-in runouts, and even-money side bets.


func test_blinds_come_out_of_the_stacks() -> void:
	var hand := _fresh([200, 200], 0)
	assert_eq(PokerHand.CHIP, 10)
	assert_eq(PokerHand.SMALL, 10)
	assert_eq(PokerHand.BIG, 20)
	assert_eq(PokerHand.chip_count(200), 20)
	assert_eq(hand.pot, 30)
	assert_eq(hand.stacks[0], 190)
	assert_eq(hand.stacks[1], 180)
	assert_eq(hand.to_act, 0)
	assert_eq(hand.hole[0].size(), 2)
	assert_eq(hand.board.size(), 0)


func test_a_fold_ships_the_pot() -> void:
	var hand := _fresh([200, 200], 0)
	assert_true(hand.apply(0, "fold"))
	assert_true(hand.over)
	assert_eq(hand.winner_seat, 1)
	assert_eq(hand.stacks[1], 210)
	assert_eq(hand.pot, 0)


func test_a_call_and_checks_run_to_showdown() -> void:
	var deck: Array = []
	for card in 52:
		deck.append(card)
	var hand := PokerHand.new()
	hand.start([200, 200], 0, null, deck)
	assert_eq(hand.street_name(), "Preflop")
	assert_true(hand.apply(0, "call"))
	assert_true(hand.apply(1, "check"))
	assert_eq(hand.street, PokerHand.Street.FLOP)
	assert_eq(hand.street_name(), "Flop")
	assert_eq(hand.board.size(), 3)
	assert_true(hand.apply(1, "check"))
	assert_true(hand.apply(0, "check"))
	assert_true(hand.apply(1, "check"))
	assert_true(hand.apply(0, "check"))
	assert_true(hand.apply(1, "check"))
	assert_true(hand.apply(0, "check"))
	assert_true(hand.over)
	assert_eq(hand.board.size(), 5)
	assert_eq(hand.street, PokerHand.Street.SHOWDOWN)
	assert_eq(hand.stacks[0] + hand.stacks[1], 400)


func test_short_all_in_runs_out_the_board() -> void:
	var hand := _fresh([10, 20], 0)
	assert_true(hand.over)
	assert_eq(hand.board.size(), 5)
	assert_eq(hand.stacks[0] + hand.stacks[1], 30)


func test_side_bets_pay_even_money_or_push() -> void:
	assert_eq(PokerHand.side_credit(0, false, 0, 20), 40)
	assert_eq(PokerHand.side_credit(0, false, 1, 20), 0)
	assert_eq(PokerHand.side_credit(-1, true, 0, 20), 20)
	assert_eq(PokerHand.side_credit(1, false, 1, 10), 20)
	assert_eq(PokerHand.snap_chips(25), 20)
	assert_eq(PokerHand.snap_chips(9), 0)


func test_cpu_picks_a_legal_action() -> void:
	var hand := _fresh([200, 200], 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var choice := PokerCpu.pick(hand, 0, rng)
	assert_true(choice.has("op"))
	assert_true(hand.apply(0, String(choice["op"]), int(choice.get("to", 0))))


func _fresh(stacks: Array, button: int) -> PokerHand:
	var hand := PokerHand.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	hand.start(stacks, button, rng)
	return hand
