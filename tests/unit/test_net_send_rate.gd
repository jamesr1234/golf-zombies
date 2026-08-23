extends GutTest
## Send intervals have to clear a physics-tick boundary. A value a hair above one
## costs a whole extra tick, which is how the pawn rate quietly became 20 Hz.

const TICK := 1.0 / 60.0


## What the synchronizer actually does: hold the send until an accumulated whole
## number of ticks reaches the interval.
func _ticks_between_sends(interval: float) -> int:
	var ticks := 1
	while float(ticks) * TICK < interval:
		ticks += 1
		if ticks > 60:
			break
	return ticks


func test_pawns_and_carts_send_every_second_tick() -> void:
	assert_eq(_ticks_between_sends(NetSync.PAWN_HZ), 2, "pawns are meant to run at 30 Hz")
	assert_eq(_ticks_between_sends(NetSync.CART_HZ), 2, "carts cover ground fastest")


func test_balls_and_zombies_send_every_third_tick() -> void:
	assert_eq(_ticks_between_sends(NetSync.BALL_HZ), 3)
	assert_eq(_ticks_between_sends(NetSync.ZOMBIE_HZ), 3)


## The regression itself: 0.034 reads as just past two ticks and buys a third.
func test_an_interval_just_past_a_tick_costs_a_whole_extra_one() -> void:
	assert_eq(_ticks_between_sends(0.034), 3, "the old pawn rate was really 20 Hz")
	assert_eq(_ticks_between_sends(0.03), 2, "clearing the boundary keeps it at 30 Hz")


## Landing exactly on a boundary is the same trap, since the accumulated ticks can
## fall a float hair short.
func test_every_interval_clears_its_boundary_by_a_margin() -> void:
	for named in [
		["PAWN_HZ", NetSync.PAWN_HZ], ["BALL_HZ", NetSync.BALL_HZ],
		["ZOMBIE_HZ", NetSync.ZOMBIE_HZ], ["CART_HZ", NetSync.CART_HZ],
	]:
		var interval: float = named[1]
		var boundary := float(_ticks_between_sends(interval)) * TICK
		assert_gt(
			boundary - interval, 0.002,
			"%s sits on a tick boundary and may cost an extra tick" % named[0]
		)
