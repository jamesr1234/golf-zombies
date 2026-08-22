class_name CpuInput
extends PlayerInput
## Drop-in pad for a CPU player. The brain writes sticks and buttons each frame;
## nothing here reads the keyboard or a controller.

var move := Vector2.ZERO
var look := Vector2.ZERO

var _held := {}
var _taps := {}
var _released := {}


func begin_frame() -> void:
	move = Vector2.ZERO
	look = Vector2.ZERO
	_held.clear()
	_taps.clear()
	_released.clear()


func hold(name: String, on := true) -> void:
	_held[name] = on


func tap(name: String) -> void:
	_taps[name] = true
	_held[name] = true


func release(name: String) -> void:
	_released[name] = true
	_held[name] = false


func pressed(name: String) -> bool:
	return _held.get(name, false)


func just_pressed(name: String) -> bool:
	return _taps.get(name, false)


func just_released(name: String) -> bool:
	return _released.get(name, false)


func move_vector() -> Vector2:
	return move.limit_length(1.0)


func stick_look() -> Vector2:
	return look.limit_length(1.0)
