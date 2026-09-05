class_name HoleBrowser
extends Control
## The holes this player has made. Pick one to play it as a round of one, or
## open it back up in the creator.

const MENU := "res://scenes/ui/main_menu.tscn"
const CREATOR := "res://scenes/creator/hole_creator.tscn"
const GAMEPLAY := "res://scenes/main.tscn"
const _Music := preload("res://scripts/fx/music.gd")
## Circle plays, Square edits, Triangle starts a new hole, L1 deletes.
const PAD_KEYS: PackedStringArray = [
	"move_forward", "move_back", "interact", "jump", "reload", "revive", "melee", "pause",
]

var rows: Array[Dictionary] = []
var picked := 0

var _list: VBoxContainer
var _blurb: Label
var _leaving := false
var _open := false
var _pad := PadInput.new()


func _enter_tree() -> void:
	InputActions.register_all()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	reload()
	_Music.play_lounge()
	# The title click that opened this is still down on the first frame.
	_open_later.call_deferred()


func reload() -> void:
	rows = HoleStore.list_holes()
	picked = clampi(picked, 0, _count() - 1)
	_refresh()


func move(delta: int) -> void:
	picked = posmod(picked + delta, _count())
	Sfx.play("ui_move", self)
	_refresh()


func picking_new() -> bool:
	return picked == 0


func play() -> void:
	if picking_new():
		create()
		return
	var hole := _selected()
	if hole == null:
		return
	if not hole.is_playable():
		Sfx.play("ui_deny", self)
		return
	Sfx.play("ui_confirm", self)
	GameSettings.play_custom(hole)
	_go(GAMEPLAY)


func edit() -> void:
	if picking_new():
		create()
		return
	var hole := _selected()
	if hole == null:
		return
	Sfx.play("ui_confirm", self)
	GameSettings.edit_custom(hole)
	_go(CREATOR)


func create() -> void:
	Sfx.play("ui_confirm", self)
	var hole := CustomHole.create()
	hole.needs_width = true
	GameSettings.edit_custom(hole)
	_go(CREATOR)


func erase() -> void:
	if picking_new() or rows.is_empty():
		return
	Sfx.play("ui_back", self)
	HoleStore.delete_hole(String(rows[_hole_index()]["id"]))
	reload()


func back() -> void:
	Sfx.play("ui_back", self)
	_go(MENU)


func _selected() -> CustomHole:
	if picking_new() or rows.is_empty():
		return null
	return HoleStore.load_hole(String(rows[_hole_index()]["id"]))


func _count() -> int:
	return rows.size() + 1


func _hole_index() -> int:
	return picked - 1


func _open_later() -> void:
	_open = true


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not _open or _leaving or key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_W, KEY_UP:
			move(-1)
		KEY_S, KEY_DOWN:
			move(1)
		KEY_E, KEY_ENTER, KEY_SPACE:
			play()
		KEY_C:
			edit()
		KEY_N:
			create()
		KEY_X, KEY_DELETE:
			erase()
		KEY_ESCAPE:
			back()
		_:
			return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


## The pad runs the same six commands. It is polled rather than read as events
## so each button counts once, and it only ever sees the controller, never the
## keyboard half of the same action.
func _process(_delta: float) -> void:
	if not _open or _leaving:
		return
	# Every button is read before any of them acts, so a press is never missed
	# because an earlier branch short-circuited the poll.
	var fired: Dictionary = {}
	for suffix in PAD_KEYS:
		fired[suffix] = _pad.just(suffix)
	if fired["move_forward"]:
		move(-1)
	elif fired["move_back"]:
		move(1)
	elif fired["interact"] or fired["jump"]:
		play()
	elif fired["reload"]:
		edit()
	elif fired["revive"]:
		create()
	elif fired["melee"]:
		erase()
	elif fired["pause"]:
		back()


func _go(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(path)


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	_list.add_child(_new_entry(picking_new()))
	if picking_new():
		_blurb.text = HudStyle.chrome("Start a blank hole.")
	else:
		var row: Dictionary = rows[_hole_index()]
		_blurb.text = HudStyle.chrome("Par %d   %d m   %d pieces   %d props%s%s" % [
			int(row["par"]), roundi(float(row["length"])), int(row["pieces"]),
			int(row["placements"]), "" if bool(row["playable"]) else "   NEEDS MORE FAIRWAY",
			_replace_note(row),
		])
	for i in rows.size():
		_list.add_child(_entry(rows[i], picked == i + 1, i + 1))


func _replace_note(row: Dictionary) -> String:
	if not bool(row["playable"]):
		return ""
	var slot := HoleStore.course_slot(String(row["title"]))
	if slot < 0:
		return ""
	return "   REPLACES HOLE %d" % (slot + 1)


func _new_entry(selected: bool) -> Button:
	var button := LobbyChrome.button("New hole")
	button.custom_minimum_size = Vector2(460.0, 40.0)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_color_override("font_color", Palette.LIME if selected else Palette.ICE)
	button.add_theme_stylebox_override("normal", _option_style(selected))
	button.add_theme_stylebox_override("hover", _option_style(true))
	button.add_theme_stylebox_override("pressed", _option_style(true))
	button.pressed.connect(func() -> void:
		if not _open:
			return
		if picking_new():
			create()
			return
		picked = 0
		_refresh()
	)
	return button


func _entry(row: Dictionary, selected: bool, index: int) -> Button:
	var button := LobbyChrome.button(String(row["title"]))
	button.custom_minimum_size = Vector2(460.0, 40.0)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_color_override("font_color", Palette.MAGENTA if selected else Palette.ICE)
	button.add_theme_stylebox_override("normal", _option_style(selected))
	button.add_theme_stylebox_override("hover", _option_style(true))
	button.add_theme_stylebox_override("pressed", _option_style(true))
	button.pressed.connect(func() -> void:
		if not _open:
			return
		if picked == index:
			edit()
			return
		picked = index
		_refresh()
	)
	return button


func _build() -> void:
	var night := ColorRect.new()
	night.set_anchors_preset(Control.PRESET_FULL_RECT)
	night.color = Palette.NIGHT
	night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(night)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 80.0
	root.offset_top = 36.0
	root.offset_right = -80.0
	root.offset_bottom = -36.0
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.label_settings = HudStyle.banner(Palette.MAGENTA, 44)
	title.text = HudStyle.chrome("Course Creator")
	root.add_child(title)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	column.add_child(_list)

	_blurb = Label.new()
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blurb.label_settings = HudStyle.readout(Palette.ICE, 16)
	column.add_child(_blurb)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.label_settings = HudStyle.readout(Palette.LIME, 14)
	hint.text = HudStyle.chrome(
		"W/S or stick move   click / C / Square edit   E / Circle play"
		+ "   N / Triangle new   X / L1 delete   Esc / Options back"
	)
	root.add_child(hint)


func _panel_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.NIGHT, 0.88)
	box.border_color = Color(Palette.CYAN, 0.7)
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.content_margin_left = 22.0
	box.content_margin_right = 22.0
	box.content_margin_top = 14.0
	box.content_margin_bottom = 14.0
	return box


func _option_style(selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.MAGENTA, 0.18) if selected else Color(0.06, 0.04, 0.1, 0.7)
	box.border_color = Palette.MAGENTA if selected else Color(Palette.CYAN, 0.35)
	box.set_border_width_all(2 if selected else 1)
	box.set_corner_radius_all(3)
	return box
