class_name PlayerInput
extends RefCounted
## Thin wrapper that turns a bare action name into this player's prefixed one,
## so gameplay code never needs to know which device it is talking to.
##
## A solo human can also read the other seat's prefix, so the same body answers
## to WASD and the pad while the partner is a CPU.

## Button names for on-screen prompts, per device.
const HINTS := {
	"p1": {
		"interact": "E", "revive": "F", "swing": "Left Click", "shoot": "Left Click",
		"move": "WASD",
		"reload": "R", "melee": "Q", "swap_weapon": "Tab", "swap_gear": "G",
		"pause": "Esc",
		"map": "M", "ascend": "E", "descend": "Q", "grab": "Space", "shield": "C",
		"zoom": "Z / Right Click", "aim": "Right Click", "look": "Mouse",
		"grapple": "V", "jump": "Space", "sprint": "Shift", "slide": "Shift + Z",
	},
	"p2": {
		"interact": "Circle", "revive": "Triangle", "swing": "R2", "shoot": "R2",
		"move": "Left Stick",
		"reload": "Square", "melee": "L1",
		"swap_weapon": "D-Pad Up/Down", "swap_gear": "D-Pad Right",
		"pause": "Options",
		"map": "Triangle", "ascend": "R1", "descend": "L1", "grab": "Circle", "shield": "R1",
		"zoom": "R3", "aim": "L2", "look": "Right Stick",
		"grapple": "D-Pad Left", "jump": "Cross", "sprint": "L3",
		"slide": "Sprint + R3",
	},
}

var prefix: String
var uses_mouse: bool
var prefixes: PackedStringArray = PackedStringArray()


func _init(
	p_prefix: String, p_uses_mouse: bool, also: PackedStringArray = PackedStringArray()
) -> void:
	prefix = p_prefix
	uses_mouse = p_uses_mouse
	prefixes = PackedStringArray([p_prefix])
	for extra in also:
		if extra != p_prefix and extra not in prefixes:
			prefixes.append(extra)
	# Registration is idempotent, and doing it here means a world can be loaded
	# on its own (in a test, for instance) without the splitscreen root.
	InputActions.register_all()


func action(name: String) -> String:
	return "%s_%s" % [prefix, name]


func hint(name: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for which in _hint_order():
		var label: String = _hints_for(which).get(name, "")
		if label != "" and label not in parts:
			parts.append(label)
	if parts.is_empty():
		return name
	return " / ".join(parts)


func pressed(name: String) -> bool:
	for which in prefixes:
		if Input.is_action_pressed("%s_%s" % [which, name]):
			return true
	return false


func just_pressed(name: String) -> bool:
	for which in prefixes:
		if Input.is_action_just_pressed("%s_%s" % [which, name]):
			return true
	return false


func just_released(name: String) -> bool:
	for which in prefixes:
		if Input.is_action_just_released("%s_%s" % [which, name]):
			return true
	return false


func move_vector() -> Vector2:
	var combined := Vector2.ZERO
	for which in prefixes:
		combined += Input.get_vector(
			"%s_move_left" % which, "%s_move_right" % which,
			"%s_move_forward" % which, "%s_move_back" % which
		)
	return combined.limit_length(1.0)


## Right stick look, in units of "screen" motion per second. Keyboard players
## get their look from mouse motion events instead, so this returns zero unless
## a pad is also wired to this seat.
func stick_look() -> Vector2:
	var combined := Vector2.ZERO
	for which in prefixes:
		combined += Input.get_vector(
			"%s_look_left" % which, "%s_look_right" % which,
			"%s_look_up" % which, "%s_look_down" % which
		)
	return combined.limit_length(1.0)


func _hint_order() -> PackedStringArray:
	var ordered: PackedStringArray = PackedStringArray()
	if "p1" in prefixes:
		ordered.append("p1")
	for which in prefixes:
		if which not in ordered:
			ordered.append(which)
	return ordered


## Co-op puts the pad on p1 and the keyboard on p2. Solo keeps keyboard on p1.
static func _hints_for(prefix: String) -> Dictionary:
	var pad_on_p1 := GameSettings.mode == GameSettings.Mode.COOP
	if pad_on_p1:
		return HINTS["p2"] if prefix == "p1" else HINTS["p1"]
	return HINTS[prefix]
