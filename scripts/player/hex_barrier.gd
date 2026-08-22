class_name HexBarrier
extends Node3D
## Six neon frames around a footprint. Zombies bash one face at a time; a hit
## lights that pane's grid so the partner can see which side to shoot.

const _Face := preload("res://scripts/player/hex_barrier_face.gd")
const _SCRIPT := preload("res://scripts/player/hex_barrier.gd")

const SIDE_COUNT := 6
const HITS_TO_BREAK := 3
## Centre to inner face. Two standing players fit with a little room to aim.
const INRADIUS := 2.5
const HEIGHT := 2.0
const THICKNESS := 0.18
const BLAST_RADIUS := 1.0
const PLACE_RANGE := 18.0
const MIN_FLOOR := 0.7
const CAM_DISTANCE := 14.0
const CAM_HEIGHT := 9.0
const CAM_FOV := 70.0
const CAM_LOOK_HEIGHT := 0.8


static func spawn(parent: Node, at: Vector3, yaw_deg: float):
	if parent == null:
		return null
	var hex = _SCRIPT.new()
	parent.add_child(hex)
	hex.global_position = at
	hex.rotation.y = deg_to_rad(yaw_deg)
	hex._build(false)
	Sfx.play("place_barrier", hex)
	return hex


static func preview():
	var hex = _SCRIPT.new()
	hex._build(true)
	hex.top_level = true
	return hex


static func side_length() -> float:
	return INRADIUS * 2.0 / sqrt(3.0)


## Outward normal of face `index` in the barrier's local XZ, yaw 0 facing -Z.
static func face_outward(index: int) -> Vector3:
	var angle := float(posmod(index, SIDE_COUNT)) * TAU / float(SIDE_COUNT)
	return Vector3(sin(angle), 0.0, cos(angle))


static func face_index_from_direction(direction: Vector3) -> int:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return 0
	flat = flat.normalized()
	var best := 0
	var best_dot := -INF
	for i in SIDE_COUNT:
		var toward := face_outward(i).dot(flat)
		if toward > best_dot:
			best_dot = toward
			best = i
	return best


static func aim_point(world: World3D, from: Vector3, direction: Vector3) -> Dictionary:
	if world == null or direction.length_squared() < 0.0001:
		return {"ok": false, "point": from}
	var dir := direction.normalized()
	var query := PhysicsRayQueryParameters3D.create(
		from, from + dir * PLACE_RANGE, Layers.WORLD
	)
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"ok": false, "point": from + dir * 8.0}
	var normal: Vector3 = hit["normal"]
	var at: Vector3 = hit["position"]
	if normal.y < MIN_FLOOR:
		return {"ok": false, "point": at}
	return {"ok": true, "point": at}


static func view_transform(origin: Vector3, yaw_deg: float, target: Vector3) -> Transform3D:
	var facing := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(yaw_deg))
	var eye := origin - facing * CAM_DISTANCE + Vector3.UP * CAM_HEIGHT
	eye.y = maxf(eye.y, origin.y + 2.0)
	var look := target + Vector3.UP * CAM_LOOK_HEIGHT
	if origin.distance_to(look) < 0.2:
		look = origin + facing * 4.0 + Vector3.UP * CAM_LOOK_HEIGHT
	var xform := Transform3D(Basis(), eye)
	return xform.looking_at(look, Vector3.UP)


func face_count() -> int:
	return get_child_count()


func face_at(index: int) -> _Face:
	return get_child(posmod(index, SIDE_COUNT)) as _Face


func hits_left(index: int) -> int:
	var face := face_at(index)
	return 0 if face == null else face.hits_left


func is_face_open(index: int) -> bool:
	var face := face_at(index)
	return face != null and face.is_open()


func set_ghost_visible(on: bool) -> void:
	visible = on


func _build(ghost: bool) -> void:
	name = "HexBarrier"
	for i in SIDE_COUNT:
		add_child(_make_face(i, ghost))


func _make_face(index: int, ghost: bool) -> _Face:
	var face := _Face.new()
	face.name = "Face%d" % index
	face.collision_layer = 0 if ghost else Layers.FORT
	face.collision_mask = 0
	var width := side_length()
	face.build(width, HEIGHT, THICKNESS, ghost)
	for child in face.get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			shape.disabled = ghost
	var outward := face_outward(index)
	face.position = outward * INRADIUS + Vector3.UP * HEIGHT * 0.5
	face.rotation.y = atan2(outward.x, outward.z)
	return face


func _burst(at: Vector3) -> void:
	HitFx.blast(_fx_root(), at, BLAST_RADIUS, Palette.CYAN)


func _fx_root() -> Node:
	if not is_inside_tree():
		return null
	var root := get_tree().get_first_node_in_group("fx_root")
	if root != null:
		return root
	return get_parent()
