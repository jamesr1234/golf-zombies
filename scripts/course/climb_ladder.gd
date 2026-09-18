class_name ClimbLadder
extends ClimbingWall
## Rung holds on a placed ladder_*.glb. Walk in and stick up the rails.

const RUNG := 0.45
const STAND := 0.72
const MOUNT := 1.45


var _stand_z := -STAND


func _ready() -> void:
	add_to_group("climb_walls")
	_cols = 2
	_rows = maxi(3, roundi(_h / RUNG))


func _build() -> void:
	pass


func is_rail_climb() -> bool:
	return true


func is_live() -> bool:
	return true


func set_stand_side(who: Node3D) -> void:
	if who == null:
		return
	_stand_z = -STAND if to_local(who.global_position).z <= 0.0 else STAND


func rail_length() -> float:
	return _h


func rail_dir() -> Vector3:
	return global_transform.basis.y


func point_on_rail(t: float) -> Vector3:
	var y := lerpf(-_h * 0.45, _h * 0.48, clampf(t, 0.0, 1.0))
	return to_global(Vector3(0.0, y, _stand_z))


func rail_t_at(point: Vector3) -> float:
	var local := to_local(point)
	return clampf((local.y + _h * 0.45) / maxf(_h * 0.93, 0.01), 0.0, 1.0)


func can_latch(who: Node3D) -> bool:
	if who == null:
		return false
	var local := to_local(who.global_position)
	return (
		absf(local.x) <= maxf(_w * 0.7, 0.55)
		and local.y > -_h * 0.55
		and local.y < _h * 0.22
		and absf(local.z) <= LATCH_DEPTH + _t
	)


func hold_locals() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var face_z := -_t * 0.5 - 0.04
	var rows := maxi(3, _rows)
	for row in rows:
		var y := lerpf(-_h * 0.42, _h * 0.42, float(row) / float(rows - 1))
		spots.append(Vector3(-_w * 0.28, y, face_z))
		spots.append(Vector3(_w * 0.28, y, face_z))
	return spots


func ledge_stand(_who: Node3D = null) -> Vector3:
	return to_global(Vector3(0.0, _h * 0.5 + 0.2, _stand_z * 0.35))


static func is_ladder(node: Node) -> bool:
	if node == null:
		return false
	return String(node.get("scene_file_path")).contains("/ladder_")


static func adopt(root: Node) -> void:
	if root == null:
		return
	_walk(root)


static func attach(host: Node3D) -> ClimbLadder:
	if host == null or not is_ladder(host):
		return null
	var existing := host.get_node_or_null("Climb") as ClimbLadder
	if existing != null:
		return existing
	var box := _local_aabb(host)
	if box.size.y < 0.4:
		return null
	var climb := ClimbLadder.new()
	climb.name = "Climb"
	climb._w = box.size.x
	climb._h = box.size.y
	climb._t = 0.16
	climb._cols = 2
	climb._rows = maxi(3, roundi(climb._h / RUNG))
	host.add_child(climb)
	climb.position = box.position + box.size * 0.5
	climb.rotation.y = PI
	return climb


static func _walk(node: Node) -> void:
	if node is Node3D and is_ladder(node):
		attach(node as Node3D)
	for child in node.get_children():
		_walk(child)


static func _local_aabb(host: Node3D) -> AABB:
	var box := AABB()
	var started := false
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if ObstacleLeds.is_led(current):
			continue
		var mesh_node := current as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			var local := mesh_node.mesh.get_aabb()
			var to_host := _xform_in(host, mesh_node)
			for i in 8:
				var point: Vector3 = to_host * local.get_endpoint(i)
				if not started:
					box = AABB(point, Vector3.ZERO)
					started = true
				else:
					box = box.expand(point)
		for child in current.get_children():
			stack.append(child)
	return box


static func _xform_in(host: Node3D, node: Node3D) -> Transform3D:
	var xf := node.transform
	var walk := node.get_parent()
	while walk != null and walk != host:
		if walk is Node3D:
			xf = (walk as Node3D).transform * xf
		walk = walk.get_parent()
	return xf
