@tool
extends EditorPlugin
## Pins a FileSystem tree to the 3D viewport so it survives fullscreen / DFM.

const _Listing := preload("res://addons/fs_pin/fs_listing.gd")
const _Panel := preload("res://addons/fs_pin/fs_panel.gd")
const _Snap := preload("res://addons/fs_pin/fs_snap.gd")
const MENU := "Pin FileSystem in 3D View"
const CATALOG_MENU := "Refresh Hole Creator Piece Catalog"

var _panel: Control
var _pinned := true
var _snap_ready := false
var _pending: Array[Node3D] = []
var _dragging := false
var _drag_from := {}
# #region agent log
var _wrote := {}
# #endregion


func _enter_tree() -> void:
	_panel = _Panel.new()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _panel)
	add_tool_menu_item(MENU, _toggle)
	add_tool_menu_item(CATALOG_MENU, _refresh_catalog)
	get_tree().node_added.connect(_on_node_added)
	set_process(true)
	_apply()


func _exit_tree() -> void:
	set_process(false)
	remove_tool_menu_item(MENU)
	remove_tool_menu_item(CATALOG_MENU)
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if _panel == null:
		return
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _panel)
	_panel.queue_free()
	_panel = null


func _process(_delta: float) -> void:
	_apply()
	_apply_snap()
	_snap_moved()


func _toggle() -> void:
	_pinned = not _pinned
	_apply()


## The in-game creator reads a committed list because an exported build cannot
## scan res:// for source .glb files. Run this after adding or removing pieces.
func _refresh_catalog() -> void:
	if PieceCatalog.write_manifest():
		EditorInterface.get_resource_filesystem().scan()


func _apply() -> void:
	if _panel == null:
		return
	var win := EditorInterface.get_base_control().get_window()
	var immersive := _Listing.is_immersive(win.mode, EditorInterface.is_distraction_free_mode_enabled())
	_panel.visible = _pinned and immersive


func _apply_snap() -> void:
	if _snap_ready or not Engine.is_editor_hint():
		return
	if not _Snap.apply(EditorInterface.get_base_control(), EditorInterface.get_editor_settings()):
		return
	if absf(EditorInterface.get_node_3d_translate_snap() - _Snap.CELL) > 0.001:
		return
	if not EditorInterface.is_node_3d_snap_enabled():
		return
	_snap_ready = true


## The 3D gizmo recomputes a drag from the pose it captured when the drag
## began, so anything written mid-drag is thrown away on the next frame and the
## piece flickers. The move is left alone until the button comes up, and the
## release pose is what the snap is measured from.
func _snap_moved() -> void:
	if not Engine.is_editor_hint():
		return
	var selection := EditorInterface.get_selection()
	if selection == null:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not _dragging:
			_dragging = true
			_drag_from = {}
			for node in selection.get_selected_nodes():
				if _Snap.is_obstacle(node) and node.is_inside_tree():
					_drag_from[node.get_instance_id()] = (node as Node3D).global_position
		return
	# #region agent log
	for id in _wrote.keys():
		var placed := instance_from_id(id) as Node3D
		if placed != null and placed.is_inside_tree():
			_dbg(
				"H12",
				"settled",
				{
					"want": _v(_wrote[id]),
					"is": _v(placed.global_position),
					"stuck": placed.global_position == _wrote[id],
				}
			)
	_wrote.clear()
	# #endregion
	if not _dragging:
		return
	_dragging = false
	var root := EditorInterface.get_edited_scene_root()
	for node in selection.get_selected_nodes():
		if not _Snap.is_obstacle(node):
			continue
		var spatial: Node3D = node
		if not spatial.is_inside_tree():
			continue
		var id := spatial.get_instance_id()
		var now := spatial.global_position
		if not _drag_from.has(id) or _drag_from[id] == now:
			continue
		var snapped := _Snap.placed(spatial, root)
		# #region agent log
		_dbg("H12", "released", {"from": _v(_drag_from[id]), "now": _v(now), "snap": _v(snapped)})
		_wrote[id] = snapped
		# #endregion
		if snapped != now:
			spatial.global_position = snapped
	_drag_from = {}


## A drop is one obstacle in a frame. Opening a scene adds many at once, and
## those meshes are not in the tree yet, so they wait a frame and then only a
## single new piece is snapped.
func _on_node_added(node: Node) -> void:
	if not _Snap.is_obstacle(node):
		return
	# Attach after Godot finishes inserting the instance. Freeing a Leds child
	# from this signal returns that instance to the editor while it is gone.
	_attach_leds.call_deferred(node.get_instance_id())
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root == node or not root.is_ancestor_of(node):
		return
	var spatial: Node3D = node
	# #region agent log
	_dbg(
		"H6",
		"node_added",
		{
			"in_tree": spatial.is_inside_tree(),
			"root_in_tree": root.is_inside_tree(),
			"path": spatial.scene_file_path,
			"pending": _pending.size() + 1,
		}
	)
	# #endregion
	if not spatial.is_inside_tree():
		return
	_pending.append(spatial)
	if _pending.size() == 1:
		_flush_added.call_deferred()


func _attach_leds(id: int) -> void:
	var host := instance_from_id(id) as Node3D
	if host == null or not is_instance_valid(host):
		return
	ObstacleLeds.attach(host)


func _flush_added() -> void:
	var nodes := _pending.duplicate()
	_pending.clear()
	# #region agent log
	_dbg("H10", "flush_added", {"n": nodes.size()})
	# #endregion
	if nodes.size() != 1:
		return
	var spatial: Node3D = nodes[0]
	if not is_instance_valid(spatial) or not spatial.is_inside_tree():
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	spatial.global_position = _Snap.placed(spatial, root)
	# #region agent log
	_dbg("H10", "dropped", {"path": spatial.scene_file_path, "at": _v(spatial.global_position)})
	_wrote[spatial.get_instance_id()] = spatial.global_position
	# #endregion


# #region agent log
func _v(at: Vector3) -> Array:
	return [snappedf(at.x, 0.001), snappedf(at.y, 0.001), snappedf(at.z, 0.001)]


func _dbg(hid: String, msg: String, data: Dictionary) -> void:
	var n: int = get_meta("_dbg_n", 0)
	if n > 120:
		return
	set_meta("_dbg_n", n + 1)
	var f := FileAccess.open("res://.cursor/debug-e4c816.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("res://.cursor/debug-e4c816.log", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(
		JSON.stringify(
			{
				"sessionId": "e4c816",
				"hypothesisId": hid,
				"location": "addons/fs_pin/plugin.gd",
				"message": msg,
				"data": data,
				"timestamp": int(Time.get_unix_time_from_system() * 1000.0),
			}
		)
	)
	f.close()
# #endregion
