@tool
class_name SpiralTrack
extends StaticBody3D
## Smooth Blender helix the carts climb, then a ski-jump that throws them off.
## The ribbon is a triangle mesh: Jolt's character body ignores convex hulls.

const RADIUS := 28.0
const WIDTH := 12.0
const TURNS := 9
const RISE := 10.0
const DECK := 0.85
const LIFT := 0.0
## Baked into spiral_track.glb; the mesh is dropped so the approach sits on the turf.
const _MESH_LIFT := 0.16
const APPROACH := 22.0
const LAUNCH_ARC := 24.0
const LAUNCH_DEG := 26.0
const LOOK := {
	"base": Color(0.07, 0.08, 0.1),
	"line": Color(0.42, 0.78, 0.88),
	"cell": 3.5,
	"energy": 1.05,
	"scroll": 0.0,
	"fill": 0.26,
}

const _MESH := preload("res://assets/course/spiral_track.glb")
const _SCRIPT := preload("res://scripts/course/spiral_track.gd")


static func height() -> float:
	return float(TURNS) * RISE + launch_rise()


static func grade_deg() -> float:
	return rad_to_deg(atan(RISE / (TAU * RADIUS)))


static func launch_deg() -> float:
	return LAUNCH_DEG


static func launch_rise() -> float:
	var start := deg_to_rad(grade_deg())
	var lip := deg_to_rad(LAUNCH_DEG)
	return (cos(start) - cos(lip)) / ((lip - start) / LAUNCH_ARC)


static func create(at := Vector3.ZERO, yaw := 0.0) -> StaticBody3D:
	var track = _SCRIPT.new()
	track.name = "SpiralTrack"
	track.position = at
	track.rotation.y = deg_to_rad(yaw)
	track._assemble()
	return track


func _ready() -> void:
	if get_child_count() == 0:
		_assemble()


func _assemble() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	var visual: Node3D = _MESH.instantiate()
	visual.name = "Mesh"
	visual.position.y = -_MESH_LIFT
	add_child(visual)
	_paint(visual)
	_collide(visual)


func _paint(visual: Node) -> void:
	for mesh in _meshes(visual):
		var n := String(mesh.name)
		if n.contains("Rail") or n.contains("Lip"):
			mesh.material_override = MeshFactory.material(Palette.CYAN, false, Palette.GLOW_MEDIUM)
		elif n.contains("Chevron") or n.contains("Start"):
			mesh.material_override = MeshFactory.material(Palette.AMBER, false, Palette.GLOW_STRONG)
		else:
			MeshFactory.apply_grid(mesh, LOOK)


func _collide(visual: Node3D) -> void:
	for mesh in _meshes(visual):
		var n := String(mesh.name)
		if not (n.contains("Deck") or n.contains("Lip")):
			continue
		if mesh.mesh == null:
			continue
		var shape := drive_shape(mesh.mesh)
		if shape == null:
			continue
		var node := CollisionShape3D.new()
		node.shape = shape
		node.transform = visual.transform * _relative(visual, mesh)
		add_child(node)


## Walkable faces only. Rails, pillars, and the ribbon's sides/underside read as
## walls to the cart, which then lip-steps and bleeds speed the whole climb.
static func drive_shape(mesh: Mesh) -> ConcavePolygonShape3D:
	var faces := mesh.get_faces()
	var kept := PackedVector3Array()
	var min_y := cos(deg_to_rad(GolfCart.FLOOR_MAX_DEG))
	var i := 0
	while i + 2 < faces.size():
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var normal := (b - a).cross(c - a)
		var length := normal.length()
		if length > 0.0001 and normal.y >= min_y * length:
			kept.append(a)
			kept.append(b)
			kept.append(c)
		i += 3
	if kept.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.data = kept
	return shape


static func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var step: Node = node
	while step != root and step is Node3D:
		xform = (step as Node3D).transform * xform
		step = step.get_parent()
		if step == null:
			break
	return xform


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		var mesh := current as MeshInstance3D
		if mesh != null:
			found.append(mesh)
		for child in current.get_children():
			stack.append(child)
	return found
