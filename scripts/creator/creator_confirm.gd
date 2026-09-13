class_name CreatorConfirm
extends Control
## Yes or no over the hole creator. Opens on a prompt and waits, so the press
## that asked the question cannot also answer it.

signal confirmed
signal cancelled

const PROMPT := "Are you sure you want to erase this hole?"
const LABELS: PackedStringArray = ["Yes", "No"]
const PAD_KEYS: PackedStringArray = [
	"move_forward", "move_back", "interact", "jump", "shoot", "pause",
	"swap_weapon_prev", "swap_weapon",
]

var _prompt: Label
var _rows: Array[Button] = []
var _pick := 1
var _pad := PadInput.new()
var _open := false


static func create() -> CreatorConfirm:
	var panel := CreatorConfirm.new()
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	return panel


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	if not visible:
		return
	_poll_pad(delta)


func is_open() -> bool:
	return visible


func prompt() -> String:
	return _prompt.text if _prompt != null else ""


func open(text := PROMPT) -> void:
	_pick = 1
	if _prompt != null:
		_prompt.text = HudStyle.chrome(text)
	visible = true
	_open = false
	_refresh()
	_eat_held()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_open_later.call_deferred()


func close() -> void:
	visible = false


func move(delta: int) -> void:
	_pick = posmod(_pick + delta, _rows.size())
	_refresh()
	Sfx.play("ui_move", self)


func confirm() -> void:
	if not _open:
		return
	if _pick == 0:
		_accept()
	else:
		_cancel()


func _accept() -> void:
	if not _open:
		return
	close()
	confirmed.emit()
	Sfx.play("ui_confirm", self)


func _cancel() -> void:
	if not _open:
		return
	close()
	cancelled.emit()
	Sfx.play("ui_back", self)


func _open_later() -> void:
	_open = true


func _eat_held() -> void:
	for suffix in PAD_KEYS:
		_pad.just(suffix)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not visible or not _open or key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_W, KEY_UP, KEY_A, KEY_LEFT:
			move(-1)
		KEY_S, KEY_DOWN, KEY_D, KEY_RIGHT:
			move(1)
		KEY_E, KEY_ENTER, KEY_SPACE:
			confirm()
		KEY_ESCAPE:
			_cancel()
		_:
			return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _poll_pad(delta: float) -> void:
	if not _open:
		return
	var stick := _pad.repeat_dir(delta)
	if _pad.just("move_forward") or _pad.just("swap_weapon_prev") or stick.y < 0 or stick.x < 0:
		move(-1)
	elif _pad.just("move_back") or _pad.just("swap_weapon") or stick.y > 0 or stick.x > 0:
		move(1)
	elif _pad.just("interact") or _pad.just("jump") or _pad.just("shoot"):
		confirm()
	elif _pad.just("pause"):
		_cancel()


func _refresh() -> void:
	for i in _rows.size():
		var selected := i == _pick
		_rows[i].add_theme_color_override("font_color", Palette.LIME if selected else Palette.ICE)
		_rows[i].add_theme_stylebox_override("normal", _option_style(selected))
		_rows[i].add_theme_stylebox_override("hover", _option_style(true))
		_rows[i].add_theme_stylebox_override("pressed", _option_style(true))


func _build() -> void:
	var night := ColorRect.new()
	night.set_anchors_preset(Control.PRESET_FULL_RECT)
	night.color = Color(Palette.NIGHT, 0.92)
	night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(night)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 80.0
	root.offset_top = 36.0
	root.offset_right = -80.0
	root.offset_bottom = -36.0
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.label_settings = HudStyle.banner(Palette.MAGENTA, 28)
	_prompt.text = HudStyle.chrome(PROMPT)
	root.add_child(_prompt)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", CreatorChrome.panel_style())
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	for i in LABELS.size():
		var button := CreatorChrome.button(LABELS[i], _hit.bind(i))
		button.custom_minimum_size = Vector2(280.0, 36.0)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows.append(button)
		column.add_child(button)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.label_settings = HudStyle.readout(Palette.LIME, 14)
	hint.text = HudStyle.chrome(
		"W/S or stick move   click / E / Circle pick   Esc / Options back"
	)
	root.add_child(hint)
	_refresh()


func _hit(index: int) -> void:
	if not _open:
		return
	_pick = index
	if index == 0:
		_accept()
	else:
		_cancel()


func _option_style(selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.MAGENTA, 0.18) if selected else Color(0.06, 0.04, 0.1, 0.7)
	box.border_color = Palette.MAGENTA if selected else Color(Palette.CYAN, 0.35)
	box.set_border_width_all(2 if selected else 1)
	box.set_corner_radius_all(3)
	return box
