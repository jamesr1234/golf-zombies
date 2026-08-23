class_name InputGhost
extends RefCounted
## Presses the same p1_* actions a keyboard or pad would, so a Computer 2 CPU
## goes through PlayerInput and the existing online RPCs.

const BUTTONS: PackedStringArray = [
	"sprint", "jump", "shoot", "reload", "melee", "interact", "revive", "swing",
	"shield", "aim", "zoom",
]
const FORBIDDEN: PackedStringArray = ["pause", "map"]

var prefix := "p1"
var move := Vector2.ZERO
var look := Vector2.ZERO

var _held := {}
var _taps := {}
var _down := {}


func _init(p_prefix := "p1") -> void:
	prefix = p_prefix
	InputActions.register_all()


func begin_frame() -> void:
	for name in _taps.keys():
		_set_strength(String(name), 0.0)
	_taps.clear()
	_held.clear()
	move = Vector2.ZERO
	look = Vector2.ZERO


func hold(name: String, on := true) -> void:
	if name in FORBIDDEN:
		return
	_held[name] = on


func tap(name: String) -> void:
	if name in FORBIDDEN:
		return
	_taps[name] = true
	_held[name] = true


func wants(name: String) -> bool:
	return bool(_held.get(name, false)) or bool(_taps.get(name, false))


func apply() -> void:
	_set_strength("move_left", maxf(-move.x, 0.0))
	_set_strength("move_right", maxf(move.x, 0.0))
	_set_strength("move_forward", maxf(-move.y, 0.0))
	_set_strength("move_back", maxf(move.y, 0.0))
	_set_strength("look_left", maxf(-look.x, 0.0))
	_set_strength("look_right", maxf(look.x, 0.0))
	_set_strength("look_up", maxf(-look.y, 0.0))
	_set_strength("look_down", maxf(look.y, 0.0))
	for name in BUTTONS:
		_set_strength(name, 1.0 if wants(name) else 0.0)


func release_all() -> void:
	for action in _down.keys():
		if InputMap.has_action(action):
			Input.action_release(action)
	_down.clear()
	_taps.clear()
	_held.clear()
	move = Vector2.ZERO
	look = Vector2.ZERO


func _set_strength(suffix: String, strength: float) -> void:
	var action := "%s_%s" % [prefix, suffix]
	if not InputMap.has_action(action):
		return
	if strength > 0.01:
		Input.action_press(action, clampf(strength, 0.0, 1.0))
		_down[action] = true
	elif _down.get(action, false):
		Input.action_release(action)
		_down.erase(action)
