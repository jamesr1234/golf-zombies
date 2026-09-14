class_name CreatorSpawn
extends Control
## How many of each walker to plant at the spawn that was just dropped.

signal picked(counts: Dictionary)
signal cancelled

const PAD_KEYS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right",
	"interact", "jump", "shoot", "pause",
	"swap_weapon_prev", "swap_weapon", "grapple", "swap_gear",
]

var _counts := SpawnPack.empty_counts()
var _rows: Array[Button] = []
var _values: Array[Label] = []
var _pick := 0
var _pad := PadInput.new()
var _open := false


static func create() -> CreatorSpawn:
	var panel := CreatorSpawn.new()
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


func open() -> void:
	_counts = SpawnPack.empty_counts()
	_pick = 0
	visible = true
	_open = false
	_refresh()
	_eat_held()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_open_later.call_deferred()


func close() -> void:
	visible = false


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
		KEY_W, KEY_UP:
			move(-1)
		KEY_S, KEY_DOWN:
			move(1)
		KEY_A, KEY_LEFT:
			nudge(-1)
		KEY_D, KEY_RIGHT:
			nudge(1)
		KEY_E, KEY_ENTER:
			confirm()
		KEY_ESCAPE:
			_cancel()
		_:
			return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func move(delta: int) -> void:
	_pick = posmod(_pick + delta, SpawnPack.KEYS.size())
	_refresh()
	Sfx.play("ui_move", self)


func nudge(delta: int) -> void:
	var key := SpawnPack.KEYS[_pick]
	var next := clampi(int(_counts[key]) + delta, 0, SpawnPack.MAX_EACH)
	if next == int(_counts[key]):
		return
	_counts[key] = next
	_refresh()
	Sfx.play("ui_move", self)


func confirm() -> void:
	if not _open:
		return
	if SpawnPack.total(_counts) <= 0:
		Sfx.play("ui_deny", self)
		return
	close()
	picked.emit(_counts.duplicate())
	Sfx.play("ui_confirm", self)


func _cancel() -> void:
	if not _open:
		return
	close()
	cancelled.emit()
	Sfx.play("ui_back", self)


func _poll_pad(delta: float) -> void:
	if not _open:
		return
	var stick := _pad.repeat_dir(delta)
	if _pad.just("move_forward") or _pad.just("swap_weapon_prev") or stick.y < 0:
		move(-1)
	elif _pad.just("move_back") or _pad.just("swap_weapon") or stick.y > 0:
		move(1)
	elif _pad.just("move_left") or _pad.just("grapple") or stick.x < 0:
		nudge(-1)
	elif _pad.just("move_right") or _pad.just("swap_gear") or stick.x > 0:
		nudge(1)
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
		_values[i].text = str(int(_counts[SpawnPack.KEYS[i]]))
		_values[i].label_settings = HudStyle.readout(
			Palette.LIME if selected else Palette.ICE, 20
		)


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

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.label_settings = HudStyle.banner(Palette.ORANGE, 36)
	title.text = HudStyle.chrome("Spawn Enemies")
	root.add_child(title)

	var blurb := Label.new()
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.label_settings = HudStyle.readout(Palette.ICE, 16)
	blurb.text = HudStyle.chrome("How many of each should walk this yard?")
	root.add_child(blurb)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", CreatorChrome.panel_style())
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	for i in SpawnPack.KEYS.size():
		column.add_child(_make_row(i))

	var done := CreatorChrome.button("Confirm", confirm)
	done.custom_minimum_size = Vector2(360.0, 36.0)
	done.alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(done)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.label_settings = HudStyle.readout(Palette.LIME, 14)
	hint.text = HudStyle.chrome(
		"W/S pick   A/D count   click / E / Circle confirm   Esc / Options back"
	)
	root.add_child(hint)
	_refresh()


func _make_row(index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var name := CreatorChrome.button(SpawnPack.LABELS[index], _hit.bind(index))
	name.custom_minimum_size = Vector2(180.0, 36.0)
	name.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.append(name)
	row.add_child(name)
	row.add_child(_count_button("-", -1, index))
	var value := CreatorChrome.centered(Palette.ICE, 20)
	value.custom_minimum_size = Vector2(48.0, 36.0)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_values.append(value)
	row.add_child(value)
	row.add_child(_count_button("+", 1, index))
	return row


func _count_button(text: String, delta: int, index: int) -> Button:
	var made := CreatorChrome.button(text, _bump.bind(index, delta))
	made.custom_minimum_size = Vector2(44.0, 36.0)
	made.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return made


func _hit(index: int) -> void:
	if not _open:
		return
	if _pick != index:
		_pick = index
		_refresh()
		Sfx.play("ui_move", self)


func _bump(index: int, delta: int) -> void:
	if not _open:
		return
	_pick = index
	nudge(delta)


func _option_style(selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.ORANGE, 0.18) if selected else Color(0.04, 0.06, 0.08, 0.7)
	box.border_color = Palette.ORANGE if selected else Color(Palette.CYAN, 0.35)
	box.set_border_width_all(2 if selected else 1)
	box.set_corner_radius_all(3)
	return box
