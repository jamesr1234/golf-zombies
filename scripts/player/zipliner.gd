class_name Zipliner
extends RefCounted
## Hang under a zipline cable and slide from the high deck to the low one.
## A metal triangle trolley rides the line; both hands hold the bottom bar.

const BAR := 0.035
const CAM_BACK := 4.6
const CAM_SIDE := 1.55
const CAM_HEIGHT := 1.85
const CAM_LOOK := 1.4
const CAM_FOV := 70.0

var line: Zipline
var t := 0.0
var _trolley: Node3D


func is_active() -> bool:
	return line != null and is_instance_valid(line)


func latch(player: Player, on: Zipline) -> bool:
	if on == null:
		return false
	line = on
	t = 0.0
	player.global_position = on.ride_at(0.0)
	player.velocity = Vector3.ZERO
	player.set_look_yaw(on.land_yaw())
	_spawn_trolley()
	_pose_trolley()
	return true


func tick(player: Player, delta: float) -> bool:
	if not is_active() or player.health == null or not player.health.is_alive():
		return false
	if player.input.just_pressed("jump"):
		player.velocity = line.along() * line.ride_speed()
		drop()
		Sfx.play("zipline_drop", player)
		return false
	var span := maxf(line.cable_length(), 0.01)
	t = clampf(t + line.ride_speed() / span * delta, 0.0, 1.0)
	player.global_position = line.ride_at(t)
	player.velocity = line.along() * line.ride_speed()
	player.rotation.y = deg_to_rad(line.land_yaw())
	_pose_trolley()
	if t >= 1.0:
		player.stand_at(line.land_at(), line.land_yaw())
		drop()
		Sfx.play("zipline_drop", player)
		return false
	return true


func drop() -> void:
	if _trolley != null and is_instance_valid(_trolley):
		_trolley.free()
	_trolley = null
	line = null
	t = 0.0


func hook_at() -> Vector3:
	if not is_active():
		return Vector3.INF
	return line.point_on_cable(t)


func grip_left() -> Vector3:
	if not is_active():
		return Vector3.INF
	return line.grip_at(t, -1.0)


func grip_right() -> Vector3:
	if not is_active():
		return Vector3.INF
	return line.grip_at(t, 1.0)


func view_transform(player: Player) -> Transform3D:
	var target := player.global_position + Vector3.UP * CAM_LOOK
	var yaw_r := deg_to_rad(player.look.yaw)
	var pitch_r := deg_to_rad(player.look.pitch)
	var back := Vector3(sin(yaw_r), 0.0, cos(yaw_r))
	var right := Vector3(cos(yaw_r), 0.0, -sin(yaw_r))
	var eye := (
		target + back * CAM_BACK * cos(pitch_r) + right * CAM_SIDE
		+ Vector3.UP * (CAM_HEIGHT + sin(pitch_r) * CAM_BACK)
	)
	return Transform3D(Basis(), eye).looking_at(target, Vector3.UP)


func _spawn_trolley() -> void:
	if _trolley != null and is_instance_valid(_trolley):
		_trolley.free()
	_trolley = _build_trolley()
	line.add_child(_trolley)


func _pose_trolley() -> void:
	if _trolley == null or not is_instance_valid(_trolley) or not is_active():
		return
	var hook := line.point_on_cable(t)
	var x := line.trolley_side()
	var y := Vector3.UP
	var z := x.cross(y)
	if z.length_squared() < 0.0001:
		z = Vector3.FORWARD
	else:
		z = z.normalized()
	_trolley.global_transform = Transform3D(Basis(x, y, z), hook)


func _build_trolley() -> Node3D:
	var root := Node3D.new()
	root.name = "Trolley"
	var drop := Zipline.TROLLEY_DROP
	var half := Zipline.GRIP_HALF
	var left := Vector3(-half, -drop, 0.0)
	var right := Vector3(half, -drop, 0.0)
	var apex := Vector3.ZERO
	root.add_child(_bar(apex, left))
	root.add_child(_bar(apex, right))
	root.add_child(_bar(left, right))
	var wheel := MeshFactory.torus(0.028, 0.07, Palette.ICE, Palette.GLOW_MEDIUM)
	wheel.name = "Pulley"
	wheel.rotation.x = deg_to_rad(90.0)
	wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wheel)
	return root


func _bar(from: Vector3, to: Vector3) -> MeshInstance3D:
	var delta := to - from
	var span := maxf(delta.length(), 0.04)
	var bar := MeshFactory.box(Vector3(BAR, span, BAR), Palette.TOWER_TRIM, Palette.GLOW_SOFT)
	bar.position = (from + to) * 0.5
	var y := delta / span
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	bar.basis = Basis(x, y, x.cross(y))
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bar
