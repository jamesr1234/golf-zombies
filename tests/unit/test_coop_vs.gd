extends GutTest
## Coop Multiplayer VS contract: seats, fill, alternate shot, team +4.


func after_each() -> void:
	NetSession.seats.clear()
	GameSettings.reset()


func test_seats_pair_into_eight_teams() -> void:
	assert_eq(CoopVs.FIELD_SIZE, 16)
	assert_eq(CoopVs.TEAM_COUNT, 8)
	assert_eq(CoopVs.team_of(0), 0)
	assert_eq(CoopVs.team_of(1), 0)
	assert_eq(CoopVs.team_of(2), 1)
	assert_eq(CoopVs.pair_index(0), 0)
	assert_eq(CoopVs.pair_index(1), 1)
	assert_eq(CoopVs.partner_seat(0), 1)
	assert_eq(CoopVs.partner_seat(1), 0)
	assert_eq(CoopVs.partner_seat(14), 15)
	assert_eq(CoopVs.cart_slot(3), 1)
	assert_eq(CoopVs.tee_seat(3), 6)
	assert_eq(CoopVs.ball_name(4), "TeamBall4")
	assert_eq(CoopVs.player_label(0), "Cyan A")
	assert_eq(CoopVs.player_label(1), "Cyan B")


func test_cpu_ids_stay_negative() -> void:
	assert_eq(CoopVs.cpu_peer_id(0), -1)
	assert_eq(CoopVs.cpu_peer_id(1), -2)
	assert_true(CoopVs.is_cpu_peer(-3))
	assert_false(CoopVs.is_cpu_peer(1))
	var seats := {1: 0, -1: 1}
	assert_eq(CoopVs.next_cpu_peer_id(seats), -2)


func test_empty_seats_fill_with_cpu() -> void:
	var humans := {1: 0}
	var filled := CoopVs.filled_seats(humans)
	assert_eq(filled.size(), 16)
	assert_eq(filled[1], 0)
	assert_eq(CoopVs.cpu_fill_count(1), 15)
	var used := {}
	for peer_id in filled.keys():
		var seat: int = filled[peer_id]
		assert_false(used.has(seat), "seat %d claimed twice" % seat)
		used[seat] = true
		if int(peer_id) != 1:
			assert_true(CoopVs.is_cpu_peer(int(peer_id)))
	assert_eq(used.size(), 16)


func test_a_lone_human_gets_a_cpu_partner() -> void:
	var filled := CoopVs.filled_seats({1: 4})
	var partner := CoopVs.partner_seat(4)
	var found := false
	for peer_id in filled.keys():
		if int(filled[peer_id]) == partner:
			assert_true(CoopVs.is_cpu_peer(int(peer_id)))
			found = true
	assert_true(found)


func test_seat_claim_rejects_a_taken_seat() -> void:
	var seats := {1: 0}
	assert_false(CoopVs.apply_seat_claim(seats, 12, 0), "seat 0 is taken")
	assert_eq(seats[1], 0)
	assert_false(seats.has(12))
	assert_true(CoopVs.apply_seat_claim(seats, 12, 1))
	assert_eq(seats[12], 1)
	assert_true(CoopVs.apply_seat_claim(seats, 12, 3), "you may move to a free seat")
	assert_eq(seats[12], 3)
	assert_true(CoopVs.apply_seat_claim(seats, 1, 0), "keeping your own seat is fine")


func test_alternate_turn_flips_to_the_partner() -> void:
	assert_eq(CoopVs.next_striker(0), 1)
	assert_eq(CoopVs.next_striker(1), 0)
	assert_eq(CoopVs.next_striker(7), 6)
	var card := TeamScore.new(PackedInt32Array([4, 3, 5]))
	card.team = 2
	assert_eq(card.striker_seat(), 4)
	assert_eq(card.advance_turn(), 5)
	assert_eq(card.striker_seat(), 5)
	assert_eq(card.advance_turn(), 4)


func test_team_score_caps_at_plus_four() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	var card := TeamScore.new(PackedInt32Array([4, 3, 5]))
	assert_eq(card.max_over, 4)
	assert_eq(card.max_strokes(), 8)
	card.add_stroke(8)
	assert_true(card.at_stroke_limit())
	card.settle_pickup()
	assert_true(card.done_this_hole)
	assert_eq(card.strokes, 8)
	assert_eq(card.results[0], 8)
	assert_eq(card.relative_to_par(), 4)


func test_timeout_locks_the_team_at_plus_four() -> void:
	var card := TeamScore.new(PackedInt32Array([3]))
	card.add_stroke(1)
	card.settle_pickup()
	assert_eq(card.strokes, 7)
	assert_eq(card.relative_to_par(), 4)
	assert_true(card.done_this_hole)


func test_team_relative_is_one_total_not_a_sum() -> void:
	var cyan := TeamScore.new(PackedInt32Array([4, 4, 4]))
	cyan.team = 0
	cyan.strokes = 5
	cyan.finish_hole()
	var amber := TeamScore.new(PackedInt32Array([4, 4, 4]))
	amber.team = 1
	amber.strokes = 3
	amber.finish_hole()
	var totals := CoopVs.team_relative([cyan, amber])
	assert_eq(totals[0], 1)
	assert_eq(totals[1], -1)
	assert_eq(CoopVs.winning_team([cyan, amber]), 1)
	assert_false(totals[0] == 2, "must not sum two player cards")


func test_player_score_keeps_money_only_in_coop() -> void:
	var wallet := PlayerScore.new()
	wallet.credit(40)
	wallet.add_stroke(2)
	assert_eq(wallet.money, 40)
	assert_eq(wallet.strokes, 2, "the player card still stores a wallet; strokes are unused")


func test_coop_vs_mode_raises_the_stroke_cap() -> void:
	assert_eq(GameSettings.max_over_par(), GameState.MAX_OVER_PAR)
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	assert_true(GameSettings.is_coop_vs())
	assert_eq(GameSettings.online_max_players(), 16)
	assert_eq(GameSettings.max_over_par(), 4)


func test_one_ball_offset_per_team() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	assert_almost_eq(VsCourse.ball_offset(0, 16), VsCourse.ball_offset(1, 16), 0.001)
	assert_gt(absf(VsCourse.ball_offset(0, 16) - VsCourse.ball_offset(2, 16)), 1.0)
	assert_eq(VsCourse.cart_index_for_seat(0), VsCourse.cart_index_for_seat(1))
	assert_eq(VsCourse.cart_index_for_seat(2), 1)


func test_both_teammates_resolve_the_same_team_ball() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	NetSession.seats = {1: 0, -1: 1}
	var ball := GolfBall.new()
	ball.name = "TeamBall0"
	ball.team = 0
	ball.owner_peer = 1
	add_child_autofree(ball)
	assert_eq(CoopVs.ball_for_peer([ball], 1, NetSession.seats), ball)
	assert_eq(CoopVs.ball_for_peer([ball], -1, NetSession.seats), ball)


func test_host_rejects_a_taken_seat() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	NetSession.seats = {1: 0, 12: 2}
	assert_false(NetSession._try_claim_seat(12, 0))
	assert_eq(NetSession.seat_for(12), 2)
	assert_true(NetSession._try_claim_seat(12, 5))
	assert_eq(NetSession.seat_for(12), 5)
	assert_true(NetSession._try_claim_seat(1, 0), "keeping your seat is fine")
