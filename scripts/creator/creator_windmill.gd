class_name CreatorWindmill
extends Control
## Speed dial after a mill is dropped. A tap nudges one degree. Holding the
## D-pad, stick or arrows cranks faster the longer they stay down.

signal picked(deg: float)
signal cancelled

const PAD_KEYS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right",
	"interact", "jump", "shoot", "pause",
	"swap_weapon_prev", "swap_weapon", "grapple", "swap_gear",
]
const FIRST_WAIT := 0.22
const SLOW_RATE := 18.0
const FAST_RATE := 1600.0
const RAMP := 1.8

var _spin := CartPathWindmill.SPIN_DEFAULT
var _value: Label
var _fill: ColorRect
var _pad := PadInput.new()
var _open := false
var _mouse_dir := 0
var _held_dir := 0
var _held := 0.0
var _accrued := 0.0


static func create() -> CreatorWindmill:
	var panel := CreatorWindmill.new()
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


func spin_deg() -> float:
	return _spin


func open(start := CartPathWindmill.SPIN_DEFAULT) -> void:
	_spin = CartPathWindmill.clamp_spin(start)
	_held_dir = 0
	_held = 0.0
	_accrued = 0.0
	_mouse_dir = 0
	visible = true
	_open = false
	_refresh()
	_eat_held()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_open_later.call_deferred()


func close() -> void:
	visible = false


func nudge(delta: int, tick := true) -> void:
	var next := CartPathWindmill.clamp_spin(_spin + float(delta))
	if is_equal_approx(next, _spin):
		return
	_spin = next
	_refresh()
	if tick:
		Sfx.play("ui_move", self)


## One frame of a hold, so a test can crank the dial without a pad.
func crank(dir: int, delta: float) -> void:
	_drive(dir, delta)


func confirm() -> void:
	if not _open:
		return
	close()
	picked.emit(_spin)
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
		KEY_E, KEY_ENTER, KEY_SPACE:
			confirm()
		KEY_ESCAPE:
			_cancel()
		_:
			return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _open:
		return
	var wheel := event as InputEventMouseButton
	if wheel == null or not wheel.pressed:
		return
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
		nudge(4)
	elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		nudge(-4)
	else:
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _poll_pad(delta: float) -> void:
	if not _open:
		return
	if _pad.just("interact") or _pad.just("jump") or _pad.just("shoot"):
		confirm()
		return
	if _pad.just("pause"):
		_cancel()
		return
	_drive(_wish_dir(), delta)


func _wish_dir() -> int:
	var dir := _mouse_dir
	if (
		PadInput.pressed("move_right") or PadInput.pressed("move_forward")
		or PadInput.pressed("swap_gear") or PadInput.pressed("swap_weapon_prev")
		or Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_UP)
		or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_W)
	):
		dir += 1
	if (
		PadInput.pressed("move_left") or PadInput.pressed("move_back")
		or PadInput.pressed("grapple") or PadInput.pressed("swap_weapon")
		or Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_DOWN)
		or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_S)
	):
		dir -= 1
	var stick := PadInput.joy_move()
	if stick.x >= PadInput.STICK_GATE or stick.y <= -PadInput.STICK_GATE:
		dir += 1
	if stick.x <= -PadInput.STICK_GATE or stick.y >= PadInput.STICK_GATE:
		dir -= 1
	return clampi(dir, -1, 1)


func _drive(dir: int, delta: float) -> void:
	if dir == 0:
		_held_dir = 0
		_held = 0.0
		_accrued = 0.0
		return
	if dir != _held_dir:
		_held_dir = dir
		_held = 0.0
		_accrued = 0.0
		nudge(dir)
		return
	_held += delta
	if _held < FIRST_WAIT:
		return
	var t := clampf((_held - FIRST_WAIT) / RAMP, 0.0, 1.0)
	_accrued += lerpf(SLOW_RATE, FAST_RATE, t * t) * delta
	var step := int(_accrued)
	if step == 0:
		return
	_accrued -= float(step)
	nudge(dir * step, false)


func _refresh() -> void:
	if _value != null:
		_value.text = str(roundi(_spin))
	if _fill != null:
		var span := CartPathWindmill.SPIN_MAX - CartPathWindmill.SPIN_MIN
		_fill.anchor_right = _spin / span if span > 0.0 else 0.0


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
	title.text = HudStyle.chrome("Windmill Speed")
	root.add_child(title)

	var blurb := Label.new()
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.label_settings = HudStyle.readout(Palette.ICE, 16)
	blurb.text = HudStyle.chrome("How fast should the sails turn?")
	root.add_child(blurb)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", CreatorChrome.panel_style())
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_hold_button("-", -1))
	_value = CreatorChrome.centered(Palette.LIME, 48)
	_value.custom_minimum_size = Vector2(180.0, 64.0)
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_value)
	row.add_child(_hold_button("+", 1))
	column.add_child(row)

	var unit := CreatorChrome.centered(Palette.CYAN, 14)
	unit.text = HudStyle.chrome("DEG / SEC")
	column.add_child(unit)

	var track := Control.new()
	track.custom_minimum_size = Vector2(360.0, 10.0)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(track)
	var rail := ColorRect.new()
	rail.set_anchors_preset(Control.PRESET_FULL_RECT)
	rail.color = Color(Palette.CYAN, 0.22)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(rail)
	_fill = ColorRect.new()
	_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_fill.anchor_right = 0.0
	_fill.color = Palette.LIME
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_fill)

	var done := CreatorChrome.button("Confirm", confirm)
	done.custom_minimum_size = Vector2(360.0, 36.0)
	done.alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(done)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.label_settings = HudStyle.readout(Palette.LIME, 14)
	hint.text = HudStyle.chrome(
		"hold D-pad to crank   click / E / Circle confirm   Esc / Options back"
	)
	root.add_child(hint)
	_refresh()


func _hold_button(text: String, dir: int) -> Button:
	var made := CreatorChrome.button(text, func() -> void: pass)
	made.custom_minimum_size = Vector2(56.0, 56.0)
	made.alignment = HORIZONTAL_ALIGNMENT_CENTER
	made.button_down.connect(func() -> void:
		_mouse_dir = dir
		_drive(dir, 0.0)
	)
	made.button_up.connect(func() -> void:
		if _mouse_dir == dir:
			_mouse_dir = 0
	)
	return made
