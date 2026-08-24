class_name HoleOverlay
extends Object
## Authored props for one hole. Trees are not placed here; CourseTrees still
## plants those in code. Origin is the tee. Y is overwritten from the heightmap.

const HOLE_DIR := "res://scenes/course/holes/"
const PROP_DIR := "res://scenes/course/props/"
const PREVIEW_NAME := "Preview"
const PAD_NAME := "MechPad"
const _Box := preload("res://scripts/course/box_prop.gd")
const _MillDesk := preload("res://scripts/course/windmill_control.gd")

## Skip attach while the editor is building a preview of this overlay.
static var _suspend_attach := 0
## Live overlay root in the editor, so harvest reads unsaved props from the scene
## instead of instantiating the packed scene (which would recurse).
static var _live_root: Node = null


static func path_for(index: int) -> String:
	return HOLE_DIR + "hole_%d.tscn" % (index + 1)


static func packed_for(index: int) -> PackedScene:
	var path := path_for(index)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


static func harvest(data: HoleData) -> void:
	if _live_root != null:
		collect_into(data, _live_root)
		return
	var packed := packed_for(data.index)
	if packed == null:
		return
	var root := packed.instantiate()
	if root.get_child_count() == 0:
		root.free()
		return
	collect_into(data, root)
	root.free()


static func attach(host: Node3D, data: HoleData) -> void:
	if _suspend_attach > 0:
		return
	var packed := packed_for(data.index)
	if packed == null:
		return
	var overlay := packed.instantiate() as Node3D
	if overlay == null or overlay.get_child_count() == 0:
		if overlay != null:
			overlay.free()
		return
	overlay.name = "Overlay"
	apply_lifted(overlay, data)
	strip_suits(overlay)
	_strip_pads(overlay)
	host.add_child(overlay)


## Generated hole for the overlay editor. Does not nest the overlay scene inside
## itself, which would recurse.
static func preview(index: int, seed: int) -> Node3D:
	_suspend_attach += 1
	var data := HoleGenerator.generate(index, seed)
	var root := HoleBuilder.build(data)
	_suspend_attach -= 1
	root.name = PREVIEW_NAME
	root.set_meta("overlay_preview", true)
	return root


static func collect_into(data: HoleData, root: Node) -> void:
	for child in root.get_children():
		_collect_node(data, root, child)


static func apply_lifted(overlay: Node, data: HoleData) -> void:
	for prop in data.props:
		if not bool(prop.get("authored", false)):
			continue
		var node := _node_at(overlay, prop)
		if node != null:
			_place_prop(node, prop)
	for jump in data.jumps:
		if not bool(jump.get("authored", false)):
			continue
		var node := _node_at(overlay, jump)
		if node == null:
			continue
		node.position = jump["position"]
		node.rotation.y = deg_to_rad(float(jump["yaw"]))


## A live suit in the overlay is a local body on every peer. Computer 2 then
## simulates that copy and never sees the shop-spawned one walk.
static func strip_suits(root: Node) -> int:
	if root == null:
		return 0
	var stripped := 0
	for node in root.find_children("*", "MechSuit", true, false):
		node.free()
		stripped += 1
	return stripped


static func _strip_pads(root: Node) -> void:
	if root == null:
		return
	for node in root.find_children(PAD_NAME, "", true, false):
		node.free()


static func _collect_pad(data: HoleData, node: Node3D) -> void:
	if data.has_mech_pad() or node == null:
		return
	data.mech_pad = node.position
	data.mech_yaw = rad_to_deg(node.rotation.y)


static func _collect_node(data: HoleData, root: Node, node: Node) -> void:
	if _is_preview(node):
		return
	if node is MechSuit or (node is Node3D and String(node.name) == PAD_NAME):
		_collect_pad(data, node as Node3D)
		return
	if node is TreeProp:
		return
	if node is JumpRamp:
		data.jumps.append(_stamp(root, node, (node as JumpRamp).to_jump()))
		return
	if node.get_script() == _Box:
		data.props.append(_stamp(root, node, node.call("to_prop")))
		return
	if node is SniperTower:
		data.props.append(_stamp(root, node, (node as SniperTower).to_prop()))
		return
	if node is ClimbingWall:
		data.props.append(_stamp(root, node, (node as ClimbingWall).to_prop()))
		return
	if node is Culvert:
		data.props.append(_stamp(root, node, (node as Culvert).to_prop()))
		return
	if node is CartPathWindmill:
		data.props.append(_stamp(root, node, (node as CartPathWindmill).to_prop()))
		return
	if node.get_script() == _MillDesk:
		data.props.append(_stamp(root, node, node.call("to_prop")))
		return
	for child in node.get_children():
		_collect_node(data, root, child)


static func _stamp(root: Node, node: Node, entry: Dictionary) -> Dictionary:
	entry["authored"] = true
	entry["overlay_path"] = str(root.get_path_to(node))
	return entry


static func _node_at(overlay: Node, entry: Dictionary) -> Node3D:
	var path := String(entry.get("overlay_path", ""))
	if path.is_empty():
		return null
	return overlay.get_node_or_null(NodePath(path)) as Node3D


static func _place_prop(node: Node3D, prop: Dictionary) -> void:
	node.position = prop["position"]
	node.rotation.y = deg_to_rad(float(prop["yaw"]))
	if String(prop.get("kind", "")) == "climb_wall":
		var size: Vector3 = prop.get("size", Vector3(ClimbingWall.WIDTH, ClimbingWall.HEIGHT, 1.0))
		node.position.y += size.y * 0.5


static func _is_preview(node: Node) -> bool:
	return node.name == PREVIEW_NAME or bool(node.get_meta("overlay_preview", false))
