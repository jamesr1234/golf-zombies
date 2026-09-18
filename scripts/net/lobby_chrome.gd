class_name LobbyChrome
extends RefCounted
## Widget factory for the online lobby, kept apart so lobby_ui.gd stays about
## session state instead of layout boilerplate.


static func button(copy: String, compact := false) -> Button:
	var made := Button.new()
	made.text = HudStyle.chrome(copy)
	made.focus_mode = Control.FOCUS_NONE
	made.custom_minimum_size = Vector2(148.0, 28.0) if compact else Vector2(220.0, 44.0)
	made.add_theme_font_size_override("font_size", 14 if compact else 22)
	made.add_theme_color_override("font_color", Palette.ICE)
	made.add_theme_color_override("font_hover_color", Palette.ORANGE)
	return made


static func row(buttons: Array[Button], compact := false) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6 if compact else 12)
	for made in buttons:
		box.add_child(made)
	return box


static func field(placeholder: String, text := "", compact := false) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = text
	edit.custom_minimum_size = Vector2(280.0, 26.0) if compact else Vector2(360.0, 36.0)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if compact:
		edit.add_theme_font_size_override("font_size", 14)
	return edit


static func menu(compact := false) -> OptionButton:
	var made := OptionButton.new()
	made.custom_minimum_size = Vector2(280.0, 26.0) if compact else Vector2(360.0, 36.0)
	made.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if compact:
		made.add_theme_font_size_override("font_size", 14)
	return made


static func slider(min_value: float, max_value: float, value: float) -> HSlider:
	var bar := HSlider.new()
	bar.min_value = min_value
	bar.max_value = max_value
	bar.step = 0.05
	bar.value = value
	bar.custom_minimum_size = Vector2(220.0, 18.0)
	bar.focus_mode = Control.FOCUS_NONE
	return bar


static func heading(copy: String, compact := false) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.label_settings = HudStyle.readout(Palette.AZURE, 12 if compact else 14)
	label.text = HudStyle.chrome(copy)
	return label


static func color_chip(color: Color) -> ColorRect:
	var chip := ColorRect.new()
	chip.custom_minimum_size = Vector2(14.0, 14.0)
	chip.color = color
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return chip


static func seat_button(copy: String, color: Color, compact := false) -> Button:
	var made := Button.new()
	made.text = HudStyle.chrome(copy)
	made.focus_mode = Control.FOCUS_NONE
	made.custom_minimum_size = Vector2(48.0, 24.0) if compact else Vector2(56.0, 32.0)
	made.add_theme_font_size_override("font_size", 13 if compact else 16)
	made.add_theme_color_override("font_color", color)
	made.add_theme_color_override("font_hover_color", Palette.ICE)
	return made


static func team_row() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	return box
