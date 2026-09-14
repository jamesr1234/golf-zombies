class_name CreatorHelp
extends PanelContainer
## Medium right-side pad command list. L1+R1 / H toggles whether the
## builder asked for it; blocking chrome hides it so the hole stays visible.

const GLYPH := 24.0
const LETTER_GLYPH := Vector2(44.0, 26.0)
const LETTERS: PackedStringArray = ["l1", "l2", "l3", "r1", "r2", "r3"]
const PANEL_WIDTH := 320.0
const PAD := 12.0
const ICON_DIR := "res://assets/ui/pad"

const ROWS: Array[Dictionary] = [
	{"icons": ["r2"], "join": "", "label": "Place / confirm"},
	{"icons": ["l2"], "join": "", "label": "Take back"},
	{"icons": ["dpad_up", "dpad_down"], "join": "/", "label": "Cycle list"},
	{"icons": ["dpad_left", "dpad_right"], "join": "/", "label": "Turn / grow / reach"},
	{"icons": ["l1", "r1"], "join": "/", "label": "Previous / next tool"},
	{"icons": ["square"], "join": "", "label": "Next shelf"},
	{"icons": ["circle"], "join": "", "label": "Hold / merge"},
	{"icons": ["l1", "circle"], "join": "+", "label": "Undo"},
	{"icons": ["l1", "triangle"], "join": "+", "label": "Redo"},
	{"icons": ["l3"], "join": "", "label": "Surface snap"},
	{"icons": ["r3"], "join": "", "label": "Rotation snap"},
	{"icons": ["l_stick", "r_stick"], "join": "/", "label": "Move / look"},
	{"icons": ["triangle"], "join": "", "label": "Climb"},
	{"icons": ["cross"], "join": "", "label": "Drop"},
	{"icons": ["options"], "join": "", "label": "Menu"},
	{"icons": ["l1", "r1"], "join": "+", "label": "This list"},
]

var _wanted := false
var _blocked := false
var _column: VBoxContainer


static func create() -> CreatorHelp:
	var help := CreatorHelp.new()
	help.name = "CreatorHelp"
	return help


static func labels() -> PackedStringArray:
	var found := PackedStringArray()
	for row in ROWS:
		found.append(String(row["label"]))
	return found


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	add_theme_stylebox_override("panel", _style())
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -18.0 - PANEL_WIDTH
	offset_right = -18.0
	offset_top = 16.0
	custom_minimum_size.x = PANEL_WIDTH
	_build()


func toggle() -> void:
	_wanted = not _wanted
	_sync()


func is_open() -> bool:
	return _wanted


func set_blocked(blocked: bool) -> void:
	if _blocked == blocked:
		return
	_blocked = blocked
	_sync()


func _sync() -> void:
	visible = _wanted and not _blocked


func _build() -> void:
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 2)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.custom_minimum_size.x = PANEL_WIDTH - PAD * 2.0
	add_child(_column)
	var title := CreatorChrome.label(Palette.AMBER, 15, true)
	title.text = HudStyle.chrome("Pad")
	_column.add_child(title)
	for row in ROWS:
		_column.add_child(_row(row))


func _row(data: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var icons: Array = data["icons"]
	var join := String(data["join"])
	for i in icons.size():
		if i > 0 and not join.is_empty():
			var sep := CreatorChrome.label(Palette.LIME, 12)
			sep.text = join
			line.add_child(sep)
		line.add_child(_glyph(String(icons[i])))
	var text := CreatorChrome.label(Palette.ICE, 12)
	text.text = HudStyle.chrome(String(data["label"]))
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(text)
	return line


func _glyph(name: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = LETTER_GLYPH if LETTERS.has(name) else Vector2(GLYPH, GLYPH)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = load("%s/pad_%s.png" % [ICON_DIR, name]) as Texture2D
	return icon


func _style() -> StyleBoxFlat:
	var box := CreatorChrome.panel_style()
	box.content_margin_left = PAD
	box.content_margin_right = PAD
	box.content_margin_top = PAD
	box.content_margin_bottom = PAD
	return box
