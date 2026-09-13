class_name CreatorHistory
extends RefCounted
## Snapshots of the hole. Each change stores what the hole was; undo walks
## back, redo walks forward. A new change drops the redo side so it cannot
## jump to a hole the player already left.

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


func remember(hole: CustomHole) -> void:
	if hole != null:
		record(hole.to_dict())


func record(before: Dictionary) -> void:
	if before.is_empty():
		return
	_undo.append(before)
	_redo.clear()


func stash(body: Dictionary) -> void:
	record(body)


func clear() -> void:
	_undo.clear()
	_redo.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo(hole: CustomHole) -> bool:
	if hole == null or not can_undo():
		return false
	_redo.append(hole.to_dict())
	hole.take_from(CustomHole.from_dict(_undo.pop_back()))
	return true


func redo(hole: CustomHole) -> bool:
	if hole == null or not can_redo():
		return false
	_undo.append(hole.to_dict())
	hole.take_from(CustomHole.from_dict(_redo.pop_back()))
	return true
