class_name SwingMeter
extends RefCounted
## Three-click swing timing, kept free of the scene tree so it can be tested.
##
## Click one starts the backswing, click two at the top sets the power, click
## three at the bottom sets the contact. A fast tap-tap is a short shot, which
## is the only way to play short distances with a single club.

enum State { READY, BACKSWING, DOWNSWING, DONE }

const BACKSWING_SPEED := 2.1
const DOWNSWING_SPEED := 2.7
## How far past the sweet spot the club can travel and still make contact.
const CONTACT_WINDOW := 0.16
const MAX_DEVIATION_DEG := 11.0
const MISS_DEVIATION_DEG := 22.0
const MISS_POWER_LOSS := 0.35
const MIN_POWER := 0.05

var state: State = State.READY
var value := 0.0
var power := 0.0
## Signed aim error in degrees: positive slices right, negative hooks left.
var deviation_deg := 0.0
var mishit := false
var kit: ClubKit = ClubKit.starter()


func reset() -> void:
	state = State.READY
	value = 0.0
	power = 0.0
	deviation_deg = 0.0
	mishit = false


func is_swinging() -> bool:
	return state == State.BACKSWING or state == State.DOWNSWING


func is_done() -> bool:
	return state == State.DONE


func click() -> void:
	match state:
		State.READY:
			state = State.BACKSWING
			value = 0.0
		State.BACKSWING:
			power = maxf(MIN_POWER, value)
			state = State.DOWNSWING
		State.DOWNSWING:
			_finish_on_contact()


func tick(delta: float) -> void:
	match state:
		State.BACKSWING:
			value += BACKSWING_SPEED * delta
			if value >= 1.0:
				value = 1.0
				power = 1.0
				state = State.DOWNSWING
		State.DOWNSWING:
			value -= DOWNSWING_SPEED * delta
			if value <= -_contact_window():
				_finish_missed()


## Takes a swing that was timed on someone else's machine. The golfer runs their
## own meter, so the host has to hold what arrives to what a real swing can
## produce before it strikes: no club sends a ball further than a full backswing,
## and a shank tops out at MISS_DEVIATION_DEG.
func accept_remote(p_power: float, p_deviation_deg: float) -> void:
	power = clampf(p_power, MIN_POWER, 1.0) if is_finite(p_power) else MIN_POWER
	deviation_deg = (
		clampf(p_deviation_deg, -MISS_DEVIATION_DEG, MISS_DEVIATION_DEG)
		if is_finite(p_deviation_deg) else 0.0
	)


func _contact_window() -> float:
	return CONTACT_WINDOW * kit.contact_scale


func _finish_on_contact() -> void:
	var error := clampf(value / _contact_window(), -1.0, 2.0)
	deviation_deg = error * MAX_DEVIATION_DEG * kit.deviation_scale
	power = maxf(MIN_POWER, power * (1.0 - 0.2 * absf(error) * kit.mishit_power_scale))
	mishit = absf(error) > 1.0
	state = State.DONE


func _finish_missed() -> void:
	deviation_deg = MISS_DEVIATION_DEG * kit.deviation_scale
	power = maxf(MIN_POWER, power * (1.0 - MISS_POWER_LOSS * kit.mishit_power_scale))
	mishit = true
	state = State.DONE
