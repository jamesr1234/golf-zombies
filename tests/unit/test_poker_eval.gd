extends GutTest
## 5-card ranks and 7-card "best of" for Hold'em showdowns.


func test_a_straight_flush_beats_quads() -> void:
	var steel := _cards([8, 9, 10, 11, 12])
	var quads := _cards([12, 25, 38, 51, 0])
	assert_gt(PokerEval.five(steel), PokerEval.five(quads))


func test_the_wheel_is_a_five_high_straight() -> void:
	var wheel := _cards([12, 13, 27, 41, 3])
	var six := _cards([0, 14, 28, 42, 4])
	assert_gt(PokerEval.five(six), PokerEval.five(wheel))
	assert_gt(PokerEval.five(wheel), PokerEval.five(_cards([12, 24, 10, 9, 7])))


func test_a_pair_of_aces_beats_kings() -> void:
	var aces := _cards([12, 25, 0, 1, 2])
	var kings := _cards([11, 24, 0, 1, 2])
	assert_gt(PokerEval.five(aces), PokerEval.five(kings))


func test_seven_cards_pick_the_flush_over_the_pair() -> void:
	var mixed := [0, 13, 1, 2, 3, 4, 18]
	assert_gt(PokerEval.best(mixed), PokerEval.five([0, 13, 1, 2, 18]))


func test_tied_boards_split() -> void:
	var board := [0, 1, 2, 3, 4]
	var a := board + [12, 24]
	var b := board + [25, 37]
	assert_eq(PokerEval.best(a), PokerEval.best(b))


func test_labels_name_ace_of_spades() -> void:
	assert_eq(PokerEval.label(51), "AS")
	assert_eq(PokerEval.labels([12, 0]), "AC 2C")


func _cards(ids: Array) -> Array:
	return ids
