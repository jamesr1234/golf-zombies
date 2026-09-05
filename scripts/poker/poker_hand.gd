class_name PokerHand
extends RefCounted
## Heads-up no-limit Hold'em. Pure chips and cards; wallets stay on the table.

enum Street { PREFLOP, FLOP, TURN, RIVER, SHOWDOWN }

const CHIP := 10
const SMALL := 10
const BIG := 20

var stacks: Array[int] = [0, 0]
var button := 0
var street: Street = Street.PREFLOP
var pot := 0
var hole: Array = [[], []]
var board: Array[int] = []
var folded: Array[bool] = [false, false]
var street_bet: Array[int] = [0, 0]
var acted: Array[bool] = [false, false]
var to_act := 0
var last_raise := BIG
var over := false
var split := false
var winner_seat := -1
var last_put := 0
var deck: Array[int] = []


func start(
	p_stacks: Array, p_button: int, rng: RandomNumberGenerator = null, p_deck: Array = []
) -> void:
	stacks = [int(p_stacks[0]), int(p_stacks[1])]
	button = p_button
	street = Street.PREFLOP
	pot = 0
	hole = [[], []]
	board = []
	folded = [false, false]
	street_bet = [0, 0]
	acted = [false, false]
	over = false
	split = false
	winner_seat = -1
	last_put = 0
	last_raise = BIG
	if p_deck.is_empty():
		deck = []
		for card in 52:
			deck.append(card)
		_shuffle(rng)
	else:
		deck = []
		for card in p_deck:
			deck.append(int(card))
	_put(button, SMALL)
	_put(1 - button, BIG)
	for _r in 2:
		for seat in 2:
			hole[seat].append(_draw())
	to_act = button
	_advance_if_closed()


func street_name() -> String:
	match street:
		Street.PREFLOP:
			return "Preflop"
		Street.FLOP:
			return "Flop"
		Street.TURN:
			return "Turn"
		Street.RIVER:
			return "River"
		_:
			return "Showdown"


func to_call(seat: int) -> int:
	return maxi(street_bet[0], street_bet[1]) - street_bet[seat]


func can_check(seat: int) -> bool:
	return not over and to_call(seat) == 0


func raise_targets(seat: int) -> Array[int]:
	var out: Array[int] = []
	if over:
		return out
	var cap := street_bet[seat] + stacks[seat]
	var max_bet := maxi(street_bet[0], street_bet[1])
	if cap <= max_bet:
		return out
	var min_to := snap_up(max_bet + last_raise)
	if min_to < cap:
		out.append(min_to)
	var pot_to := snap_chips(max_bet + pot + to_call(seat))
	if pot_to > min_to and pot_to < cap:
		out.append(pot_to)
	out.append(cap)
	return out


static func chip_count(amount: int) -> int:
	return maxi(0, amount) / CHIP


static func snap_chips(amount: int) -> int:
	return maxi(0, amount / CHIP) * CHIP


static func snap_up(amount: int) -> int:
	if amount <= 0:
		return 0
	return ((amount + CHIP - 1) / CHIP) * CHIP


func apply(seat: int, op: String, raise_to := 0) -> bool:
	last_put = 0
	if over or seat != to_act or folded[seat]:
		return false
	if op == "fold":
		folded[seat] = true
		_win(1 - seat, false)
		return true
	if op == "check":
		if to_call(seat) != 0:
			return false
		acted[seat] = true
		_after_act()
		return true
	if op == "call":
		var need := to_call(seat)
		if need <= 0:
			return false
		_put(seat, need)
		acted[seat] = true
		_after_act()
		return true
	if op == "raise":
		return _raise(seat, raise_to)
	return false


func force_timeout(seat: int) -> void:
	if can_check(seat):
		apply(seat, "check")
	else:
		apply(seat, "fold")


static func side_credit(p_winner: int, p_split: bool, on_seat: int, amount: int) -> int:
	if amount <= 0:
		return 0
	if p_split or p_winner < 0:
		return amount
	if p_winner == on_seat:
		return amount * 2
	return 0


func _raise(seat: int, raise_to: int) -> bool:
	var cap := street_bet[seat] + stacks[seat]
	var max_bet := maxi(street_bet[0], street_bet[1])
	if cap <= max_bet:
		return false
	var min_to := snap_up(max_bet + last_raise)
	var to := raise_to
	if to >= cap:
		to = cap
	else:
		to = snap_chips(to)
	if to < min_to:
		return false
	var add := to - street_bet[seat]
	if add <= to_call(seat):
		return false
	_put(seat, add)
	last_raise = maxi(last_raise, street_bet[seat] - max_bet)
	acted[seat] = true
	acted[1 - seat] = false
	_after_act()
	return true


func _after_act() -> void:
	if over:
		return
	if _street_closed():
		_advance_if_closed()
		return
	to_act = 1 - to_act
	if stacks[to_act] == 0:
		_advance_if_closed()


func _advance_if_closed() -> void:
	if over:
		return
	if not _street_closed():
		return
	_refund_unmatched()
	if folded[0] or folded[1]:
		return
	if stacks[0] == 0 or stacks[1] == 0 or street == Street.RIVER:
		_runout_or_show()
		return
	_next_street()


func _street_closed() -> bool:
	if folded[0] or folded[1]:
		return true
	var matched := street_bet[0] == street_bet[1]
	var all_in := stacks[0] == 0 or stacks[1] == 0
	if not matched:
		if not all_in:
			return false
		var rich := 0 if stacks[0] > 0 else 1
		return stacks[rich] <= 0 or acted[rich]
	if all_in:
		return true
	return acted[0] and acted[1]


func _next_street() -> void:
	_deal_board()
	street_bet = [0, 0]
	acted = [false, false]
	last_raise = BIG
	to_act = 1 - button
	if stacks[to_act] == 0:
		to_act = button


func _deal_board() -> void:
	if street == Street.PREFLOP:
		for _i in 3:
			board.append(_draw())
		street = Street.FLOP
	elif street == Street.FLOP:
		board.append(_draw())
		street = Street.TURN
	elif street == Street.TURN:
		board.append(_draw())
		street = Street.RIVER


func _runout_or_show() -> void:
	while board.size() < 5 and not deck.is_empty() and street != Street.SHOWDOWN:
		if street == Street.PREFLOP or street == Street.FLOP or street == Street.TURN:
			_deal_board()
		else:
			break
	_showdown()


func _showdown() -> void:
	if folded[0]:
		_win(1, false)
		return
	if folded[1]:
		_win(0, false)
		return
	var a := PokerEval.best(hole[0] + board)
	var b := PokerEval.best(hole[1] + board)
	if a > b:
		_win(0, false)
	elif b > a:
		_win(1, false)
	else:
		_win(-1, true)


func _win(seat: int, p_split: bool) -> void:
	over = true
	street = Street.SHOWDOWN
	split = p_split
	winner_seat = seat
	if p_split:
		var half := pot / 2
		stacks[0] += half
		stacks[1] += pot - half
	elif seat >= 0:
		stacks[seat] += pot
	pot = 0


func _put(seat: int, amount: int) -> int:
	var pay := mini(maxi(0, amount), stacks[seat])
	stacks[seat] -= pay
	street_bet[seat] += pay
	pot += pay
	last_put = pay
	return pay


func _refund_unmatched() -> void:
	var extra := street_bet[0] - street_bet[1]
	if extra == 0:
		return
	var rich := 0 if extra > 0 else 1
	var take := absi(extra)
	street_bet[rich] -= take
	stacks[rich] += take
	pot -= take


func _draw() -> int:
	if deck.is_empty():
		return 0
	return deck.pop_back()


func _shuffle(rng: RandomNumberGenerator) -> void:
	var mix := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		mix.randomize()
	for i in range(deck.size() - 1, 0, -1):
		var j := mix.randi_range(0, i)
		var swap := deck[i]
		deck[i] = deck[j]
		deck[j] = swap
