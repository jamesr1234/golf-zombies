class_name PokerPlay
extends Object
## Betting window, deal, CPU/timeout actions, and showdown on a PokerTable.


static func tick(table: PokerTable, delta: float) -> void:
	drop_dead(table)
	if table.phase == PokerTable.Phase.BETTING:
		table.timer -= delta
		if table.timer <= 0.0:
			deal(table)
			table._broadcast_state()
	elif table.phase == PokerTable.Phase.PLAYING:
		tick_play(table, delta)


static func on_seated(table: PokerTable) -> void:
	if table.filled() >= 2:
		begin_betting(table)
	elif table.filled() == 1:
		table.phase = PokerTable.Phase.WAIT_FILL
		table.timer = 0.0


static func on_left(table: PokerTable) -> void:
	if table.filled() >= 2:
		return
	if table.phase == PokerTable.Phase.PLAYING or table.phase == PokerTable.Phase.SHOWDOWN:
		table.bets.refund()
		table.hand = null
	if table.filled() == 1:
		table.phase = PokerTable.Phase.WAIT_FILL
		table.timer = 0.0
		table.replay = [-1, -1]
	else:
		idle(table)


static func begin_betting(table: PokerTable) -> void:
	table.phase = PokerTable.Phase.BETTING
	table.timer = PokerTable.BET_SEC
	table.bets.clear()
	table.hand = null
	table.last_act = ""
	table.replay = [-1, -1]
	table.clear_chips()


static func skip_bets(table: PokerTable) -> void:
	if table.phase == PokerTable.Phase.BETTING and table.filled() >= 2:
		deal(table)


static func deal(table: PokerTable) -> void:
	if table.filled() < 2:
		on_left(table)
		return
	if kick_short(table):
		return
	table.dealt_stacks = [table.stacks[0], table.stacks[1]]
	table.hand = PokerHand.new()
	table.hand.start(table.stacks, table.button, table._rng)
	table.sync_stacks()
	table.phase = PokerTable.Phase.PLAYING
	table.timer = PokerTable.ACT_SEC
	table._cpu_wait = PokerTable.CPU_THINK
	table.last_act = "Blinds %s / %s" % [
		GameState.format_money(PokerHand.SMALL), GameState.format_money(PokerHand.BIG)
	]
	table.toss_blinds()
	if table.hand.over:
		begin_show(table)


static func tick_play(table: PokerTable, delta: float) -> void:
	if table.hand == null or table.hand.over:
		begin_show(table)
		table._broadcast_state()
		return
	var seat := table.hand.to_act
	if table.is_cpu_seat(seat):
		table._cpu_wait -= delta
		if table._cpu_wait <= 0.0:
			var choice := PokerCpu.pick(table.hand, seat, table._rng)
			var op := String(choice.get("op", "check"))
			var to := int(choice.get("to", 0))
			var line := describe(table, seat, op, to)
			if table.hand.apply(seat, op, to):
				table.toss_last(seat)
				table.last_act = line
			table.sync_stacks()
			table._cpu_wait = PokerTable.CPU_THINK
			table.timer = PokerTable.ACT_SEC
			if table.hand.over:
				begin_show(table)
			table._broadcast_state()
		return
	table.timer -= delta
	if table.timer <= 0.0:
		var op := "check" if table.hand.can_check(seat) else "fold"
		var line := describe(table, seat, op, 0)
		table.hand.force_timeout(seat)
		table.last_act = line
		table.sync_stacks()
		table.timer = PokerTable.ACT_SEC
		if table.hand.over:
			begin_show(table)
		table._broadcast_state()


static func describe(table: PokerTable, seat: int, op: String, raise_to: int) -> String:
	var who := table.occupant_name(seat)
	if op == "fold":
		return "%s folds" % who
	if op == "check":
		return "%s checks" % who
	if op == "call":
		var need := 0 if table.hand == null else table.hand.to_call(seat)
		return "%s calls %s" % [who, GameState.format_money(need)]
	if op == "raise":
		var by := raise_size(table.hand, raise_to)
		if by > 0:
			return "%s raises %s" % [who, GameState.format_money(by)]
		return "%s raises to %s" % [who, GameState.format_money(raise_to)]
	return ""


static func raise_size(hand: PokerHand, raise_to: int) -> int:
	if hand == null:
		return maxi(0, raise_to)
	return maxi(0, raise_to - maxi(hand.street_bet[0], hand.street_bet[1]))


static func idle(table: PokerTable) -> void:
	table.phase = PokerTable.Phase.IDLE
	table.timer = 0.0
	table.hand = null
	table.bets.clear()
	table.last_act = ""
	table.replay = [-1, -1]
	table.clear_chips()


static func begin_show(table: PokerTable) -> void:
	table.sync_stacks()
	var win := -1
	var is_split := true
	if table.hand != null:
		win = table.hand.winner_seat
		is_split = table.hand.split
	table.bets.pay(win, is_split)
	if is_split or win < 0:
		table.last_act = "Split pot"
	else:
		table.last_act = "%s wins" % table.occupant_name(win)
	table.phase = PokerTable.Phase.SHOWDOWN
	table.timer = 0.0
	table.button = 1 - table.button
	table.replay = [-1, -1]
	tell_players(table)
	auto_replay(table)


static func vote_replay(table: PokerTable, seat: int, yes: bool) -> void:
	if table.phase != PokerTable.Phase.SHOWDOWN or seat < 0 or seat > 1:
		return
	if table.occupants[seat] == null or table.replay[seat] >= 0:
		return
	if yes and not can_continue(table, seat):
		yes = false
	table.replay[seat] = 1 if yes else 0
	if _all_voted(table):
		_resolve_replay(table)


static func auto_replay(table: PokerTable) -> void:
	for seat in 2:
		if table.is_cpu_seat(seat):
			vote_replay(table, seat, can_continue(table, seat))


static func can_continue(table: PokerTable, seat: int) -> bool:
	if seat < 0 or seat > 1 or table.occupants[seat] == null:
		return false
	if table.is_cpu_seat(seat):
		return true
	if table.stacks[seat] >= PokerTable.STAY:
		return true
	return _wallet_cash(table, seat) >= PokerTable.BUY_IN


static func after_show(table: PokerTable) -> void:
	table.replay = [-1, -1]
	table.hand = null
	_rebuy_short(table)
	kick_short(table)
	if table.filled() >= 2:
		begin_betting(table)
	else:
		on_left(table)


static func _all_voted(table: PokerTable) -> bool:
	for seat in 2:
		if table.occupants[seat] != null and table.replay[seat] < 0:
			return false
	return true


static func _resolve_replay(table: PokerTable) -> void:
	for seat in 2:
		if table.occupants[seat] != null and table.replay[seat] == 0:
			table.clear_seat(seat, true)
	after_show(table)


static func _wallet_cash(table: PokerTable, seat: int) -> int:
	var card = table.wallets[seat]
	if card == null:
		return 0
	return int(card.money)


static func _rebuy_short(table: PokerTable) -> void:
	for seat in 2:
		if table.occupants[seat] == null or table.stacks[seat] >= PokerTable.STAY:
			continue
		if table.is_cpu_seat(seat):
			table.stacks[seat] += PokerTable.BUY_IN
			continue
		var card = table.wallets[seat]
		if card == null or not card.has_method("try_spend"):
			continue
		if int(card.money) < PokerTable.BUY_IN or not card.try_spend(PokerTable.BUY_IN):
			continue
		table.stacks[seat] += PokerTable.BUY_IN


static func kick_short(table: PokerTable) -> bool:
	var kicked := false
	for seat in 2:
		if table.occupants[seat] == null or table.stacks[seat] >= PokerTable.STAY:
			continue
		table.last_act = "Not enough money to bet on the game"
		table.clear_seat(seat, true)
		kicked = true
	if kicked:
		on_left(table)
		table._broadcast_state()
	return kicked


static func tell_players(table: PokerTable) -> void:
	for seat in 2:
		var who = table.occupants[seat]
		if not who is Player:
			continue
		var player := who as Player
		var gained := table.stacks[seat] - table.dealt_stacks[seat]
		player.poker.note_result(gained)
		if gained > 0:
			player.celebrate()


static func drop_dead(table: PokerTable) -> void:
	for seat in 2:
		var who = table.occupants[seat]
		if who is Player and not (who as Player).health.is_alive():
			table.clear_seat(seat, true)
			on_left(table)
			table._broadcast_state()
