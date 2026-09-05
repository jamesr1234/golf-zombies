class_name InputActions
extends Object
## Registers the p1_* and p2_* action pairs. Solo maps the pad onto p2 with any
## device. Co-op is one pad and the keyboard: player 1 is the controller, player 2
## is WASD and the mouse.

const STICK_DEADZONE := 0.25
const TRIGGER_DEADZONE := 0.4

const ACTIONS: PackedStringArray = [
	"move_left", "move_right", "move_forward", "move_back",
	"look_left", "look_right", "look_up", "look_down",
	"sprint", "jump", "shoot", "aim", "zoom", "slide", "reload", "melee", "swap_weapon",
	"swap_weapon_prev", "swap_gear", "swap_gear_prev",
	"interact", "revive", "swing", "pause", "map", "ascend", "grab", "shield",
	"grapple",
]


static func register_all() -> void:
	register_for_mode(_current_mode())


static func register_for_mode(mode: int) -> void:
	for suffix in ACTIONS:
		_declare("p1_" + suffix)
		_declare("p2_" + suffix)
	# Wipe both seats clean. Surgical strip can leave leftover stick axes from
	# the title screen's solo map, which then turns both bodies with one pad.
	_clear_prefix("p1")
	_clear_prefix("p2")
	if mode == GameSettings.Mode.COOP:
		_register_keyboard("p2")
		_ensure_keyboard_overrides("p2")
		_register_gamepad_for("p1", -1)
	elif mode == GameSettings.Mode.ONLINE_VS or mode == GameSettings.Mode.ONLINE_COOP_VS:
		_register_keyboard("p1")
		_ensure_keyboard_overrides("p1")
		_register_gamepad_for("p1", -1)
	else:
		_register_keyboard("p1")
		_ensure_keyboard_overrides("p1")
		_register_gamepad_for("p2", -1)


static func _current_mode() -> int:
	return GameSettings.mode


static func _declare(action: String, deadzone := STICK_DEADZONE) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)


static func _register_keyboard(prefix: String) -> void:
	_key(prefix + "_move_left", KEY_A)
	_key(prefix + "_move_right", KEY_D)
	_key(prefix + "_move_forward", KEY_W)
	_key(prefix + "_move_back", KEY_S)
	_key(prefix + "_sprint", KEY_SHIFT)
	_key(prefix + "_jump", KEY_SPACE)
	_key(prefix + "_reload", KEY_R)
	_key(prefix + "_melee", KEY_Q)
	_key(prefix + "_swap_weapon", KEY_TAB)
	_key(prefix + "_swap_gear", KEY_G)
	_key(prefix + "_interact", KEY_E)
	_key(prefix + "_revive", KEY_F)
	_key(prefix + "_map", KEY_M)
	_key(prefix + "_pause", KEY_ESCAPE)
	_key(prefix + "_shield", KEY_C)
	_key(prefix + "_grapple", KEY_V)
	_key(prefix + "_zoom", KEY_Z)
	_key(prefix + "_slide", KEY_Z)
	_mouse(prefix + "_shoot", MOUSE_BUTTON_LEFT)
	_mouse(prefix + "_swing", MOUSE_BUTTON_LEFT)
	_mouse(prefix + "_aim", MOUSE_BUTTON_RIGHT)
	_mouse(prefix + "_zoom", MOUSE_BUTTON_RIGHT)


static func _ensure_keyboard_overrides(prefix: String) -> void:
	_set_key(prefix + "_ascend", KEY_E)
	_set_key(prefix + "_grab", KEY_SPACE)
	_set_key(prefix + "_shield", KEY_C)
	_set_key(prefix + "_grapple", KEY_V)
	_set_key(prefix + "_swap_gear", KEY_G)
	_set_key(prefix + "_map", KEY_M)


static func _register_gamepad_for(prefix: String, device: int) -> void:
	_axis(prefix + "_move_left", JOY_AXIS_LEFT_X, -1.0, STICK_DEADZONE, device)
	_axis(prefix + "_move_right", JOY_AXIS_LEFT_X, 1.0, STICK_DEADZONE, device)
	_axis(prefix + "_move_forward", JOY_AXIS_LEFT_Y, -1.0, STICK_DEADZONE, device)
	_axis(prefix + "_move_back", JOY_AXIS_LEFT_Y, 1.0, STICK_DEADZONE, device)
	_axis(prefix + "_look_left", JOY_AXIS_RIGHT_X, -1.0, STICK_DEADZONE, device)
	_axis(prefix + "_look_right", JOY_AXIS_RIGHT_X, 1.0, STICK_DEADZONE, device)
	_axis(prefix + "_look_up", JOY_AXIS_RIGHT_Y, -1.0, STICK_DEADZONE, device)
	_axis(prefix + "_look_down", JOY_AXIS_RIGHT_Y, 1.0, STICK_DEADZONE, device)
	_axis(prefix + "_shoot", JOY_AXIS_TRIGGER_RIGHT, 1.0, TRIGGER_DEADZONE, device)
	_axis(prefix + "_swing", JOY_AXIS_TRIGGER_RIGHT, 1.0, TRIGGER_DEADZONE, device)
	_axis(prefix + "_aim", JOY_AXIS_TRIGGER_LEFT, 1.0, TRIGGER_DEADZONE, device)
	_button(prefix + "_sprint", JOY_BUTTON_LEFT_STICK, device)
	_button(prefix + "_zoom", JOY_BUTTON_RIGHT_STICK, device)
	_button(prefix + "_slide", JOY_BUTTON_RIGHT_STICK, device)
	_button(prefix + "_jump", JOY_BUTTON_A, device)
	_button(prefix + "_reload", JOY_BUTTON_X, device)
	_button(prefix + "_melee", JOY_BUTTON_LEFT_SHOULDER, device)
	_button(prefix + "_swap_weapon", JOY_BUTTON_DPAD_DOWN, device)
	_button(prefix + "_swap_weapon_prev", JOY_BUTTON_DPAD_UP, device)
	_button(prefix + "_swap_gear", JOY_BUTTON_DPAD_RIGHT, device)
	_button(prefix + "_grapple", JOY_BUTTON_DPAD_LEFT, device)
	_button(prefix + "_interact", JOY_BUTTON_B, device)
	_button(prefix + "_revive", JOY_BUTTON_Y, device)
	_button(prefix + "_map", JOY_BUTTON_Y, device)
	_button(prefix + "_pause", JOY_BUTTON_START, device)
	_button(prefix + "_shield", JOY_BUTTON_RIGHT_SHOULDER, device)
	_button(prefix + "_ascend", JOY_BUTTON_RIGHT_SHOULDER, device)
	_button(prefix + "_grab", JOY_BUTTON_B, device)


static func _clear_prefix(prefix: String) -> void:
	for suffix in ACTIONS:
		var action := "%s_%s" % [prefix, suffix]
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)


static func _set_key(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	_key(action, keycode)


static func _key(action: String, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


static func _mouse(action: String, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


static func _button(action: String, button: JoyButton, device := -1) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	InputMap.action_add_event(action, event)


static func _axis(
	action: String, axis: JoyAxis, value: float, deadzone := STICK_DEADZONE, device := -1
) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)
	InputMap.action_set_deadzone(action, deadzone)
