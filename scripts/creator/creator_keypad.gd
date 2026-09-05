class_name CreatorKeypad
extends PanelContainer
## On-screen name pad. A keyboard still types; a controller walks the grid.
## Opens on OK when a name is already filled, so Circle can take the suggestion.

signal submitted(text: String)
signal cancelled

const COLS := 7
const MAX_LEN := 28
const KEYS: PackedStringArray = [
	"A", "B", "C", "D", "E", "F", "G",
	"H", "I", "J", "K", "L", "M", "N",
	"O", "P", "Q", "R", "S", "T", "U",
	"V", "W", "X", "Y", "Z", "0", "1",
	"2", "3", "4", "5", "6", "7", "8",
	"9", "SPC", "DEL", "OK", ".", "-", "CLR",
]

var _heading: Label
var _preview: Label
var _cells: Array[Button] = []
var _text := ""
var _pick := 0
var _pad := PadInput.new()


static func create() -> CreatorKeypad:
	var pad := CreatorKeypad.new()
	pad.visible = false
	pad.set_anchors_preset(Control.PRESET_CENTER)
	pad.offset_left = -220.0
	pad.offset_right = 220.0
	pad.offset_top = -210.0
	pad.offset_bottom = 210.0
	return pad


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	if not visible:
		return
	_poll_pad(delta)


func is_open() -> bool:
	return visible


func open(heading: String, current: String) -> void:
	_heading.text = HudStyle.chrome(heading)
	_text = current
	_pick = KEYS.find("OK")
	if _pick < 0:
		_pick = 0
	visible = true
	_refresh()
	_eat_held()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Circle opened this pad. Eating the current down edges means releasing that
## press does not immediately type OK.
func _eat_held() -> void:
	for suffix in ["shoot", "aim", "interact", "jump", "reload", "pause",
			"swap_weapon_prev", "swap_weapon", "grapple", "swap_gear"]:
		_pad.just(suffix)


func close() -> void:
	visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and handle_key(key):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func handle_key(event: InputEventKey) -> bool:
	if not visible or not event.pressed or event.echo:
		return false
	match event.physical_keycode:
		KEY_ESCAPE:
			_cancel()
		KEY_ENTER:
			_submit()
		KEY_BACKSPACE:
			_delete()
		KEY_LEFT:
			_move(-1, 0)
		KEY_RIGHT:
			_move(1, 0)
		KEY_UP:
			_move(0, -1)
		KEY_DOWN:
			_move(0, 1)
		_:
			var letter := char(event.unicode).to_upper()
			if not _typeable(letter):
				return false
			_append(letter)
	return true


func _typeable(letter: String) -> bool:
	if letter.length() != 1:
		return false
	var code := letter.unicode_at(0)
	return (
		(code >= 65 and code <= 90) or (code >= 48 and code <= 57)
		or letter == " " or letter == "." or letter == "-"
	)


func _poll_pad(delta: float) -> void:
	var step := _pad.repeat_dir(delta)
	if step != Vector2i.ZERO:
		_move(step.x, step.y)
	if _pad.just("swap_weapon_prev"):
		_move(0, -1)
	if _pad.just("swap_weapon"):
		_move(0, 1)
	if _pad.just("grapple"):
		_move(-1, 0)
	if _pad.just("swap_gear"):
		_move(1, 0)
	if _pad.just("shoot") or _pad.just("interact") or _pad.just("jump"):
		_hit(_pick)
	if _pad.just("aim") or _pad.just("reload"):
		_delete()
	if _pad.just("pause"):
		_cancel()


func _move(dx: int, dy: int) -> void:
	var col := posmod(_pick % COLS + dx, COLS)
	var row := posmod(int(_pick / COLS) + dy, int(KEYS.size() / COLS))
	_pick = row * COLS + col
	_refresh()
	Sfx.play("ui_move", self)


func _hit(index: int) -> void:
	if index < 0 or index >= KEYS.size():
		return
	var key := KEYS[index]
	match key:
		"OK":
			_submit()
		"DEL":
			_delete()
		"CLR":
			_text = ""
			_refresh()
			Sfx.play("ui_back", self)
		"SPC":
			_append(" ")
		_:
			_append(key)


func _append(letter: String) -> void:
	if _text.length() >= MAX_LEN:
		return
	_text += letter
	_refresh()
	Sfx.play("ui_move", self)


func _delete() -> void:
	if _text.is_empty():
		return
	_text = _text.substr(0, _text.length() - 1)
	_refresh()
	Sfx.play("ui_back", self)


func _submit() -> void:
	close()
	submitted.emit(_text)
	Sfx.play("ui_confirm", self)


func _cancel() -> void:
	close()
	cancelled.emit()
	Sfx.play("ui_back", self)


func _refresh() -> void:
	_preview.text = _text if not _text.is_empty() else "_"
	for i in _cells.size():
		_cells[i].add_theme_color_override(
			"font_color", Palette.MAGENTA if i == _pick else Palette.ICE
		)


func _build() -> void:
	add_theme_stylebox_override("panel", CreatorChrome.panel_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	_heading = CreatorChrome.centered(Palette.AMBER, 18)
	column.add_child(_heading)
	_preview = CreatorChrome.centered(Palette.MAGENTA, 22)
	column.add_child(_preview)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)
	for i in KEYS.size():
		var cell := CreatorChrome.button(KEYS[i], _hit.bind(i))
		cell.custom_minimum_size = Vector2(48.0, 32.0)
		_cells.append(cell)
		grid.add_child(cell)
	var hint := CreatorChrome.centered(Palette.LIME, 13)
	hint.text = HudStyle.chrome("STICK MOVE   CIRCLE / R2 TYPE   L2 DELETE   OPTIONS BACK")
	column.add_child(hint)
