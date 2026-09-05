class_name SoccerGoal
extends Area3D
## Neon goal mouth. A ball that enters the net scores even at full speed.

const WIDTH := 18.0
const HEIGHT := 6.0
const DEPTH := 3.4
const POST := 0.22
const NET_GAP := 0.85


static func create(data: HoleData) -> SoccerGoal:
	var face := data.tee - data.cup
	face.y = 0.0
	return place(data.cup, face)


static func place(at: Vector3, face: Vector3) -> SoccerGoal:
	var node := SoccerGoal.new()
	node.name = "SoccerGoal"
	node.position = at
	if face.length_squared() > 0.0001:
		var toward := face.normalized()
		node.rotation.y = atan2(-toward.x, -toward.z)
	node._assemble()
	return node


func _ready() -> void:
	collision_layer = Layers.SURFACE
	collision_mask = Layers.BALL
	monitoring = true
	if get_child_count() == 0:
		_assemble()


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		var ball := body as GolfBall
		if ball != null:
			ball.try_score_goal()


func _assemble() -> void:
	collision_layer = Layers.SURFACE
	collision_mask = Layers.BALL
	monitoring = true
	var mouth := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH - POST * 2.0, HEIGHT - POST, DEPTH * 0.72)
	mouth.shape = box
	mouth.position = Vector3(0.0, HEIGHT * 0.5, DEPTH * 0.38)
	add_child(mouth)
	_frame()
	_net()
	add_child(HoleBuilder.pin_beam())


func _frame() -> void:
	var half := WIDTH * 0.5
	for side in [-1.0, 1.0]:
		_post(Vector3(side * half, HEIGHT * 0.5, 0.0), Vector3(POST, HEIGHT, POST))
		_post(
			Vector3(side * half, HEIGHT * 0.5, DEPTH),
			Vector3(POST, HEIGHT, POST)
		)
		_post(
			Vector3(side * half, HEIGHT - POST * 0.5, DEPTH * 0.5),
			Vector3(POST, POST, DEPTH)
		)
	_post(Vector3(0.0, HEIGHT, 0.0), Vector3(WIDTH + POST, POST, POST))
	_post(Vector3(0.0, HEIGHT, DEPTH), Vector3(WIDTH + POST, POST, POST))
	_post(Vector3(0.0, POST * 0.5, DEPTH), Vector3(WIDTH + POST, POST, POST))


func _post(at: Vector3, size: Vector3) -> void:
	var body := MeshFactory.box_body(size, Palette.ICE, Layers.PROP, true, Palette.GLOW_MEDIUM)
	body.position = at
	add_child(body)


func _net() -> void:
	var half := WIDTH * 0.5
	var x := -half
	while x <= half + 0.01:
		_cord(Vector3(x, HEIGHT * 0.5, DEPTH * 0.5), Vector3(0.04, HEIGHT, DEPTH))
		x += NET_GAP
	var y := NET_GAP
	while y < HEIGHT - 0.1:
		_cord(Vector3(0.0, y, DEPTH * 0.5), Vector3(WIDTH, 0.04, DEPTH))
		y += NET_GAP
	for side in [-1.0, 1.0]:
		_cord(Vector3(side * half, HEIGHT * 0.5, DEPTH * 0.5), Vector3(0.04, HEIGHT, DEPTH))
	_cord(Vector3(0.0, HEIGHT * 0.5, DEPTH), Vector3(WIDTH, HEIGHT, 0.04))
	var back := MeshFactory.box_body(
		Vector3(WIDTH - POST, HEIGHT - POST, 0.12), Palette.NET, Layers.PROP, false
	)
	back.position = Vector3(0.0, HEIGHT * 0.5, DEPTH - 0.08)
	add_child(back)


func _cord(at: Vector3, size: Vector3) -> void:
	var line := MeshFactory.box(size, Palette.NET, Palette.GLOW_SOFT)
	line.position = at
	add_child(line)
