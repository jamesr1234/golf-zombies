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


func test_cart_tint_uses_the_team_color() -> void:
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	add_child_autofree(cart)
	var color := Palette.seat_color(3)
	cart.apply_tint(color)
	var found := false
	for mesh in cart.find_children("*", "MeshInstance3D", true, false):
		var mat := (mesh as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if mat != null and mat.albedo_color.is_equal_approx(color):
			found = true
			break
	assert_true(found, "the cart body should pick up the team colour")


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


func test_a_team_ball_belongs_to_both_seats() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	NetSession.seats = {4: 0, 5: 1, 6: 2}
	var ball: GolfBall = preload("res://scenes/golf/ball.tscn").instantiate()
	add_child_autofree(ball)
	ball.team = 0
	ball.owner_peer = 4
	ball.place_at(Vector3.ZERO)
	var owner := _pawn(4, Vector3(1.0, 0.0, 0.0))
	var mate := _pawn(5, Vector3(1.0, 0.0, 0.0))
	var other := _pawn(6, Vector3(1.0, 0.0, 0.0))
	assert_true(ball.is_owned_by(owner))
	assert_true(ball.is_owned_by(mate))
	assert_false(ball.is_owned_by(other))


func test_only_the_striker_can_claim_the_team_ball() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	NetSession.seats = {4: 0, 5: 1}
	var ball: GolfBall = preload("res://scenes/golf/ball.tscn").instantiate()
	add_child_autofree(ball)
	ball.team = 0
	ball.owner_peer = 4
	ball.place_at(Vector3.ZERO)
	var flow := VsMatchFlow.new()
	flow.phase = VsMatchFlow.Phase.PLAYING
	var card := TeamScore.new()
	card.team = 0
	flow._team_scores[0] = card
	var owner := _pawn(4, Vector3(1.0, 0.0, 0.0))
	var mate := _pawn(5, Vector3(1.0, 0.0, 0.0))
	owner.flow = flow
	mate.flow = flow
	var golf := GolfSession.new()
	ball.add_child(golf)
	golf.setup(ball, Vector3(0.0, 0.0, -20.0))
	assert_true(golf.can_claim(owner), "slot A tees first")
	assert_false(golf.can_claim(mate), "slot B waits")
	card.advance_turn()
	assert_false(golf.can_claim(owner))
	assert_true(golf.can_claim(mate))
	flow.free()


func test_ffa_still_autopickups_at_plus_two() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	var card := PlayerScore.new(PackedInt32Array([4]))
	assert_eq(card.max_over, 2)
	card.add_stroke(6)
	card.settle_pickup()
	assert_eq(card.strokes, 6)
	assert_eq(card.relative_to_par(), 2)


func test_disconnect_takeover_keeps_the_seat() -> void:
	var seats := {1: 0, 12: 1, -1: 2}
	assert_eq(CoopVs.takeover_seat(seats, 1), 0, "host leave does not migrate")
	assert_eq(seats[1], 0)
	var cpu_id := CoopVs.takeover_seat(seats, 12)
	assert_true(CoopVs.is_cpu_peer(cpu_id))
	assert_eq(seats[cpu_id], 1)
	assert_false(seats.has(12))
	assert_eq(seats[-1], 2)


func test_cpu_waits_when_it_is_not_their_turn() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	NetSession.seats = {1: 0, -1: 1}
	var flow := VsMatchFlow.new()
	flow.phase = VsMatchFlow.Phase.PLAYING
	var card := TeamScore.new()
	card.team = 0
	flow._team_scores[0] = card
	var cpu := _pawn(-1, Vector3.ZERO)
	cpu.flow = flow
	cpu.cpu_filled = true
	assert_false(flow.can_strike(cpu))
	card.advance_turn()
	assert_true(flow.can_strike(cpu))
	flow.free()


func test_ball_rest_hands_the_club_to_the_partner() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	NetSession.seats = {4: 0, 5: 1}
	var flow := VsMatchFlow.new()
	flow.phase = VsMatchFlow.Phase.PLAYING
	var card := TeamScore.new()
	card.team = 0
	flow._team_scores[0] = card
	var owner := _pawn(4, Vector3.ZERO)
	var mate := _pawn(5, Vector3.ZERO)
	owner.flow = flow
	mate.flow = flow
	assert_true(flow.can_strike(owner), "slot A tees first")
	flow._on_ball_rest(Vector3.ZERO, owner)
	assert_eq(card.striker_slot, 1)
	assert_false(flow.can_strike(owner))
	assert_true(flow.can_strike(mate))
	flow.free()


func test_finishing_a_team_leaves_the_ball_to_retrieve() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	NetSession.seats = {1: 0, -1: 1, -2: 2, -3: 3}
	var flow := VsMatchFlow.new()
	flow.phase = VsMatchFlow.Phase.PLAYING
	var cyan := TeamScore.new()
	cyan.team = 0
	var amber := TeamScore.new()
	amber.team = 1
	flow._team_scores[0] = cyan
	flow._team_scores[1] = amber
	var ball: GolfBall = preload("res://scenes/golf/ball.tscn").instantiate()
	add_child_autofree(ball)
	ball.team = 0
	ball.owner_peer = 1
	ball.place_at(Vector3.ZERO)
	flow._balls = [ball]
	var owner := _pawn(1, Vector3(1.0, 0.0, 0.0))
	owner.flow = flow
	flow._finish_team(owner, true)
	assert_true(cyan.done_this_hole)
	assert_false(amber.done_this_hole)
	assert_true(ball.is_closed())
	assert_false(ball.is_stowed(), "no autopickup; walk up after the hole")
	assert_eq(flow.phase, VsMatchFlow.Phase.PLAYING)
	flow.free()


func test_retrieve_is_a_walk_up_during_retrieve_phase() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	NetSession.seats = {1: 0, -1: 1}
	var flow := VsMatchFlow.new()
	flow.phase = VsMatchFlow.Phase.PLAYING
	var ball: GolfBall = preload("res://scenes/golf/ball.tscn").instantiate()
	add_child_autofree(ball)
	ball.team = 0
	ball.owner_peer = 1
	ball.place_at(Vector3.ZERO)
	var leftover := GolfBall.new()
	leftover.team = 1
	add_child_autofree(leftover)
	leftover.place_at(Vector3(20.0, 0.0, 0.0))
	flow._balls = [ball, leftover]
	var owner := _pawn(1, Vector3(1.0, 0.0, 0.0))
	owner.flow = flow
	assert_false(flow.can_retrieve_ball(owner), "not during play")
	flow.phase = VsMatchFlow.Phase.RETRIEVE
	assert_true(flow.can_retrieve_ball(owner))
	flow._do_retrieve(owner)
	assert_true(ball.is_stowed())
	assert_false(leftover.is_stowed())
	assert_eq(flow.phase, VsMatchFlow.Phase.RETRIEVE, "other teams still have a ball out")
	flow.free()


func test_the_ninth_carded_hole_completes_the_course() -> void:
	var pars := PackedInt32Array()
	pars.resize(9)
	pars.fill(4)
	var card := TeamScore.new(pars)
	for i in 8:
		card.add_stroke(4)
		card.finish_hole()
		assert_false(card.is_course_complete(), "hole %d is not the ninth" % (i + 1))
		card.advance_to(i + 1)
	card.add_stroke(4)
	card.finish_hole()
	assert_true(card.is_course_complete())
	assert_true(CoopVs.winner_line([card]).begins_with("Team Cyan wins"))


func test_all_eight_ninth_cards_end_the_round() -> void:
	var pars := PackedInt32Array()
	pars.resize(9)
	pars.fill(4)
	var flow := VsMatchFlow.new()
	for team in CoopVs.TEAM_COUNT:
		var card := TeamScore.new(pars)
		card.team = team
		card.hole_index = 8
		card.add_stroke(5)
		card.finish_hole()
		flow._team_scores[team] = card
	assert_true(flow._teams_course_complete())
	assert_eq(CoopVs.winning_team(flow._team_scores.values()), 0)
	flow.free()


func test_host_rejects_a_taken_seat() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_COOP_VS
	NetSession.seats = {1: 0, 12: 2}
	assert_false(NetSession._try_claim_seat(12, 0))
	assert_eq(NetSession.seat_for(12), 2)
	assert_true(NetSession._try_claim_seat(12, 5))
	assert_eq(NetSession.seat_for(12), 5)
	assert_true(NetSession._try_claim_seat(1, 0), "keeping your seat is fine")


func _pawn(peer_id: int, at: Vector3) -> Player:
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	player.peer_id = peer_id
	add_child_autofree(player)
	player.global_position = at
	return player
