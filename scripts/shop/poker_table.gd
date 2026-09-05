class_name PokerTable
extends Node3D
## One heads-up table: sit, 8s side-bets, then Hold'em. Host owns the money.

enum Phase { IDLE, WAIT_FILL, BETTING, PLAYING, SHOWDOWN }

const BUY_IN := 200
const STAY := PokerHand.BIG
const BET_SEC := 8.0
const ACT_SEC := 12.0
const SHOW_SEC := 6.0
const CPU_THINK := 0.8
const USE_RANGE := 2.2
const TABLE_RANGE := 3.4

var phase: Phase = Phase.IDLE
var timer := 0.0
var chairs: Array[Node3D] = []
var occupants: Array = [null, null]
var stacks: Array[int] = [0, 0]
var dealt_stacks: Array[int] = [0, 0]
var wallets: Array = [null, null]
var hand: PokerHand
var button := 0
var bets := PokerBets.new()
var _rng := RandomNumberGenerator.new()
var _cards: PokerCards
var _chips: PokerChips
var _cpu_wait := 0.0
var last_act := ""
var replay: Array[int] = [-1, -1]


func bind_chairs() -> void:
	chairs.clear()
	for child in get_children():
		if child.is_in_group("clubhouse_poker_chairs"):
			chairs.append(child as Node3D)
	_cards = PokerCards.new()
	_cards.name = "Cards"
	add_child(_cards)
	_chips = PokerChips.new()
	_chips.name = "Chips"
	add_child(_chips)
	_rng.randomize()


static func nearest_table(who: Node3D) -> PokerTable:
	if who == null or not who.is_inside_tree():
		return null
	var best: PokerTable = null
	var best_d := 8.0
	for node in who.get_tree().get_nodes_in_group("clubhouse_poker"):
		var table := node as PokerTable
		if table == null:
			continue
		var offset := who.global_position - table.global_position
		offset.y = 0.0
		var d := offset.length()
		if d < best_d:
			best = table
			best_d = d
	return best


static func nearest_open(who: Node3D) -> PokerTable:
	if who == null or not who.is_inside_tree():
		return null
	for node in who.get_tree().get_nodes_in_group("clubhouse_poker"):
		var table := node as PokerTable
		if table != null and table.open_seat_for(who) >= 0:
			return table
	return null


static func stand_everyone(tree: SceneTree) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group("clubhouse_poker"):
		if node.has_method("kick_all"):
			node.kick_all()


func _process(delta: float) -> void:
	if NetSession.is_active() and not multiplayer.is_server():
		visual_tick(delta)
		return
	tick(delta)


func tick(delta: float) -> void:
	PokerPlay.tick(self, delta)
	refresh_cards()


func visual_tick(delta: float) -> void:
	if phase == Phase.BETTING or phase == Phase.PLAYING or phase == Phase.SHOWDOWN:
		timer = maxf(0.0, timer - delta)
	refresh_cards()


func refresh_cards() -> void:
	if _cards != null:
		_cards.refresh(hand, chairs, occupants, phase)


func open_seat_for(who: Node3D) -> int:
	if who == null or not _can_join(who):
		return -1
	return vacant_seat_for(who)


func vacant_seat_for(who: Node3D) -> int:
	if who == null:
		return -1
	var best := -1
	var best_d := TABLE_RANGE
	for seat in chairs.size():
		if occupants[seat] != null:
			continue
		if _near_chair(who, seat):
			return seat
		var d := _flat(who.global_position, chairs[seat].global_position)
		if d < best_d:
			best = seat
			best_d = d
	if best >= 0 and _near_table(who):
		return best
	return -1


func bet_seat_for(who: Node3D) -> int:
	if who == null or phase != Phase.BETTING or _seated_player(who) >= 0:
		return -1
	for seat in chairs.size():
		if occupants[seat] != null and _near_chair(who, seat):
			return seat
	return -1


func peek_seat(who: Node3D) -> int:
	if NetSession.is_active():
		return -1
	if who == null or hand == null or hand.hole[0].is_empty():
		return -1
	for seat in chairs.size():
		if _in_peek(who, seat):
			return seat
	return -1


func hole_cards(seat: int) -> Array:
	if hand == null or seat < 0 or seat > 1:
		return []
	return hand.hole[seat]


func try_sit(player: Player, seat := -1) -> void:
	if NetSession.is_active() and not multiplayer.is_server():
		_request_sit.rpc_id(1, player.peer_id, seat)
		return
	_sit(player, seat)


func try_stand(player: Player) -> void:
	if NetSession.is_active() and not multiplayer.is_server():
		_request_stand.rpc_id(1, player.peer_id)
		return
	_stand_player(player)


func try_act(player: Player, op: String, raise_to := 0) -> void:
	if NetSession.is_active() and not multiplayer.is_server():
		_request_act.rpc_id(1, player.peer_id, op, raise_to)
		return
	_act(player, op, raise_to)


func try_side_bet(player: Player, seat: int, amount: int) -> void:
	if NetSession.is_active() and not multiplayer.is_server():
		_request_bet.rpc_id(1, player.peer_id, seat, amount)
		return
	_side_bet(player, seat, amount)


func try_skip_bets(player: Player) -> void:
	if NetSession.is_active() and not multiplayer.is_server():
		_request_skip.rpc_id(1, player.peer_id)
		return
	if _seated_player(player) >= 0:
		PokerPlay.skip_bets(self)
		_broadcast_state()


func try_replay(player: Player, yes: bool) -> void:
	if NetSession.is_active() and not multiplayer.is_server():
		_request_replay.rpc_id(1, player.peer_id, yes)
		return
	_replay(player, yes)


func kick_all() -> void:
	var pay := not (NetSession.is_active() and not multiplayer.is_server())
	if pay:
		bets.refund()
	for seat in 2:
		clear_seat(seat, pay)
	PokerPlay.idle(self)
	_broadcast_state()


func occupant_name(seat: int) -> String:
	var who = occupants[seat]
	if who is Player:
		return _player_name(who)
	return "Empty"


func empty_seat() -> int:
	for seat in 2:
		if occupants[seat] == null:
			return seat
	return -1


func is_cpu_seat(seat: int) -> bool:
	if seat < 0 or seat > 1:
		return false
	var who = occupants[seat]
	return who is Player and (who as Player).is_cpu()


func panel_text() -> String:
	var pot := 0 if hand == null else hand.pot
	var lines := "Pot %s" % GameState.format_money(pot)
	for seat in 2:
		lines += "\n%s  %s" % [occupant_name(seat), GameState.format_money(stacks[seat])]
	if hand != null:
		lines += "\n%s" % hand.street_name()
		if not last_act.is_empty():
			lines += "\n%s" % last_act
		if not hand.over:
			var actor := hand.to_act
			var call := hand.to_call(actor)
			lines += "\n%s to act" % occupant_name(actor)
			if call > 0:
				lines += "  call %s" % GameState.format_money(call)
	if phase == Phase.BETTING:
		lines += "\nSide bets close in %s" % GameState.format_clock(timer)
		lines += bets.listing()
	return lines


func _can_join(who: Node3D) -> bool:
	if who is Player:
		var p := who as Player
		if p.shopping or p.talking or p.is_poker_seated() or not p.health.is_alive():
			return false
		if p.state != Player.State.NORMAL:
			return false
		var card = p.wallet()
		return card != null and card.money >= BUY_IN
	return false


func _near_chair(who: Node3D, seat: int) -> bool:
	if seat < 0 or seat >= chairs.size():
		return false
	return _flat(who.global_position, chairs[seat].global_position) <= USE_RANGE


func _near_table(who: Node3D) -> bool:
	return _flat(who.global_position, global_position) <= TABLE_RANGE


func _flat(a: Vector3, b: Vector3) -> float:
	var offset := a - b
	offset.y = 0.0
	return offset.length()


func _in_peek(who: Node3D, seat: int) -> bool:
	var chair := chairs[seat]
	var local := chair.to_local(who.global_position)
	return absf(local.x) < 0.95 and local.z > 0.45 and local.z < 1.9 and local.y > -0.2 and local.y < 2.4


func _sit(player: Player, seat: int) -> void:
	if seat < 0:
		seat = open_seat_for(player)
	if seat < 0 or occupants[seat] != null or not _can_join(player):
		return
	if not _near_chair(player, seat) and not _near_table(player):
		return
	var buy := _buy_in(player)
	if buy < BUY_IN:
		return
	occupants[seat] = player
	stacks[seat] = buy
	wallets[seat] = player.wallet()
	player.poker.bind(self, seat)
	_place(player, seat)
	PokerPlay.on_seated(self)
	_broadcast_state()


func _buy_in(player: Player) -> int:
	var card = player.wallet()
	if card == null:
		return 0
	if int(card.money) < BUY_IN or not card.try_spend(BUY_IN):
		return 0
	return BUY_IN


func _place(player: Player, seat: int) -> void:
	var chair := chairs[seat]
	var at := chair.global_position
	at.y = global_position.y
	var yaw := rad_to_deg(chair.global_transform.basis.get_euler().y)
	player.spawn_at(at, yaw)


func _stand_player(player: Player) -> void:
	var seat := _seated_player(player)
	if seat < 0:
		return
	if hand != null and not hand.over:
		hand.apply(seat, "fold")
		sync_stacks()
	clear_seat(seat, true)
	PokerPlay.on_left(self)
	_broadcast_state()


func _act(player: Player, op: String, raise_to: int) -> void:
	if phase != Phase.PLAYING or hand == null or hand.over:
		return
	var seat := _seated_player(player)
	if seat < 0:
		return
	var line := PokerPlay.describe(self, seat, op, raise_to)
	if not hand.apply(seat, op, raise_to):
		return
	toss_last(seat)
	last_act = line
	sync_stacks()
	timer = ACT_SEC
	if hand.over:
		PokerPlay.begin_show(self)
	_broadcast_state()


func _side_bet(player: Player, seat: int, amount: int) -> void:
	if phase != Phase.BETTING or occupants[seat] == null or amount <= 0:
		return
	if _seated_player(player) >= 0:
		return
	amount = PokerHand.snap_chips(amount)
	if not bets.place(player, seat, amount):
		return
	toss_from(player.global_position + Vector3(0.0, 0.9, 0.0), amount)
	_broadcast_state()


func clear_seat(seat: int, pay: bool) -> void:
	var who = occupants[seat]
	if pay and wallets[seat] != null and wallets[seat].has_method("credit"):
		wallets[seat].credit(stacks[seat])
	if who is Player:
		var player := who as Player
		player.poker.clear()
		_step_off(player, seat)
	occupants[seat] = null
	stacks[seat] = 0
	wallets[seat] = null


func _step_off(player: Player, seat: int) -> void:
	if player == null or seat < 0 or seat >= chairs.size():
		return
	var chair := chairs[seat]
	var out := chair.global_position - global_position
	out.y = 0.0
	if out.length() < 0.05:
		out = Vector3(0.0, 0.0, 1.0)
	var at := chair.global_position + out.normalized() * (USE_RANGE + 0.35)
	at.y = global_position.y
	player.spawn_at(at, rad_to_deg(chair.global_transform.basis.get_euler().y))


func filled() -> int:
	var n := 0
	for seat in 2:
		if occupants[seat] != null:
			n += 1
	return n


func sync_stacks() -> void:
	if hand != null:
		stacks = [hand.stacks[0], hand.stacks[1]]


func toss_blinds() -> void:
	if hand == null:
		return
	toss_chips(button, hand.street_bet[button])
	toss_chips(1 - button, hand.street_bet[1 - button])


func toss_last(seat: int) -> void:
	if hand != null and hand.last_put >= PokerHand.CHIP:
		toss_chips(seat, hand.last_put)


func toss_chips(seat: int, amount: int) -> void:
	if _chips == null or _chips.throw_seat(self, seat, amount) <= 0:
		return
	_replicate_toss(amount, seat)


func toss_from(at: Vector3, amount: int) -> void:
	if _chips == null or _chips.throw_from(at, amount) <= 0:
		return
	_replicate_toss(amount, -1, at)


func clear_chips() -> void:
	if _chips != null:
		_chips.clear()


func _replicate_toss(amount: int, seat: int, at := Vector3.ZERO) -> void:
	if not NetSession.is_active() or not multiplayer.is_server():
		return
	_replicate_chips.rpc(seat, amount, at)


@rpc("authority", "call_remote", "unreliable")
func _replicate_chips(seat: int, amount: int, at: Vector3) -> void:
	if _chips == null:
		return
	if seat >= 0:
		_chips.throw_seat(self, seat, amount)
	else:
		_chips.throw_from(at, amount)


func _seated_player(who: Node) -> int:
	for seat in 2:
		if occupants[seat] == who:
			return seat
	return -1


func _player_name(player: Player) -> String:
	if player.body_color == Palette.PLAYER_TWO:
		return "Amber"
	return "Cyan"


func _broadcast_state() -> void:
	if not NetSession.is_active() or not multiplayer.is_server():
		return
	for peer_id in multiplayer.get_peers():
		_replicate_state.rpc_id(peer_id, PokerNet.snapshot(self, peer_id))


@rpc("authority", "call_remote", "reliable")
func _replicate_state(payload: Dictionary) -> void:
	PokerNet.apply(self, payload)


@rpc("any_peer", "reliable")
func _request_sit(peer_id: int, seat: int) -> void:
	if not multiplayer.is_server():
		return
	var who := _player_for(peer_id)
	if who is Player:
		_sit(who, seat)


@rpc("any_peer", "reliable")
func _request_stand(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var who := _player_for(peer_id)
	if who is Player:
		_stand_player(who)


@rpc("any_peer", "reliable")
func _request_act(peer_id: int, op: String, raise_to: int) -> void:
	if not multiplayer.is_server():
		return
	var who := _player_for(peer_id)
	if who is Player:
		_act(who, op, raise_to)


@rpc("any_peer", "reliable")
func _request_bet(peer_id: int, seat: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var who := _player_for(peer_id)
	if who is Player:
		_side_bet(who, seat, amount)


@rpc("any_peer", "reliable")
func _request_skip(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var who := _player_for(peer_id)
	if who is Player and _seated_player(who) >= 0:
		PokerPlay.skip_bets(self)
		_broadcast_state()


func _replay(player: Player, yes: bool) -> void:
	var seat := _seated_player(player)
	if seat < 0:
		return
	PokerPlay.vote_replay(self, seat, yes)
	_broadcast_state()


@rpc("any_peer", "reliable")
func _request_replay(peer_id: int, yes: bool) -> void:
	if not multiplayer.is_server():
		return
	var who := _player_for(peer_id)
	if who is Player:
		_replay(who, yes)


func _player_for(peer_id: int) -> Node:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("players"):
		if int(node.get("peer_id")) == peer_id:
			return node
	return null
