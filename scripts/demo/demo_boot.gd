class_name DemoBoot
extends Control
## Web demo menu. Practice is free and unlimited. A bottle's QR code (?c= on
## the address) adds Ranked: three tries on the online leaderboard, under a
## nickname picked once per bottle.

const HOLE := "res://resources/demo/demo_hole.json"
const ROUND := "res://scenes/demo/demo_main.tscn"
const MENU := "res://scenes/demo/demo_boot.tscn"
const NAME_PROMPT := "Pick a leaderboard nickname (2-14 letters or numbers). You only get to pick once for this bottle."

var _busy := false
var _armed := false
var _code := ""
var _status := {}
var _api: LeaderboardApi
var _info: Label
var _ranked: Button
var _name_button: Button
var _name_box: LineEdit
var _turn_hint: Label


static func setup_round() -> bool:
	var hole := HoleStore.load_bundled(HOLE)
	if hole == null:
		return false
	GameSettings.reset()
	GameSettings.mode = GameSettings.Mode.SOLO
	GameSettings.difficulty = GameSettings.Kind.EASY
	GameSettings.custom_hole = hole
	return true


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_api = LeaderboardApi.new()
	add_child(_api)
	_build()
	_code = DemoRun.page_code()
	if _code.is_empty():
		_info.text = "Scan the code on a bottle to play for the leaderboard."
	elif not DemoRun.valid_code(_code):
		_info.text = "That bottle code doesn't look right. Try scanning it again."
	else:
		DemoRun.code = _code
		_refresh()


func _process(_delta: float) -> void:
	_turn_hint.visible = size.y > size.x


func _refresh() -> void:
	_info.text = "Checking your bottle..."
	var reply := await _api.code_status(_code)
	if not reply.ok:
		_info.text = reply.error
		return
	_status = reply.data
	_show_status()


func _show_status() -> void:
	var named := not str(_status.get("nickname", "")).is_empty()
	_name_button.visible = not named
	_ranked.visible = named
	_ranked.disabled = int(_status.get("tries_left", 0)) <= 0
	var lines := PackedStringArray()
	if named:
		lines.append("Playing as %s" % _status.nickname)
	lines.append(DemoRun.tries_copy(_status))
	var best := DemoRun.best_copy(_status)
	if not best.is_empty():
		lines.append(best)
	_info.text = "\n".join(lines)


func practice() -> void:
	if _busy:
		return
	DemoRun.begin(false)
	_play()


func ranked() -> void:
	if _busy:
		return
	if not _armed:
		_armed = true
		_ranked.text = "TAP AGAIN TO USE 1 TRY"
		return
	_busy = true
	_go_fullscreen()
	_info.text = "Starting your ranked round..."
	var reply := await _api.start_run(_code)
	if not reply.ok:
		_busy = false
		_armed = false
		_ranked.text = "PLAY RANKED"
		_info.text = reply.error
		return
	DemoRun.begin(true, str(reply.data.ticket))
	_play()


func _play() -> void:
	if not setup_round():
		return
	_busy = true
	_go_fullscreen()
	DemoEnd.played = false
	get_tree().change_scene_to_file(ROUND)


## Browsers only allow these straight after a tap. iPhone Safari ignores both.
func _go_fullscreen() -> void:
	if OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)


## The web canvas can't raise a phone keyboard, so the browser's own prompt asks.
func _ask_name() -> void:
	if not OS.has_feature("web"):
		_name_box.visible = true
		_name_box.grab_focus()
		return
	var raw := str(JavaScriptBridge.eval("prompt(%s)||''" % JSON.stringify(NAME_PROMPT), true))
	if not raw.strip_edges().is_empty():
		_save_name(raw)


func _save_name(raw: String) -> void:
	if _busy:
		return
	_busy = true
	var reply := await _api.set_nickname(_code, raw)
	_busy = false
	if not reply.ok:
		_info.text = reply.error
		return
	_name_box.visible = false
	_status.nickname = reply.data.nickname
	_show_status()


func _open_board() -> void:
	OS.shell_open(LeaderboardApi.base_url() + "/leaderboard")


func _build() -> void:
	var column := DemoUi.column(self)
	column.add_child(DemoUi.label("GOLF IS?", HudStyle.banner(Palette.CYAN, 56)))
	column.add_child(DemoUi.label("ONE HOLE. ZOMBIES. GOOD LUCK.", HudStyle.readout(Palette.ICE)))
	column.add_child(DemoUi.button("PRACTICE", practice))
	_name_button = DemoUi.button("PICK A NICKNAME", _ask_name)
	_name_button.visible = false
	column.add_child(_name_button)
	_name_box = LineEdit.new()
	_name_box.placeholder_text = "Nickname"
	_name_box.max_length = 14
	_name_box.custom_minimum_size = Vector2(360, 56)
	_name_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_name_box.visible = false
	_name_box.text_submitted.connect(_save_name)
	column.add_child(_name_box)
	_ranked = DemoUi.button("PLAY RANKED", ranked)
	_ranked.visible = false
	column.add_child(_ranked)
	_info = DemoUi.label("", HudStyle.readout(Palette.AMBER))
	column.add_child(_info)
	column.add_child(DemoUi.button("LEADERBOARD", _open_board))
	_turn_hint = DemoUi.label("TURN SIDEWAYS IF THE PICTURE WILL LET YOU", HudStyle.readout(Palette.ICE))
	column.add_child(_turn_hint)
