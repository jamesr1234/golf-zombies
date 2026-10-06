class_name CreatorMarks
extends MeshInstance3D
## Neon guides drawn over the hole while it is being built: where the next
## fairway piece would run, the ring the group tool is gathering from, and a box
## around anything already picked up. None of it exists once the hole is played.

const LIFT := 0.35
## Keep the ghost inside the strip. The lip walls sit on width/2, so an outline
## drawn there is buried in the pane and disappears as the camera orbits.
const GHOST_INSET := 0.8
const RING_STEPS := 40
const MARK := GridSnap.CELL * 0.9
## How tall a weapon line stands, so it reads as a wall to walk through rather
## than a stripe painted on the grass.
const POST := 3.2

var _lines := ImmediateMesh.new()
var _drawn := 0
var _ghost := MeshInstance3D.new()
var _fill := MeshInstance3D.new()
# #region agent log
var _dbg_i := 0
var _dbg_yaw := 999.0
# #endregion


static func create() -> CreatorMarks:
	var marks := CreatorMarks.new()
	marks.name = "CreatorMarks"
	marks.mesh = marks._lines
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.emission_enabled = true
	material.emission_energy_multiplier = Palette.GLOW_SOFT
	marks.material_override = material
	marks._ghost.name = "GhostOutline"
	marks._ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marks._ghost.material_override = ObstacleLeds.overlay_material(Palette.GLOW_SOFT)
	marks.add_child(marks._ghost)
	marks._fill.name = "AreaFill"
	marks._fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fill := StandardMaterial3D.new()
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill.no_depth_test = true
	fill.emission_enabled = true
	marks._fill.material_override = fill
	marks.add_child(marks._fill)
	# #region agent log
	marks._dbg_create()
	# #endregion
	return marks


func clear() -> void:
	_lines.clear_surfaces()


func begin() -> void:
	clear()
	_drawn = 0
	_ghost.mesh = null
	_ghost.visible = false
	_fill.mesh = null
	_fill.visible = false


func finish() -> void:
	if _drawn == 0:
		return
	_lines.surface_end()
	# #region agent log
	_dbg_finish()
	# #endregion


## The corner a fairway piece would add, so the shape is read before it lands.
func ghost_segment(from: Vector3, to: Vector3, width: float, ok: bool) -> void:
	var color := Palette.LIME if ok else Palette.SUN
	var along := to - from
	along.y = 0.0
	if along.length_squared() < 0.01:
		return
	var half := maxf(width * 0.5 - GHOST_INSET, width * 0.15)
	var side := along.normalized().cross(Vector3.UP) * half
	var p_l0 := from + side
	var p_l1 := to + side
	var p_r0 := from - side
	var p_r1 := to - side
	var lift := Vector3.UP * LIFT
	var segs: Array = [
		[p_l0 + lift, p_l1 + lift], [p_r0 + lift, p_r1 + lift],
		[p_l0 + lift, p_r0 + lift], [p_l1 + lift, p_r1 + lift],
	]
	_ghost.mesh = ObstacleLeds.mesh_from_segs(segs)
	_ghost.visible = true
	var tint := _ghost.material_override as ShaderMaterial
	if tint != null:
		tint.set_shader_parameter("tint", color)
	# #region agent log
	_dbg_ghost(from, to, width, along, side, [
		["left", p_l0, p_l1], ["right", p_r0, p_r1], ["start", p_l0, p_r0], ["end", p_l1, p_r1],
	])
	# #endregion


## Where a dropped gun stops working, drawn across the fairway. This is the only
## place it is ever shown: the played hole has nothing there.
func gate_line(data: HoleData, t: float, width: float, color: Color) -> void:
	if data == null or t < 0.0:
		return
	var at := HoleGenerator.point_along(data, t)
	var along := HoleGenerator.point_along(data, minf(1.0, t + 0.01)) - at
	along.y = 0.0
	if along.length_squared() < 0.0001:
		along = data.along_cup()
	var side := along.normalized().cross(Vector3.UP) * width * 0.5
	var lift := Vector3.UP * POST
	_segment(at + side, at - side, color)
	_segment(at + side, at + side + lift, color)
	_segment(at - side, at - side + lift, color)
	_segment(at + side + lift, at - side + lift, color)


## A yard stays on the grass. A group ring faces the lens so flying around
## still shows a full circle instead of a line on the ground.
func ring(
	center: Vector3, radius: float, color: Color,
	along := Vector3.RIGHT, around := Vector3.BACK
) -> void:
	var previous := ring_point(center, radius, 0.0, along, around)
	for i in range(1, RING_STEPS + 1):
		var angle := TAU * float(i) / float(RING_STEPS)
		var point := ring_point(center, radius, angle, along, around)
		_segment(previous, point, color)
		previous = point


func view_ring(center: Vector3, radius: float, color: Color, camera: Camera3D) -> void:
	if camera == null:
		ring(center, radius, color)
		return
	var basis := camera.global_transform.basis
	ring(center, radius, color, basis.x, basis.y)


static func ring_point(
	center: Vector3, radius: float, angle: float,
	along := Vector3.RIGHT, around := Vector3.BACK
) -> Vector3:
	var x := along
	var y := around
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	if y.length_squared() < 0.0001:
		y = Vector3.BACK
	return center + (x.normalized() * cos(angle) + y.normalized() * sin(angle)) * radius


func line(from: Vector3, to: Vector3, color: Color) -> void:
	_segment(from, to, color)


## A free circle, the sandtrap size before it is a tile fill.
func disk(center: Vector3, radius: float, color: Color) -> void:
	ring(center, radius, color)
	var mesh := CylinderMesh.new()
	mesh.top_radius = maxf(radius, 0.08)
	mesh.bottom_radius = maxf(radius, 0.08)
	mesh.height = 0.06
	mesh.radial_segments = 28
	_fill.mesh = mesh
	_fill.position = center + Vector3.UP * 0.05
	_fill.visible = true
	var mat := _fill.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(color, 0.32)
		mat.emission = color
		mat.emission_energy_multiplier = Palette.GLOW_SOFT


## Circle plus a sunken floor so the depth pass reads as a bowl.
func bowl(center: Vector3, radius: float, depth: float, color: Color) -> void:
	disk(center, radius, color)
	var floor := center - Vector3.UP * maxf(depth, 0.05)
	var inner := maxf(radius * 0.28, 0.4)
	ring(floor, inner, color)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var rim := center + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var bottom := floor + Vector3(cos(angle), 0.0, sin(angle)) * inner
		_segment(rim, bottom, color)


## Depth lock: a column from the water line down to the floor.
func column(center: Vector3, depth: float, color: Color) -> void:
	var floor := center - Vector3.UP * maxf(depth, 0.05)
	_segment(center, floor, color)
	var half := GridSnap.CELL * 0.5
	for corner in [
		Vector3(-half, 0.0, -half), Vector3(half, 0.0, -half),
		Vector3(half, 0.0, half), Vector3(-half, 0.0, half),
	]:
		_segment(center + corner, floor + corner, color)
	var slab := BoxMesh.new()
	slab.size = Vector3(GridSnap.CELL, maxf(depth, 0.08), GridSnap.CELL)
	_fill.mesh = slab
	_fill.position = center - Vector3.UP * (maxf(depth, 0.08) * 0.5)
	_fill.visible = true
	var mat := _fill.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(color, 0.28)
		mat.emission = color
		mat.emission_energy_multiplier = Palette.GLOW_SOFT


## The line a dig follows, drawn as a square tube at its real bore so the size
## being set is the size that gets swum through.
func tube(line: Array, bore: float, color: Color) -> void:
	if line.size() < 2:
		return
	var half := maxf(bore, 0.2) * 0.5
	var last: Array = []
	for i in line.size():
		var ring := _ring_at(line, i, half)
		for c in 4:
			_segment(ring[c], ring[(c + 1) % 4], color)
			if not last.is_empty():
				_segment(last[c], ring[c], color)
		last = ring


## Four corners square to the way the dig is heading, matching how the built
## tunnel is swept so the guide and the real thing line up.
func _ring_at(line: Array, index: int, half: float) -> Array:
	var dir := Vector3.ZERO
	if index > 0:
		dir += (line[index] - line[index - 1]).normalized()
	if index < line.size() - 1:
		dir += (line[index + 1] - line[index]).normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized() * half
	var up := right.normalized().cross(dir).normalized() * half
	var at: Vector3 = line[index]
	return [at + right + up, at - right + up, at - right - up, at + right - up]


## The lava fill before it lands: a tinted slab plus a grid so each tile reads.
func area(from: Vector3, to: Vector3, color: Color) -> void:
	var half := GridSnap.CELL * 0.5
	var x0 := minf(from.x, to.x) - half
	var x1 := maxf(from.x, to.x) + half
	var z0 := minf(from.z, to.z) - half
	var z1 := maxf(from.z, to.z) + half
	var y := (from.y + to.y) * 0.5
	var a := Vector3(x0, y, z0)
	var b := Vector3(x1, y, z0)
	var c := Vector3(x1, y, z1)
	var d := Vector3(x0, y, z1)
	_segment(a, b, color)
	_segment(b, c, color)
	_segment(c, d, color)
	_segment(d, a, color)
	var x := snappedf(minf(from.x, to.x), GridSnap.CELL)
	var x_end := snappedf(maxf(from.x, to.x), GridSnap.CELL)
	while x <= x_end + 0.001:
		_segment(Vector3(x, y, z0), Vector3(x, y, z1), color)
		x += GridSnap.CELL
	var z := snappedf(minf(from.z, to.z), GridSnap.CELL)
	var z_end := snappedf(maxf(from.z, to.z), GridSnap.CELL)
	while z <= z_end + 0.001:
		_segment(Vector3(x0, y, z), Vector3(x1, y, z), color)
		z += GridSnap.CELL
	var slab := PlaneMesh.new()
	slab.size = Vector2(maxf(x1 - x0, 0.08), maxf(z1 - z0, 0.08))
	_fill.mesh = slab
	_fill.position = Vector3((x0 + x1) * 0.5, y + 0.04, (z0 + z1) * 0.5)
	_fill.visible = true
	var mat := _fill.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(color, 0.32)
		mat.emission = color
		mat.emission_energy_multiplier = Palette.GLOW_SOFT


## Outer edge of a lava pool, so a take-back shows the whole section.
func footprint(cells: Array, color: Color) -> void:
	if cells.is_empty():
		return
	var half := GridSnap.CELL * 0.5
	var occupied := {}
	var y := 0.0
	for cell in cells:
		var at: Vector3 = cell
		occupied[_cell_key(at)] = true
		y += at.y
	y /= float(cells.size())
	var steps: Array[Vector3] = [
		Vector3(GridSnap.CELL, 0.0, 0.0), Vector3(-GridSnap.CELL, 0.0, 0.0),
		Vector3(0.0, 0.0, GridSnap.CELL), Vector3(0.0, 0.0, -GridSnap.CELL),
	]
	for cell in cells:
		var at := Vector3((cell as Vector3).x, y, (cell as Vector3).z)
		for step in steps:
			if occupied.has(_cell_key(at + step)):
				continue
			var along := Vector3(-step.z, 0.0, step.x).normalized() * half
			var mid := at + step.normalized() * half
			_segment(mid - along, mid + along, color)


func _cell_key(at: Vector3) -> String:
	return "%d,%d" % [roundi(at.x / GridSnap.CELL), roundi(at.z / GridSnap.CELL)]


func marker(at: Vector3, color: Color) -> void:
	_segment(at + Vector3(-MARK, 0.0, 0.0), at + Vector3(MARK, 0.0, 0.0), color)
	_segment(at + Vector3(0.0, 0.0, -MARK), at + Vector3(0.0, 0.0, MARK), color)
	_segment(at, at + Vector3(0.0, MARK * 2.0, 0.0), color)


func _segment(from: Vector3, to: Vector3, color: Color) -> void:
	if _drawn == 0:
		_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(from + Vector3.UP * LIFT)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(to + Vector3.UP * LIFT)
	_drawn += 2


# #region agent log
func _dbg_create() -> void:
	var mat := material_override as StandardMaterial3D
	var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-f6d8e1.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-f6d8e1.log", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"sessionId": "f6d8e1", "runId": "post-fix", "hypothesisId": "H",
		"location": "creator_marks.gd:create",
		"message": "creator marks script loaded",
		"timestamp": Time.get_ticks_msec(),
		"data": {
			"cull_mode": mat.cull_mode if mat != null else -1,
			"has_ghost": _ghost != null,
			"ghost_mat": _ghost.material_override is ShaderMaterial if _ghost != null else false,
			"overlay": (
				_ghost.material_override.shader.resource_path.get_file()
				if _ghost != null and _ghost.material_override is ShaderMaterial
				and (_ghost.material_override as ShaderMaterial).shader != null
				else ""
			),
		},
	}))
	f.close()


func _dbg_should() -> bool:
	_dbg_i += 1
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var yaw := 0.0
	if cam != null:
		yaw = rad_to_deg(cam.global_transform.basis.get_euler().y)
	var turned := absf(yaw - _dbg_yaw) >= 8.0
	if turned:
		_dbg_yaw = yaw
	return _dbg_i <= 400 and (_dbg_i == 1 or _dbg_i % 15 == 0 or turned)


func _dbg_ghost(from: Vector3, to: Vector3, width: float, along: Vector3, side: Vector3, segs: Array) -> void:
	if not _dbg_should():
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var sides: Array = []
	var eul := Vector3.ZERO
	var fwd := Vector3.ZERO
	if cam != null:
		eul = cam.global_transform.basis.get_euler()
		fwd = -cam.global_transform.basis.z
	for seg in segs:
		var a: Vector3 = seg[1] + Vector3.UP * LIFT
		var b: Vector3 = seg[2] + Vector3.UP * LIFT
		var dir := b - a
		var row := {
			"name": String(seg[0]),
			"len": snappedf(dir.length(), 0.01),
			"dir": [snappedf(dir.x, 0.01), snappedf(dir.y, 0.01), snappedf(dir.z, 0.01)],
		}
		if cam != null and dir.length_squared() > 0.0001:
			var n := dir.normalized().cross(Vector3.UP)
			row["view_along"] = snappedf(absf(fwd.dot(dir.normalized())), 0.01)
			row["cull_dot"] = snappedf(fwd.dot(n.normalized()) if n.length_squared() > 0.0001 else 0.0, 0.01)
			row["a_behind"] = cam.is_position_behind(a)
			row["b_behind"] = cam.is_position_behind(b)
			row["a_frustum"] = cam.is_position_in_frustum(a)
			row["b_frustum"] = cam.is_position_in_frustum(b)
			row["screen"] = snappedf(cam.unproject_position(a).distance_to(cam.unproject_position(b)), 0.1)
			var space := get_world_3d().direct_space_state
			var mid := (a + b) * 0.5
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, mid))
			var col = hit.get("collider") if not hit.is_empty() else null
			row["occluder"] = String(col.name) if col != null else ""
			row["hit_dist"] = -1.0 if hit.is_empty() else snappedf(cam.global_position.distance_to(hit["position"]), 0.01)
			row["mid_dist"] = snappedf(cam.global_position.distance_to(mid), 0.01)
		sides.append(row)
	var mat := material_override as StandardMaterial3D
	var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-f6d8e1.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-f6d8e1.log", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"sessionId": "f6d8e1", "runId": "post-fix", "hypothesisId": "F",
		"location": "creator_marks.gd:ghost_segment",
		"message": "fairway ghost sides vs camera",
		"timestamp": Time.get_ticks_msec(),
		"data": {
			"draw_mode": "bars",
			"inset": CreatorMarks.GHOST_INSET,
			"half": snappedf(side.length(), 0.01),
			"bar_verts": 0 if _ghost.mesh == null or _ghost.mesh.get_surface_count() == 0 else _ghost.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),
			"ghost_on": _ghost.visible,
			"drawn": _drawn,
			"width": snappedf(width, 0.01),
			"along_len": snappedf(along.length(), 0.01),
			"side_len": snappedf(side.length(), 0.01),
			"from": [snappedf(from.x, 0.01), snappedf(from.y, 0.01), snappedf(from.z, 0.01)],
			"to": [snappedf(to.x, 0.01), snappedf(to.y, 0.01), snappedf(to.z, 0.01)],
			"cull_mode": mat.cull_mode if mat != null else -1,
			"no_depth": mat.no_depth_test if mat != null else false,
			"cam_eul": [snappedf(rad_to_deg(eul.x), 0.1), snappedf(rad_to_deg(eul.y), 0.1), snappedf(rad_to_deg(eul.z), 0.1)],
			"cam_fwd": [snappedf(fwd.x, 0.01), snappedf(fwd.y, 0.01), snappedf(fwd.z, 0.01)],
			"sides": sides,
		},
	}))
	f.close()


func _dbg_finish() -> void:
	if _dbg_i > 400 or (_dbg_i > 1 and _dbg_i % 15 != 0):
		return
	var box := get_aabb()
	var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-f6d8e1.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-f6d8e1.log", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"sessionId": "f6d8e1", "runId": "pre-fix", "hypothesisId": "D",
		"location": "creator_marks.gd:finish",
		"message": "ghost mesh aabb after rebuild",
		"timestamp": Time.get_ticks_msec(),
		"data": {
			"drawn": _drawn,
			"aabb_pos": [snappedf(box.position.x, 0.01), snappedf(box.position.y, 0.01), snappedf(box.position.z, 0.01)],
			"aabb_size": [snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01), snappedf(box.size.z, 0.01)],
		},
	}))
	f.close()
# #endregion
