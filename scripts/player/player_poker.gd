class_name PlayerPoker
extends RefCounted
## Sit, act, and even-money side-bets. Prompts and the shop panel read this.

const CHIPS: Array[int] = [10, 20, 50]

var table: PokerTable
var seat := -1
var act_idx := 0
var chip_idx := 0
var last_delta := 0
var want_replay := true
var _stick_armed := false


func seated() -> bool:
	return table != null and is_instance_valid(table) and seat >= 0


func bind(p_table: PokerTable, p_seat: int) -> void:
	table = p_table
	seat = p_seat
	act_idx = 0
	last_delta = 0
	want_replay = true
	_stick_armed = false


func clear() -> void:
	table = null
	seat = -1
	act_idx = 0
	last_delta = 0
	want_replay = true
	_stick_armed = false


func stand(player: Player) -> void:
	if seated():
		table.try_stand(player)


func tick(player: Player, _delta: float) -> void:
	if seated():
		if asking_replay():
			_tick_replay(player)
			return
		if player.input.just_pressed("reload"):
			act_idx += 1
		if player.input.just_pressed("melee"):
			if _to_act():
				table.try_act(player, "fold")
			else:
				table.try_stand(player)
		return
	if player.input.just_pressed("swap_weapon"):
		chip_idx = (chip_idx + 1) % CHIPS.size()
	elif player.input.just_pressed("swap_weapon_prev"):
		chip_idx = posmod(chip_idx - 1, CHIPS.size())


func use(player: Player) -> bool:
	if seated():
		if asking_replay():
			pick_replay(player, replay_yes())
			return true
		if _to_act():
			_confirm(player)
		elif table.phase == PokerTable.Phase.BETTING:
			table.try_skip_bets(player)
		return true
	var open := PokerTable.nearest_open(player)
	if open != null:
		open.try_sit(player)
		return true
	if _can_bet(player):
		var live := PokerTable.nearest_table(player)
		live.try_side_bet(player, live.bet_seat_for(player), CHIPS[chip_idx])
		return true
	return false


func prompt(player: Player) -> String:
	if seated():
		if _to_act():
			return _act_prompt(player)
		if table.phase == PokerTable.Phase.SHOWDOWN:
			return _replay_prompt(player)
		if table.phase == PokerTable.Phase.PLAYING and table.hand != null:
			return "Waiting on %s   %s to stand" % [
				table.occupant_name(table.hand.to_act), player.input.hint("melee")
			]
		if table.phase == PokerTable.Phase.BETTING:
			return "Waiting on side bets   %s to deal   %s to stand" % [
				player.input.hint("interact"), player.input.hint("melee")
			]
		if table.phase == PokerTable.Phase.WAIT_FILL:
			return "Waiting for a player   %s to stand" % player.input.hint("melee")
		return "Waiting   %s to stand" % player.input.hint("melee")
	if PokerTable.nearest_open(player) != null:
		return "%s to sit ($%d buy-in)" % [player.input.hint("interact"), PokerTable.BUY_IN]
	var live := PokerTable.nearest_table(player)
	if live != null and live.vacant_seat_for(player) >= 0:
		return "Not enough money to bet on the game"
	if _can_bet(player):
		return "%s to bet %s   %s cycles" % [
			player.input.hint("interact"),
			GameState.format_money(CHIPS[chip_idx]),
			player.input.hint("swap_weapon"),
		]
	return ""


func shows_panel(player: Player) -> bool:
	return seated() or _can_bet(player) or _near_live(player)


func board_ids(player: Player) -> Array:
	if not shows_panel(player):
		return []
	var live := table if seated() else PokerTable.nearest_table(player)
	if live == null or live.hand == null:
		return []
	return live.hand.board


func reveal_ids(player: Player) -> Array:
	if not shows_panel(player):
		return []
	var live := table if seated() else PokerTable.nearest_table(player)
	if live == null or live.hand == null or live.phase != PokerTable.Phase.SHOWDOWN:
		return []
	if seated():
		return live.hole_cards(1 - seat)
	return []


func note_result(delta: int) -> void:
	last_delta = delta
	want_replay = true
	_stick_armed = false


func showing_result() -> bool:
	return seated() and table.phase == PokerTable.Phase.SHOWDOWN


func asking_replay() -> bool:
	return showing_result() and table.replay[seat] < 0


func can_replay() -> bool:
	return seated() and PokerPlay.can_continue(table, seat)


func replay_yes() -> bool:
	return can_replay() and want_replay


func result_title() -> String:
	return _result_line()


func result_body() -> String:
	if not asking_replay():
		var other := 1 - seat
		if table.occupants[other] != null and table.replay[other] < 0:
			return "Waiting on %s" % table.occupant_name(other)
		return "Waiting"
	if can_replay():
		return "Play again?"
	return "Not enough money to play again"


func pick_replay(player: Player, yes: bool) -> void:
	if not asking_replay():
		return
	if yes and not can_replay():
		yes = false
	Sfx.play("ui_confirm" if yes else "ui_back", player)
	table.try_replay(player, yes)


func shown_cash(player: Player) -> int:
	var card = player.wallet() if player != null else null
	var cash := 0 if card == null else int(card.money)
	if seated():
		cash += table.stacks[seat]
	return cash


func headline() -> String:
	if not seated():
		return ""
	return table.last_act


func choices() -> Array[Dictionary]:
	return _ops()


func pick_act(player: Player, op: String, raise_to := 0) -> void:
	if not _to_act():
		return
	table.try_act(player, op, raise_to)
	act_idx = 0


func panel_text(player: Player) -> String:
	var live := table if seated() else PokerTable.nearest_table(player)
	if live == null:
		return ""
	var text := live.panel_text()
	if seated() and live.hand != null:
		text += "\nYou  %s" % PokerEval.labels(live.hole_cards(seat))
		if live.phase == PokerTable.Phase.SHOWDOWN:
			text += "\n%s  %s" % [
				live.occupant_name(1 - seat), PokerEval.labels(live.hole_cards(1 - seat))
			]
			text += "\n%s" % _result_line()
	if _to_act():
		var ops := _ops()
		if not ops.is_empty():
			var choice: Dictionary = ops[act_idx % ops.size()]
			text += "\n%s   %s Fold" % [
				String(choice["label"]), player.input.hint("melee")
			]
	var peek := -1 if live == null else live.peek_seat(player)
	if peek >= 0 and not seated():
		text += "\nPeek  %s" % PokerEval.labels(live.hole_cards(peek))
	return text


func timer_left(player: Player) -> float:
	var live := table if seated() else PokerTable.nearest_table(player)
	if live == null:
		return -1.0
	if live.phase == PokerTable.Phase.BETTING or live.phase == PokerTable.Phase.PLAYING:
		return live.timer
	return -1.0


func blocks_weapon_swap(player: Player) -> bool:
	return seated() or _can_bet(player)


func _to_act() -> bool:
	return (
		seated()
		and table.phase == PokerTable.Phase.PLAYING
		and table.hand != null
		and not table.hand.over
		and table.hand.to_act == seat
	)


func _confirm(player: Player) -> void:
	var ops := _ops()
	if ops.is_empty():
		return
	var choice: Dictionary = ops[act_idx % ops.size()]
	table.try_act(player, String(choice["op"]), int(choice.get("to", 0)))
	act_idx = 0


func _act_prompt(player: Player) -> String:
	var ops := _ops()
	if ops.is_empty():
		return ""
	var choice: Dictionary = ops[act_idx % ops.size()]
	return "%s %s   %s Fold   %s cycles" % [
		player.input.hint("interact"),
		String(choice["label"]),
		player.input.hint("melee"),
		player.input.hint("reload"),
	]


func _ops() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _to_act():
		return out
	if table.hand.can_check(seat):
		out.append({"op": "check", "label": "Check", "to": 0})
	else:
		out.append({
			"op": "call",
			"label": "Call %s" % GameState.format_money(table.hand.to_call(seat)),
			"to": 0,
		})
	var facing := not table.hand.can_check(seat)
	for to in table.hand.raise_targets(seat):
		var all_in := to >= table.hand.street_bet[seat] + table.hand.stacks[seat]
		var label := "All-in"
		if not all_in:
			var by := PokerPlay.raise_size(table.hand, to)
			label = "%s %s" % ["Reraise" if facing else "Raise", GameState.format_money(by)]
		out.append({"op": "raise", "label": label, "to": to})
	return out


func _can_bet(player: Player) -> bool:
	var live := PokerTable.nearest_table(player)
	return live != null and live.bet_seat_for(player) >= 0


func _near_live(player: Player) -> bool:
	var live := PokerTable.nearest_table(player)
	return live != null and live.phase != PokerTable.Phase.IDLE


func _result_line() -> String:
	if last_delta > 0:
		return "You win %s" % GameState.format_money(last_delta)
	if last_delta < 0:
		return "You lose %s" % GameState.format_money(-last_delta)
	return "Split pot"


func _replay_prompt(player: Player) -> String:
	if not asking_replay():
		return result_body()
	if not can_replay():
		return "%s No" % player.input.hint("interact")
	return "%s %s   %s cycles" % [
		player.input.hint("interact"),
		"Yes" if replay_yes() else "No",
		player.input.hint("reload"),
	]


func _tick_replay(player: Player) -> void:
	if player.input.just_pressed("reload"):
		want_replay = not want_replay
		Sfx.play("ui_move", player)
	var stick := player.input.move_vector().x
	if absf(stick) < 0.35:
		_stick_armed = true
	elif _stick_armed and stick > 0.55:
		want_replay = false
		_stick_armed = false
		Sfx.play("ui_move", player)
	elif _stick_armed and stick < -0.55:
		want_replay = true
		_stick_armed = false
		Sfx.play("ui_move", player)
	if player.input.just_pressed("melee"):
		pick_replay(player, false)
