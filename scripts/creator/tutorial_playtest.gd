class_name TutorialPlaytest
extends RefCounted
## One job on a lesson playtest: land a cart jump, or wipe the pack. Finish it
## and the workbench opens again. Leaving early does not count.

const CART := "res://scenes/vehicles/golf_cart.tscn"
const LAND_HOLD := 3.0

var _goal := GameSettings.TutorialGoal.NONE
var _done := false
var _saw_pack := false
var _saw_air := false
var _landed := false
var _hold := 0.0


func start(goal: GameSettings.TutorialGoal) -> void:
	_goal = goal
	_done = false
	_saw_pack = false
	_saw_air = false
	_landed = false
	_hold = 0.0


func is_done() -> bool:
	return _done


func can_leave() -> bool:
	return _goal == GameSettings.TutorialGoal.NONE or _done


func pause_leave_copy() -> String:
	if can_leave():
		return "Press interact to return to the hole creator."
	match _goal:
		GameSettings.TutorialGoal.DRIVE_RAMP:
			return "Land a cart jump before you go back."
		GameSettings.TutorialGoal.CLEAR_PACK:
			return "Defeat every enemy before you go back."
		_:
			return "Press interact to quit to the menu."


static func banner_body(goal: GameSettings.TutorialGoal) -> String:
	match goal:
		GameSettings.TutorialGoal.DRIVE_RAMP:
			return "Board the cart, drive off a ramp, and land the jump.\nThat takes you back to the workbench."
		GameSettings.TutorialGoal.CLEAR_PACK:
			return "Step onto the tee to start, then wipe out every zombie.\nThat takes you back to the workbench."
		_:
			return ""


static func is_cart(path: String) -> bool:
	return path == CART


static func is_ramp(path: String) -> bool:
	return path.get_file().begins_with("ramp_")


func tick(root: Node, playing: bool, live: int, delta := 0.0) -> bool:
	if _done or _goal == GameSettings.TutorialGoal.NONE:
		return _done
	match _goal:
		GameSettings.TutorialGoal.DRIVE_RAMP:
			_done = _drove_jump(root, delta)
		GameSettings.TutorialGoal.CLEAR_PACK:
			_done = note_zombies(playing, live)
		_:
			pass
	return _done


func note_zombies(playing: bool, live: int) -> bool:
	if _goal != GameSettings.TutorialGoal.CLEAR_PACK:
		return false
	if not playing:
		return false
	if live > 0:
		_saw_pack = true
	_done = _saw_pack and live == 0
	return _done


func note_cart(airborne: bool, delta := 0.0) -> bool:
	if _goal != GameSettings.TutorialGoal.DRIVE_RAMP:
		return false
	if airborne:
		_saw_air = true
		if _landed:
			_landed = false
			_hold = 0.0
		return false
	if _saw_air:
		_landed = true
	if not _landed:
		return false
	_hold += delta
	_done = _hold >= LAND_HOLD
	return _done


func _drove_jump(root: Node, delta: float) -> bool:
	if root == null or not root.is_inside_tree():
		return _done
	var air := false
	var driving := false
	for node in root.get_tree().get_nodes_in_group("golf_carts"):
		var cart := node as GolfCart
		if cart == null or cart.driver == null or cart.driver.is_cpu():
			continue
		driving = true
		if cart.is_airborne():
			air = true
			break
	if driving:
		return note_cart(air, delta)
	if _landed:
		return note_cart(false, delta)
	return _done
