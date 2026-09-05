class_name PadInput
extends RefCounted
## Reads the controller half of the p1/p2 action map, and only that half.
##
## The creator and the hole browser bind their own keys. If they also listened
## to whole actions, one press of R would both turn a piece and change the
## shelf, because the gameplay map already puts reload on R. Looking only at the
## joypad events registered for an action keeps input_actions.gd the single
## place buttons are chosen while leaving each screen's keyboard to itself.
##
## Poll once per frame per action: the down edge is tracked here.

const PREFIXES: PackedStringArray = ["p1_", "p2_"]
const STICK_GATE := 0.55
const REPEAT_FIRST := 0.32
const REPEAT_AGAIN := 0.14

var _held: Dictionary = {}
var _repeat_dir := Vector2i.ZERO
var _repeat_wait := 0.0


## True on the frame a pad button or trigger for this action goes down.
## The first sample is only a rest pose: a button still held from the last
## screen must not fire the moment this one opens.
func just(suffix: String) -> bool:
	return _rose(suffix, pressed(suffix))


func _rose(suffix: String, down: bool) -> bool:
	if not _held.has(suffix):
		_held[suffix] = down
		return false
	var was: bool = _held[suffix]
	_held[suffix] = down
	return down and not was


static func pressed(suffix: String) -> bool:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return false
	for prefix in PREFIXES:
		var action := prefix + suffix
		if not InputMap.has_action(action):
			continue
		if _action_down(action, pads):
			return true
	return false


static func _action_down(action: String, pads: Array[int]) -> bool:
	var deadzone := InputMap.action_get_deadzone(action)
	for event in InputMap.action_get_events(action):
		for device in pads:
			if _event_down(event, device, deadzone):
				return true
	return false


static func _event_down(event: InputEvent, device: int, deadzone: float) -> bool:
	var button := event as InputEventJoypadButton
	if button != null:
		return Input.is_joy_button_pressed(device, button.button_index)
	var motion := event as InputEventJoypadMotion
	if motion == null:
		return false
	var value := Input.get_joy_axis(device, motion.axis)
	if signf(value) != signf(motion.axis_value):
		return false
	return absf(value) >= maxf(deadzone, 0.1)


## Left stick only, so a keyboard letter never walks a menu or keypad.
static func joy_move() -> Vector2:
	var best := Vector2.ZERO
	for device in Input.get_connected_joypads():
		var stick := Vector2(
			Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
		)
		if stick.length_squared() > best.length_squared():
			best = stick
	return best


## One cell per press, then a slow repeat if the stick is held.
func repeat_dir(delta: float) -> Vector2i:
	var wish := joy_move()
	var next := Vector2i.ZERO
	if wish.x >= STICK_GATE:
		next.x = 1
	elif wish.x <= -STICK_GATE:
		next.x = -1
	if wish.y >= STICK_GATE:
		next.y = 1
	elif wish.y <= -STICK_GATE:
		next.y = -1
	if next == Vector2i.ZERO:
		_repeat_dir = Vector2i.ZERO
		_repeat_wait = 0.0
		return Vector2i.ZERO
	if next != _repeat_dir:
		_repeat_dir = next
		_repeat_wait = REPEAT_FIRST
		return next
	_repeat_wait -= delta
	if _repeat_wait > 0.0:
		return Vector2i.ZERO
	_repeat_wait = REPEAT_AGAIN
	return next
