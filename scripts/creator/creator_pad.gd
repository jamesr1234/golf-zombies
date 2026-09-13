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
## D-pad walks the list you can see. Shoulders change the tool. Circle parks a
## piece so you can walk around it, or draws a weapon line when a gun is down.
## Group Circle is merge. L1 held with Circle or Triangle walks history.
## Options is the rest. L1+R1 opens the pad command list.

const BUTTONS: PackedStringArray = [
	"shoot", "aim", "melee", "shield", "swap_weapon_prev", "swap_weapon",
	"grapple", "swap_gear", "reload", "interact", "pause", "sprint", "zoom",
]

const HINT := (
	"1 2 3 TOOL   Q/E LIST   TAB SHELF   R TURN   F HOLD   T SNAP"
	+ "   Y ROTATE SNAP   BKSP TAKE BACK   CTRL+Z UNDO   CTRL+Y REDO   ESC MENU"
	+ "   H HELP"
)
const PAD_HINT := (
	"R2 PLACE   L2 TAKE BACK   D-PAD LIST / TURN   L1/R1 TOOL   SQUARE SHELF"
	+ "   CIRCLE HOLD   L1+CIRCLE UNDO   L1+TRIANGLE REDO   L3 SURFACE"
	+ "   R3 ROTATE SNAP   TRIANGLE UP   CROSS DOWN   OPTIONS MENU"
	+ "   L1+R1 HELP"
)
const CHORD_FIRST := 0.32
const CHORD_AGAIN := 0.14

var _host: CreatorMode
var _pad := PadInput.new()
var _keys: Dictionary = {}
var _l1_held := false
var _l1_used := false
var _chord := 0
var _chord_wait := 0.0


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
		KEY_Y: _on_y,
		KEY_Z: _on_z,
		KEY_S: _ask_save,
		KEY_P: func(_k: InputEventKey) -> void: _host.playtest(),
		KEY_H: func(_k: InputEventKey) -> void: _host.toggle_help(),
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
	_pad.just("revive")
	var l1 := PadInput.pressed("melee")
	var help := false
	if active:
		help = apply_help_chord(
			l1, PadInput.pressed("shield"), fired["melee"], fired["shield"]
		)
	if not active or _host.menu_is_open() or fired["pause"]:
		if not help:
			_drop_l1()
		if not active:
			return
		if fired["pause"]:
			_host.toggle_menu()
			return
		_drive_menu(fired, delta)
		return
	if apply_history_hold(
		l1, PadInput.pressed("interact"), PadInput.pressed("revive"), delta
	):
		_mark_l1(l1)
		if fired["shield"] and not help:
			_host.cycle_tool(1)
		return
	_mark_l1(l1)
	if fired["shoot"]:
		_host.confirm()
	if fired["aim"]:
		_host.cancel()
	if fired["swap_weapon_prev"]:
		_host.step_piece(-1)
	if fired["swap_weapon"]:
		_host.step_piece(1)
	if fired["shield"] and not help:
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


## L1 held with R1 opens the command list. Either shoulder can be the one that
## just went down, so the chord does not care which finger landed first.
func apply_help_chord(l1: bool, r1: bool, l1_down: bool, r1_down: bool) -> bool:
	if not l1 or not r1 or not (l1_down or r1_down):
		return false
	_l1_held = true
	_l1_used = true
	_host.toggle_help()
	return true


## L1 held with Circle walks back, L1 held with Triangle walks forward. Holding
## both keeps stepping so a long hole can be wound all the way back.
func apply_history_hold(l1: bool, circle: bool, triangle: bool, delta: float) -> bool:
	var next := 0
	if l1 and circle:
		next = -1
	elif l1 and triangle:
		next = 1
	if next == 0:
		_chord = 0
		_chord_wait = 0.0
		return false
	if next != _chord:
		_chord = next
		_chord_wait = CHORD_FIRST
		_step_history(next)
		return true
	_chord_wait -= delta
	if _chord_wait <= 0.0:
		_chord_wait = CHORD_AGAIN
		_step_history(next)
	return true


func _step_history(dir: int) -> void:
	_l1_used = true
	if dir < 0:
		_host.undo_change()
	else:
		_host.redo_change()


func _mark_l1(down: bool) -> void:
	if down:
		_l1_held = true
		return
	if _l1_held and not _l1_used:
		_host.cycle_tool(-1)
	_drop_l1()


func _drop_l1() -> void:
	_l1_held = false
	_l1_used = false
	_chord = 0
	_chord_wait = 0.0


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


## Z by itself drops the camera. The chord is undo.
func _on_z(key: InputEventKey) -> void:
	if key.ctrl_pressed or key.meta_pressed:
		_host.undo_change()


## Y by itself flips rotation snap. The chord is redo, same idea as save.
func _on_y(key: InputEventKey) -> void:
	if key.ctrl_pressed or key.meta_pressed:
		_host.redo_change()
		return
	_host.toggle_yaw_snap()
