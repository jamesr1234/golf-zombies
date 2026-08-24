@tool
extends Node3D
## Hole overlay you edit in Godot. Builds a live preview of the generated hole
## so props can be placed on it. The preview is not saved.

const _Overlay := preload("res://scripts/course/hole_overlay.gd")
const PREVIEW_SEED := 20260816

@export var hole_index := 0:
	set(value):
		hole_index = value
		_refresh()

@export var preview_seed := PREVIEW_SEED:
	set(value):
		preview_seed = value
		_refresh()


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	for child in get_children(true):
		if child.name == _Overlay.PREVIEW_NAME:
			child.free()
	_Overlay._live_root = self
	_Overlay._suspend_attach += 1
	var data := HoleGenerator.generate(hole_index, preview_seed)
	var preview := HoleBuilder.build(data)
	_Overlay._suspend_attach -= 1
	_Overlay._live_root = null
	preview.name = _Overlay.PREVIEW_NAME
	preview.set_meta("overlay_preview", true)
	preview.set_meta("_edit_lock_", true)
	add_child(preview, false, INTERNAL_MODE_BACK)
	_Overlay.apply_lifted(self, data)
