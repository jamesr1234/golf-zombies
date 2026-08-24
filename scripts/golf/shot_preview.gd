class_name ShotPreview
extends MeshInstance3D
## White flight line for a perfect-contact swing, plus a ground line and a ring
## on the landing so a punch and a flop read as different carries.

const WIDTH := 0.045
const GROUND_WIDTH := 0.07
const GROUND_LIFT := 0.06


var landing := Vector3.ZERO
var _spot: MeshInstance3D


func _ready() -> void:
	top_level = true
	mesh = ImmediateMesh.new()
	material_override = _line_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spot = MeshFactory.torus(0.55, 0.9, Palette.LED_WHITE, Palette.GLOW_STRONG)
	_spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spot)
	_spot.visible = false


func draw(points: PackedVector3Array) -> void:
	var immediate := mesh as ImmediateMesh
	immediate.clear_surfaces()
	if points.size() < 2:
		if _spot != null:
			_spot.visible = false
		return
	_add_ribbon(immediate, points, true)
	_add_ribbon(immediate, points, false)
	_add_ribbon(immediate, _ground_line(points), true, GROUND_WIDTH)
	landing = points[points.size() - 1]
	_spot.visible = true
	_spot.global_position = landing + Vector3.UP * 0.05


func spot_visible() -> bool:
	return _spot != null and _spot.visible


func _ground_line(points: PackedVector3Array) -> PackedVector3Array:
	var start := points[0]
	var land := points[points.size() - 1]
	var ground := PackedVector3Array()
	ground.append(Vector3(start.x, start.y + GROUND_LIFT, start.z))
	ground.append(Vector3(land.x, start.y + GROUND_LIFT, land.z))
	return ground


func _add_ribbon(
	immediate: ImmediateMesh, points: PackedVector3Array, flat: bool, width := WIDTH
) -> void:
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var color := Palette.LED_WHITE
	for i in points.size():
		var direction := _direction_at(points, i)
		var side := direction.cross(Vector3.UP)
		if side.length_squared() < 0.001:
			side = Vector3.RIGHT
		side = side.normalized()
		var offset := side if flat else side.cross(direction).normalized()
		immediate.surface_set_color(color)
		immediate.surface_add_vertex(points[i] + offset * width)
		immediate.surface_set_color(color)
		immediate.surface_add_vertex(points[i] - offset * width)
	immediate.surface_end()


func _direction_at(points: PackedVector3Array, index: int) -> Vector3:
	var from := points[maxi(index - 1, 0)]
	var to := points[mini(index + 1, points.size() - 1)]
	var direction := to - from
	if direction.length_squared() < 0.001:
		return Vector3.FORWARD
	return direction.normalized()


func _line_material() -> StandardMaterial3D:
	var mat := MeshFactory.material(Palette.LED_WHITE, true, Palette.GLOW_STRONG)
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
