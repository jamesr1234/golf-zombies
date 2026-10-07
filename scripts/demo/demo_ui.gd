class_name DemoUi
extends RefCounted
## The few widgets the demo's menu and end screens share.


## Night backdrop and a centred column on `owner`. Returns the column.
static func column(owner: Control) -> VBoxContainer:
	owner.set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Palette.NIGHT
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	owner.add_child(back)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	owner.add_child(box)
	return box


static func label(text: String, settings: LabelSettings) -> Label:
	var out := Label.new()
	out.text = text
	out.label_settings = settings
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return out


static func button(text: String, on_press: Callable) -> Button:
	var out := Button.new()
	out.text = text
	out.custom_minimum_size = Vector2(360, 64)
	out.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	out.add_theme_font_override("font", HudStyle.BANNER_FONT)
	out.add_theme_font_size_override("font_size", 24)
	out.pressed.connect(on_press)
	return out
