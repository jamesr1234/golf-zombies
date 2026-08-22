class_name Buzz
extends RefCounted
## Beers in hand and beers already chugged. Each sip lasts a fixed window, so
## stacking is just how many timers are still running. Past three active beers
## the first-person view starts to go, and every extra sip makes it worse.

const PRICE := 30
const DURATION := 30.0
const BLUR_AFTER := 3
const PER_BEER := 0.12
const SPLIT_PER_EXTRA := 0.011
const BLUR_PER_EXTRA := 2.2
const SWAY_PER_EXTRA := 0.035
const FOV_PER_EXTRA := 4.0
const FOV_CAP := 18.0
const EXTRA_CAP := 8
const CHUG_KICK := 7.5

var held := 0
var _sips: PackedFloat32Array = PackedFloat32Array()


func take(count := 1) -> void:
	held += maxi(0, count)


func spend() -> bool:
	if held <= 0:
		return false
	held -= 1
	return true


func chug() -> bool:
	if not spend():
		return false
	_sips.append(DURATION)
	return true


func tick(delta: float) -> void:
	if _sips.is_empty():
		return
	var next := PackedFloat32Array()
	for left in _sips:
		var remain := left - delta
		if remain > 0.0:
			next.append(remain)
	_sips = next


func active() -> int:
	return _sips.size()


func extra_beers() -> int:
	return extra_from(active())


func boost_mult() -> float:
	return boost_from(active())


func strength_mult() -> float:
	return boost_mult()


func weapon_mult() -> float:
	return boost_mult()


func cart_mult() -> float:
	return boost_mult()


func split_amount() -> float:
	return float(extra_beers()) * SPLIT_PER_EXTRA


func blur_amount() -> float:
	return float(extra_beers()) * BLUR_PER_EXTRA


func sway_amount() -> float:
	return float(extra_beers()) * SWAY_PER_EXTRA


func fov_bump() -> float:
	return minf(FOV_CAP, float(extra_beers()) * FOV_PER_EXTRA)


func longest_sip() -> float:
	var best := 0.0
	for left in _sips:
		best = maxf(best, left)
	return best


static func boost_from(beers: int) -> float:
	return 1.0 + PER_BEER * float(maxi(0, beers))


static func extra_from(beers: int) -> int:
	return mini(EXTRA_CAP, maxi(0, beers - BLUR_AFTER))


static func can_afford(money: int) -> bool:
	return money >= PRICE
