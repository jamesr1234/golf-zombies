class_name CpuPoker
extends RefCounted
## Solo partner sits across from you. VsCpu does not use this.


static func tick(player: Player, _pad: CpuInput) -> bool:
	if player.is_poker_seated():
		var partner := player.partner
		if partner == null or not partner.is_poker_seated():
			player.poker.stand(player)
		return true
	var partner := player.partner
	if partner == null or not partner.is_poker_seated() or partner.poker.table == null:
		return false
	ensure_bank(player)
	if not _can_buy(player):
		return true
	var table: PokerTable = partner.poker.table
	var seat := table.empty_seat()
	if seat < 0:
		return true
	_sit_across(player, table, seat)
	return true


static func ensure_bank(player: Player) -> void:
	if player == null:
		return
	if player.score == null:
		var card := GameState.new(PackedInt32Array([4]))
		card.credit(PokerTable.BUY_IN)
		player.score = card
		return
	var cash := int(player.score.money)
	if cash < PokerTable.BUY_IN:
		player.score.credit(PokerTable.BUY_IN - cash)


static func _sit_across(player: Player, table: PokerTable, seat: int) -> void:
	if seat < 0 or seat >= table.chairs.size():
		return
	var chair := table.chairs[seat]
	var at := chair.global_position
	at.y = table.global_position.y
	player.spawn_at(at, rad_to_deg(chair.global_transform.basis.get_euler().y))
	table.try_sit(player, seat)


static func _can_buy(player: Player) -> bool:
	var card = player.wallet()
	return card != null and card.money >= PokerTable.BUY_IN
