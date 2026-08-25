class_name LobbyChrome
extends RefCounted
## Widget factory for the online lobby, kept apart so lobby_ui.gd stays about
## session state instead of layout boilerplate.


static func button(copy: String) -> Button:
	var made := Button.new()
	made.text = HudStyle.chrome(copy)
	made.focus_mode = Control.FOCUS_NONE
	made.custom_minimum_size = Vector2(220.0, 44.0)
	made.add_theme_font_size_override("font_size", 22)
	made.add_theme_color_override("font_color", Palette.ICE)
	made.add_theme_color_override("font_hover_color", Palette.MAGENTA)
	return made


static func row(buttons: Array[Button]) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	for made in buttons:
		box.add_child(made)
	return box


static func field(placeholder: String, text := "") -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = text
	edit.custom_minimum_size = Vector2(360.0, 36.0)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return edit


static func heading(copy: String) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.label_settings = HudStyle.readout(Palette.VIOLET, 14)
	label.text = HudStyle.chrome(copy)
	return label


static func color_chip(color: Color) -> ColorRect:
	var chip := ColorRect.new()
	chip.custom_minimum_size = Vector2(18.0, 18.0)
	chip.color = color
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return chip


static func seat_button(copy: String, color: Color) -> Button:
	var made := Button.new()
	made.text = HudStyle.chrome(copy)
	made.focus_mode = Control.FOCUS_NONE
	made.custom_minimum_size = Vector2(56.0, 32.0)
	made.add_theme_font_size_override("font_size", 16)
	made.add_theme_color_override("font_color", color)
	made.add_theme_color_override("font_hover_color", Palette.ICE)
	return made


static func team_row() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	return box
