class_name DemoEnd
extends Control
## After the demo hole: how it went, play again, and the call to action.

## Set on the scene once the store page or brand link exists. Empty hides it.
@export var cta_url := ""
@export var cta_label := "GET THE FULL GAME"

static var won := false
static var strokes := -1
static var par := 0
static var played := false


static func record(p_won: bool, p_strokes: int, p_par: int) -> void:
	won = p_won
	strokes = p_strokes
	par = p_par
	played = true


static func headline() -> String:
	if not played:
		return "THANKS FOR PLAYING"
	if won and strokes > 0:
		return "HOLED IN %d" % strokes
	return "THE ZOMBIES GOT YOU"


static func detail() -> String:
	if not played or not won or strokes <= 0:
		return "Give it another swing."
	var diff := strokes - par
	if diff == 0:
		return "Par %d. Right on the number." % par
	return "Par %d. %s%d." % [par, "+" if diff > 0 else "", diff]


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Palette.NIGHT
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	add_child(column)
	column.add_child(_label(headline(), HudStyle.banner(Palette.ORANGE, 48)))
	column.add_child(_label(detail(), HudStyle.readout(Palette.ICE)))
	column.add_child(_button("PLAY AGAIN", _play_again))
	if not cta_url.is_empty():
		column.add_child(_button(cta_label, _open_cta))


func _play_again() -> void:
	if DemoBoot.setup_round():
		get_tree().change_scene_to_file(DemoBoot.ROUND)


func _open_cta() -> void:
	OS.shell_open(cta_url)


func _label(text: String, settings: LabelSettings) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 72)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_override("font", HudStyle.BANNER_FONT)
	button.add_theme_font_size_override("font_size", 26)
	button.pressed.connect(on_press)
	return button
