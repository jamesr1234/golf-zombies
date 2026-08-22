class_name MainMenu
extends Control
## Neon title screen: pick 1P or 2P, then a difficulty, then load the course.

const GAMEPLAY := "res://scenes/main.tscn"
const LOBBY := "res://scenes/net/lobby.tscn"
const _Music := preload("res://scripts/fx/music.gd")
const MODE_COPY := ["1 Player", "2 Player", "Online"]
const MODE_BLURB := [
	"You and a CPU partner. One screen. Hold Circle / E for the CPU to take a shot.",
	"Local co-op. Player 1 uses the controller. Player 2 uses the keyboard.",
	"Eight players. Own ball. Melee only. Host or join by IP.",
]
const DIFF_BLURB := [
	"More time, fewer zombies, gunners wait until hole 3.",
	"The standard nine. Gunners from hole 2.",
	"Faster swarms, tougher zombies, 90 seconds a hole.",
	"No mercy. 60 seconds. Gunners from the first tee.",
]

enum Step { MODE, DIFFICULTY }

var step: Step = Step.MODE
var mode_index := 0
var difficulty_index := 1
var started := false

var _title: Label
var _tag: Label
var _panel: PanelContainer
var _heading: Label
var _options: VBoxContainer
var _blurb: Label
var _hint: Label
var _buttons: Array[Button] = []


func _enter_tree() -> void:
	InputActions.register_all()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh()
	_Music.play_lounge()


func move(delta: int) -> void:
	var count := MODE_COPY.size() if step == Step.MODE else GameSettings.LABELS.size()
	if step == Step.MODE:
		mode_index = posmod(mode_index + delta, count)
	else:
		difficulty_index = posmod(difficulty_index + delta, count)
	Sfx.play("ui_move", self)
	_refresh()


func confirm() -> void:
	Sfx.play("ui_confirm", self)
	if step == Step.MODE:
		if mode_index == 2:
			GameSettings.mode = GameSettings.Mode.ONLINE_VS
			start_lobby()
			return
		step = Step.DIFFICULTY
		_refresh()
		return
	apply_settings()
	start_game()


func back() -> void:
	if step == Step.DIFFICULTY:
		step = Step.MODE
		Sfx.play("ui_back", self)
		_refresh()


func apply_settings() -> void:
	if mode_index == 0:
		GameSettings.mode = GameSettings.Mode.SOLO
	elif mode_index == 1:
		GameSettings.mode = GameSettings.Mode.COOP
	else:
		GameSettings.mode = GameSettings.Mode.ONLINE_VS
	GameSettings.difficulty = difficulty_index as GameSettings.Kind


func start_game() -> void:
	if started:
		return
	started = true
	get_tree().change_scene_to_file(GAMEPLAY)


func start_lobby() -> void:
	if started:
		return
	started = true
	get_tree().change_scene_to_file(LOBBY)


func _unhandled_input(event: InputEvent) -> void:
	if started:
		return
	var viewport := get_viewport()
	if _pressed(event, [KEY_W, KEY_UP]) or _action_just("move_forward"):
		_mark_handled(viewport)
		move(-1)
	elif _pressed(event, [KEY_S, KEY_DOWN]) or _action_just("move_back"):
		_mark_handled(viewport)
		move(1)
	elif (
		_pressed(event, [KEY_E, KEY_ENTER, KEY_SPACE])
		or _action_just("interact")
		or _action_just("jump")
	):
		_mark_handled(viewport)
		confirm()
	elif _pressed(event, [KEY_ESCAPE]) or _action_just("pause"):
		_mark_handled(viewport)
		back()


func _mark_handled(viewport: Viewport) -> void:
	if viewport != null:
		viewport.set_input_as_handled()


func _action_just(suffix: String) -> bool:
	return (
		Input.is_action_just_pressed("p1_" + suffix)
		or Input.is_action_just_pressed("p2_" + suffix)
	)


func _pressed(event: InputEvent, keys: Array) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	return (event as InputEventKey).physical_keycode in keys


func _build() -> void:
	var night := ColorRect.new()
	night.set_anchors_preset(Control.PRESET_FULL_RECT)
	night.color = Palette.NIGHT
	night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(night)

	var glow := ColorRect.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = 80.0
	glow.offset_top = 40.0
	glow.offset_right = -80.0
	glow.offset_bottom = -40.0
	glow.color = Color(Palette.MAGENTA, 0.05)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 120.0
	root.offset_top = 70.0
	root.offset_right = -120.0
	root.offset_bottom = -70.0
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 18)
	add_child(root)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.label_settings = HudStyle.banner(Palette.MAGENTA, 64)
	_title.text = HudStyle.chrome("Golf Zombies")
	root.add_child(_title)

	_tag = Label.new()
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.label_settings = HudStyle.readout(Palette.CYAN, 18)
	_tag.text = HudStyle.chrome("Nine holes. One ball. Don't get eaten.")
	root.add_child(_tag)

	_panel = PanelContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.custom_minimum_size = Vector2(640.0, 0.0)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)

	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.label_settings = HudStyle.readout(Palette.AMBER, 20)
	column.add_child(_heading)

	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 8)
	column.add_child(_options)

	_blurb = Label.new()
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.label_settings = HudStyle.readout(Palette.ICE, 16)
	column.add_child(_blurb)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.label_settings = HudStyle.readout(Palette.LIME, 14)
	_hint.text = HudStyle.chrome(
		"W/S or stick to move   E / Circle / Cross to confirm   Esc / Options back"
	)
	root.add_child(_hint)


func _refresh() -> void:
	var labels := MODE_COPY if step == Step.MODE else Array(GameSettings.LABELS)
	var selected := mode_index if step == Step.MODE else difficulty_index
	_heading.text = HudStyle.chrome("Select players" if step == Step.MODE else "Select difficulty")
	_blurb.text = MODE_BLURB[mode_index] if step == Step.MODE else DIFF_BLURB[difficulty_index]
	for child in _options.get_children():
		child.queue_free()
	_buttons.clear()
	for i in labels.size():
		var button := Button.new()
		button.text = HudStyle.chrome(str(labels[i]))
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_override("font", HudStyle.banner(Palette.CYAN).font)
		button.add_theme_font_size_override("font_size", 28)
		button.add_theme_stylebox_override("normal", _option_style(i == selected))
		button.add_theme_stylebox_override("hover", _option_style(true))
		button.add_theme_stylebox_override("pressed", _option_style(true))
		button.add_theme_color_override(
			"font_color", Palette.MAGENTA if i == selected else Palette.ICE
		)
		button.add_theme_color_override("font_hover_color", Palette.MAGENTA)
		var index := i
		button.pressed.connect(func() -> void:
			if step == Step.MODE:
				mode_index = index
			else:
				difficulty_index = index
			_refresh()
			confirm()
		)
		_options.add_child(button)
		_buttons.append(button)


func _panel_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.NIGHT, 0.88)
	box.border_color = Color(Palette.CYAN, 0.7)
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.content_margin_left = 28.0
	box.content_margin_right = 28.0
	box.content_margin_top = 22.0
	box.content_margin_bottom = 22.0
	return box


func _option_style(selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.MAGENTA, 0.18) if selected else Color(0.06, 0.04, 0.1, 0.7)
	box.border_color = Palette.MAGENTA if selected else Color(Palette.CYAN, 0.35)
	box.set_border_width_all(2 if selected else 1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box
