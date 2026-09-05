@tool
class_name GrapplePoint
extends StaticBody3D
## Post with a neon bullseye. The claw latches here the same way it bites a cart.

const HEIGHT := 4.2
const POST_R := 0.1
const TARGET_R := 0.78
const FACE_Z := 0.18
const LAND_FORWARD := 0.95
## Same reach as the claw. Kept here so this script does not import Grappler.
const FIND := 36.0


@export var height := HEIGHT


static func create(at := Vector3.ZERO, yaw := 0.0, tall := HEIGHT) -> GrapplePoint:
	var point := GrapplePoint.new()
	point.name = "GrapplePoint"
	point.height = tall
	point.position = at
	point.rotation.y = deg_to_rad(yaw)
	point._assemble()
	return point


static func nearest(who: Node3D) -> GrapplePoint:
	if who == null or not who.is_inside_tree():
		return null
	var best: GrapplePoint
	var best_d := INF
	for node in who.get_tree().get_nodes_in_group("grapple_points"):
		var point := node as GrapplePoint
		if point == null:
			continue
		var d := who.global_position.distance_to(point.aim_at())
		if d < FIND and d < best_d:
			best = point
			best_d = d
	return best


func aim_at() -> Vector3:
	return to_global(Vector3(0.0, _face_y(), FACE_Z))


## Feet on the deck under the bullseye, in front of the post so you stand clear.
func land_at() -> Vector3:
	var pad := to_global(Vector3(0.0, 0.0, LAND_FORWARD))
	if not is_inside_tree():
		return pad
	var world := get_world_3d()
	if world == null:
		return pad
	var from := to_global(Vector3(0.0, _face_y(), LAND_FORWARD))
	var query := PhysicsRayQueryParameters3D.create(
		from, from + Vector3.DOWN * 16.0, Layers.WORLD | Layers.PROP
	)
	query.exclude = [get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return pad
	return hit["position"]


func _ready() -> void:
	add_to_group("grapple_points")
	if get_child_count() == 0:
		collision_layer = Layers.PROP
		collision_mask = 0
		_assemble()


func _assemble() -> void:
	add_to_group("grapple_points")
	collision_layer = Layers.PROP
	collision_mask = 0
	_post()
	_target()


func _face_y() -> float:
	return maxf(height - 0.7, 1.4)


func _post() -> void:
	var foot := MeshFactory.box(Vector3(0.7, 0.12, 0.7), Palette.TOWER, Palette.GLOW_FAINT)
	foot.position.y = 0.06
	add_child(foot)
	var pole := MeshFactory.cylinder(POST_R, height, Palette.TOWER, Palette.GLOW_FAINT)
	pole.position.y = height * 0.5
	add_child(pole)
	_shape_cyl(POST_R + 0.04, height, Vector3(0.0, height * 0.5, 0.0), Vector3.ZERO)
	for t in [0.28, 0.55, 0.82]:
		var band := MeshFactory.cylinder(POST_R + 0.03, 0.07, Palette.HOT_PINK, Palette.GLOW_MEDIUM)
		band.position.y = height * t
		add_child(band)
	var cap := MeshFactory.sphere(POST_R + 0.04, Palette.ICE, Palette.GLOW_SOFT)
	cap.position.y = height
	add_child(cap)


func _target() -> void:
	var face := Node3D.new()
	face.name = "Target"
	face.position = Vector3(0.0, _face_y(), FACE_Z)
	add_child(face)
	var back := MeshFactory.disk(TARGET_R + 0.06, Palette.NIGHT, 0.2)
	back.rotation.x = deg_to_rad(90.0)
	back.position.z = -0.05
	face.add_child(back)
	_ring(face, TARGET_R, Palette.HOT_PINK, Palette.GLOW_MEDIUM, 0.0)
	_ring(face, TARGET_R * 0.64, Palette.ICE, Palette.GLOW_SOFT, 0.012)
	_ring(face, TARGET_R * 0.34, Palette.MAGENTA, Palette.GLOW_STRONG, 0.024)
	var bull := MeshFactory.disk(TARGET_R * 0.12, Palette.HOT_PINK, Palette.GLOW_STRONG)
	bull.rotation.x = deg_to_rad(90.0)
	bull.position.z = 0.036
	face.add_child(bull)
	for angle in [0.0, 90.0]:
		var bar := MeshFactory.box(
			Vector3(TARGET_R * 1.7, 0.045, 0.03), Palette.ICE, Palette.GLOW_MEDIUM
		)
		bar.rotation.z = deg_to_rad(angle)
		bar.position.z = 0.04
		face.add_child(bar)
	var lamp := OmniLight3D.new()
	lamp.light_color = Palette.HOT_PINK
	lamp.light_energy = 2.8
	lamp.omni_range = 6.0
	lamp.position.z = 0.2
	face.add_child(lamp)
	_shape_cyl(
		TARGET_R, 0.22, Vector3(0.0, _face_y(), FACE_Z), Vector3(deg_to_rad(90.0), 0.0, 0.0)
	)


func _ring(face: Node3D, radius: float, color: Color, glow: float, z: float) -> void:
	var disk := MeshFactory.disk(radius, color, glow)
	disk.rotation.x = deg_to_rad(90.0)
	disk.position.z = z
	face.add_child(disk)


func _shape_cyl(radius: float, tall: float, at: Vector3, rot: Vector3) -> void:
	var node := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = tall
	node.shape = cyl
	node.position = at
	node.rotation = rot
	add_child(node)
