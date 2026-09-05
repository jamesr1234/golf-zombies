class_name PokerBets
extends RefCounted
## Even-money house side-bets on a seated player. Spent now, paid at showdown.

var rows: Array[Dictionary] = []


func clear() -> void:
	rows.clear()


func refund() -> void:
	for bet in rows:
		_credit(bet, int(bet["amount"]))
	rows.clear()


func pay(winner_seat: int, split: bool) -> void:
	for bet in rows:
		_credit(bet, PokerHand.side_credit(winner_seat, split, int(bet["seat"]), int(bet["amount"])))
	rows.clear()


func drop_player(player: Player) -> void:
	var id := player.get_instance_id()
	var kept: Array[Dictionary] = []
	for bet in rows:
		if int(bet["id"]) != id:
			kept.append(bet)
			continue
		_credit(bet, int(bet["amount"]))
	rows = kept


func place(player: Player, seat: int, amount: int) -> bool:
	amount = PokerHand.snap_chips(amount)
	if amount < PokerHand.CHIP:
		return false
	var card = player.wallet()
	if card == null:
		return false
	drop_player(player)
	if not card.try_spend(amount):
		return false
	rows.append({
		"id": player.get_instance_id(),
		"peer": player.peer_id,
		"seat": seat,
		"amount": amount,
		"wallet": card,
	})
	return true


func listing() -> String:
	var text := ""
	for bet in rows:
		text += "\n  %s on seat %d" % [GameState.format_money(int(bet["amount"])), int(bet["seat"])]
	return text


func to_net() -> Array:
	var out: Array = []
	for bet in rows:
		out.append({
			"peer": int(bet.get("peer", 0)),
			"seat": int(bet["seat"]),
			"amount": int(bet["amount"]),
		})
	return out


func apply_net(raw: Array) -> void:
	rows.clear()
	for bet in raw:
		if not bet is Dictionary:
			continue
		var row: Dictionary = bet
		rows.append({
			"id": 0,
			"peer": int(row.get("peer", 0)),
			"seat": int(row.get("seat", 0)),
			"amount": int(row.get("amount", 0)),
			"wallet": null,
		})


func _credit(bet: Dictionary, amount: int) -> void:
	var card = bet.get("wallet")
	if card != null and card.has_method("credit"):
		card.credit(amount)
