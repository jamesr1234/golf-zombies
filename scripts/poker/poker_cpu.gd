class_name PokerCpu
extends Object
## Legal Hold'em actions. Seed the RNG to keep picks deterministic in tests.


static func pick(hand: PokerHand, seat: int, rng: RandomNumberGenerator) -> Dictionary:
	if hand == null or rng == null or hand.over or hand.to_act != seat:
		return {}
	var strength := hole_strength(hand.hole[seat])
	if hand.can_check(seat):
		var targets := hand.raise_targets(seat)
		if strength >= 0.55 and not targets.is_empty() and rng.randf() < 0.35:
			return {"op": "raise", "to": targets[0]}
		return {"op": "check"}
	if strength < 0.22 and rng.randf() < 0.7:
		return {"op": "fold"}
	if strength >= 0.62:
		var raises := hand.raise_targets(seat)
		if not raises.is_empty() and rng.randf() < 0.45:
			var idx := 0 if rng.randf() < 0.7 else raises.size() - 1
			return {"op": "raise", "to": raises[idx]}
	return {"op": "call"}


static func hole_strength(cards: Array) -> float:
	if cards.size() < 2:
		return 0.0
	var a := PokerEval.rank(int(cards[0]))
	var b := PokerEval.rank(int(cards[1]))
	var suited := PokerEval.suit(int(cards[0])) == PokerEval.suit(int(cards[1]))
	var hi := maxi(a, b)
	var lo := mini(a, b)
	var score := hi / 12.0 * 0.45 + lo / 12.0 * 0.15
	if a == b:
		score = 0.55 + a / 12.0 * 0.4
	elif suited:
		score += 0.08
	if hi - lo == 1:
		score += 0.06
	return clampf(score, 0.0, 1.0)
