class_name ObstacleLeds
extends Object
## Thin neon bars on the hard edges of an obstacle GLB. Import and adopt both
## call attach, so the editor and a live hole stay in sync.

const SHADER := preload("res://assets/shaders/led_edge.gdshader")
const NODE := "Leds"
## Narrowest a bar may draw. Below roughly two pixels an unfiltered line starts
## dropping pixels and reads as a dashed one.
const MIN_PX := 2.2
const THICK := 0.03
const LIFT := 0.018
const OVERLAP := 0.04
const MIN_LEN := 0.55
const WELD := 0.003
const SHARP := 0.86
const COLIN := 0.995
const JOIN := 0.03
const CLEAR := 0.05

# #region agent log
const DBG_PATH := "/Users/jamesritchie/golf-zombies/.cursor/debug-3dfb49.log"
static var _dbg_n := 0
static var _dbg_stats: Dictionary = {}


static func _dbg(hid: String, msg: String, data: Dictionary) -> void:
	if _dbg_n > 140:
		return
	_dbg_n += 1
	var f := FileAccess.open(DBG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(DBG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"sessionId": "3dfb49",
		"runId": "post-fix",
		"hypothesisId": hid,
		"location": "scripts/course/obstacle_leds.gd",
		"message": msg,
		"data": data,
		"timestamp": int(Time.get_unix_time_from_system() * 1000.0),
	}))
	f.close()


static func _dbg_bind(mesh_node: MeshInstance3D, raw: Array, segs: Array) -> void:
	if not is_instance_valid(mesh_node) or mesh_node.mesh == null:
		return
	var b := mesh_node.global_transform.basis if mesh_node.is_inside_tree() else mesh_node.transform.basis
	var lo := 999.0
	var hi := 0.0
	for seg in segs:
		var d: float = (seg[1] as Vector3).distance_to(seg[0] as Vector3)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	var gap := 999.0
	for i in segs.size():
		for j in range(i + 1, segs.size()):
			var pd: Vector3 = ((segs[i][1] as Vector3) - (segs[i][0] as Vector3)).normalized()
			var qd: Vector3 = ((segs[j][1] as Vector3) - (segs[j][0] as Vector3)).normalized()
			if absf(pd.dot(qd)) < COLIN:
				continue
			for u in segs[i]:
				for v in segs[j]:
					gap = minf(gap, (u as Vector3).distance_to(v as Vector3))
	var box := mesh_node.mesh.get_aabb()
	var kin := 0
	var parent := mesh_node.get_parent()
	if parent != null:
		for child in parent.get_children():
			if child is MeshInstance3D and not is_led(child):
				kin += 1
	_dbg("ABCDE", "bind", {
		"mesh": String(mesh_node.name),
		"owner": String(parent.name) if parent != null else "",
		"world_scale": [snappedf(b.x.length(), 0.001), snappedf(b.y.length(), 0.001), snappedf(b.z.length(), 0.001)],
		"det": snappedf(b.determinant(), 0.001),
		"raw_segs": raw.size(),
		"merged_segs": segs.size(),
		"seg_len_min_max": [snappedf(lo, 0.01), snappedf(hi, 0.01)],
		"min_collinear_gap": snappedf(gap, 0.001),
		"local_size": [snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01), snappedf(box.size.z, 0.01)],
		"sibling_meshes": kin,
		"edge_stats": _dbg_stats,
		"lift_local": snappedf(THICK * 0.5 + LIFT, 0.003),
	})
# #endregion


static func is_led(node: Node) -> bool:
	return node != null and String(node.name) == NODE


static func adopt(root: Node) -> void:
	if root == null:
		return
	# #region agent log
	var _found := 0
	# #endregion
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if _is_obstacle(node):
			# #region agent log
			_found += 1
			# #endregion
			attach(node as Node3D)
		if not is_instance_valid(node):
			continue
		for child in node.get_children():
			stack.append(child)
	# #region agent log
	_dbg("A", "adopt done", {"root": String(root.name), "obstacles": _found})
	# #endregion


static func attach(host: Node3D) -> MeshInstance3D:
	if host == null or not is_instance_valid(host):
		return null
	_strip_loose(host)
	var nodes: Array[MeshInstance3D] = []
	for node in _meshes(host):
		if is_instance_valid(node) and node.mesh != null:
			nodes.append(node)
	var spots: Array[Transform3D] = []
	var boxes: Array[AABB] = []
	for node in nodes:
		var xf := _rel(host, node)
		spots.append(xf)
		boxes.append(xf * node.mesh.get_aabb())
	var first: MeshInstance3D
	for i in nodes.size():
		if not is_instance_valid(nodes[i]):
			continue
		var leds := _bind(nodes[i], spots[i], boxes, i)
		if first == null and is_instance_valid(leds):
			first = leds
	return first if is_instance_valid(first) else null


## Transform of a mesh relative to the obstacle root, so sibling shapes can be
## compared without needing the node to be inside a tree.
static func _rel(host: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var step := node
	while step != null and step != host:
		xf = step.transform * xf
		step = step.get_parent() as Node3D
	return xf


## An edge that sits inside, or flush against, another part of the same obstacle
## is a seam rather than a silhouette. Lighting it buries the bar in the
## neighbour's surface, so it z-fights into dashes.
static func _buried(at: Vector3, boxes: Array[AABB], skip: int) -> bool:
	for i in boxes.size():
		if i != skip and boxes[i].grow(CLEAR).has_point(at):
			return true
	return false


static func _strip_loose(host: Node3D) -> void:
	var loose := host.get_node_or_null(NODE)
	if loose == null or not is_instance_valid(loose):
		return
	# Pull it off the tree before free. A live free() during node_added leaves
	# Godot holding the same instance as it finishes inserting the obstacle.
	if loose.get_parent() == host:
		host.remove_child(loose)
	loose.free()


static func _bind(mesh_node: MeshInstance3D, xf: Transform3D, boxes: Array[AABB], skip: int) -> MeshInstance3D:
	if not is_instance_valid(mesh_node) or mesh_node.mesh == null:
		return null
	var raw: Array = _edges(mesh_node, xf, boxes, skip)
	var segs: Array = _merge(raw)
	# #region agent log
	_dbg_bind(mesh_node, raw, segs)
	# #endregion
	if segs.is_empty():
		return null
	var leds := mesh_node.get_node_or_null(NODE) as MeshInstance3D
	if not is_instance_valid(leds):
		leds = MeshInstance3D.new()
		leds.name = NODE
		mesh_node.add_child(leds)
		if leds.get_parent() != mesh_node:
			leds.free()
			return null
		leds.owner = mesh_node.owner if mesh_node.owner != null else mesh_node
	leds.mesh = _mesh(segs)
	leds.material_override = _material()
	leds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return leds


static func edge_material(energy := Palette.GLOW_STRONG) -> ShaderMaterial:
	return _material(energy)


static func mesh_from_segs(segs: Array) -> ArrayMesh:
	return _mesh(segs)


static func _material(energy := Palette.GLOW_STRONG) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("tint", Palette.CYAN)
	mat.set_shader_parameter("energy", energy)
	mat.set_shader_parameter("min_width", MIN_PX)
	mat.render_priority = 1
	return mat


static func _is_obstacle(node: Node) -> bool:
	return node is Node3D and String(node.get("scene_file_path")).begins_with("res://assets/obstacles/")


static func _edges(mesh_node: MeshInstance3D, xf: Transform3D, boxes: Array[AABB], skip: int) -> Array:
	var verts: Dictionary = {}
	var faces: Array = []
	for surface in mesh_node.mesh.get_surface_count():
		var arrs := mesh_node.mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array()
			for vi in points.size():
				idx.append(vi)
		var i := 0
		while i + 2 < idx.size():
			var a := _weld(verts, points[idx[i]])
			var b := _weld(verts, points[idx[i + 1]])
			var c := _weld(verts, points[idx[i + 2]])
			var pa: Vector3 = a[0]
			var pb: Vector3 = b[0]
			var pc: Vector3 = c[0]
			var n := (pb - pa).cross(pc - pa)
			if n.length_squared() > 0.000001:
				faces.append([a[1], b[1], c[1], n.normalized()])
			i += 3
	var by_id: Dictionary = {}
	for key in verts:
		by_id[verts[key][1]] = verts[key][0]
	var shared: Dictionary = {}
	for face in faces:
		_touch(shared, face[0], face[1], face[3])
		_touch(shared, face[1], face[2], face[3])
		_touch(shared, face[2], face[0], face[3])
	var segs: Array = []
	# #region agent log
	var _flat := 0
	var _short := 0
	var _zero_pull := 0
	var _lone := 0
	var _seam := 0
	# #endregion
	for key in shared:
		var rec: Dictionary = shared[key]
		var normals: Array = rec["n"]
		if normals.size() == 2 and (normals[0] as Vector3).dot(normals[1] as Vector3) > SHARP:
			# #region agent log
			_flat += 1
			# #endregion
			continue
		var a: Vector3 = by_id[rec["a"]]
		var b: Vector3 = by_id[rec["b"]]
		if a.distance_to(b) < MIN_LEN:
			# #region agent log
			_short += 1
			# #endregion
			continue
		if _buried(xf * ((a + b) * 0.5), boxes, skip):
			# #region agent log
			_seam += 1
			# #endregion
			continue
		var pull := Vector3.ZERO
		for n in normals:
			pull += n
		# #region agent log
		if normals.size() != 2:
			_lone += 1
		# #endregion
		if pull.length_squared() > 0.0001:
			var shift := pull.normalized() * (THICK * 0.5 + LIFT)
			a += shift
			b += shift
		# #region agent log
		else:
			_zero_pull += 1
		# #endregion
		segs.append([a, b])
	# #region agent log
	_dbg_stats = {
		"edges": shared.size(),
		"flat": _flat,
		"short": _short,
		"seam": _seam,
		"zero_pull": _zero_pull,
		"odd_fan": _lone,
	}
	# #endregion
	return segs


static func _meshes(host: Node) -> Array[MeshInstance3D]:
	var all: Array[MeshInstance3D] = []
	var solids: Array[MeshInstance3D] = []
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node = stack.pop_back()
		if not is_instance_valid(node) or is_led(node):
			continue
		var mesh_node := node as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			all.append(mesh_node)
			if String(mesh_node.name).contains("convcol"):
				solids.append(mesh_node)
		for child in node.get_children():
			stack.append(child)
	return solids if not solids.is_empty() else all


static func _weld(verts: Dictionary, at: Vector3) -> Array:
	var key := Vector3i(roundi(at.x / WELD), roundi(at.y / WELD), roundi(at.z / WELD))
	if verts.has(key):
		return verts[key]
	var row := [at, verts.size()]
	verts[key] = row
	return row


static func _touch(shared: Dictionary, a: int, b: int, n: Vector3) -> void:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	var key := Vector2i(lo, hi)
	if not shared.has(key):
		shared[key] = {"a": lo, "b": hi, "n": []}
	(shared[key]["n"] as Array).append(n)


static func _merge(segs: Array) -> Array:
	var open: Array = segs.duplicate()
	var changed := true
	while changed:
		changed = false
		var i := 0
		while i < open.size():
			var j := i + 1
			while j < open.size():
				var joined: Variant = _join(open[i], open[j])
				if joined != null:
					open[i] = joined
					open.remove_at(j)
					changed = true
				else:
					j += 1
			i += 1
	return open


static func _join(p: Array, q: Array) -> Variant:
	var pa: Vector3 = p[0]
	var pb: Vector3 = p[1]
	var qa: Vector3 = q[0]
	var qb: Vector3 = q[1]
	var pd := (pb - pa).normalized()
	var qd := (qb - qa).normalized()
	if absf(pd.dot(qd)) < COLIN:
		return null
	if (
		pa.distance_to(qa) > JOIN
		and pa.distance_to(qb) > JOIN
		and pb.distance_to(qa) > JOIN
		and pb.distance_to(qb) > JOIN
	):
		return null
	var best_a := pa
	var best_b := pb
	var best_d := pa.distance_squared_to(pb)
	for u in [pa, pb, qa, qb]:
		for v in [pa, pb, qa, qb]:
			var d: float = u.distance_squared_to(v)
			if d > best_d:
				best_d = d
				best_a = u
				best_b = v
	return [best_a, best_b]


static func _mesh(segs: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	for seg in segs:
		_bar(st, seg[0], seg[1])
	st.generate_normals()
	return st.commit()


## Each corner ships the offset that put it there, so the shader can widen the
## bar about its centre line without having to guess which way is out.
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var axis := b - a
	if axis.length() < 0.001:
		return
	axis = axis.normalized()
	a -= axis * OVERLAP
	b += axis * OVERLAP
	var side := Vector3.UP.cross(axis)
	if side.length_squared() < 0.05:
		side = Vector3.RIGHT.cross(axis)
	side = side.normalized() * (THICK * 0.5)
	var up := axis.cross(side).normalized() * (THICK * 0.5)
	var offsets: Array[Vector3] = [
		side + up, side - up, -side - up, -side + up,
		side + up, side - up, -side - up, -side + up,
	]
	var spines: Array[Vector3] = [a, a, a, a, b, b, b, b]
	for f in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [3, 2, 1, 0], [4, 5, 6, 7]]:
		for i in [f[0], f[1], f[2], f[0], f[2], f[3]]:
			var offset: Vector3 = offsets[i]
			st.set_custom(0, Color(offset.x, offset.y, offset.z, 0.0))
			st.add_vertex(spines[i] + offset)
