class_name PokerEval
extends Object
## 5–7 card ranks for heads-up Hold'em. Higher int wins; equal ints split.

const RANKS := ["2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"]
const SUITS := ["C", "D", "H", "S"]


static func rank(card: int) -> int:
	return posmod(card, 13)


static func suit(card: int) -> int:
	return int(card / 13.0)


static func label(card: int) -> String:
	return RANKS[rank(card)] + SUITS[suit(card)]


static func labels(cards: Array) -> String:
	var parts: PackedStringArray = []
	for card in cards:
		parts.append(label(int(card)))
	return " ".join(parts)


## Best 5-card rank in a 5–7 card set. 0 if there are not enough cards.
static func best(cards: Array) -> int:
	var n := cards.size()
	if n < 5:
		return 0
	if n == 5:
		return five(cards)
	var top := 0
	if n == 6:
		for skip in 6:
			var pick: Array = []
			for i in 6:
				if i != skip:
					pick.append(cards[i])
			top = maxi(top, five(pick))
		return top
	for a in n:
		for b in range(a + 1, n):
			var pick: Array = []
			for i in n:
				if i != a and i != b:
					pick.append(cards[i])
			top = maxi(top, five(pick))
	return top


static func five(cards: Array) -> int:
	var ranks: Array[int] = []
	var suits: Array[int] = []
	for card in cards:
		ranks.append(rank(int(card)))
		suits.append(suit(int(card)))
	var flush := (
		suits[0] == suits[1]
		and suits[0] == suits[2]
		and suits[0] == suits[3]
		and suits[0] == suits[4]
	)
	var straight := _straight_high(ranks)
	if flush and straight >= 0:
		return _pack(8, [straight])
	var groups := _groups(ranks)
	if groups[0].x == 4:
		return _pack(7, [groups[0].y, groups[1].y])
	if groups[0].x == 3 and groups.size() > 1 and groups[1].x >= 2:
		return _pack(6, [groups[0].y, groups[1].y])
	if flush:
		return _pack(5, _sorted_desc(ranks))
	if straight >= 0:
		return _pack(4, [straight])
	if groups[0].x == 3:
		return _pack(3, [groups[0].y] + _rest_ranks(groups))
	if groups[0].x == 2 and groups.size() > 1 and groups[1].x == 2:
		return _pack(2, [groups[0].y, groups[1].y, groups[2].y])
	if groups[0].x == 2:
		return _pack(1, [groups[0].y] + _rest_ranks(groups))
	return _pack(0, _sorted_desc(ranks))


static func _pack(category: int, kickers: Array) -> int:
	var value := category << 20
	for i in mini(5, kickers.size()):
		value |= (int(kickers[i]) & 15) << (16 - i * 4)
	return value


static func _straight_high(ranks: Array[int]) -> int:
	var bits := 0
	for r in ranks:
		bits |= 1 << r
	if _bit_count(bits) != 5:
		return -1
	if bits == (1 << 12) | 15:
		return 3
	for high in range(12, 3, -1):
		var mask := 0
		for i in 5:
			mask |= 1 << (high - i)
		if bits == mask:
			return high
	return -1


static func _bit_count(bits: int) -> int:
	var n := 0
	var v := bits
	while v > 0:
		n += v & 1
		v >>= 1
	return n


static func _groups(ranks: Array[int]) -> Array[Vector2i]:
	var counts := {}
	for r in ranks:
		counts[r] = int(counts.get(r, 0)) + 1
	var groups: Array[Vector2i] = []
	for r in counts:
		groups.append(Vector2i(int(counts[r]), int(r)))
	groups.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x != b.x:
			return a.x > b.x
		return a.y > b.y
	)
	return groups


static func _rest_ranks(groups: Array[Vector2i]) -> Array[int]:
	var rest: Array[int] = []
	for i in range(1, groups.size()):
		rest.append(groups[i].y)
	return rest


static func _sorted_desc(ranks: Array[int]) -> Array[int]:
	var copy := ranks.duplicate()
	copy.sort()
	copy.reverse()
	return copy
