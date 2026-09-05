class_name CarVisuals
extends Object
## Instantiates a Blender car GLB and reads the seat / wheel empties.


static func build(scene: PackedScene) -> Node3D:
	var root := Node3D.new()
	root.name = "Visuals"
	if scene == null:
		root.add_child(CartVisuals.build())
		return root
	var model := scene.instantiate() as Node3D
	if model == null:
		root.add_child(CartVisuals.build())
		return root
	root.add_child(model)
	return root


static func marker(root: Node, marker_name: String) -> Vector3:
	var node := find_named(root, marker_name)
	if node == null or root == null:
		return Vector3.ZERO
	return root.to_local(node.global_position) if root.is_inside_tree() else node.position


static func find_named(root: Node, marker_name: String) -> Node3D:
	if root == null:
		return null
	if _marker_match(root.name, marker_name):
		return root as Node3D
	var exact := root.find_child(marker_name, true, false) as Node3D
	if exact != null:
		return exact
	for child in root.get_children():
		var nested := find_named(child, marker_name)
		if nested != null:
			return nested
	return null


static func _marker_match(node_name: String, marker_name: String) -> bool:
	if node_name == marker_name:
		return true
	if not (node_name.begins_with(marker_name + ".") or node_name.begins_with(marker_name + "_")):
		return false
	return node_name.substr(marker_name.length() + 1).is_valid_int()


static func apply_tint(root: Node, color: Color) -> void:
	if root == null:
		return
	_tint_node(root, color)


static func _tint_node(node: Node, color: Color) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null:
		var mat := mesh.get_active_material(0) as StandardMaterial3D
		if mat != null and _is_paint(mat, mesh):
			var tinted := mat.duplicate() as StandardMaterial3D
			tinted.albedo_color = color
			if tinted.emission_enabled:
				tinted.emission = color
			mesh.material_override = tinted
	for child in node.get_children():
		_tint_node(child, color)


static func _is_paint(mat: StandardMaterial3D, mesh: MeshInstance3D) -> bool:
	if mat.albedo_color.is_equal_approx(Palette.HEADLIGHT):
		return false
	var name := mat.resource_name
	if name.is_empty() and mesh.mesh != null:
		name = mesh.mesh.resource_name
	return name.begins_with("CarPaint") or name.begins_with("CartBody")
