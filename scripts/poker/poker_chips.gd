class_name PokerChips
extends Node3D
## $10 discs. Each put tosses that many rigid chips onto the felt.

const RADIUS := 0.048
const THICK := 0.012
const MAX_TOSS := 40
const COLORS: Array[Color] = [
	Palette.AMBER, Palette.MAGENTA, Palette.CYAN, Palette.LIME, Palette.HOT_PINK,
]

var _rng := RandomNumberGenerator.new()
var _mat: PhysicsMaterial


func _ready() -> void:
	_ensure()


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()


func throw_seat(table: PokerTable, seat: int, amount: int) -> int:
	return throw_from(_origin(table, seat), amount, seat)


func throw_from(from: Vector3, amount: int, seat := -1) -> int:
	_ensure()
	var n := mini(PokerHand.chip_count(amount), MAX_TOSS)
	if n <= 0:
		return 0
	var well := _well()
	for i in n:
		var chip := _chip(from, i)
		add_child(chip)
		_kick(chip, from, well)
	return n


func _origin(table: PokerTable, seat: int) -> Vector3:
	if table == null or seat < 0 or seat >= table.chairs.size():
		return global_position + Vector3(0.0, 1.15, 0.0)
	var chair := table.chairs[seat]
	var inward := table.global_position - chair.global_position
	inward.y = 0.0
	if inward.length() < 0.05:
		inward = Vector3(0.0, 0.0, -1.0)
	return chair.global_position + inward.normalized() * 0.72 + Vector3(0.0, 0.72, 0.0)


func _well() -> Vector3:
	return global_position + Vector3(0.0, 0.92, 0.0)


func _chip(from: Vector3, idx: int) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = 0.018
	body.physics_material_override = _mat
	body.continuous_cd = true
	body.collision_layer = Layers.PROP
	body.collision_mask = Layers.WORLD | Layers.PROP
	body.position = to_local(from) + Vector3(
		_rng.randf_range(-0.1, 0.1), _rng.randf_range(0.0, 0.1), _rng.randf_range(-0.1, 0.1)
	)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = THICK
	shape.shape = cyl
	body.add_child(shape)
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS
	mesh.bottom_radius = RADIUS
	mesh.height = THICK
	mesh.radial_segments = 16
	var vis := MeshInstance3D.new()
	vis.mesh = mesh
	vis.material_override = MeshFactory.material(COLORS[idx % COLORS.size()], false, Palette.GLOW_SOFT)
	body.add_child(vis)
	return body


func _kick(body: RigidBody3D, from: Vector3, well: Vector3) -> void:
	var aim := well - from
	aim.y = 0.0
	if aim.length() < 0.08:
		aim = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
	aim = aim.normalized()
	body.linear_velocity = aim * _rng.randf_range(1.5, 2.9) + Vector3(
		_rng.randf_range(-0.5, 0.5), _rng.randf_range(1.5, 2.7), _rng.randf_range(-0.5, 0.5)
	)
	body.angular_velocity = Vector3(
		_rng.randf_range(-14.0, 14.0), _rng.randf_range(-20.0, 20.0), _rng.randf_range(-14.0, 14.0)
	)


func _ensure() -> void:
	if _mat != null:
		return
	_rng.randomize()
	_mat = PhysicsMaterial.new()
	_mat.friction = 0.88
	_mat.bounce = 0.2
