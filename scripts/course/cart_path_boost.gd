class_name CartPathBoost
extends Area3D
## Glowing blue speed stripe down the middle of the clubhouse circuit. Driving
## it dumps far more speed than the cart's own trigger.

const _SCRIPT := preload("res://scripts/course/cart_path_boost.gd")

const SPEED := 56.0
const PLAYER_SPEED := 24.0
const ACCEL := 92.0
const WIDTH := 3.4
const DETECT_HEIGHT := 2.8
const CHEVRON_SPACING := 5.0
const START_SKIP := 8.0
const END_SKIP := 16.0

var along := Vector3.FORWARD


static func dress(path: Node3D) -> void:
	var centerline: Array = path.get("centerline")
	if centerline.size() < 2:
		return
	var travelled := 0.0
	var stop_after := float(path.get("track_length")) - END_SKIP
	for i in range(1, centerline.size()):
		var a: Vector3 = centerline[i - 1]
		var b: Vector3 = centerline[i]
		var span := a.distance_to(b)
		travelled += span
		if span < 0.8:
			continue
		if travelled < START_SKIP:
			continue
		if travelled - span > stop_after:
			break
		path.add_child(create(a, b))


static func create(from: Vector3, to: Vector3) -> Area3D:
	var pad = _SCRIPT.new()
	pad.add_to_group("transit_boost")
	var delta := to - from
	delta.y = 0.0
	var span := delta.length()
	pad.along = delta / maxf(span, 0.001)
	var mid := from.lerp(to, 0.5)
	pad.position = Vector3(mid.x, from.y + 0.12, mid.z)
	pad.rotation.y = atan2(-pad.along.x, -pad.along.z)
	pad.add_child(_detector(span))
	pad.add_child(_stripe(span))
	for mark in _chevrons(span):
		pad.add_child(mark)
	return pad


static func cart_speed(current: float, delta: float) -> float:
	return move_toward(current, SPEED, ACCEL * delta)


static func player_velocity(current: Vector3, heading: Vector3, delta: float) -> Vector3:
	var dir := heading
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return current
	var wanted := dir.normalized() * PLAYER_SPEED
	return Vector3(
		move_toward(current.x, wanted.x, ACCEL * delta),
		current.y,
		move_toward(current.z, wanted.z, ACCEL * delta)
	)


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.VEHICLE | Layers.PLAYER
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_boost"):
		body.enter_boost(along)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_boost"):
		body.exit_boost()


static func _detector(span: float) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, DETECT_HEIGHT, span)
	node.shape = box
	return node


static func _stripe(span: float) -> MeshInstance3D:
	var strip := MeshFactory.box(
		Vector3(WIDTH * 0.42, 0.05, span * 0.98), Palette.CYAN, Palette.GLOW_MEDIUM
	)
	strip.position.y = 0.02
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return strip


static func _chevrons(span: float) -> Array[Node3D]:
	var marks: Array[Node3D] = []
	var count := maxi(1, int(span / CHEVRON_SPACING))
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var mark := _arrow()
		mark.position = Vector3(0.0, 0.06, lerpf(span * 0.5, -span * 0.5, t))
		marks.append(mark)
	return marks


static func _arrow() -> Node3D:
	var root := Node3D.new()
	var shaft := MeshFactory.box(Vector3(0.85, 0.07, 2.6), Palette.CYAN, Palette.GLOW_STRONG)
	shaft.position = Vector3(0.0, 0.0, -0.7)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tip := MeshFactory.box(Vector3(1.7, 0.07, 1.7), Palette.CYAN, Palette.GLOW_STRONG)
	tip.position = Vector3(0.0, 0.0, -2.35)
	tip.rotation.y = deg_to_rad(45.0)
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shaft)
	root.add_child(tip)
	return root
