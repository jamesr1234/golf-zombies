class_name DemoBoot
extends Control
## Web demo title. Browsers only allow sound and fullscreen after a tap, so the
## whole screen is one big "tap to play" that sets up a solo round of the
## bundled hole.

const HOLE := "res://resources/demo/demo_hole.json"
const ROUND := "res://scenes/demo/demo_main.tscn"

var _started := false
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
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _process(_delta: float) -> void:
	_turn_hint.visible = size.y > size.x


func start() -> void:
	if _started or not setup_round():
		return
	_started = true
	if OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		# Browsers only allow this after the tap. iPhone Safari ignores it.
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	get_tree().change_scene_to_file(ROUND)


func _build() -> void:
	var back := ColorRect.new()
	back.color = Palette.NIGHT
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)
	column.add_child(_label("GOLF IS?", HudStyle.banner(Palette.CYAN, 56)))
	column.add_child(_label("ONE HOLE. ZOMBIES. GOOD LUCK.", HudStyle.readout(Palette.ICE)))
	column.add_child(_label("TAP TO PLAY", HudStyle.banner(Palette.ORANGE)))
	_turn_hint = _label("TURN SIDEWAYS IF THE PICTURE WILL LET YOU", HudStyle.readout(Palette.AMBER))
	column.add_child(_turn_hint)
	var tap := Button.new()
	tap.flat = true
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(start)
	add_child(tap)


func _label(text: String, settings: LabelSettings) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
