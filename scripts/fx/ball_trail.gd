class_name BallTrail
extends MeshInstance3D
## Draws the flight line of the shot in the air behind the ball. It fades out a
## couple of seconds after the ball settles, so you can read the shape of the
## shot you just hit without it becoming a permanent yardage marker on the hole.

const MAX_POINTS := 240
## Distance between samples. Small enough to keep a high arc smooth.
const STEP := 0.5
const WIDTH := 0.07
const FADE_TIME := 2.0

var _ball: GolfBall
var _points: PackedVector3Array = PackedVector3Array()
var _fade := 0.0
var _was_in_play := false


func _ready() -> void:
	_ball = get_parent() as GolfBall
	# Points are recorded in world space, so the trail must not ride along with
	# the ball it hangs off.
	top_level = true
	mesh = ImmediateMesh.new()
	material_override = _trail_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if _ball == null:
		return
	var in_play := _ball.is_in_play()
	if in_play and not _was_in_play:
		_points.clear()
		_fade = 1.0
	_was_in_play = in_play
	if in_play:
		_record(_ball.global_position)
	elif _fade > 0.0:
		_fade = maxf(0.0, _fade - delta / FADE_TIME)
		if is_zero_approx(_fade):
			_points.clear()
	_rebuild()


func _record(at: Vector3) -> void:
	if _points.size() >= MAX_POINTS:
		return
	if _points.is_empty() or _points[_points.size() - 1].distance_to(at) >= STEP:
		_points.append(at)


func _rebuild() -> void:
	var immediate := mesh as ImmediateMesh
	immediate.clear_surfaces()
	if _points.size() < 2 or _fade <= 0.0:
		return
	_add_ribbon(immediate, true)
	_add_ribbon(immediate, false)


## Two ribbons at right angles to each other. A single one would disappear when a
## camera caught it edge on, and both players watch the same shot from different
## angles.
func _add_ribbon(immediate: ImmediateMesh, flat: bool) -> void:
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var color := Color(Palette.ICE, _fade)
	for i in _points.size():
		var direction := _direction_at(i)
		var side := direction.cross(Vector3.UP)
		if side.length_squared() < 0.001:
			side = Vector3.RIGHT
		side = side.normalized()
		var offset := side if flat else side.cross(direction).normalized()
		immediate.surface_set_color(color)
		immediate.surface_add_vertex(_points[i] + offset * WIDTH)
		immediate.surface_set_color(color)
		immediate.surface_add_vertex(_points[i] - offset * WIDTH)
	immediate.surface_end()


func _direction_at(index: int) -> Vector3:
	var from := _points[maxi(index - 1, 0)]
	var to := _points[mini(index + 1, _points.size() - 1)]
	var direction := to - from
	if direction.length_squared() < 0.001:
		return Vector3.FORWARD
	return direction.normalized()


func _trail_material() -> StandardMaterial3D:
	var mat := MeshFactory.material(Palette.ICE, true)
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
