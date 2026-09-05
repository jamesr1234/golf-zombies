class_name SwingMeter
extends RefCounted
## Three-click swing timing, kept free of the scene tree so it can be tested.
##
## Click one starts the backswing. The meter then travels up and down until
## click two locks the power. Click three at the bottom sets the contact. Miss
## that last click and the shot mishits badly. A fast tap-tap is a short shot,
## which is the only way to play short distances with a single club.

enum State { READY, BACKSWING, DOWNSWING, DONE }

const BACKSWING_SPEED := 2.1
const DOWNSWING_SPEED := 2.7
## How far past the sweet spot the club can travel and still make contact.
const CONTACT_WINDOW := 0.16
## Click inside this of 1.0 for a full-power lock.
const POWER_SWEET := 0.09
## Click inside this of 0.0 for a pure strike.
const CONTACT_SWEET := 0.07
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
var sweet := false
var kit: ClubKit = ClubKit.starter()
var _rising := true


func reset() -> void:
	state = State.READY
	value = 0.0
	power = 0.0
	deviation_deg = 0.0
	mishit = false
	sweet = false
	_rising = true


func is_swinging() -> bool:
	return state == State.BACKSWING or state == State.DOWNSWING


func is_done() -> bool:
	return state == State.DONE


func click() -> void:
	match state:
		State.READY:
			state = State.BACKSWING
			value = 0.0
			_rising = true
		State.BACKSWING:
			power = 1.0 if _in_power_sweet() else maxf(MIN_POWER, value)
			state = State.DOWNSWING
		State.DOWNSWING:
			_finish_on_contact()


func tick(delta: float) -> void:
	match state:
		State.BACKSWING:
			value += BACKSWING_SPEED * delta * (1.0 if _rising else -1.0)
			if value >= 1.0:
				value = 1.0
				_rising = false
			elif value <= 0.0:
				value = 0.0
				_rising = true
		State.DOWNSWING:
			value -= DOWNSWING_SPEED * delta
			if value <= -_contact_window():
				_finish_missed()


func _contact_window() -> float:
	return CONTACT_WINDOW * kit.contact_scale


func _contact_sweet() -> float:
	return CONTACT_SWEET * kit.contact_scale


func _in_power_sweet() -> bool:
	return value >= 1.0 - POWER_SWEET


func _in_contact_sweet() -> bool:
	return absf(value) <= _contact_sweet()


func _finish_on_contact() -> void:
	if _in_contact_sweet():
		deviation_deg = 0.0
		sweet = true
		mishit = false
		state = State.DONE
		return
	var error := clampf(value / _contact_window(), -1.0, 2.0)
	deviation_deg = error * MAX_DEVIATION_DEG * kit.deviation_scale
	power = maxf(MIN_POWER, power * (1.0 - 0.2 * absf(error) * kit.mishit_power_scale))
	mishit = absf(error) > 1.0
	sweet = false
	state = State.DONE


func _finish_missed() -> void:
	deviation_deg = MISS_DEVIATION_DEG * kit.deviation_scale
	power = maxf(MIN_POWER, power * (1.0 - MISS_POWER_LOSS * kit.mishit_power_scale))
	mishit = true
	sweet = false
	state = State.DONE
