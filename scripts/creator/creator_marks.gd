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


func finish() -> void:
	if _drawn == 0:
		return
	_lines.surface_end()
	# #region agent log
	_dbg_finish()
	# #endregion


## The corner a fairway piece would add, so the shape is read before it lands.
func ghost_segment(from: Vector3, to: Vector3, width: float, ok: bool) -> void:
	var color := Palette.LIME if ok else Palette.HOT_PINK
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


func ring(center: Vector3, radius: float, color: Color) -> void:
	var previous := center + Vector3(radius, 0.0, 0.0)
	for i in range(1, RING_STEPS + 1):
		var angle := TAU * float(i) / float(RING_STEPS)
		var point := center + Vector3(cos(angle), 0.0, sin(angle)) * radius
		_segment(previous, point, color)
		previous = point


func line(from: Vector3, to: Vector3, color: Color) -> void:
	_segment(from, to, color)


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
