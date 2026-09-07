class_name CreatorHistory
extends RefCounted
## One take-back. Backspace / L2 stores the hole as it was; Redo puts that
## change back. A new place clears the slot so redo cannot jump to a stale hole.

var _redo: Dictionary = {}


func remember(hole: CustomHole) -> void:
	if hole != null:
		stash(hole.to_dict())


func stash(body: Dictionary) -> void:
	_redo = body


func clear() -> void:
	_redo = {}


func can_redo() -> bool:
	return not _redo.is_empty()


func redo(hole: CustomHole) -> bool:
	if hole == null or not can_redo():
		return false
	hole.take_from(CustomHole.from_dict(_redo))
	_redo = {}
	return true
