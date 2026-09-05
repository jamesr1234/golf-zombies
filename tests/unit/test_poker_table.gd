extends GutTest
## Sit, 8s side-bets, peek-after-deal, and even-money payouts at the clubhouse tables.

const PLAYER := preload("res://scenes/players/player.tscn")
const _CpuPoker := preload("res://scripts/player/cpu_poker.gd")


func test_sitting_buys_in_across_the_table() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 300)
	var b := await _player(table.chairs[1].global_position, 300)
	assert_eq(table.open_seat_for(a), 0)
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	assert_true(a.is_poker_seated())
	assert_true(b.is_poker_seated())
	assert_eq(a.wallet().money, 100)
	assert_eq(table.stacks[0], 200)
	assert_eq(table.phase, PokerTable.Phase.BETTING)
	assert_almost_eq(table.timer, PokerTable.BET_SEC, 0.05)
	assert_eq(table.hole_cards(0).size(), 0)


func test_a_broke_player_is_told_to_bring_cash() -> void:
	var table := _table()
	var who := await _player(table.chairs[0].global_position, 0)
	assert_eq(table.open_seat_for(who), -1)
	assert_eq(table.vacant_seat_for(who), 0)
	assert_string_contains(who.poker.prompt(who), "enough money")
	table.try_sit(who, 0)
	assert_false(who.is_poker_seated())


func test_short_cash_cannot_buy_in() -> void:
	var table := _table()
	var who := await _player(table.chairs[0].global_position, 50)
	assert_eq(table.open_seat_for(who), -1)
	table.try_sit(who, 0)
	assert_false(who.is_poker_seated())
	assert_eq(who.wallet().money, 50)
	assert_string_contains(who.poker.prompt(who), "enough money")


func test_a_short_stack_is_kicked_after_the_hand() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	table.try_skip_bets(a)
	table.try_act(a, "fold")
	assert_eq(table.stacks[0], 190)
	assert_eq(table.phase, PokerTable.Phase.SHOWDOWN)
	assert_true(a.is_poker_seated(), "stay seated through showdown so you see the result")
	table.stacks[0] = 5
	table.tick(PokerTable.SHOW_SEC + 0.05)
	assert_true(a.is_poker_seated(), "the clock no longer stands you; you have to answer")
	assert_true(a.poker.asking_replay())
	assert_false(a.poker.can_replay())
	a.poker.use(a)
	b.poker.use(b)
	assert_false(a.is_poker_seated())
	assert_eq(a.wallet().money, 5)
	a.global_position = table.chairs[0].global_position
	assert_string_contains(a.poker.prompt(a), "enough money")
	assert_eq(table.filled(), 1)


func test_a_busted_stack_can_rebuy_from_the_wallet() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 400)
	var cpu := await _player(table.chairs[1].global_position, 200)
	cpu.possess_cpu()
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	table.try_skip_bets(human)
	table.try_act(human, "fold")
	table.stacks[0] = 0
	assert_eq(human.wallet().money, 200)
	assert_true(human.poker.can_replay(), "pocket cash covers another buy-in")
	assert_eq(human.poker.result_body(), "Play again?")
	human.poker.use(human)
	assert_eq(table.stacks[0], 200)
	assert_eq(human.wallet().money, 0)
	assert_eq(table.phase, PokerTable.Phase.BETTING)
	assert_true(human.is_poker_seated())


func test_a_busted_cpu_rebuy_stays_for_the_next_hand() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 200)
	var cpu := await _player(table.chairs[1].global_position, 200)
	cpu.possess_cpu()
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	table.try_skip_bets(human)
	table.hand.stacks = [400, 0]
	table.hand.over = true
	table.hand.split = false
	table.hand.winner_seat = 0
	table.sync_stacks()
	PokerPlay.begin_show(table)
	assert_eq(table.stacks[1], 0)
	assert_eq(cpu.wallet().money, 0)
	assert_eq(table.replay[1], 1, "a busted CPU still says yes")
	assert_true(cpu.poker.can_replay(), "the buddy always has another buy-in")
	human.poker.use(human)
	assert_true(cpu.is_poker_seated(), "she stays in the chair")
	assert_eq(table.stacks[1], 200)
	assert_eq(table.phase, PokerTable.Phase.BETTING)
	assert_eq(table.filled(), 2)


func test_you_can_sit_from_the_rail() -> void:
	var table := _table()
	var who := await _player(table.global_position + Vector3(2.4, 0.9, 0.0), 200)
	assert_eq(table.open_seat_for(who), 0)
	table.try_sit(who)
	assert_true(who.is_poker_seated())


func test_an_empty_chair_waits_for_a_player() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	table.try_sit(a, 0)
	assert_eq(table.phase, PokerTable.Phase.WAIT_FILL)
	table.tick(10.0)
	assert_eq(table.filled(), 1)
	assert_eq(table.phase, PokerTable.Phase.WAIT_FILL)
	assert_false(table.is_cpu_seat(1))
	assert_string_contains(a.poker.prompt(a), "Waiting for a player")


func test_peeking_only_works_after_the_deal() -> void:
	var table := _table()
	await _seat_pair(table)
	var spy := Marker3D.new()
	table.add_child(spy)
	spy.global_position = table.chairs[0].to_global(Vector3(0.0, 1.0, 1.1))
	assert_eq(table.peek_seat(spy), -1)
	table.tick(PokerTable.BET_SEC + 0.05)
	assert_eq(table.phase, PokerTable.Phase.PLAYING)
	assert_eq(table.hole_cards(0).size(), 2)
	assert_eq(table.peek_seat(spy), 0)


func test_a_spectator_bet_pays_even_money_on_a_fold() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	var watcher := await _player(table.chairs[1].global_position + Vector3(1.5, 0.0, 0.0), 100)
	table.try_side_bet(watcher, 1, 20)
	assert_eq(watcher.wallet().money, 80)
	assert_eq((table.get_node("Chips") as Node).get_child_count(), 2)
	table.tick(PokerTable.BET_SEC + 0.05)
	assert_eq(table.hand.to_act, 0)
	table.try_act(a, "fold")
	assert_eq(watcher.wallet().money, 120)
	assert_string_contains(table.last_act, "wins")


func test_a_call_and_check_deal_the_flop() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	table.tick(PokerTable.BET_SEC + 0.05)
	assert_eq(table.hand.to_act, 0)
	table.try_act(a, "call")
	assert_string_contains(table.last_act, "calls")
	table.try_act(b, "check")
	assert_eq(table.hand.board.size(), 3)
	assert_eq(table.hand.street, PokerHand.Street.FLOP)
	assert_string_contains(table.panel_text(), "Flop")
	assert_string_contains(table.last_act, "checks")
	a.body.hold_cards()
	b.body.hold_cards()
	table.tick(0.0)
	await wait_physics_frames(2)
	table.tick(0.0)
	var cards := table.get_node("Cards") as PokerCards
	assert_eq(cards.get_child_count(), 7, "two holes each plus the flop")
	var felt := 0
	for child in cards.get_children():
		if child.has_meta("seat"):
			continue
		felt += 1
		assert_gt((child as Node3D).position.y, 0.88, "board sits above the well and rail")
	assert_eq(felt, 3)
	for seat in 2:
		var who: Player = table.occupants[seat]
		for slot in 2:
			var card := _card_for(cards, seat, slot)
			assert_not_null(card)
			assert_lt(
				card.global_position.distance_to(who.head.global_position),
				who.body.arm_hands[slot].global_position.distance_to(who.head.global_position),
				"cards sit in front of the fists"
			)
	assert_eq(a.poker.board_ids(a).size(), 3)


func test_waiting_on_a_hand_does_not_stand_you() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	table.tick(PokerTable.BET_SEC + 0.05)
	assert_eq(table.hand.to_act, 0)
	assert_true(b.poker.use(b))
	assert_true(b.is_poker_seated(), "interact waits; it does not stand mid-hand")
	assert_eq(table.phase, PokerTable.Phase.PLAYING)
	assert_string_contains(b.poker.prompt(b), "Waiting on")


func test_blinds_throw_one_chip_per_ten() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	assert_true(a.poker.use(a))
	var chips: Node = table.get_node("Chips")
	assert_eq(chips.get_child_count(), 3, "small 10 and big 20 are three $10 chips")
	assert_eq(table.hand.to_call(0), 10)
	table.try_act(a, "call")
	assert_eq(chips.get_child_count(), 4, "a $10 call tosses one more chip")
	assert_not_null(table.get_node_or_null("FeltPlate"))


func test_interact_during_side_bets_deals_now() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	assert_eq(table.phase, PokerTable.Phase.BETTING)
	assert_true(a.poker.use(a))
	assert_eq(table.phase, PokerTable.Phase.PLAYING)
	assert_true(a.is_poker_seated())
	assert_eq(table.hole_cards(0).size(), 2)


func test_melee_stands_you_between_hands() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	table.try_sit(a, 0)
	var pad := CpuInput.new("p1", false)
	a.input = pad
	pad.tap("melee")
	a.poker.tick(a, 0.0)
	assert_false(a.is_poker_seated())
	assert_eq(table.filled(), 0)


func test_a_human_act_resets_the_clock() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	table.tick(PokerTable.BET_SEC + 0.05)
	table.timer = 3.0
	table.try_act(a, "call")
	assert_almost_eq(table.timer, PokerTable.ACT_SEC, 0.05)


func test_held_cards_face_the_holder_until_showdown() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 200)
	var cpu := await _player(table.chairs[1].global_position, 200)
	cpu.possess_cpu()
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	table.tick(PokerTable.BET_SEC + 0.05)
	human.body.hold_cards()
	cpu.body.hold_cards()
	var palms := human.body.arm_hands[0].global_position.distance_to(human.body.arm_hands[1].global_position)
	var shoulders := human.body.arms[0].global_position.distance_to(human.body.arms[1].global_position)
	assert_lt(palms, shoulders * 0.85, "hands tuck in so both hole cards sit in view")
	table.tick(0.0)
	var cards := table.get_node("Cards") as PokerCards
	var hole := _card_for(cards, 0, 0)
	var other := _card_for(cards, 0, 1)
	assert_not_null(hole)
	assert_not_null(other)
	var face := -hole.global_transform.basis.z.normalized()
	assert_gt(
		face.dot(human.head.global_transform.basis.z),
		0.7,
		"hole cards stay face-on to the camera"
	)
	assert_gt(
		(-hole.global_transform.basis.x.normalized()).dot(human.head.global_transform.basis.x),
		0.7,
		"ranks sit on the left, not mirrored"
	)
	assert_gt(
		hole.global_position.distance_to(other.global_position),
		0.18,
		"hole cards sit apart so they do not overlap"
	)
	var card_d := hole.global_position.distance_to(human.head.global_position)
	var palm_d := human.body.arm_hands[0].global_position.distance_to(human.head.global_position)
	assert_lt(card_d, palm_d, "fists stay behind the cards")


func test_the_cpu_partner_sits_across_on_her_own_bank() -> void:
	var table := _table()
	var team := GameState.new(PackedInt32Array([4]))
	team.credit(400)
	var human := await _player_with(table.chairs[0].global_position, team)
	var cpu := await _cpu_at(table.chairs[1].global_position)
	human.partner = cpu
	cpu.partner = human
	table.try_sit(human, 0)
	assert_eq(table.stacks[0], 200)
	assert_eq(team.money, 200)
	assert_true(_CpuPoker.tick(cpu, cpu.input as CpuInput))
	assert_true(cpu.is_poker_seated())
	assert_eq(table.filled(), 2)
	assert_eq(table.phase, PokerTable.Phase.BETTING)
	assert_eq(table.stacks[1], 200)
	assert_eq(team.money, 200, "Amber buys in from her own $200, not the team wallet")
	assert_eq(cpu.wallet().money, 0)


func test_the_cpu_partner_sits_from_the_lobby() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 400)
	var cpu := await _cpu_at(table.global_position + Vector3(0.0, -5.0, 12.0))
	human.partner = cpu
	cpu.partner = human
	table.try_sit(human, 0)
	assert_true(_CpuPoker.tick(cpu, cpu.input as CpuInput))
	assert_true(cpu.is_poker_seated(), "warp onto the empty chair even from another floor")
	assert_eq(table.filled(), 2)
	assert_eq(table.phase, PokerTable.Phase.BETTING)


func test_winning_a_fold_cheers_and_names_the_pot() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 200)
	var cpu := await _player(table.chairs[1].global_position, 200)
	cpu.possess_cpu()
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	table.tick(PokerTable.BET_SEC + 0.05)
	table.try_act(human, "call")
	table.try_act(cpu, "fold")
	assert_eq(table.phase, PokerTable.Phase.SHOWDOWN)
	assert_eq(human.poker.last_delta, 20)
	assert_true(human.is_poker_seated())
	assert_false(human.is_celebrating(), "stay in the chair; the dialogue is not a hole-out dance")
	human._animate(0.0)
	assert_almost_eq(human.body.hips.position.y, PlayerBody.SIT_HIP_HEIGHT, 0.02)
	assert_lt(
		human.get_view_transform().origin.distance_to(human.head.global_position),
		0.8,
		"keep the first-person seat camera"
	)
	assert_true(human.poker.showing_result())
	assert_eq(human.poker.result_title(), "You win $20")
	assert_eq(human.poker.result_body(), "Play again?")
	assert_string_contains(human.poker.prompt(human), human.input.hint("interact"))
	assert_string_contains(human.poker.prompt(human), "Yes")
	assert_eq(human.poker.reveal_ids(human), table.hole_cards(1))
	assert_eq(cpu.poker.last_delta, -20)
	assert_false(cpu.is_celebrating())
	assert_eq(table.replay[1], 1, "the CPU already said yes")


func test_folding_names_the_loss_and_shows_their_cards() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 200)
	var cpu := await _player(table.chairs[1].global_position, 200)
	cpu.possess_cpu()
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	table.tick(PokerTable.BET_SEC + 0.05)
	table.try_act(human, "fold")
	assert_eq(table.phase, PokerTable.Phase.SHOWDOWN)
	assert_eq(human.poker.last_delta, -10)
	assert_false(human.is_celebrating())
	assert_true(human.poker.showing_result())
	assert_eq(human.poker.result_title(), "You lose $10")
	assert_eq(human.poker.result_body(), "Play again?")
	assert_true(human.poker.can_replay())
	assert_string_contains(human.poker.prompt(human), "Yes")
	assert_eq(human.poker.reveal_ids(human), table.hole_cards(1))
	assert_eq(cpu.poker.last_delta, 10)


func test_standing_after_a_win_keeps_the_pot() -> void:
	var table := _table()
	var team := GameState.new(PackedInt32Array([4]))
	team.credit(400)
	var human := await _player_with(table.chairs[0].global_position, team)
	var cpu := await _cpu_at(table.chairs[1].global_position)
	human.partner = cpu
	cpu.partner = human
	table.try_sit(human, 0)
	assert_true(_CpuPoker.tick(cpu, cpu.input as CpuInput))
	table.try_skip_bets(human)
	assert_eq(table.hand.to_act, 0)
	table.try_act(human, "call")
	table.try_act(cpu, "fold")
	assert_eq(table.stacks[0], 220)
	assert_eq(table.stacks[1], 180)
	table.try_stand(human)
	assert_true(_CpuPoker.tick(cpu, cpu.input as CpuInput))
	assert_false(human.is_poker_seated())
	assert_false(cpu.is_poker_seated())
	assert_eq(team.money, 420, "your leftover cash plus the pot you won")
	assert_eq(cpu.wallet().money, 180, "her stack cashes out to her card, not yours")


func test_yes_deals_another_hand() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 200)
	var cpu := await _player(table.chairs[1].global_position, 200)
	cpu.possess_cpu()
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	table.try_skip_bets(human)
	table.try_act(human, "call")
	table.try_act(cpu, "fold")
	assert_eq(table.phase, PokerTable.Phase.SHOWDOWN)
	assert_true(human.poker.use(human), "circle confirms the highlighted Yes")
	assert_eq(table.phase, PokerTable.Phase.BETTING)
	assert_true(human.is_poker_seated())
	assert_true(cpu.is_poker_seated())


func test_no_stands_you_after_the_hand() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 200)
	var cpu := await _player(table.chairs[1].global_position, 200)
	cpu.possess_cpu()
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	table.try_skip_bets(human)
	table.try_act(human, "call")
	table.try_act(cpu, "fold")
	human.poker.want_replay = false
	assert_string_contains(human.poker.prompt(human), "No")
	human.poker.use(human)
	assert_false(human.is_poker_seated())
	assert_eq(human.wallet().money, 220)
	assert_eq(table.open_seat_for(human), -1, "step off so confirm-No cannot sit you again")


func test_the_hud_shows_the_result_buttons() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 200)
	var cpu := await _player(table.chairs[1].global_position, 200)
	cpu.possess_cpu()
	human.partner = cpu
	cpu.partner = human
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	table.try_skip_bets(human)
	table.try_act(human, "call")
	table.try_act(cpu, "fold")
	var hud: Hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child_autofree(hud)
	hud.poker_result.refresh(human)
	assert_true(hud.poker_result.visible)
	assert_eq(hud.poker_result.title.text, "YOU WIN $20")
	assert_eq(hud.poker_result.body.text, "PLAY AGAIN?")
	assert_true(hud.poker_result.yes_btn.visible)
	assert_true(hud.poker_result.no_btn.visible)
	hud.poker_result.yes_btn.pressed.emit()
	assert_eq(table.phase, PokerTable.Phase.BETTING)


func test_reload_cycles_the_replay_buttons() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 200)
	var cpu := await _player(table.chairs[1].global_position, 200)
	cpu.possess_cpu()
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	table.try_skip_bets(human)
	table.try_act(human, "call")
	table.try_act(cpu, "fold")
	assert_true(human.poker.replay_yes())
	var pad := CpuInput.new("p1", false)
	human.input = pad
	pad.tap("reload")
	human.poker.tick(human, 0.0)
	assert_false(human.poker.replay_yes())
	assert_string_contains(human.poker.prompt(human), "No")
	pad.tap("interact")
	assert_true(human.poker.use(human))
	assert_false(human.is_poker_seated())
	assert_eq(human.wallet().money, 220)


func _table() -> PokerTable:
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	var table: PokerTable = house.get_tree().get_nodes_in_group("clubhouse_poker")[0]
	table.set_process(false)
	return table


func _seat_pair(table: PokerTable) -> void:
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	table.try_sit(a, 0)
	table.try_sit(b, 1)


func _player(at: Vector3, cash: int) -> Player:
	var score := GameState.new(PackedInt32Array([4]))
	score.credit(cash)
	return await _player_with(at, score)


func _cpu_at(at: Vector3) -> Player:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	player.global_position = at
	player.score = null
	player.possess_cpu()
	return player


func _player_with(at: Vector3, score: GameState) -> Player:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	player.global_position = at
	player.score = score
	return player


func _card_for(host: PokerCards, seat: int, slot: int) -> Node3D:
	for child in host.get_children():
		if int(child.get_meta("seat", -1)) == seat and int(child.get_meta("slot", -1)) == slot:
			return child as Node3D
	return null
