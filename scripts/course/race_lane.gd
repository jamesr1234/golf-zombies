extends Node3D
## Neon rails on both lips of Test Hole 2. Tight hairpins are narrower than
## the strip, so the inner rail pinches instead of flipping across the path.
## Dark until the ball goes through the hoop.

const _SCRIPT := preload("res://scripts/course/race_lane.gd")
const GROUP := "race_lanes"
const INSET := 0.22
const LIFT := 0.1
const MIN_SPAN := 0.35
## Inner offset stays below local radius so hairpins do not invert.
const INNER_KEEP := 0.68
const JOIN := 0.25
const SAMPLE := 2.2


static func create(data: HoleData) -> Node3D:
	var node = _SCRIPT.new()
	node.name = "RaceLane"
	node._assemble(data)
	return node


static func ignite_in(tree: SceneTree) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group(GROUP):
		if node.has_method("ignite"):
			node.ignite()


var _mat: ShaderMaterial
var _lit := false


func is_lit() -> bool:
	return _lit


func ignite() -> void:
	if _lit:
		return
	_lit = true
	visible = true
	if _mat != null:
		_mat.set_shader_parameter("tint", Palette.CYAN)
		_mat.set_shader_parameter("energy", Palette.GLOW_STRONG)


func _ready() -> void:
	add_to_group(GROUP)
	if not _lit:
		visible = false


func _assemble(data: HoleData) -> void:
	add_to_group(GROUP)
	visible = false
	_lit = false
	var segs := _segs(data)
	if segs.is_empty():
		return
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = ObstacleLeds.mesh_from_segs(segs)
	_mat = ObstacleLeds.edge_material(0.0)
	_mat.set_shader_parameter("tint", Palette.CYAN)
	mesh_node.material_override = _mat
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_node)


static func _segs(data: HoleData) -> Array:
	var segs: Array = []
	if data == null or data.centerline.size() < 2:
		return segs
	var left := _follow(data, -1.0)
	var right := _follow(data, 1.0)
	# #region agent log
	_dbg_rails(data, left, right)
	_dbg_follow(data, left, right)
	# #endregion
	_append_run(segs, left)
	_append_run(segs, right)
	return segs


static func wrong_side_count(data: HoleData) -> int:
	if data == null or data.centerline.size() < 2:
		return 0
	return _overshoot(data, -1.0) + _overshoot(data, 1.0)


static func _dbg_rails(data: HoleData, left: Array[Vector3], right: Array[Vector3]) -> void:
	var inverted := 0
	var min_room := 999.0
	var min_r := 999.0
	for i in range(1, data.centerline.size() - 1):
		var a: Vector3 = data.centerline[i - 1]
		var b: Vector3 = data.centerline[i]
		var c: Vector3 = data.centerline[i + 1]
		var d0 := b - a
		var d1 := c - b
		d0.y = 0.0
		d1.y = 0.0
		var l0 := d0.length()
		var l1 := d1.length()
		if l0 < 0.05 or l1 < 0.05:
			continue
		var turn := absf(d0.normalized().angle_to(d1.normalized()))
		var radius := 999.0 if turn < 0.02 else ((l0 + l1) * 0.5) / turn
		min_r = minf(min_r, radius)
		var half := _half_at(data, b)
		var room := radius - half
		min_room = minf(min_room, room)
		if room < 0.0:
			inverted += 1
	var min_step := 999.0
	var backtrack := 0
	var skipped := 0
	for rail in [left, right]:
		for i in range(1, rail.size()):
			var step: float = rail[i - 1].distance_to(rail[i])
			min_step = minf(min_step, step)
			if step < MIN_SPAN:
				skipped += 1
			if i >= 2:
				var u: Vector3 = rail[i] - rail[i - 1]
				var v: Vector3 = rail[i - 1] - rail[i - 2]
				u.y = 0.0
				v.y = 0.0
				if u.length_squared() > 0.0001 and v.length_squared() > 0.0001 and u.dot(v) < 0.0:
					backtrack += 1
	var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-8cf7b5.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-8cf7b5.log", FileAccess.WRITE)
	else:
		f.seek_end()
	if f != null:
		f.store_line(JSON.stringify({
			"sessionId": "8cf7b5",
			"hypothesisId": "A",
			"location": "race_lane.gd:_segs",
			"message": "rail quality",
			"data": {
				"centerline": data.centerline.size(),
				"half": snappedf(_half_at(data, data.tee), 0.01),
				"min_radius": snappedf(min_r, 0.01),
				"min_room": snappedf(min_room, 0.01),
				"inverted": inverted,
				"min_step": snappedf(min_step, 0.01),
				"skipped": skipped,
				"backtrack": backtrack,
			},
			"timestamp": Time.get_ticks_msec(),
		}))
		f.close()


# #region agent log
static func _dbg_follow(data: HoleData, left: Array[Vector3], right: Array[Vector3]) -> void:
	var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-8cf7b5.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-8cf7b5.log", FileAccess.WRITE)
	else:
		f.seek_end()
	if f != null:
		f.store_line(JSON.stringify({
			"sessionId": "8cf7b5",
			"runId": "post-fix",
			"hypothesisId": "A",
			"location": "race_lane.gd:_follow",
			"message": "rail follow",
			"data": {
				"left_over": _overshoot(data, -1.0),
				"right_over": _overshoot(data, 1.0),
				"left_n": left.size(),
				"right_n": right.size(),
				"left_back": _folds(left),
				"right_back": _folds(right),
				"left_raw_back": _folds(_rail(data, -1.0)),
				"right_raw_back": _folds(_rail(data, 1.0)),
				"min_dot": snappedf(minf(_min_dot(left), _min_dot(right)), 0.01),
				"raw_min_dot": snappedf(
					minf(_min_dot(_rail(data, -1.0)), _min_dot(_rail(data, 1.0))),
					0.01
				),
			},
			"timestamp": Time.get_ticks_msec(),
		}))
		f.close()
# #endregion


static func _follow(data: HoleData, side: float) -> Array[Vector3]:
	return _sample(_clean(_rail(data, side)))


static func _rail(data: HoleData, side: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in data.centerline.size():
		var at: Vector3 = data.centerline[i]
		var width := _width_at(data, i, side, _half_at(data, at))
		var forward := _forward_at(data, i)
		var right := forward.cross(Vector3.UP)
		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT
		points.append(at + right.normalized() * side * width + Vector3.UP * LIFT)
	return points


static func _forward_at(data: HoleData, i: int) -> Vector3:
	var a: Vector3
	var b: Vector3
	if i <= 0:
		a = data.centerline[0]
		b = data.centerline[1]
	elif i >= data.centerline.size() - 1:
		a = data.centerline[i - 1]
		b = data.centerline[i]
	else:
		a = data.centerline[i - 1]
		b = data.centerline[i + 1]
	var d := b - a
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return data.along_tee()
	return d.normalized()


static func _width_at(data: HoleData, i: int, side: float, half: float) -> float:
	if i <= 0 or i >= data.centerline.size() - 1:
		return half
	var radius := _radius_at(data, i)
	var turn_y := _turn_y(data, i)
	if radius > 400.0 or absf(turn_y) < 0.001:
		return half
	if turn_y * side >= 0.0:
		return half
	return minf(half, maxf(0.8, radius * INNER_KEEP))


static func _turn_y(data: HoleData, i: int) -> float:
	var d0: Vector3 = data.centerline[i] - data.centerline[i - 1]
	var d1: Vector3 = data.centerline[i + 1] - data.centerline[i]
	d0.y = 0.0
	d1.y = 0.0
	if d0.length_squared() < 0.0025 or d1.length_squared() < 0.0025:
		return 0.0
	return d0.normalized().cross(d1.normalized()).y


static func _radius_at(data: HoleData, i: int) -> float:
	var d0: Vector3 = data.centerline[i] - data.centerline[i - 1]
	var d1: Vector3 = data.centerline[i + 1] - data.centerline[i]
	d0.y = 0.0
	d1.y = 0.0
	var l0 := d0.length()
	var l1 := d1.length()
	if l0 < 0.05 or l1 < 0.05:
		return 999.0
	var turn := absf(d0.normalized().angle_to(d1.normalized()))
	return 999.0 if turn < 0.02 else ((l0 + l1) * 0.5) / turn


static func _clean(rail: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in rail:
		if out.is_empty() or p.distance_to(out.back()) >= JOIN:
			out.append(p)
	return out


static func _sample(rail: Array[Vector3]) -> Array[Vector3]:
	if rail.size() < 2:
		return rail
	var out: Array[Vector3] = [rail[0]]
	for i in range(1, rail.size()):
		var a: Vector3 = out.back()
		var b: Vector3 = rail[i]
		var span := a.distance_to(b)
		if span < 0.001:
			continue
		var dir := (b - a) / span
		var pos := SAMPLE
		while pos < span - 0.5:
			out.append(a + dir * pos)
			pos += SAMPLE
		out.append(b)
	return out


static func _overshoot(data: HoleData, side: float) -> int:
	var n := 0
	for i in range(1, data.centerline.size() - 1):
		var radius := _radius_at(data, i)
		if radius > 400.0:
			continue
		if _turn_y(data, i) * side >= 0.0:
			continue
		var width := _width_at(data, i, side, _half_at(data, data.centerline[i]))
		if width >= radius - 0.05:
			n += 1
	return n


static func _folds(rail: Array[Vector3]) -> int:
	var n := 0
	for i in range(2, rail.size()):
		var u: Vector3 = rail[i] - rail[i - 1]
		var v: Vector3 = rail[i - 1] - rail[i - 2]
		u.y = 0.0
		v.y = 0.0
		if u.length_squared() > 0.0001 and v.length_squared() > 0.0001:
			if u.normalized().dot(v.normalized()) < -0.35:
				n += 1
	return n


static func _min_dot(rail: Array[Vector3]) -> float:
	var best := 1.0
	for i in range(2, rail.size()):
		var u: Vector3 = rail[i] - rail[i - 1]
		var v: Vector3 = rail[i - 1] - rail[i - 2]
		u.y = 0.0
		v.y = 0.0
		if u.length_squared() > 0.0001 and v.length_squared() > 0.0001:
			best = minf(best, u.normalized().dot(v.normalized()))
	return best


static func _half_at(data: HoleData, at: Vector3) -> float:
	var fairway := HoleGenerator.fairway_width(data.par, data.index) * 0.5
	var green := data.green_radius + HoleGenerator.FRINGE_WIDTH
	var blend := 1.0 - clampf((at.distance_to(data.cup) - green) / 12.0, 0.0, 1.0)
	return maxf(0.4, lerpf(fairway, green, blend) - INSET)


static func _append_run(segs: Array, rail: Array[Vector3]) -> void:
	for i in range(1, rail.size()):
		if rail[i - 1].distance_to(rail[i]) >= MIN_SPAN:
			segs.append([rail[i - 1], rail[i]])
