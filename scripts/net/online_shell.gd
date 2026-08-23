class_name OnlineShell
extends Node
## One-seat VS match. Pause is local; the round keeps running.
##
## The world renders into a SubViewport at the design resolution, the same way
## split-screen does, rather than straight into the window. Drawing into the
## window means the full native resolution, which on a retina display is several
## times the pixels, and the project's multisampling on top of that. The neon
## look leans on glow and fog, so the cost scales with pixels rather than with
## what is on screen, and the difference is the whole frame budget on a laptop.

const TITLE := "res://scenes/ui/main_menu.tscn"
const _Music := preload("res://scripts/fx/music.gd")

@onready var camera: PlayerCamera = $Screen/Viewport/Camera
@onready var hud: Hud = $Screen/Viewport/Hud
@onready var world: Node3D = $Screen/Viewport/World
@onready var overlay: Label = $PauseLayer/Message

var _local: Player
var _flow: VsMatchFlow
var _debug: NetDebug
var _paused := false
var _ended := false


func _enter_tree() -> void:
	InputActions.register_for_mode(GameSettings.Mode.ONLINE_VS)


func _ready() -> void:
	_flow = world.get_node("VsMatchFlow") as VsMatchFlow
	_flow.run_ended.connect(_on_run_ended)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_Music.play_lounge()
	overlay.visible = false
	_debug = NetDebug.new()
	_debug.world = world
	hud.add_child(_debug)
	call_deferred("_bind_local")


func _bind_local() -> void:
	_local = _find_local()
	if _local == null:
		await get_tree().create_timer(0.15).timeout
		_local = _find_local()
	if _local == null:
		return
	_local.listen_to_both_devices()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.player = _local
	hud.setup(_local, _flow)


func _find_local() -> Player:
	var id := multiplayer.get_unique_id()
	for node in world.get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player != null and player.peer_id == id:
			return player
	return null


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _local != null:
			_local.add_mouse_look((event as InputEventMouseMotion).relative)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		_debug.toggle()


func _process(_delta: float) -> void:
	if _local == null:
		_local = _find_local()
		if _local != null and hud.player == null:
			_bind_local()
	var interact := Input.is_action_just_pressed("p1_interact")
	var pause := Input.is_action_just_pressed("p1_pause")
	if _ended and (interact or pause):
		_restart()
	elif _paused and interact:
		_quit()
	elif pause:
		_toggle_pause()


func _toggle_pause() -> void:
	_paused = not _paused
	overlay.visible = _paused
	overlay.text = HudStyle.chrome(
		"PAUSED\nThe round is still on.\nPause to return.  Interact quits."
	)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _paused else Input.MOUSE_MODE_CAPTURED
	Sfx.play("pause", self)


func _restart() -> void:
	if NetSession.is_host():
		NetSession.start_match()
	else:
		_quit()


func _quit() -> void:
	NetSession.quit_to_menu()


func _on_run_ended(_won: bool) -> void:
	_ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
