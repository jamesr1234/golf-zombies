class_name CreatorCoach
extends Control
## Banner plus the big pad glyphs in the middle of the hole, so the next
## action is the thing sitting under the crosshair.

const WIDTH := 640.0
const GLYPH := 64.0
const LETTER_GLYPH := Vector2(104.0, 60.0)
const LETTERS: PackedStringArray = ["l1", "l2", "l3", "r1", "r2", "r3"]
const ICON_DIR := "res://assets/ui/pad"


static func create() -> CreatorCoach:
	var coach := CreatorCoach.new()
	coach.name = "CreatorCoach"
	return coach


var _title: Label
var _line: Label
var _tip: Label
var _next: Label
var _mark: Label
var _keys: Label
var _glyphs: HBoxContainer
var _hint: Control
var _banner: Control
var _middle: Control
var _lesson: CreatorLesson


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func bind(lesson: CreatorLesson) -> void:
	_lesson = lesson
	visible = true
	lesson.prompted.connect(_show_prompt)
	lesson.praised.connect(_show_praise)
	lesson.finished.connect(func() -> void: _show_prompt(lesson.prompt()))
	_show_prompt(lesson.prompt())
	_dbg_layout.call_deferred("bind")


func _show_prompt(text: String) -> void:
	_line.text = HudStyle.chrome(text)
	_line.label_settings = HudStyle.readout(Palette.ICE, 16)
	_tip.visible = false
	_next.visible = false
	if _lesson != null:
		_mark.text = _progress(_lesson)
		_title.label_settings = HudStyle.banner(Palette.AMBER, 14)
	_show_glyphs(true)


func _show_praise(text: String) -> void:
	_line.text = HudStyle.chrome(text)
	_line.label_settings = HudStyle.readout(Palette.LIME, 22)
	_title.label_settings = HudStyle.banner(Palette.LIME, 14)
	var extra := _lesson.tip() if _lesson != null else ""
	_tip.visible = not extra.is_empty()
	_tip.text = HudStyle.chrome(extra)
	_next.visible = true
	_next.text = HudStyle.chrome(CreatorLesson.NEXT_HINT)
	_show_glyphs(false)


func _show_glyphs(on: bool) -> void:
	if _lesson == null or not on or _lesson.praising() or not _lesson.is_live():
		_hint.visible = false
		return
	var names := _lesson.icons()
	_hint.visible = not names.is_empty()
	for child in _glyphs.get_children():
		child.queue_free()
	var join := _lesson.icon_join()
	for i in names.size():
		if i > 0 and not join.is_empty():
			var sep := CreatorChrome.label(Palette.LIME, 28, true)
			sep.text = join
			_glyphs.add_child(sep)
		_glyphs.add_child(_glyph(names[i]))
	var keys := _lesson.keys()
	_keys.visible = not keys.is_empty()
	_keys.text = HudStyle.chrome(keys)
	_dbg_layout.call_deferred("glyphs")


func _progress(lesson: CreatorLesson) -> String:
	if not lesson.is_live():
		return ""
	return "%d / %d" % [lesson.index() + 1, lesson.count() - 1]


func _build() -> void:
	var banner := PanelContainer.new()
	_banner = banner
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_stylebox_override("panel", _style())
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.offset_left = -WIDTH * 0.5
	banner.offset_right = WIDTH * 0.5
	banner.offset_top = 0.0
	add_child(banner)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(column)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	_title = CreatorChrome.label(Palette.AMBER, 14, true)
	_title.text = HudStyle.chrome("Tutorial")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_mark = CreatorChrome.label(Palette.CYAN, 13)
	_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_mark)

	_line = CreatorChrome.centered(Palette.ICE, 16)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size.x = WIDTH - 36.0
	column.add_child(_line)
	_tip = CreatorChrome.centered(Palette.CYAN, 14)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size.x = WIDTH - 36.0
	_tip.visible = false
	column.add_child(_tip)
	_next = CreatorChrome.centered(Palette.AMBER, 13)
	_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next.custom_minimum_size.x = WIDTH - 36.0
	_next.visible = false
	column.add_child(_next)

	var middle := CenterContainer.new()
	_middle = middle
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(middle)
	_hint = VBoxContainer.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_constant_override("separation", 8)
	middle.add_child(_hint)
	_glyphs = HBoxContainer.new()
	_glyphs.alignment = BoxContainer.ALIGNMENT_CENTER
	_glyphs.add_theme_constant_override("separation", 10)
	_glyphs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(_glyphs)
	_keys = CreatorChrome.centered(Palette.AMBER, 16)
	_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_child(_keys)


func _glyph(name: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = LETTER_GLYPH if LETTERS.has(name) else Vector2(GLYPH, GLYPH)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = load("%s/pad_%s.png" % [ICON_DIR, name]) as Texture2D
	return icon


func _dbg_layout(where: String) -> void:
	# #region agent log
	var vp := get_viewport_rect().size
	var self_r := get_global_rect()
	var banner_r := _banner.get_global_rect() if _banner != null else Rect2()
	var mid_r := _middle.get_global_rect() if _middle != null else Rect2()
	var hint_r := _hint.get_global_rect() if _hint != null else Rect2()
	var glyph_r := _glyphs.get_global_rect() if _glyphs != null else Rect2()
	var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-73ff83.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-73ff83.log", FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(JSON.stringify({
			"sessionId": "73ff83",
			"runId": "post-fix",
			"hypothesisId": "A",
			"location": "creator_coach.gd:_dbg_layout",
			"message": where,
			"timestamp": Time.get_ticks_msec(),
			"data": {
				"vp": [snappedf(vp.x, 1.0), snappedf(vp.y, 1.0)],
				"coach": [snappedf(self_r.position.x, 1.0), snappedf(self_r.position.y, 1.0), snappedf(self_r.size.x, 1.0), snappedf(self_r.size.y, 1.0)],
				"coach_anchors": [snappedf(anchor_left, 0.01), snappedf(anchor_top, 0.01), snappedf(anchor_right, 0.01), snappedf(anchor_bottom, 0.01)],
				"coach_offsets": [snappedf(offset_left, 1.0), snappedf(offset_top, 1.0), snappedf(offset_right, 1.0), snappedf(offset_bottom, 1.0)],
				"banner": [snappedf(banner_r.position.x, 1.0), snappedf(banner_r.position.y, 1.0), snappedf(banner_r.size.x, 1.0), snappedf(banner_r.size.y, 1.0)],
				"middle": [snappedf(mid_r.position.x, 1.0), snappedf(mid_r.position.y, 1.0), snappedf(mid_r.size.x, 1.0), snappedf(mid_r.size.y, 1.0)],
				"hint": [snappedf(hint_r.position.x, 1.0), snappedf(hint_r.position.y, 1.0), snappedf(hint_r.size.x, 1.0), snappedf(hint_r.size.y, 1.0)],
				"glyphs": [snappedf(glyph_r.position.x, 1.0), snappedf(glyph_r.position.y, 1.0), snappedf(glyph_r.size.x, 1.0), snappedf(glyph_r.size.y, 1.0)],
				"hint_vis": _hint.visible if _hint != null else false,
				"step": _lesson.id() if _lesson != null else "",
			},
		}))
		f.close()
	# #endregion


func _style() -> StyleBoxFlat:
	var box := CreatorChrome.panel_style()
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 12.0
	return box
