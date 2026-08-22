class_name Splitscreen
extends Node
## Root of the game: one shared 3D world, either a single full-screen seat or
## stacked split-screen. Owns pause, restart, and the quit back to the title.

const TITLE := "res://scenes/ui/main_menu.tscn"

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


func _enter_tree() -> void:
	InputActions.register_for_mode(GameSettings.mode)


func _ready() -> void:
	bottom_viewport.world_3d = top_viewport.world_3d
	_flow = world.get_node("MatchFlow") as MatchFlow
	_players.append(world.get_node("Players/Player1") as Player)
	_players.append(world.get_node("Players/Player2") as Player)
	_solo = GameSettings.is_solo()
	if _solo:
		_players[0].possess_cpu()
		_players[1].listen_to_both_devices()
		_cpu = _players[0]
		_human = _players[1]
		_setup_solo()
	else:
		_human = _players[0]
		_setup_coop()
	_flow.run_ended.connect(_on_run_ended)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_flow.begin()


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


func _process(_delta: float) -> void:
	_update_solo_view()
	var interact := (
		Input.is_action_just_pressed("p1_interact")
		or Input.is_action_just_pressed("p2_interact")
	)
	var pause := (
		Input.is_action_just_pressed("p1_pause")
		or Input.is_action_just_pressed("p2_pause")
	)
	if _ended and (interact or pause):
		_restart()
	elif _paused and interact:
		_quit_to_menu()
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _paused else Input.MOUSE_MODE_CAPTURED
	_broadcast(
		"PAUSED",
		"Press pause again to get back to the round.\nPress interact to quit to the menu.",
		_paused
	)


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quit_to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(TITLE)


func _on_run_ended(_won: bool) -> void:
	_ended = true


func _broadcast(title: String, body: String, shown: bool) -> void:
	top_hud.show_message(title, body, shown)
	if bottom_screen.visible:
		bottom_hud.show_message(title, body, shown)
