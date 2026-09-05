extends GutTest
## Seated cash follows the stack, and fold / check / raise sit on the main HUD.

const PLAYER := preload("res://scenes/players/player.tscn")
const HUD := preload("res://scenes/ui/hud.tscn")


func test_shown_cash_includes_the_stack_after_a_win() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 300)
	var cpu := await _cpu(table.chairs[1].global_position, 200)
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	assert_eq(human.wallet().money, 100)
	assert_eq(human.poker.shown_cash(human), 300, "buy-in chips still count as your money")
	table.try_skip_bets(human)
	table.try_act(human, "call")
	table.try_act(cpu, "fold")
	assert_eq(table.phase, PokerTable.Phase.SHOWDOWN)
	assert_eq(human.poker.shown_cash(human), 320)
	assert_eq(cpu.poker.shown_cash(cpu), 180)
	var hud: Hud = HUD.instantiate()
	add_child_autofree(hud)
	hud.player = human
	hud._update_money()
	assert_eq(hud.money_label.text, "$320")


func test_a_raise_names_the_amount() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 200)
	var cpu := await _cpu(table.chairs[1].global_position, 200)
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	table.try_skip_bets(human)
	table.try_act(human, "call")
	table.try_act(cpu, "raise", 40)
	assert_eq(table.last_act, "Amber raises $20")
	assert_eq(human.poker.headline(), "Amber raises $20")
	var labels: PackedStringArray = []
	for choice in human.poker.choices():
		labels.append(String(choice["label"]))
	assert_true("Call $20" in labels)
	assert_true("Reraise $20" in labels)


func test_the_act_hud_shows_fold_check_and_raise() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 200)
	var cpu := await _cpu(table.chairs[1].global_position, 200)
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	table.try_skip_bets(human)
	table.try_act(human, "call")
	table.try_act(cpu, "check")
	table.try_act(cpu, "check")
	var hud: Hud = HUD.instantiate()
	add_child_autofree(hud)
	await wait_physics_frames(1)
	hud.poker_act.refresh(human)
	assert_true(hud.poker_act.visible)
	assert_eq(hud.poker_act.title.text, "AMBER CHECKS")
	assert_true(hud.poker_act.fold_btn.visible)
	assert_true(hud.poker_act.soft_btn.visible)
	assert_true(hud.poker_act.raise_btn.visible)
	assert_eq(hud.poker_act.soft_btn.text, "CHECK")
	assert_string_contains(hud.poker_act.raise_btn.text, "RAISE")


func test_facing_a_raise_offers_reraise_call_and_fold() -> void:
	var table := _table()
	var human := await _player(table.chairs[0].global_position, 200)
	var cpu := await _cpu(table.chairs[1].global_position, 200)
	table.try_sit(human, 0)
	table.try_sit(cpu, 1)
	table.try_skip_bets(human)
	table.try_act(human, "call")
	table.try_act(cpu, "raise", 40)
	var hud: Hud = HUD.instantiate()
	add_child_autofree(hud)
	await wait_physics_frames(1)
	hud.poker_act.refresh(human)
	assert_true(hud.poker_act.visible)
	assert_eq(hud.poker_act.title.text, "AMBER RAISES $20")
	assert_eq(hud.poker_act.soft_btn.text, "CALL $20")
	assert_string_contains(hud.poker_act.raise_btn.text, "RERAISE")
	assert_true(hud.poker_act.fold_btn.visible)
	hud.poker_act.soft_btn.pressed.emit()
	assert_eq(table.hand.to_act, 1, "call sends it back across the table")


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


func _cpu(at: Vector3, cash: int) -> Player:
	var player := await _player(at, cash)
	player.body_color = Palette.PLAYER_TWO
	player.set_process(false)
	return player
