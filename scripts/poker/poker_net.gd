class_name PokerNet
extends Object
## Snapshot occupancy and the live hand so remote sitters can act.


static func snapshot(table: PokerTable, viewer := 0) -> Dictionary:
	var hand := table.hand
	var hole0 := _cards(hand, 0) if hand != null else PackedInt32Array()
	var hole1 := _cards(hand, 1) if hand != null else PackedInt32Array()
	if viewer > 0 and not _showdown(table):
		var seat := _seat_of(table, viewer)
		if seat != 0:
			hole0 = PackedInt32Array()
		if seat != 1:
			hole1 = PackedInt32Array()
	return {
		"id0": _peer(table.occupants[0]),
		"id1": _peer(table.occupants[1]),
		"s0": table.stacks[0],
		"s1": table.stacks[1],
		"phase": int(table.phase),
		"timer": table.timer,
		"last": table.last_act,
		"button": table.button,
		"has_hand": hand != null,
		"hole0": hole0,
		"hole1": hole1,
		"board": PackedInt32Array(hand.board) if hand != null else PackedInt32Array(),
		"street": int(hand.street) if hand != null else 0,
		"pot": 0 if hand == null else hand.pot,
		"to_act": -1 if hand == null else hand.to_act,
		"over": false if hand == null else hand.over,
		"split": false if hand == null else hand.split,
		"winner": -1 if hand == null else hand.winner_seat,
		"bet0": 0 if hand == null else hand.street_bet[0],
		"bet1": 0 if hand == null else hand.street_bet[1],
		"raise": PokerHand.BIG if hand == null else hand.last_raise,
		"fold0": 0 if hand == null or not hand.folded[0] else 1,
		"fold1": 0 if hand == null or not hand.folded[1] else 1,
		"d0": _delta(table, 0),
		"d1": _delta(table, 1),
		"r0": table.replay[0],
		"r1": table.replay[1],
		"bets": table.bets.to_net(),
	}


static func apply(table: PokerTable, payload: Dictionary) -> void:
	table.phase = payload["phase"] as PokerTable.Phase
	table.stacks = [int(payload["s0"]), int(payload["s1"])]
	table.timer = float(payload["timer"])
	table.last_act = String(payload["last"])
	table.button = int(payload.get("button", 0))
	_bind(table, 0, int(payload["id0"]))
	_bind(table, 1, int(payload["id1"]))
	if bool(payload["has_hand"]):
		table.hand = _hand(table, payload)
	else:
		table.hand = null
	_note(table, 0, int(payload.get("d0", 0)))
	_note(table, 1, int(payload.get("d1", 0)))
	table.replay = [int(payload.get("r0", -1)), int(payload.get("r1", -1))]
	table.bets.apply_net(payload.get("bets", []))
	table.refresh_cards()


static func _bind(table: PokerTable, seat: int, peer_id: int) -> void:
	var who = null if peer_id <= 0 else table._player_for(peer_id)
	var cur = table.occupants[seat]
	if cur == who:
		if who is Player and not (who as Player).is_poker_seated():
			(who as Player).poker.bind(table, seat)
			table._place(who, seat)
		return
	if cur is Player:
		(cur as Player).poker.clear()
	table.occupants[seat] = who
	if who is Player:
		(who as Player).poker.bind(table, seat)
		table.wallets[seat] = who.wallet()
		table._place(who, seat)
	else:
		table.wallets[seat] = null


static func _hand(table: PokerTable, payload: Dictionary) -> PokerHand:
	var hand := PokerHand.new()
	hand.stacks = [table.stacks[0], table.stacks[1]]
	hand.button = table.button
	hand.street = payload["street"] as PokerHand.Street
	hand.pot = int(payload["pot"])
	hand.to_act = int(payload["to_act"])
	hand.over = bool(payload["over"])
	hand.split = bool(payload["split"])
	hand.winner_seat = int(payload["winner"])
	hand.street_bet = [int(payload["bet0"]), int(payload["bet1"])]
	hand.last_raise = int(payload["raise"])
	hand.folded = [int(payload["fold0"]) != 0, int(payload["fold1"]) != 0]
	hand.hole = [_list(payload["hole0"]), _list(payload["hole1"])]
	hand.board.clear()
	for card in payload["board"]:
		hand.board.append(int(card))
	return hand


static func _peer(who) -> int:
	return 0 if who == null or not who is Player else (who as Player).peer_id


static func _seat_of(table: PokerTable, peer_id: int) -> int:
	if _peer(table.occupants[0]) == peer_id:
		return 0
	if _peer(table.occupants[1]) == peer_id:
		return 1
	return -1


static func _showdown(table: PokerTable) -> bool:
	return table.phase == PokerTable.Phase.SHOWDOWN


static func _cards(hand: PokerHand, seat: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for card in hand.hole[seat]:
		out.append(int(card))
	return out


static func _list(raw) -> Array:
	var out: Array = []
	for card in raw:
		out.append(int(card))
	return out


static func _delta(table: PokerTable, seat: int) -> int:
	var who = table.occupants[seat]
	if who is Player:
		return (who as Player).poker.last_delta
	return 0


static func _note(table: PokerTable, seat: int, delta: int) -> void:
	var who = table.occupants[seat]
	if not who is Player:
		return
	var player := who as Player
	var prev := player.poker.last_delta
	player.poker.note_result(delta)
	if table.phase != PokerTable.Phase.SHOWDOWN or delta <= 0 or prev == delta:
		return
	if player.is_celebrating():
		return
	player.celebrate()
