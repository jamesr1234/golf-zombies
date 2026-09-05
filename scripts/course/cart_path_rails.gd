class_name CartPathRails
extends Object
## Forcefield on both lips, extruded along the track's real straights and
## circular sweeps. Same pane as the fairway field: it tries to keep you on
## the tarmac, and you snap back if you get through.

const ARC_DEG := 2.5
const ARC_STEP := 0.4
const DECK := 0.14
const _Field := preload("res://scripts/course/fairway_field.gd")
const _SHADER := preload("res://assets/shaders/fairway_field.gdshader")


static func dress(path: CartPath) -> void:
	if path.centerline.size() < 2:
		return
	var start: Vector3 = path.centerline[0]
	var heading := path.centerline[1] - start
	heading.y = 0.0
	if heading.length_squared() < 0.0001:
		return
	var runs := CartPathTrack.strokes(start, heading.normalized(), start.y)
	var mat := _material()
	for side in [-1.0, 1.0]:
		var lip := _lip(runs, side, path.tee)
		if lip["at"].size() < 2:
			continue
		_add_field(path, lip, mat)


static func _lip(runs: Array[Dictionary], side: float, tee: Vector3) -> Dictionary:
	var at := PackedVector3Array()
	var out := PackedVector3Array()
	var half := CartPath.PATH_WIDTH * 0.5
	for run in runs:
		if String(run["kind"]) == "line":
			_line(at, out, run["a"], run["b"], side, half)
		else:
			_arc(at, out, run, side, half)
	if side > 0.0:
		_clip_plaza(at, out, tee)
	return {"at": at, "out": out}


static func _line(
	at: PackedVector3Array, out: PackedVector3Array, a: Vector3, b: Vector3, side: float, half: float
) -> void:
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if along.length_squared() < 0.0001:
		return
	var right := along.normalized().cross(Vector3.UP)
	var outward := right * side
	_push(at, out, a + outward * half, outward)
	_push(at, out, b + outward * half, outward)


static func _arc(
	at: PackedVector3Array, out: PackedVector3Array, run: Dictionary, side: float, half: float
) -> void:
	var center: Vector3 = run["center"]
	var from: Vector3 = run["from"]
	var sweep: float = run["sweep"]
	var heading: Vector3 = run["heading"]
	var arm := Vector3(from.x - center.x, 0.0, from.z - center.z)
	if arm.length_squared() < 0.0001:
		return
	var lip := from + heading.cross(Vector3.UP) * side * half
	var span := lip.distance_to(center) * absf(sweep)
	var steps := maxi(8, maxi(int(ceil(absf(rad_to_deg(sweep)) / ARC_DEG)), int(ceil(span / ARC_STEP))))
	for i in steps + 1:
		var rot := sweep * (float(i) / float(steps))
		var tangent := heading.rotated(Vector3.UP, rot)
		var outward := tangent.cross(Vector3.UP) * side
		var on := center + arm.rotated(Vector3.UP, rot)
		var point := on + outward * half
		point.y = float(run["height"])
		_push(at, out, point, outward)


static func _push(at: PackedVector3Array, out: PackedVector3Array, point: Vector3, outward: Vector3) -> void:
	if at.size() > 0 and at[at.size() - 1].distance_squared_to(point) < 0.0025:
		at[at.size() - 1] = point
		out[out.size() - 1] = outward
		return
	at.append(point)
	out.append(outward)


static func _clip_plaza(at: PackedVector3Array, out: PackedVector3Array, tee: Vector3) -> void:
	while at.size() >= 2:
		var last: Vector3 = at[at.size() - 1]
		if Vector2(last.x - tee.x, last.z - tee.z).length() >= CartPath.TEE_OPEN:
			return
		var prev: Vector3 = at[at.size() - 2]
		if Vector2(prev.x - tee.x, prev.z - tee.z).length() > CartPath.TEE_OPEN:
			at[at.size() - 1] = _stop_short(prev, last, tee)
			out[out.size() - 1] = out[out.size() - 2]
			return
		at.resize(at.size() - 1)
		out.resize(out.size() - 1)


static func _stop_short(from: Vector3, to: Vector3, tee: Vector3) -> Vector3:
	var from_d := Vector2(from.x - tee.x, from.z - tee.z).length()
	var to_d := Vector2(to.x - tee.x, to.z - tee.z).length()
	if from_d <= CartPath.TEE_OPEN:
		return from
	if to_d >= CartPath.TEE_OPEN:
		return to
	var t := (from_d - CartPath.TEE_OPEN) / maxf(0.001, from_d - to_d)
	return from.lerp(to, clampf(t, 0.0, 1.0))


static func _material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("line_color", Palette.CYAN)
	mat.set_shader_parameter("hit_radius", _Field.HIT_RADIUS)
	mat.set_shader_parameter("hit_energy", 0.0)
	return mat


static func _add_field(path: CartPath, lip: Dictionary, mat: ShaderMaterial) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.FORCEFIELD
	body.collision_mask = 0
	body.add_to_group(CartPath.FIELD_GROUP)
	var hit := _prism(lip["at"], lip["out"], _Field.HIT_THICK, _Field.HEIGHT)
	var shape := CollisionShape3D.new()
	shape.shape = hit.create_trimesh_shape()
	body.add_child(shape)
	var vis := MeshInstance3D.new()
	vis.mesh = _prism(lip["at"], lip["out"], _Field.THICK, _Field.HEIGHT)
	vis.material_override = mat
	vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(vis)
	path.add_child(body)


static func _prism(lip: PackedVector3Array, outward: PackedVector3Array, thick: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, lip.size()):
		var a := _deck(lip[i - 1])
		var b := _deck(lip[i])
		var ao := _deck(lip[i - 1] + outward[i - 1] * thick)
		var bo := _deck(lip[i] + outward[i] * thick)
		var ah := a + Vector3.UP * height
		var bh := b + Vector3.UP * height
		var aoh := ao + Vector3.UP * height
		var boh := bo + Vector3.UP * height
		# Both windings. Trimesh hits are one-sided, and a cart and a side
		# ray come at the lip from opposite directions.
		_quad(st, a, ah, bh, b)
		_quad(st, a, b, bh, ah)
		_quad(st, ao, bo, boh, aoh)
		_quad(st, ao, aoh, boh, bo)
		_quad(st, ah, aoh, boh, bh)
		_quad(st, ah, bh, boh, aoh)
		_quad(st, a, b, bo, ao)
		_quad(st, a, ao, bo, b)
	_cap(st, lip, outward, 0, thick, height)
	_cap(st, lip, outward, lip.size() - 1, thick, height)
	st.generate_normals()
	st.index()
	return st.commit()


static func _cap(
	st: SurfaceTool, lip: PackedVector3Array, outward: PackedVector3Array, i: int, thick: float, height: float
) -> void:
	var a := _deck(lip[i])
	var ao := _deck(lip[i] + outward[i] * thick)
	var ah := a + Vector3.UP * height
	var aoh := ao + Vector3.UP * height
	if i == 0:
		_quad(st, a, ao, aoh, ah)
	else:
		_quad(st, a, ah, aoh, ao)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


static func _deck(at: Vector3) -> Vector3:
	return Vector3(at.x, at.y + DECK, at.z)
