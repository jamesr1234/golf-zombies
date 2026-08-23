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
var _cpu_on := false
var _ghost: InputGhost
var _brain: VsCpu
var _cpu_banner: Label


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
	_cpu_banner = Label.new()
	_cpu_banner.visible = false
	_cpu_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cpu_banner.anchor_left = 0.5
	_cpu_banner.anchor_right = 0.5
	_cpu_banner.offset_left = -160.0
	_cpu_banner.offset_right = 160.0
	_cpu_banner.offset_top = 18.0
	_cpu_banner.offset_bottom = 48.0
	_cpu_banner.label_settings = HudStyle.readout(Palette.LIME, 18)
	overlay.get_parent().add_child(_cpu_banner)
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
	if _cpu_on and _brain != null and _ghost != null:
		_brain.setup(_local, _ghost)


func _find_local() -> Player:
	var id := multiplayer.get_unique_id()
	for node in world.get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player != null and player.peer_id == id:
			return player
	return null


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _local != null and not _cpu_on:
			_local.add_mouse_look((event as InputEventMouseMotion).relative)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F3:
		_debug.toggle()
	elif key.keycode == KEY_F4:
		_toggle_cpu()


func _physics_process(delta: float) -> void:
	if not _cpu_on or _paused or _ended or _local == null or _ghost == null or _brain == null:
		return
	_ghost.begin_frame()
	_brain.tick(delta)
	_ghost.apply()


func _toggle_cpu() -> void:
	if _local == null:
		_local = _find_local()
	if _local == null:
		return
	_cpu_on = not _cpu_on
	if _cpu_on:
		if _ghost == null:
			_ghost = InputGhost.new()
		if _brain == null:
			_brain = VsCpu.new()
		_brain.setup(_local, _ghost)
	elif _ghost != null:
		_ghost.release_all()
	_cpu_banner.visible = _cpu_on
	_cpu_banner.text = HudStyle.chrome("CPU ON" if _cpu_on else "CPU OFF")
	if not _cpu_on:
		_cpu_banner.visible = true
		get_tree().create_timer(1.2).timeout.connect(
			func() -> void:
				if not _cpu_on and _cpu_banner != null:
					_cpu_banner.visible = false
		)


func _exit_tree() -> void:
	if _ghost != null:
		_ghost.release_all()


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
