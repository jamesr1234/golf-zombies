class_name CreatorUi
extends CanvasLayer
## Chrome for the hole creator, built in code and styled off HudStyle and
## Palette so it reads like the rest of the game rather than like an editor.

signal save_requested(title: String)
signal group_requested(title: String)
signal merge_requested
signal exit_requested
signal playtest_requested
signal overview_requested
signal name_requested
signal width_picked(size: FairwayPiece.Width)
signal width_cancelled

const FLASH_SECONDS := 2.6
const PALETTE_HEIGHT := 340.0

var _title: Label
var _stat: Label
var _tool: Label
var _picked: Label
var _heading: Label
var _flash: Label
var _key_hint: Label
var _pad_hint: Label
var _scroll: ScrollContainer
var _palette: VBoxContainer
var _keypad: CreatorKeypad
var _width: CreatorWidth
var _menu: PanelContainer
## Menu rows are held as data so the stick can walk them, not just the mouse.
var _menu_rows: Array[Button] = []
var _menu_pick := 0
var _flash_left := 0.0
## The creator asks for a redraw every frame. Rebuilding label settings that
## often is wasted work, so a repeat of what is already on screen is dropped.
var _shown := ""
var _shelf := ""
## Which of the two things the open name field is naming.
var _grouping := false


static func create() -> CreatorUi:
	var ui := CreatorUi.new()
	ui.name = "CreatorUi"
	return ui


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	_flash.modulate.a = clampf(_flash_left / FLASH_SECONDS * 2.0, 0.0, 1.0)
	if _flash_left <= 0.0:
		_flash.text = ""


func is_typing() -> bool:
	return _keypad != null and _keypad.is_open()


func picking_width() -> bool:
	return _width != null and _width.is_open()


func ask_width() -> void:
	_width.open()


func _mark_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func flash(message: String) -> void:
	_flash.text = HudStyle.chrome(message)
	_flash.modulate.a = 1.0
	_flash_left = FLASH_SECONDS


## Escape backs out of the name pad before it reaches the creator, which would
## otherwise read it as a request to pause.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not is_typing():
		return
	if _keypad.handle_key(key):
		_mark_handled()


func show_hole(hole: CustomHole, tool_name: String, stat: String, picked: String) -> void:
	var line := "PAR %d   %d M   %s   %d PIECES   %d PLACED" % [
		hole.par(), roundi(hole.length()), hole.width_label(), hole.pieces.size(),
		hole.placements.size()
	]
	var state := "%s|%s|%s|%s" % [hole.title, line, tool_name, picked + stat]
	if state == _shown:
		return
	_shown = state
	_title.text = HudStyle.chrome(hole.title)
	_stat.text = HudStyle.chrome("%s\n%s" % [line, stat])
	_tool.text = HudStyle.chrome(tool_name)
	_picked.text = HudStyle.chrome(picked)


func show_palette(
	labels: PackedStringArray, selected: int, allowed: Array[bool], heading := ""
) -> void:
	var state := "%s|%s|%d|%s" % [heading, ", ".join(labels), selected, str(allowed)]
	if state == _shelf:
		return
	_shelf = state
	_heading.text = HudStyle.chrome(heading)
	_heading.visible = not heading.is_empty()
	_scroll.visible = not labels.is_empty()
	_picked.visible = labels.is_empty()
	_scroll.custom_minimum_size.y = minf(PALETTE_HEIGHT, float(maxi(labels.size(), 1)) * 20.0)
	CreatorChrome.fill_palette(_palette, labels, selected, allowed)
	CreatorChrome.reveal(_scroll, _palette, selected)


## Opens the name pad on OK, so a pad can take the suggestion or edit it.
func ask_save(current: String) -> void:
	_grouping = false
	_keypad.open("NAME THIS HOLE", current)


## Opens the name pad on OK, so a pad can take the suggestion or edit it.
func ask_group(suggested := "") -> void:
	_grouping = true
	_keypad.open("NAME THIS STRUCTURE", suggested)


func toggle_menu() -> void:
	if is_typing():
		_keypad.close()
		_restore_mouse()
		return
	_menu.visible = not _menu.visible
	_menu_pick = 0
	_show_menu_pick()
	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE if _menu.visible else Input.MOUSE_MODE_CAPTURED
	)


func menu_is_open() -> bool:
	return _menu != null and _menu.visible


func move_menu(delta: int) -> void:
	if not menu_is_open() or _menu_rows.is_empty():
		return
	_menu_pick = posmod(_menu_pick + delta, _menu_rows.size())
	_show_menu_pick()
	Sfx.play("ui_move", self)


func pick_menu() -> void:
	if not menu_is_open() or _menu_pick >= _menu_rows.size():
		return
	_menu_rows[_menu_pick].pressed.emit()


func _show_menu_pick() -> void:
	for i in _menu_rows.size():
		_menu_rows[i].add_theme_color_override(
			"font_color", Palette.MAGENTA if i == _menu_pick else Palette.ICE
		)


func _submit(text: String) -> void:
	var grouping := _grouping
	_restore_mouse()
	if grouping:
		group_requested.emit(text)
	else:
		save_requested.emit(text)


func _restore_mouse() -> void:
	if not _menu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var side := CreatorChrome.bar(root, Control.PRESET_TOP_LEFT, Vector2(18.0, 16.0))
	_title = CreatorChrome.label(Palette.MAGENTA, 26, true)
	side.add_child(_title)
	_stat = CreatorChrome.label(Palette.CYAN, 16)
	side.add_child(_stat)
	_tool = CreatorChrome.label(Palette.AMBER, 20)
	side.add_child(_tool)
	_picked = CreatorChrome.label(Palette.ICE, 15)
	side.add_child(_picked)
	_heading = CreatorChrome.label(Palette.LIME, 14)
	side.add_child(_heading)
	_scroll = CreatorChrome.scroller(PALETTE_HEIGHT)
	_palette = VBoxContainer.new()
	_palette.add_theme_constant_override("separation", 2)
	_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_palette)
	side.add_child(_scroll)

	_flash = CreatorChrome.banner_line(root, Palette.LIME, 20, 96.0)
	_key_hint = CreatorChrome.footer(root, CreatorPad.HINT)
	_pad_hint = CreatorChrome.footer(root, CreatorPad.PAD_HINT)
	_pad_hint.offset_top = -52.0
	CreatorChrome.crosshair(root)
	_keypad = CreatorKeypad.create()
	_keypad.submitted.connect(_submit)
	_keypad.cancelled.connect(_restore_mouse)
	root.add_child(_keypad)
	_width = CreatorWidth.create()
	_width.picked.connect(width_picked.emit)
	_width.cancelled.connect(width_cancelled.emit)
	root.add_child(_width)
	_build_menu(root)


## Saving, playtesting and the overview live here as well as on keys, because a
## pad has no spare button left once the building loop has its own.
func _build_menu(root: Control) -> void:
	var column := CreatorChrome.panel(root, Vector2(180.0, 140.0))
	_menu = column.get_parent() as PanelContainer
	var heading := CreatorChrome.centered(Palette.AMBER, 20)
	heading.text = HudStyle.chrome("Paused")
	column.add_child(heading)
	_add_menu_row(column, "Keep building", toggle_menu)
	_add_menu_row(column, "Name and save", _close_then.bind(name_requested))
	_add_menu_row(column, "Merge group", _close_then.bind(merge_requested))
	_add_menu_row(column, "Playtest", _close_then.bind(playtest_requested))
	_add_menu_row(column, "Overview", _close_then.bind(overview_requested))
	_add_menu_row(column, "Save and quit", _save_and_quit)
	_add_menu_row(column, "Quit without saving", exit_requested.emit)
	_show_menu_pick()


func _add_menu_row(column: VBoxContainer, text: String, action: Callable) -> void:
	var made := CreatorChrome.button(text, action)
	_menu_rows.append(made)
	column.add_child(made)


func _close_then(after: Signal) -> void:
	toggle_menu()
	after.emit()


func _save_and_quit() -> void:
	save_requested.emit("")
	exit_requested.emit()
