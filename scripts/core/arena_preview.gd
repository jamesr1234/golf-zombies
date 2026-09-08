class_name ArenaPreview
extends RefCounted
## Camera hold on the hole-5 doors while they ease open or shut.

const OPEN_SEC := 5.6
const CLOSE_SEC := 4.8

var _doors: ArenaDoors
var _opening := true
var _t := 0.0
var _active := false


func start(doors: ArenaDoors, opening: bool) -> void:
	_doors = doors
	_opening = opening
	_t = 0.0
	_active = doors != null and is_instance_valid(doors)
	if _active:
		_doors.apply(0.0 if opening else 1.0)


func skip() -> void:
	if _doors != null and is_instance_valid(_doors):
		_doors.snap(_opening)
	_active = false


func is_active() -> bool:
	return _active


func is_opening() -> bool:
	return _opening


func is_closing() -> bool:
	return not _opening


func duration() -> float:
	return OPEN_SEC if _opening else CLOSE_SEC


func tick(delta: float) -> bool:
	if not _active:
		return false
	_t += delta
	var span := duration()
	var u := clampf(_t / span, 0.0, 1.0)
	if _doors != null and is_instance_valid(_doors):
		var eased := u * u * (3.0 - 2.0 * u)
		_doors.apply(eased if _opening else 1.0 - eased)
	if _t >= span:
		if _doors != null and is_instance_valid(_doors):
			_doors.snap(_opening)
		_active = false
		return false
	return true


func view() -> Transform3D:
	if _doors == null or not is_instance_valid(_doors):
		return Transform3D.IDENTITY
	return _doors.view(_opening, clampf(_t / duration(), 0.0, 1.0))
