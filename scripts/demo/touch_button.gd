class_name TouchButton
extends RefCounted
## One round on-screen button. Holding it holds every action it names, the way
## a left click holds both shoot and swing on the desktop.

var label := ""
var actions: PackedStringArray
## Fraction of the screen, measured from the bottom-right corner, so the layout
## follows any phone size.
var anchor := Vector2.ZERO
var radius := 60.0
var visible := true
## Browsers hand out any integer as a finger id, negative ones included.
var finger := 0
var held := false
var center := Vector2.ZERO
var _latched: PackedStringArray = PackedStringArray()


func _init(p_label: String, p_actions: PackedStringArray, p_anchor: Vector2, p_radius := 60.0) -> void:
	label = p_label
	actions = p_actions
	anchor = p_anchor
	radius = p_radius


func place(screen: Vector2) -> void:
	# The short side, so a tall upright phone doesn't drag the buttons over the stick.
	var unit := minf(screen.x, screen.y)
	center = Vector2(screen.x, screen.y) - anchor * unit


func contains(at: Vector2) -> bool:
	return visible and at.distance_to(center) <= radius * 1.15


func press(index: int) -> void:
	finger = index
	held = true
	_latched = actions.duplicate()
	for action in _latched:
		# A stuck press would make the next jump or swing look like it is still held.
		Input.action_release(action)
		Input.action_press(action)


func release() -> void:
	if not held and _latched.is_empty():
		return
	held = false
	for action in _latched:
		Input.action_release(action)
	_latched = PackedStringArray()


func is_held() -> bool:
	return held
