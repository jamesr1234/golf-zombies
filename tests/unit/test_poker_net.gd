extends GutTest
## VS clubhouse cash-out and remote occupancy bind for the poker tables.

const PLAYER := preload("res://scenes/players/player.tscn")


func test_discarding_the_vs_clubhouse_cashes_out_poker() -> void:
	var course := VsCourse.new()
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	course.clubhouse = house
	var table: PokerTable = house.get_tree().get_nodes_in_group("clubhouse_poker")[0]
	table.set_process(false)
	var who := await _player(table.chairs[0].global_position, 300)
	who.peer_id = 7
	table.try_sit(who, 0)
	assert_eq(who.wallet().money, 100)
	assert_true(who.is_poker_seated())
	course.close_shop([who])
	assert_eq(who.wallet().money, 300, "buy-in returns when VS tears down the house")
	assert_false(who.is_poker_seated())
	course.free()


func test_leaving_vs_shop_cashes_out_poker() -> void:
	var course := VsCourse.new()
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	course.clubhouse = house
	var table: PokerTable = house.get_tree().get_nodes_in_group("clubhouse_poker")[0]
	table.set_process(false)
	var who := await _player(table.chairs[0].global_position, 300)
	who.peer_id = 7
	table.try_sit(who, 0)
	assert_eq(who.wallet().money, 100)
	course.leave_to_prep([who])
	assert_eq(who.wallet().money, 300, "opening the exit cashes the table like solo")
	assert_false(who.is_poker_seated())
	course.free()


func test_replicated_occupancy_binds_without_a_second_buy_in() -> void:
	var table := _table()
	var who := await _player(table.chairs[0].global_position, 300)
	who.peer_id = 7
	table.try_sit(who, 0)
	var snap := PokerNet.snapshot(table)
	assert_eq(int(snap["id0"]), 7)
	table.kick_all()
	assert_false(who.is_poker_seated())
	assert_eq(who.wallet().money, 300)
	PokerNet.apply(table, snap)
	assert_true(who.is_poker_seated(), "the owning client has to bind locally")
	assert_eq(who.poker.seat, 0)
	assert_eq(who.wallet().money, 300, "apply must not charge again")
	assert_eq(table.phase, PokerTable.Phase.WAIT_FILL)
	assert_string_contains(who.poker.prompt(who), "Waiting for a player")


func test_replicated_hand_lets_the_sitter_act() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	a.peer_id = 7
	b.peer_id = 8
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	table.try_skip_bets(a)
	assert_eq(table.phase, PokerTable.Phase.PLAYING)
	var snap := PokerNet.snapshot(table)
	table.kick_all()
	PokerNet.apply(table, snap)
	assert_true(a.is_poker_seated())
	assert_true(b.is_poker_seated())
	assert_eq(table.phase, PokerTable.Phase.PLAYING)
	assert_not_null(table.hand)
	var actor: Player = table.occupants[table.hand.to_act]
	assert_not_null(actor)
	assert_gt(actor.poker.prompt(actor).length(), 0, "the actor sees check/call, not a blank prompt")
	assert_string_contains(actor.poker.prompt(actor), actor.input.hint("interact"))


func test_a_client_tick_counts_down_without_dealing() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	assert_eq(table.phase, PokerTable.Phase.BETTING)
	assert_almost_eq(table.timer, PokerTable.BET_SEC, 0.05)
	table.visual_tick(1.0)
	assert_eq(table.phase, PokerTable.Phase.BETTING, "visual tick must not deal")
	assert_almost_eq(table.timer, PokerTable.BET_SEC - 1.0, 0.05)
	assert_null(table.hand)
	table.visual_tick(20.0)
	assert_eq(table.phase, PokerTable.Phase.BETTING)
	assert_almost_eq(table.timer, 0.0, 0.05)
	assert_null(table.hand)


func test_applied_cards_show_on_the_felt() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	a.peer_id = 7
	b.peer_id = 8
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	table.try_skip_bets(a)
	var snap := PokerNet.snapshot(table)
	table.kick_all()
	PokerNet.apply(table, snap)
	table.visual_tick(0.0)
	var cards := table.get_node("Cards") as PokerCards
	var holes := 0
	for child in cards.get_children():
		if child.has_meta("seat"):
			holes += 1
	assert_eq(holes, 4, "two hole cards each, refreshed from the snapshot")
	assert_eq(table.hole_cards(0).size(), 2)


func test_a_viewer_snapshot_hides_the_other_hole() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	a.peer_id = 7
	b.peer_id = 8
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	table.try_skip_bets(a)
	var for_a := PokerNet.snapshot(table, 7)
	var for_b := PokerNet.snapshot(table, 8)
	var for_rail := PokerNet.snapshot(table, 99)
	var full := PokerNet.snapshot(table)
	assert_eq(_hole_n(for_a, "hole0"), 2)
	assert_eq(_hole_n(for_a, "hole1"), 0)
	assert_eq(_hole_n(for_b, "hole0"), 0)
	assert_eq(_hole_n(for_b, "hole1"), 2)
	assert_eq(_hole_n(for_rail, "hole0"), 0)
	assert_eq(_hole_n(for_rail, "hole1"), 0)
	assert_eq(_hole_n(full, "hole0"), 2)
	assert_eq(_hole_n(full, "hole1"), 2)
	var actor: Player = table.occupants[table.hand.to_act]
	table.try_act(actor, "fold")
	var shown := PokerNet.snapshot(table, 7)
	assert_eq(table.phase, PokerTable.Phase.SHOWDOWN)
	assert_eq(_hole_n(shown, "hole0"), 2)
	assert_eq(_hole_n(shown, "hole1"), 2)
	assert_eq(int(shown.get("r0", 99)), table.replay[0])
	assert_eq(int(shown.get("r1", 99)), table.replay[1])


func test_side_bets_replicate_without_charging_again() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	a.peer_id = 7
	b.peer_id = 8
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	var watcher := await _player(table.chairs[1].global_position + Vector3(1.5, 0.0, 0.0), 100)
	watcher.peer_id = 9
	table.try_side_bet(watcher, 1, 20)
	assert_eq(watcher.wallet().money, 80)
	var snap := PokerNet.snapshot(table)
	var wired: Array = snap["bets"]
	assert_eq(wired.size(), 1)
	assert_eq(int(wired[0]["amount"]), 20)
	assert_eq(int(wired[0]["seat"]), 1)
	table.bets.clear()
	assert_eq(table.bets.listing(), "")
	PokerNet.apply(table, snap)
	assert_eq(watcher.wallet().money, 80, "apply must not spend the rail again")
	assert_string_contains(table.bets.listing(), GameState.format_money(20))
	assert_string_contains(table.panel_text(), GameState.format_money(20))


func test_a_win_snapshot_cheers_once() -> void:
	var table := _table()
	var a := await _player(table.chairs[0].global_position, 200)
	var b := await _player(table.chairs[1].global_position, 200)
	a.peer_id = 7
	b.peer_id = 8
	table.try_sit(a, 0)
	table.try_sit(b, 1)
	table.try_skip_bets(a)
	var actor: Player = table.occupants[table.hand.to_act]
	table.try_act(actor, "fold")
	assert_eq(table.phase, PokerTable.Phase.SHOWDOWN)
	var snap := PokerNet.snapshot(table)
	a.look.cheer_left = 0.0
	b.look.cheer_left = 0.0
	table.kick_all()
	assert_false(a.is_celebrating())
	assert_false(b.is_celebrating())
	PokerNet.apply(table, snap)
	var winner: Player = a if int(snap["d0"]) > 0 else b
	assert_true(winner.is_poker_seated())
	assert_false(winner.is_celebrating(), "a seated win stays in the chair")
	PokerNet.apply(table, snap)
	assert_eq(winner.look.cheer_left, 0.0, "a second snap must not start a cheer")


func _table() -> PokerTable:
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	var table: PokerTable = house.get_tree().get_nodes_in_group("clubhouse_poker")[0]
	table.set_process(false)
	return table


func _player(at: Vector3, cash: int) -> Player:
	var score := GameState.new(PackedInt32Array([4]))
	score.credit(cash)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	player.global_position = at
	player.score = score
	return player


func _hole_n(snap: Dictionary, key: String) -> int:
	return PackedInt32Array(snap[key]).size()
