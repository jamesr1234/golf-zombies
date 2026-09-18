@tool
class_name Fan
extends Area3D
## Floor turbine. The column above holds a cart, a walker, or the ball up
## without taking the speed they brought in.

const MODEL_PATH := "res://assets/course/fan.glb"
const HOVER_VY := 1.8
const LIFT_ACCEL := 36.0
const SETTLE_ACCEL := 10.0
const STEER := 8.0
const COLUMN_W := 10.0
const COLUMN_H := 14.0
const SPIN_DEG := 420.0

var _rotor: Node3D


func _ready() -> void:
	add_to_group("fans")
	collision_layer = 0
	collision_mask = Layers.PLAYER | Layers.VEHICLE | Layers.BALL
	monitoring = true
	monitorable = false
	if get_node_or_null("Model") == null:
		_assemble()
	_rotor = find_child("Rotor", true, false) as Node3D
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if _rotor != null:
		_rotor.rotate_y(deg_to_rad(SPIN_DEG) * delta)
	if Engine.is_editor_hint():
		return
	for body in get_overlapping_bodies():
		_lift_ball(body as GolfBall, delta)


## Falling speeds climb toward a gentle hover. A ramp launch that is already
## going up is bled off slowly so the jump still carries forward.
static func next_vertical(current: float, delta: float) -> float:
	var accel := LIFT_ACCEL if current < HOVER_VY else SETTLE_ACCEL
	return move_toward(current, HOVER_VY, accel * delta)


## Turn toward the stick without shedding the speed you already have.
static func hold_horizontal(velocity: Vector3, wish: Vector3, delta: float) -> Vector3:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horiz.length()
	var dir := Vector3(wish.x, 0.0, wish.z)
	if dir.length_squared() < 0.0001:
		return velocity
	dir = dir.normalized()
	if speed < 0.2:
		return Vector3(dir.x * speed, velocity.y, dir.z * speed)
	var next := horiz.move_toward(dir * speed, STEER * delta)
	if next.length_squared() > 0.0001:
		next = next.normalized() * speed
	return Vector3(next.x, velocity.y, next.z)


func _assemble() -> void:
	if ResourceLoader.exists(MODEL_PATH):
		var model := (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
		if model != null:
			model.name = "Model"
			add_child(model)
	add_child(_column())
	add_child(_lamp())


func _column() -> CollisionShape3D:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(COLUMN_W, COLUMN_H, COLUMN_W)
	node.shape = box
	node.position.y = COLUMN_H * 0.5 + 0.2
	return node


func _lamp() -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.light_color = Palette.CYAN
	lamp.light_energy = 2.4
	lamp.omni_range = 12.0
	lamp.position = Vector3(0.0, 1.6, 0.0)
	return lamp


func _lift_ball(ball: GolfBall, delta: float) -> void:
	if ball == null or ball.is_carried() or ball.is_stowed() or ball.freeze:
		return
	if not NetSession.should_simulate(ball):
		return
	var velocity := ball.linear_velocity
	var kept := Vector3(velocity.x, 0.0, velocity.z)
	velocity.y = next_vertical(velocity.y, delta)
	velocity.x = kept.x
	velocity.z = kept.z
	ball.linear_velocity = velocity
	ball.sleeping = false


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_fan"):
		body.enter_fan()


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_fan"):
		body.exit_fan()
