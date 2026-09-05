@tool
extends RefCounted
## 3D editor translate snap is the extra-small cube so pieces meet flush.
## The placement math itself lives in GridSnap so the in-game hole creator and
## the editor agree; this file only drives the editor's Snap Settings dialog.


const CELL := GridSnap.CELL
const META_SECTION := "3d_editor"
const META_KEY := "snap_translate_value"
const ASSET_DIR := GridSnap.ASSET_DIR


static func to_grid(at: Vector3) -> Vector3:
	return GridSnap.to_grid(at)


static func is_obstacle(node: Node) -> bool:
	return GridSnap.is_obstacle(node)


static func world_aabb(node: Node) -> AABB:
	return GridSnap.world_aabb(node)


static func neighbor_boxes(root: Node, except: Node = null) -> Array:
	return GridSnap.neighbor_boxes(root, except)


static func place(from: Vector3, box: AABB, others: Array) -> Vector3:
	return GridSnap.place(from, box, others)


static func placed(node: Node3D, root: Node) -> Vector3:
	return GridSnap.placed(node, root)


static func is_snap_dialog(node: Node) -> bool:
	var dialog := node as ConfirmationDialog
	return dialog != null and dialog.title == "Snap Settings"


static func is_translate_snap_slider(node: Node) -> bool:
	if node == null or node.get_class() != "EditorSpinSlider":
		return false
	if str(node.get("accessibility_name")) == "Translate Snap":
		return true
	return str(node.get("suffix")) == "m"


static func is_use_snap_button(node: Node) -> bool:
	var button := node as Button
	if button == null or not button.toggle_mode:
		return false
	return str(button.get("accessibility_name")) == "Use Snap"


static func find_snap_dialog(root: Node) -> ConfirmationDialog:
	if root == null:
		return null
	for node in root.find_children("*", "ConfirmationDialog", true, false):
		if is_snap_dialog(node):
			return node
	return null


static func find_translate_slider(root: Node) -> Range:
	if root == null:
		return null
	for node in root.find_children("*", "EditorSpinSlider", true, false):
		if is_translate_snap_slider(node):
			return node as Range
	return null


static func find_use_snap_button(root: Node) -> Button:
	if root == null:
		return null
	for node in root.find_children("*", "Button", true, false):
		if is_use_snap_button(node):
			return node
	return null


static func apply(root: Node, settings: Variant = null) -> bool:
	if settings:
		settings.set_project_metadata(META_SECTION, META_KEY, CELL)
	var dialog := find_snap_dialog(root)
	var slider := find_translate_slider(dialog)
	if slider == null:
		return false
	slider.set_value(CELL)
	if dialog:
		dialog.confirmed.emit()
	var editor := dialog.get_parent() if dialog else root
	var button := find_use_snap_button(editor)
	if button and not button.button_pressed:
		button.set_pressed(true)
	return true
