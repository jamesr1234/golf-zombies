class_name Splitscreen
extends Node
## Root of the game: one shared 3D world, either a single full-screen seat or
## stacked split-screen. Owns pause, restart, and the quit back to the title.

const TITLE := "res://scenes/ui/main_menu.tscn"
const CREATOR := "res://scenes/creator/hole_creator.tscn"
const _Tutorial := preload("res://scripts/creator/tutorial_playtest.gd")
const _CPU_SEAT := "Screens/Top/Viewport/World/Players/Player1"

## Off for the web demo: the solo human plays without the CPU partner.
@export var companion := true
## Off for touch screens, where captured-mouse look would fight the touch layer.
@export var capture_mouse := true
## Where quitting lands. A finished run goes here too when leave_on_end is set.
@export_file("*.tscn") var title_scene := TITLE
@export var leave_on_end := false

@onready var screens: VBoxContainer = $Screens
@onready var top_screen: SubViewportContainer = $Screens/Top
@onready var bottom_screen: SubViewportContainer = $Screens/Bottom
@onready var top_viewport: SubViewport = $Screens/Top/Viewport
@onready var bottom_viewport: SubViewport = $Screens/Bottom/Viewport
@onready var top_camera: PlayerCamera = $Screens/Top/Viewport/Camera
@onready var bottom_camera: PlayerCamera = $Screens/Bottom/Viewport/Camera
@onready var top_hud: Hud = $Screens/Top/Viewport/Hud
@onready var bottom_hud: Hud = $Screens/Bottom/Viewport/Hud
@onready var world: Node3D = $Screens/Top/Viewport/World

var _players: Array[Player] = []
var _human: Player
var _cpu: Player
var _flow: MatchFlow
var _paused := false
var _ended := false
var _solo := true
var _leaving := false
var _drill: _Tutorial


func _enter_tree() -> void:
	InputActions.register_for_mode(GameSettings.mode)
	# Gone before the world is ready, so MatchFlow only ever collects the human.
	var seat := get_node_or_null(_CPU_SEAT)
	if not companion and GameSettings.is_solo() and seat != null:
		seat.get_parent().remove_child(seat)
		seat.free()


func _ready() -> void:
	bottom_viewport.world_3d = top_viewport.world_3d
	_flow = world.get_node("MatchFlow") as MatchFlow
	var seat := world.get_node_or_null("Players/Player1") as Player
	if seat != null:
		_players.append(seat)
	_players.append(world.get_node("Players/Player2") as Player)
	_solo = GameSettings.is_solo()
	if _solo:
		if seat != null:
			seat.possess_cpu()
			_cpu = seat
		_human = _players[_players.size() - 1]
		_human.listen_to_both_devices()
		_setup_solo()
	else:
		_human = _players[0]
		_setup_coop()
	_flow.run_ended.connect(_on_run_ended)
	if GameSettings.tutorial_goal != GameSettings.TutorialGoal.NONE:
		_drill = _Tutorial.new()
		_drill.start(GameSettings.tutorial_goal)
	_set_captured(true)
	_flow.begin()


func human() -> Player:
	return _human


func flow() -> MatchFlow:
	return _flow


func is_ended() -> bool:
	return _ended


func _setup_solo() -> void:
	bottom_screen.visible = false
	screens.add_theme_constant_override("separation", 0)
	top_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	top_camera.player = _human
	top_hud.setup(_human, _flow)


func _setup_coop() -> void:
	top_camera.keep_aspect = Camera3D.KEEP_WIDTH
	bottom_camera.keep_aspect = Camera3D.KEEP_WIDTH
	top_camera.player = _players[0]
	bottom_camera.player = _players[1]
	top_hud.setup(_players[0], _flow)
	bottom_hud.setup(_players[1], _flow)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).relative
		for player in _players:
			if not player.is_cpu():
				player.add_mouse_look(motion)


func _process(delta: float) -> void:
	_update_solo_view()
	if _drill != null and not _ended and not _leaving:
		if _drill.tick(
			world,
			_flow.phase == MatchFlow.Phase.PLAYING,
			_flow.spawner.live_count() if _flow.spawner != null else 0,
			delta
		):
			_leave_match()
			return
	var interact := (
		Input.is_action_just_pressed("p1_interact")
		or Input.is_action_just_pressed("p2_interact")
	)
	var pause := (
		Input.is_action_just_pressed("p1_pause")
		or Input.is_action_just_pressed("p2_pause")
	)
	if _ended and (interact or pause):
		if GameSettings.return_to_creator:
			if _drill != null and not _drill.can_leave():
				_restart()
			else:
				_leave_match()
		elif leave_on_end:
			_leave_match()
		else:
			_restart()
	elif _paused and interact:
		if _drill != null and not _drill.can_leave():
			return
		_leave_match()
	elif pause:
		_toggle_pause()


func _update_solo_view() -> void:
	if not _solo or _human == null:
		return
	var view := _cpu if _cpu != null and _cpu.is_golfing() else _human
	top_camera.player = view
	top_hud.player = view


func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	_set_captured(not _paused)
	_broadcast(
		"PAUSED",
		"Press pause again to get back to the round.\n%s" % _pause_leave_copy(),
		_paused
	)


func _pause_leave_copy() -> String:
	if _drill != null:
		return _drill.pause_leave_copy()
	if GameSettings.return_to_creator:
		return "Press interact to return to the hole creator."
	return "Press interact to quit to the menu."


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quit_to_menu() -> void:
	_leave_match()


func _leave_match() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var path := CREATOR if GameSettings.take_return_to_creator() else title_scene
	get_tree().change_scene_to_file(path)


func _on_run_ended(_won: bool) -> void:
	_ended = true


func _set_captured(on: bool) -> void:
	var captured := on and capture_mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _broadcast(title: String, body: String, shown: bool) -> void:
	top_hud.show_message(title, body, shown)
	if bottom_screen.visible:
		bottom_hud.show_message(title, body, shown)
