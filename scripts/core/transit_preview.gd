class_name TransitPreview
extends RefCounted
## Short flyover along the cart path so every human camera sees the next hole.

const DURATION := 4.0
const HEIGHT := 14.0
const BACK := 18.0
const LOOK_AHEAD := 22.0

var _points: Array[Vector3] = []
var _length := 0.0
var _t := 0.0
var _active := false


func start(centerline: Array[Vector3]) -> void:
	_points = centerline
	_length = CartPathTrack.length_of(centerline)
	_t = 0.0
	_active = _points.size() >= 2 and _length > 1.0


func skip() -> void:
	_active = false


func is_active() -> bool:
	return _active


func tick(delta: float) -> bool:
	if not _active:
		return false
	_t += delta
	if _t >= DURATION:
		_active = false
		return false
	return true


func view() -> Transform3D:
	if _points.size() < 2:
		return Transform3D.IDENTITY
	var along := _length * clampf(_t / DURATION, 0.0, 1.0)
	var at := CartPathTrack.at(_points, along)
	var ahead := CartPathTrack.at(_points, along + LOOK_AHEAD)
	var face := ahead - at
	face.y = 0.0
	if face.length_squared() < 0.0001:
		face = CartPathTrack.heading_at(_points, along)
	face = face.normalized()
	var origin := at - face * BACK + Vector3.UP * HEIGHT
	return Transform3D(Basis.looking_at(ahead - origin, Vector3.UP), origin)
