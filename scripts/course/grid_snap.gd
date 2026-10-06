@tool
class_name GridSnap
extends Object
## Obstacle pieces sit on a 1.35 m grid and meet flush. Pure math with no
## editor calls, so the in-game hole creator and the fs_pin editor plugin place
## a piece in exactly the same spot.

const CELL := 1.35
const ASSET_DIR := "res://assets/obstacles/"


static func to_grid(at: Vector3) -> Vector3:
	return Vector3(snappedf(at.x, CELL), snappedf(at.y, CELL), snappedf(at.z, CELL))


static func is_obstacle(node: Node) -> bool:
	return node is Node3D and node.scene_file_path.begins_with(ASSET_DIR)


## Every mesh under `node` measured in `node`'s own space, so a ghost can be
## sized before it is ever added to the tree. LED bars are decoration and never
## count toward the hull.
## Obstacle meshes sit on a ground corner. The creator stores the middle of the
## footprint so a turn spins the piece in place instead of swinging it around.
static func pivot_xz(box: AABB) -> Vector3:
	if box.size == Vector3.ZERO:
		return Vector3.ZERO
	var mid := box.get_center()
	return Vector3(mid.x, 0.0, mid.z)


static func footprint_centered(box: AABB) -> AABB:
	return AABB(box.position - pivot_xz(box), box.size)


static func anchored_at(node: Node3D, at: Vector3, yaw_deg: float) -> Vector3:
	var pivot := pivot_xz(local_aabb(node))
	return at - Basis(Vector3.UP, deg_to_rad(yaw_deg)) * pivot


static func local_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var started := false
	var stack: Array = [[node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var current: Node = entry[0]
		var xform: Transform3D = entry[1]
		if ObstacleLeds.is_led(current):
			continue
		var mesh_node := current as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			var local := mesh_node.mesh.get_aabb()
			for i in 8:
				var point: Vector3 = xform * local.get_endpoint(i)
				if not started:
					box = AABB(point, Vector3.ZERO)
					started = true
				else:
					box = box.expand(point)
		for child in current.get_children():
			var spatial := child as Node3D
			var next := xform if spatial == null else xform * spatial.transform
			stack.append([child, next])
	return box


## Empty until the piece is in the tree, because there is no world pose to
## measure from before that. Use local_aabb to size a ghost off the tree.
static func world_aabb(node: Node) -> AABB:
	var spatial := node as Node3D
	if spatial == null or not spatial.is_inside_tree():
		return AABB()
	var box := local_aabb(spatial)
	if box.size == Vector3.ZERO:
		return box
	return spatial.global_transform * box


static func neighbor_boxes(root: Node, except: Node = null) -> Array:
	var boxes: Array = []
	if root == null:
		return boxes
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node != except and is_obstacle(node) and node.is_inside_tree():
			var box := world_aabb(node)
			if box.size != Vector3.ZERO:
				boxes.append(box)
		for child in node.get_children():
			stack.append(child)
	return boxes


## Overlay rebuilds as height-field + stored Y, so a world pose has to be
## written back as an offset or a snapped piece would lift on every refresh.
static func stored_offset(at: Vector3, height: HeightField) -> Vector3:
	if height == null:
		return at
	return Vector3(at.x, at.y - height.height_at(at.x, at.z), at.z)


## Highest grass or prop in this column, so a snap can sit on a stack.
static func column_top(
	at: Vector3, space: PhysicsDirectSpaceState3D, height: HeightField
) -> float:
	var ground := height.height_at(at.x, at.z) if height != null else 0.0
	if space == null:
		return ground
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(at.x, at.y + 80.0, at.z),
		Vector3(at.x, at.y - 80.0, at.z),
		Layers.WORLD | Layers.PROP | Layers.SURFACE
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return ground
	return maxf(ground, float((hit["position"] as Vector3).y))


## Drop a piece onto a surface, then resolve overlaps the same way as a normal
## place. Y is taken from the surface so a stack sits on top instead of inside.
static func rest_on(xz: Vector3, surface_y: float, box: AABB, others: Array) -> Vector3:
	var from := Vector3(snappedf(xz.x, CELL), surface_y + 0.02, snappedf(xz.z, CELL))
	if box.size == Vector3.ZERO:
		return Vector3(from.x, snappedf(surface_y, CELL), from.z)
	# The hull is measured at the aim point. Sit it on the surface cell before
	# overlap math, or a look that still clips a neighbour pushes off-grid.
	return place(from, _moved(box, xz, from), others)


## Grid first, then if that lands inside another piece, sit on the nearest
## side or on top. Pieces never nest. The face is chosen from where the piece
## was let go, so the answer is the same every time it is asked.
static func place(from: Vector3, box: AABB, others: Array) -> Vector3:
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		return to_grid(from)
	var at := to_grid(from)
	var shifted := _moved(box, from, at)
	var hits := _hits(shifted, others)
	var result := at if not hits else _nearest_face(from, at, shifted, others)
	# #region agent log
	_dbg_place(from, at, result, box, shifted, others, hits)
	# #endregion
	return result


static func placed(node: Node3D, root: Node) -> Vector3:
	if not node.is_inside_tree():
		return to_grid(node.position)
	return place(node.global_position, world_aabb(node), neighbor_boxes(root, node))


static func _moved(box: AABB, from: Vector3, to: Vector3) -> AABB:
	return AABB(box.position + (to - from), box.size)


static func _hits(box: AABB, others: Array) -> bool:
	var inner := box.grow(-0.0001)
	for other in others:
		if inner.intersects(other):
			return true
	return false


static func _nearest_face(want: Vector3, at: Vector3, box: AABB, others: Array) -> Vector3:
	var clear_at := at
	var clear_d := INF
	var any_at := at
	var any_d := INF
	var found := false
	for other in others:
		if not box.intersects(other):
			continue
		for candidate in _faces(at, box, other):
			var moved := _moved(box, at, candidate)
			var dist := candidate.distance_squared_to(want)
			if dist < any_d:
				any_d = dist
				any_at = candidate
			if _hits(moved, others):
				continue
			if dist < clear_d:
				clear_d = dist
				clear_at = candidate
				found = true
	var picked := clear_at if found else any_at
	# #region agent log
	var _face_key := "%s|%s|%s" % [picked, found, at]
	if _face_key != _dbg_face_key:
		_dbg_face_key = _face_key
		_dbg_face(want, at, picked, found, clear_at, any_at, box, others)
	# #endregion
	return picked


static func _faces(at: Vector3, box: AABB, other: AABB) -> Array[Vector3]:
	return [
		at + Vector3(other.end.x - box.position.x, 0.0, 0.0),
		at + Vector3(other.position.x - box.end.x, 0.0, 0.0),
		at + Vector3(0.0, other.end.y - box.position.y, 0.0),
		at + Vector3(0.0, 0.0, other.end.z - box.position.z),
		at + Vector3(0.0, 0.0, other.position.z - box.end.z),
	]


# #region agent log
const _DBG := "/Users/jamesritchie/golf-zombies/.cursor/debug-ed7827.log"
static var _dbg_key := ""
static var _dbg_face_key := ""
static var _dbg_n := 0


static func _dbg_place(
	from: Vector3, at: Vector3, result: Vector3, box: AABB, shifted: AABB, others: Array, hits: bool
) -> void:
	var near_d := INF
	var near_gap := INF
	var near_sz := Vector3.ZERO
	var near_c := Vector3.ZERO
	for other in others:
		var other_box: AABB = other
		var d := shifted.get_center().distance_to(other_box.get_center())
		if d < near_d:
			near_d = d
			near_c = other_box.get_center()
			near_sz = other_box.size
			near_gap = _gap_between(shifted, other_box)
	if others.is_empty() and not hits and result == at:
		return
	var key := "%s|%s|%d|%s|%.2f" % [_v3(at), _v3(result), others.size(), hits, near_gap]
	if key == _dbg_key:
		return
	_dbg_key = key
	_dbg_n += 1
	if _dbg_n > 160:
		return
	_dbg_write("B", "grid_snap.gd:place", "place decide", {
		"from": _v3(from),
		"grid": _v3(at),
		"result": _v3(result),
		"moved": result != at,
		"hits": hits,
		"others": others.size(),
		"box": _v3(box.size),
		"shifted": [_v3(shifted.position), _v3(shifted.end)],
		"near_c": _v3(near_c),
		"near_sz": _v3(near_sz),
		"near_d": snappedf(near_d, 0.01) if near_d < INF else -1.0,
		"near_gap": snappedf(near_gap, 0.001) if near_gap < INF else -1.0,
		"dy": snappedf(at.y - near_c.y, 0.01) if near_d < INF else 0.0,
		"off_grid": Vector3(
			snappedf(fmod(absf(result.x), CELL), 0.001),
			snappedf(fmod(absf(result.y), CELL), 0.001),
			snappedf(fmod(absf(result.z), CELL), 0.001)
		),
	})


static func _dbg_face(
	want: Vector3, at: Vector3, picked: Vector3, found: bool, clear_at: Vector3, any_at: Vector3,
	box: AABB, others: Array
) -> void:
	var faces: Array = []
	for other in others:
		var other_box: AABB = other
		if not box.intersects(other_box):
			continue
		var names := ["+x", "-x", "+y", "+z", "-z"]
		var i := 0
		for candidate in _faces(at, box, other_box):
			var moved := _moved(box, at, candidate)
			faces.append({
				"f": names[i],
				"at": _v3(candidate),
				"d": snappedf(candidate.distance_to(want), 0.01),
				"hits": _hits(moved, others),
				"gap": snappedf(_gap_between(moved, other_box), 0.001),
				"off": _v3(Vector3(
					fmod(absf(candidate.x), CELL),
					fmod(absf(candidate.y), CELL),
					fmod(absf(candidate.z), CELL)
				)),
			})
			i += 1
	_dbg_write("E", "grid_snap.gd:_nearest_face", "face pick", {
		"want": _v3(want),
		"grid": _v3(at),
		"picked": _v3(picked),
		"found": found,
		"fallback": not found,
		"clear": _v3(clear_at),
		"any": _v3(any_at),
		"faces": faces,
	})


static func _gap_between(a: AABB, b: AABB) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	var dz := maxf(0.0, maxf(a.position.z - b.end.z, b.position.z - a.end.z))
	return Vector3(dx, dy, dz).length()


static func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


static func _dbg_write(hid: String, loc: String, msg: String, data: Dictionary) -> void:
	var f := FileAccess.open(_DBG, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(_DBG, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"sessionId": "ed7827",
		"hypothesisId": hid,
		"location": loc,
		"message": msg,
		"data": data,
		"timestamp": Time.get_ticks_msec(),
	}))
	f.close()
# #endregion
