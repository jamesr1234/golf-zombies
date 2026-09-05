class_name CreatorPad
extends RefCounted
## Every command the creator answers to, and the two ways of asking: a physical
## key or a controller button. Both dispatch into the same CreatorMode methods,
## so a command can never mean one thing on the keyboard and another on the pad.
##
## The pad is polled through PadInput, which reads only joypad bindings. Sharing
## whole actions would double up, since the gameplay map already puts several of
## these on the very keys the creator uses.
##
## D-pad walks the list you can see. Shoulders change the tool. Circle does the
## extra the current tool needs (weapon line, or merge). Options is the rest.

const BUTTONS: PackedStringArray = [
	"shoot", "aim", "melee", "shield", "swap_weapon_prev", "swap_weapon",
	"grapple", "swap_gear", "reload", "interact", "pause", "sprint", "zoom",
]

const HINT := (
	"1 2 3 TOOL   Q/E LIST   TAB SHELF   R TURN   F DO   T SNAP"
	+ "   Y ROTATE SNAP   BKSP UNDO   ESC MENU"
)
const PAD_HINT := (
	"R2 PLACE   L2 UNDO   D-PAD LIST / TURN   L1/R1 TOOL   SQUARE SHELF"
	+ "   CIRCLE DO   L3 SURFACE   R3 ROTATE SNAP   TRIANGLE UP   CROSS DOWN"
	+ "   OPTIONS MENU"
)

var _host: CreatorMode
var _pad := PadInput.new()
var _keys: Dictionary = {}


func _init(for_host: CreatorMode) -> void:
	_host = for_host
	_keys = {
		KEY_1: func(_k: InputEventKey) -> void: _host.switch_tool(CreatorMode.Tool.FAIRWAY),
		KEY_2: func(_k: InputEventKey) -> void: _host.switch_tool(CreatorMode.Tool.PLACE),
		KEY_3: func(_k: InputEventKey) -> void: _host.switch_tool(CreatorMode.Tool.GROUP),
		KEY_Q: func(_k: InputEventKey) -> void: _host.step_piece(-1),
		KEY_E: func(_k: InputEventKey) -> void: _host.step_piece(1),
		KEY_TAB: func(k: InputEventKey) -> void: _host.step_shelf(-1 if k.shift_pressed else 1),
		KEY_R: func(k: InputEventKey) -> void:
			if not _host.spins_free():
				_host.turn(-1 if k.shift_pressed else 1),
		KEY_F: func(_k: InputEventKey) -> void: _host.context(),
		KEY_L: func(_k: InputEventKey) -> void: _host.draw_weapon_line(),
		KEY_BACKSPACE: func(_k: InputEventKey) -> void: _host.cancel(),
		KEY_G: func(_k: InputEventKey) -> void: _host.ask_group(),
		KEY_T: func(_k: InputEventKey) -> void: _host.snap_surface(),
		KEY_Y: func(_k: InputEventKey) -> void: _host.toggle_yaw_snap(),
		KEY_S: _ask_save,
		KEY_P: func(_k: InputEventKey) -> void: _host.playtest(),
		KEY_ESCAPE: func(_k: InputEventKey) -> void: _host.toggle_menu(),
	}


func on_key(key: InputEventKey) -> void:
	var action = _keys.get(key.physical_keycode)
	if action != null:
		action.call(key)


## Read every button before acting on any, so a press is never swallowed by an
## earlier branch skipping the poll that tracks its down edge. Buttons are still
## read while the name pad has the controller, and thrown away, so releasing
## Circle on the keypad does not place a piece the moment it closes.
func poll(active := true, delta := 0.0) -> void:
	var fired: Dictionary = {}
	for suffix in BUTTONS:
		fired[suffix] = _pad.just(suffix)
	if not active:
		return
	if fired["pause"]:
		_host.toggle_menu()
		return
	if _host.menu_is_open():
		_drive_menu(fired, delta)
		return
	if fired["shoot"]:
		_host.confirm()
	if fired["aim"]:
		_host.cancel()
	if fired["swap_weapon_prev"]:
		_host.step_piece(-1)
	if fired["swap_weapon"]:
		_host.step_piece(1)
	if fired["melee"]:
		_host.cycle_tool(-1)
	if fired["shield"]:
		_host.cycle_tool(1)
	if _host.spins_free():
		_host.spin(_held_turn(), delta)
	else:
		if fired["grapple"]:
			_host.side(-1)
		if fired["swap_gear"]:
			_host.side(1)
	if fired["reload"]:
		_host.step_shelf(1)
	if fired["interact"]:
		_host.context()
	if fired["sprint"]:
		_host.snap_surface()
	if fired["zoom"]:
		_host.toggle_yaw_snap()


func _held_turn() -> float:
	var dir := 0.0
	if PadInput.pressed("swap_gear"):
		dir += 1.0
	if PadInput.pressed("grapple"):
		dir -= 1.0
	if Input.is_physical_key_pressed(KEY_R):
		dir += -1.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	return dir


func _drive_menu(fired: Dictionary, delta: float) -> void:
	if fired["swap_weapon_prev"]:
		_host.move_menu(-1)
	if fired["swap_weapon"]:
		_host.move_menu(1)
	var stick := _pad.repeat_dir(delta)
	if stick.y != 0:
		_host.move_menu(stick.y)
	if fired["shoot"] or fired["interact"]:
		_host.pick_menu()


## Plain S walks the camera backwards, so saving is the chord.
func _ask_save(key: InputEventKey) -> void:
	if key.ctrl_pressed or key.meta_pressed:
		_host.ask_save()
