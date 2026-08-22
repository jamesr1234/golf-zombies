class_name TireMarks
extends MeshInstance3D
## Rubber left on the turf while the cart is sliding. Each wheel paints its own
## ribbon, and the oldest stretch fades so a long drift does not stain the hole.

const MAX_POINTS := 72
const STEP := 0.16
const WIDTH := 0.16
const LIFE := 2.4
const LIFT := 0.05

var _tracks: Array[PackedVector3Array] = []
var _ages: Array[PackedFloat32Array] = []


func _ready() -> void:
	top_level = true
	mesh = ImmediateMesh.new()
	material_override = _mark_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func clear() -> void:
	_tracks.clear()
	_ages.clear()
	_rebuild()


func trace(contacts: Array[Vector3], sliding: bool, delta: float) -> void:
	_ensure_tracks(contacts.size())
	for i in _tracks.size():
		_age_track(i, delta)
		if sliding and i < contacts.size():
			_record(i, contacts[i])
	_rebuild()


func _ensure_tracks(count: int) -> void:
	while _tracks.size() < count:
		_tracks.append(PackedVector3Array())
		_ages.append(PackedFloat32Array())
	while _tracks.size() > count:
		_tracks.pop_back()
		_ages.pop_back()


func _age_track(index: int, delta: float) -> void:
	var points := PackedVector3Array()
	var ages := PackedFloat32Array()
	for i in _tracks[index].size():
		var age := _ages[index][i] + delta
		if age < LIFE:
			points.append(_tracks[index][i])
			ages.append(age)
	_tracks[index] = points
	_ages[index] = ages


func _record(index: int, at: Vector3) -> void:
	var points := _tracks[index]
	var ages := _ages[index]
	if points.size() >= MAX_POINTS:
		points.remove_at(0)
		ages.remove_at(0)
	if points.is_empty() or points[points.size() - 1].distance_to(at) >= STEP:
		points.append(at)
		ages.append(0.0)
	_tracks[index] = points
	_ages[index] = ages


func _rebuild() -> void:
	var immediate := mesh as ImmediateMesh
	if immediate == null:
		return
	immediate.clear_surfaces()
	for i in _tracks.size():
		if _tracks[i].size() < 2:
			continue
		immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for p in _tracks[i].size():
			var direction := _direction_at(i, p)
			var side := direction.cross(Vector3.UP)
			if side.length_squared() < 0.001:
				side = Vector3.RIGHT
			side = side.normalized() * WIDTH
			var color := Color(Palette.TIRE_MARK, 1.0 - _ages[i][p] / LIFE)
			immediate.surface_set_color(color)
			immediate.surface_add_vertex(_tracks[i][p] + side)
			immediate.surface_set_color(color)
			immediate.surface_add_vertex(_tracks[i][p] - side)
		immediate.surface_end()


func _direction_at(track: int, index: int) -> Vector3:
	var points := _tracks[track]
	var from := points[maxi(index - 1, 0)]
	var to := points[mini(index + 1, points.size() - 1)]
	var direction := to - from
	if direction.length_squared() < 0.001:
		return Vector3.FORWARD
	return direction.normalized()


func _mark_material() -> StandardMaterial3D:
	var mat := MeshFactory.material(Palette.TIRE_MARK, true)
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
