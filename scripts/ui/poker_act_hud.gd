class_name PokerActHud
extends Control
## Center callout for the last seat action, plus fold / check-call / raise.

@onready var title: Label = $Panel/Lines/Title
@onready var body: Label = $Panel/Lines/Body
@onready var fold_btn: Button = $Panel/Lines/Buttons/Fold
@onready var soft_btn: Button = $Panel/Lines/Buttons/Soft
@onready var raise_btn: Button = $Panel/Lines/Buttons/Raise

var _player: Player
var _idle: StyleBoxFlat
var _pick: StyleBoxFlat


func _ready() -> void:
	visible = false
	z_index = 30
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := $Panel as PanelContainer
	if panel != null:
		panel.add_theme_stylebox_override("panel", _box(Palette.CYAN))
	title.label_settings = HudStyle.banner(Palette.MAGENTA)
	body.label_settings = HudStyle.readout(Palette.ICE, HudStyle.BODY_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_idle = _box(Palette.CYAN)
	_pick = _box(Palette.MAGENTA)
	_style(fold_btn)
	_style(soft_btn)
	_style(raise_btn)
	fold_btn.pressed.connect(_on_fold)
	soft_btn.pressed.connect(_on_soft)
	raise_btn.pressed.connect(_on_raise)


func refresh(player: Player) -> void:
	_player = player
	if player == null or player.poker == null or not player.poker.seated():
		visible = false
		return
	if player.poker.table.phase != PokerTable.Phase.PLAYING:
		visible = false
		return
	var line := player.poker.headline()
	if line.is_empty() and player.poker.choices().is_empty():
		visible = false
		return
	visible = true
	move_to_front()
	title.text = HudStyle.chrome(line if not line.is_empty() else "Your action")
	var ops := player.poker.choices()
	var acting := not ops.is_empty()
	body.visible = not acting
	if not acting:
		body.text = HudStyle.chrome(
			"Waiting on %s" % player.poker.table.occupant_name(player.poker.table.hand.to_act)
		)
	fold_btn.visible = acting
	soft_btn.visible = acting
	raise_btn.visible = acting and _raise_choice(player, ops).size() > 0
	if not acting:
		return
	var pick: Dictionary = ops[player.poker.act_idx % ops.size()]
	var soft := _soft_choice(ops)
	var bump := _raise_choice(player, ops)
	soft_btn.text = HudStyle.chrome(String(soft.get("label", "Check")))
	raise_btn.text = HudStyle.chrome(String(bump.get("label", "Raise")))
	_paint(fold_btn, false)
	_paint(soft_btn, String(pick.get("op", "")) != "raise")
	_paint(raise_btn, String(pick.get("op", "")) == "raise")


func _on_fold() -> void:
	if _player != null:
		_player.poker.pick_act(_player, "fold")


func _on_soft() -> void:
	if _player == null:
		return
	var soft := _soft_choice(_player.poker.choices())
	if soft.is_empty():
		return
	_player.poker.pick_act(_player, String(soft["op"]))


func _on_raise() -> void:
	if _player == null:
		return
	var bump := _raise_choice(_player, _player.poker.choices())
	if bump.is_empty():
		return
	_player.poker.pick_act(_player, "raise", int(bump.get("to", 0)))


func _soft_choice(ops: Array[Dictionary]) -> Dictionary:
	for op in ops:
		var name := String(op.get("op", ""))
		if name == "check" or name == "call":
			return op
	return {}


func _raise_choice(player: Player, ops: Array[Dictionary]) -> Dictionary:
	if ops.is_empty():
		return {}
	var pick: Dictionary = ops[player.poker.act_idx % ops.size()]
	if String(pick.get("op", "")) == "raise":
		return pick
	for op in ops:
		if String(op.get("op", "")) == "raise":
			return op
	return {}


func _style(btn: Button) -> void:
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
