class_name PokerResultHud
extends Control
## Big post-hand readout: how much you won or lost, then yes/no to play again.

@onready var title: Label = $Panel/Lines/Title
@onready var body: Label = $Panel/Lines/Body
@onready var yes_btn: Button = $Panel/Lines/Buttons/Yes
@onready var no_btn: Button = $Panel/Lines/Buttons/No

var _player: Player
var _idle: StyleBoxFlat
var _pick: StyleBoxFlat


func _ready() -> void:
	visible = false
	z_index = 40
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := $Panel as PanelContainer
	if panel != null:
		panel.add_theme_stylebox_override("panel", _box(Palette.MAGENTA))
	title.label_settings = HudStyle.banner(Palette.MAGENTA)
	body.label_settings = HudStyle.readout(Palette.ICE, HudStyle.BODY_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_idle = _box(Palette.CYAN)
	_pick = _box(Palette.MAGENTA)
	_style(yes_btn, "Yes")
	_style(no_btn, "No")
	yes_btn.pressed.connect(_on_yes)
	no_btn.pressed.connect(_on_no)


func refresh(player: Player) -> void:
	_player = player
	if player == null or player.poker == null or not player.poker.showing_result():
		visible = false
		return
	visible = true
	move_to_front()
	title.text = HudStyle.chrome(player.poker.result_title())
	body.text = HudStyle.chrome(player.poker.result_body())
	var asking := player.poker.asking_replay()
	yes_btn.visible = asking
	no_btn.visible = asking
	if not asking:
		return
	yes_btn.disabled = not player.poker.can_replay()
	_paint(yes_btn, player.poker.replay_yes())
	_paint(no_btn, not player.poker.replay_yes())


func _on_yes() -> void:
	if _player != null:
		_player.poker.pick_replay(_player, true)


func _on_no() -> void:
	if _player != null:
		_player.poker.pick_replay(_player, false)


func _style(btn: Button, copy: String) -> void:
	btn.text = HudStyle.chrome(copy)
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(168.0, 52.0)
	btn.add_theme_font_override("font", HudStyle.banner(Palette.ICE).font)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Palette.ICE)
	btn.add_theme_color_override("font_hover_color", Palette.MAGENTA)
	btn.add_theme_color_override("font_disabled_color", Color(Palette.ICE, 0.35))
	btn.mouse_filter = Control.MOUSE_FILTER_STOP


func _paint(btn: Button, on: bool) -> void:
	btn.add_theme_stylebox_override("normal", _pick if on else _idle)
	btn.add_theme_stylebox_override("hover", _pick)
	btn.add_theme_stylebox_override("pressed", _pick)
	btn.add_theme_stylebox_override("disabled", _idle)
	btn.add_theme_color_override("font_color", Palette.MAGENTA if on else Palette.ICE)


func _box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.02, 0.09, 0.97)
	box.border_color = Color(color, 0.9)
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(10)
	return box
