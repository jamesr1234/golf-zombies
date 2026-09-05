class_name CreatorChrome
extends RefCounted
## Widget factory for the hole creator, kept apart so creator_ui.gd stays about
## what the builder is looking at instead of layout boilerplate. Same split as
## LobbyChrome, and the same neon styling.

const PANEL_ALPHA := 0.92
const CROSSHAIR := 4.0


static func label(color: Color, size: int, banner := false) -> Label:
	var made := Label.new()
	made.label_settings = HudStyle.banner(color, size) if banner else HudStyle.readout(color, size)
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return made


static func centered(color: Color, size: int) -> Label:
	var made := label(color, size)
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return made


static func button(text: String, action: Callable) -> Button:
	var made := Button.new()
	made.text = HudStyle.chrome(text)
	made.focus_mode = Control.FOCUS_NONE
	made.add_theme_font_size_override("font_size", 17)
	made.add_theme_color_override("font_color", Palette.ICE)
	made.add_theme_color_override("font_hover_color", Palette.MAGENTA)
	made.pressed.connect(action)
	return made


static func panel(root: Control, half: Vector2) -> VBoxContainer:
	var made := PanelContainer.new()
	made.add_theme_stylebox_override("panel", _box())
	made.visible = false
	made.set_anchors_preset(Control.PRESET_CENTER)
	made.offset_left = -half.x
	made.offset_right = half.x
	made.offset_top = -half.y
	made.offset_bottom = half.y
	root.add_child(made)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	made.add_child(column)
	return column


## A stack of readouts pinned to one edge, returned as the column to fill.
static func bar(root: Control, preset: Control.LayoutPreset, offset: Vector2) -> VBoxContainer:
	var holder := Control.new()
	holder.set_anchors_preset(preset)
	holder.offset_left = offset.x
	holder.offset_top = offset.y
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	holder.add_child(column)
	root.add_child(holder)
	return column


static func banner_line(root: Control, color: Color, size: int, top: float) -> Label:
	var made := centered(color, size)
	made.set_anchors_preset(Control.PRESET_CENTER_TOP)
	made.offset_left = -420.0
	made.offset_right = 420.0
	made.offset_top = top
	root.add_child(made)
	return made


## A tall shelf of names. The selected row is kept in view so a long catalog
## (obstacles, weapons) reads the same way as the short fairway list.
static func scroller(height: float) -> ScrollContainer:
	var made := ScrollContainer.new()
	made.custom_minimum_size = Vector2(280.0, height)
	made.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	made.mouse_filter = Control.MOUSE_FILTER_STOP
	return made


static func fill_palette(
	box: VBoxContainer, labels: PackedStringArray, selected: int, allowed: Array[bool]
) -> void:
	while box.get_child_count() > labels.size():
		var extra := box.get_child(box.get_child_count() - 1)
		box.remove_child(extra)
		extra.free()
	while box.get_child_count() < labels.size():
		var row := Label.new()
		row.label_settings = HudStyle.readout(Palette.ICE, 15)
		box.add_child(row)
	for i in labels.size():
		var row := box.get_child(i) as Label
		row.text = HudStyle.chrome("%s %s" % [">" if i == selected else " ", labels[i]])
		var ok: bool = i >= allowed.size() or allowed[i]
		row.modulate = Color.WHITE if ok else Color(1.0, 1.0, 1.0, 0.28)
		row.label_settings = HudStyle.readout(
			Palette.MAGENTA if i == selected else (Palette.ICE if ok else Palette.HOT_PINK), 15
		)


static func reveal(scroll: ScrollContainer, box: VBoxContainer, selected: int) -> void:
	if selected < 0 or selected >= box.get_child_count():
		return
	var row := box.get_child(selected) as Control
	if row != null:
		scroll.ensure_control_visible(row)


static func footer(root: Control, text: String) -> Label:
	var made := centered(Palette.LIME, 13)
	made.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	made.offset_top = -34.0
	made.text = HudStyle.chrome(text)
	root.add_child(made)
	return made


static func crosshair(root: Control) -> void:
	var dot := ColorRect.new()
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.offset_left = -CROSSHAIR * 0.5
	dot.offset_top = -CROSSHAIR * 0.5
	dot.offset_right = CROSSHAIR * 0.5
	dot.offset_bottom = CROSSHAIR * 0.5
	dot.color = Palette.MAGENTA
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)


static func field(on_submit: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.max_length = 28
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_size_override("font_size", 20)
	edit.text_submitted.connect(on_submit)
	return edit


static func panel_style() -> StyleBoxFlat:
	return _box()


static func _box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.NIGHT, PANEL_ALPHA)
	box.border_color = Color(Palette.CYAN, 0.7)
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 14.0
	box.content_margin_bottom = 14.0
	return box
