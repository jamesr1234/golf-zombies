class_name TreeProp
extends StaticBody3D
## Parkland tree: a tapered trunk and a lumpy crown that sways in the wind.

const _SCRIPT := preload("res://scripts/course/tree_prop.gd")
const _CANOPY_SHADER := preload("res://assets/shaders/tree_canopy.gdshader")

const SWAY_DEG := 6.5
const SWAY_SPEED := 1.15

var _canopy: Node3D
var _phase := 0.0


static func create(prop: Dictionary) -> Node3D:
	if bool(prop.get("cheap", false)):
		return _cheap(prop)
	var size: Vector3 = prop["size"]
	var at: Vector3 = prop["position"]
	var tree = _SCRIPT.new()
	tree.collision_layer = Layers.PROP
	tree.collision_mask = 0
	tree._phase = _phase_at(at)
	tree.add_child(_collider(size))
	tree.add_child(_trunk(size))
	tree._canopy = _crown(size, canopy_tint(at), tree._phase, _is_pine(at))
	tree.add_child(tree._canopy)
	tree.position = at + Vector3.UP * size.y * 0.5
	tree.rotation.y = deg_to_rad(float(prop["yaw"]))
	return tree


## Watcher look: one trunk, one puff, no collider, no per-tree sway script.
static func _cheap(prop: Dictionary) -> Node3D:
	var size: Vector3 = prop["size"]
	var at: Vector3 = prop["position"]
	var tree := Node3D.new()
	tree.position = at + Vector3.UP * size.y * 0.5
	tree.rotation.y = deg_to_rad(float(prop["yaw"]))
	tree.add_child(_trunk(size))
	var tint := canopy_tint(at)
	var phase := _phase_at(at)
	if _is_pine(at):
		var cone := MeshFactory.taper(size.y * 0.18, 0.02, size.y * 0.42, tint)
		cone.position.y = size.y * 0.04
		cone.material_override = _foliage(tint, phase)
		cone.name = "Canopy"
		tree.add_child(cone)
	else:
		var puff := MeshFactory.sphere(size.y * 0.18, tint)
		puff.position.y = size.y * 0.08
		puff.material_override = _foliage(tint, phase)
		puff.name = "Canopy"
		tree.add_child(puff)
	return tree


static func canopy_tint(at: Vector3) -> Color:
	var colors := Palette.TREE_CANOPIES
	return colors[_seed(at) % colors.size()]


static func crown_tilt(time: float, phase: float) -> Vector2:
	return Vector2(
		sin(time * SWAY_SPEED + phase) * deg_to_rad(SWAY_DEG),
		cos(time * SWAY_SPEED * 0.72 + phase * 0.8) * deg_to_rad(SWAY_DEG) * 0.45
	)


func _process(_delta: float) -> void:
	if _canopy == null:
		return
	var tilt := crown_tilt(Time.get_ticks_msec() * 0.001, _phase)
	_canopy.rotation.z = tilt.x
	_canopy.rotation.x = tilt.y


static func _collider(size: Vector3) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = size.x * 0.7
	shape.height = size.y
	node.shape = shape
	return node


static func _trunk(size: Vector3) -> MeshInstance3D:
	var height := size.y * 0.58
	var mesh := MeshFactory.taper(size.x * 0.48, size.x * 0.18, height, Palette.TREE_TRUNK)
	mesh.name = "Trunk"
	mesh.position.y = -size.y * 0.5 + height * 0.5
	return mesh


static func _crown(size: Vector3, tint: Color, phase: float, pine: bool) -> Node3D:
	var canopy := Node3D.new()
	canopy.name = "Canopy"
	canopy.position.y = size.y * 0.02
	if pine:
		_pine_crown(canopy, size.y, tint, phase)
	else:
		_round_crown(canopy, size.y, tint, phase)
	return canopy


static func _round_crown(canopy: Node3D, height: float, tint: Color, phase: float) -> void:
	var r := height * 0.16
	_blob(canopy, Vector3(0.0, r * 0.85, 0.0), r * 1.12, tint, phase)
	_blob(canopy, Vector3(r * 0.62, r * 0.55, r * 0.18), r * 0.78, tint, phase + 0.8)
	_blob(canopy, Vector3(-r * 0.55, r * 0.62, -r * 0.32), r * 0.74, tint, phase + 1.6)
	_blob(canopy, Vector3(r * 0.12, r * 1.45, -r * 0.2), r * 0.58, tint, phase + 2.3)


static func _pine_crown(canopy: Node3D, height: float, tint: Color, phase: float) -> void:
	var layer_h := height * 0.22
	for i in 3:
		var t := float(i) / 2.0
		var cone := MeshFactory.taper(
			height * lerpf(0.20, 0.07, t), 0.02, layer_h, tint
		)
		cone.position.y = -height * 0.06 + float(i) * layer_h * 0.58
		cone.material_override = _foliage(tint, phase + float(i) * 0.9)
		canopy.add_child(cone)


static func _blob(canopy: Node3D, at: Vector3, radius: float, tint: Color, phase: float) -> void:
	var puff := MeshFactory.sphere(radius, tint)
	puff.position = at
	puff.material_override = _foliage(tint, phase)
	canopy.add_child(puff)


static func _foliage(tint: Color, phase: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _CANOPY_SHADER
	mat.set_shader_parameter("albedo", tint)
	mat.set_shader_parameter("emission_energy", Palette.GLOW_FAINT)
	mat.set_shader_parameter("sway_phase", phase)
	mat.set_shader_parameter("sway_amp", 0.16)
	return mat


static func _is_pine(at: Vector3) -> bool:
	return _seed(at) % 3 == 0


static func _phase_at(at: Vector3) -> float:
	return at.x * 0.37 + at.z * 0.21


static func _seed(at: Vector3) -> int:
	return absi(hash(Vector2(snappedf(at.x, 0.5), snappedf(at.z, 0.5))))
