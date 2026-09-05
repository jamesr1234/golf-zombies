class_name WallBreak
extends Object
## Rocket blast carves a hole through scenery. Size stays put; the chewed
## interior is rolled fresh every shot so two hits never match.

const GROUP := "wall_craters"
const REACH := 1.55
const HOLE_R := 1.2


static func fresh_seed() -> int:
	return maxi(1, randi())


static func punch(
	from: Node, at: Vector3, collider: Object = null, normal := Vector3.ZERO, p_seed := 0
) -> int:
	if from == null or not from.is_inside_tree():
		return 0
	var seed := p_seed if p_seed != 0 else fresh_seed()
	var walls: Array[StaticBody3D] = []
	var hit := _body_of(collider)
	if hit != null and _should_carve(hit, at, normal):
		walls.append(hit)
	for other in _query_walls(from, at):
		if not walls.has(other) and _should_carve(other, at, Vector3.ZERO):
			walls.append(other)
	var carved := 0
	for wall in walls:
		if _carve(wall, at, normal, seed):
			carved += 1
	if carved > 0:
		WallDebris.toss(from, at, seed)
	return carved


static func crater(at: Vector3, normal: Vector3, seed: int, thick := 0.8) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else 1
	var face := normal if normal.length_squared() > 0.01 else Vector3.FORWARD
	face = face.normalized()
	var depth := maxf(0.42, thick * 0.5)
	var centre := at - face * depth
	centre.y = maxf(centre.y, 1.15)
	var through := maxf(1.1, (thick * 0.7 + 0.25) / HOLE_R)
	var bites: Array[Dictionary] = []
	var main := Vector3(
		rng.randf_range(1.04, 1.2),
		rng.randf_range(1.34, 1.56),
		rng.randf_range(1.02, 1.18)
	)
	if absf(face.x) >= absf(face.z):
		main.x = maxf(main.x, through)
	else:
		main.z = maxf(main.z, through)
	bites.append({
		"kind": "ball",
		"at": centre,
		"radius": HOLE_R,
		"scale": main,
		"spin": _spin(rng),
		"seg": rng.randi_range(6, 9),
	})
	for _i in rng.randi_range(6, 9):
		var dir := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-0.85, 1.0),
			rng.randf_range(-1.0, 1.0)
		)
		if dir.length_squared() < 0.001:
			dir = Vector3.UP
		dir = dir.normalized()
		var along := centre - face * rng.randf_range(0.0, thick * 0.45)
		if rng.randf() < 0.4:
			bites.append({
				"kind": "chip",
				"at": along + dir * rng.randf_range(0.2, 0.62),
				"size": Vector3(
					rng.randf_range(0.22, 0.48),
					rng.randf_range(0.18, 0.42),
					rng.randf_range(0.22, 0.5)
				),
				"spin": _spin(rng),
			})
		else:
			bites.append({
				"kind": "ball",
				"at": along + dir * rng.randf_range(0.16, 0.7),
				"radius": rng.randf_range(0.22, 0.52),
				"scale": Vector3(
					rng.randf_range(0.7, 1.35),
					rng.randf_range(0.65, 1.4),
					rng.randf_range(0.7, 1.3)
				),
				"spin": _spin(rng),
				"seg": rng.randi_range(5, 8),
			})
	return bites


static func _spin(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(
		rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU)
	)


static func in_crater(point: Vector3, at: Vector3, normal: Vector3, seed: int) -> bool:
	for bite in crater(at, normal, seed, 0.6):
		var offset: Vector3 = point - bite["at"]
		if String(bite.get("kind", "ball")) == "chip":
			var size: Vector3 = bite.get("size", Vector3.ONE)
			if absf(offset.x) <= size.x * 0.5 and absf(offset.y) <= size.y * 0.5 and absf(offset.z) <= size.z * 0.5:
				return true
			continue
		var scale: Vector3 = bite.get("scale", Vector3.ONE)
		var stretched := Vector3(
			offset.x / maxf(0.08, scale.x),
			offset.y / maxf(0.08, scale.y),
			offset.z / maxf(0.08, scale.z)
		)
		if stretched.length() <= float(bite.get("radius", HOLE_R)):
			return true
	return false


static func _carve(body: StaticBody3D, at: Vector3, normal: Vector3, seed: int) -> bool:
	var crater_n := _crater_of(body)
	var applied: Array = crater_n.get_meta("seeds", [])
	if applied.has(seed):
		return false
	applied.append(seed)
	crater_n.set_meta("seeds", applied)
	if crater_n.get_child_count() == 0:
		_add_hull(crater_n, body)
		_hollow(body)
	var face := normal if normal.length_squared() > 0.01 else _face_near(body, at)
	var bounds := _world_aabb(body)
	var thick := minf(bounds.size.x, bounds.size.z)
	if thick < 0.05:
		thick = 0.8
	for bite in crater(at, face, seed, thick):
		var cut := _cut(bite)
		crater_n.add_child(cut)
		cut.global_position = bite["at"]
		cut.rotation = bite.get("spin", Vector3.ZERO)
	crater_n.use_collision = true
	crater_n.collision_layer = body.collision_layer
	crater_n.collision_mask = 0
	return true


static func _cut(bite: Dictionary) -> CSGShape3D:
	var cut: CSGShape3D
	if String(bite.get("kind", "ball")) == "chip":
		var box := CSGBox3D.new()
		box.size = bite.get("size", Vector3(0.3, 0.25, 0.3))
		cut = box
	else:
		var ball := CSGSphere3D.new()
		ball.radius = float(bite.get("radius", HOLE_R))
		ball.radial_segments = int(bite.get("seg", 6))
		ball.rings = 4
		ball.smooth_faces = false
		ball.scale = bite.get("scale", Vector3.ONE)
		cut = ball
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	return cut


static func _crater_of(body: StaticBody3D) -> CSGCombiner3D:
	var existing := body.get_node_or_null("WallCrater") as CSGCombiner3D
	if existing != null:
		return existing
	var crater_n := CSGCombiner3D.new()
	crater_n.name = "WallCrater"
	crater_n.add_to_group(GROUP)
	body.add_child(crater_n)
	return crater_n


static func _add_hull(crater_n: CSGCombiner3D, body: StaticBody3D) -> void:
	var added := 0
	for child in body.get_children():
		var node := child as CollisionShape3D
		if node == null or node.shape == null:
			continue
		var box := node.shape as BoxShape3D
		if box == null:
			continue
		var hull := CSGBox3D.new()
		hull.size = box.size
		hull.material = _hull_material(body)
		crater_n.add_child(hull)
		hull.transform = node.transform
		added += 1
	if added > 0:
		return
	var bounds := _local_aabb(body)
	if bounds.size.length() < 0.05:
		return
	var fill := CSGBox3D.new()
	fill.size = bounds.size
	fill.position = bounds.get_center()
	fill.material = _hull_material(body)
	crater_n.add_child(fill)


static func _hull_material(body: StaticBody3D) -> Material:
	var mesh_node := _owned_mesh(body)
	if mesh_node != null and mesh_node.material_override != null:
		return mesh_node.material_override
	if body is BoxProp and (body as BoxProp).kind == "rock":
		return MeshFactory.material(Palette.ROCK)
	return MeshFactory.material(Palette.WALL)


static func _hollow(body: StaticBody3D) -> void:
	for child in body.get_children():
		if child is CSGCombiner3D:
			continue
		var shape := child as CollisionShape3D
		if shape != null:
			shape.disabled = true
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.visible = false
	var mesh_node := _owned_mesh(body)
	if mesh_node == null or mesh_node.get_parent() == body:
		return
	## GLB imports parent the collider under the mesh. Hiding that mesh would
	## hide the crater too, so strip the surface and leave the node up.
	mesh_node.mesh = null
	for child in mesh_node.get_children():
		var extra := child as MeshInstance3D
		if extra != null:
			extra.visible = false


static func _owned_mesh(body: StaticBody3D) -> MeshInstance3D:
	for child in body.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null and mesh.mesh != null and not ObstacleLeds.is_led(mesh):
			return mesh
	var parent := body.get_parent()
	if parent == null or _static_count(parent) != 1:
		return null
	if parent is MeshInstance3D and (parent as MeshInstance3D).mesh != null:
		return parent as MeshInstance3D
	for child in parent.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null and mesh.mesh != null and not ObstacleLeds.is_led(mesh):
			return mesh
	return null


static func _should_carve(body: StaticBody3D, at: Vector3, normal: Vector3) -> bool:
	if not _is_punchable(body):
		return false
	if not _near_volume(body, at, REACH):
		return false
	if body is BoxProp or body is ClimbingWall or body is Culvert:
		return true
	if _obstacle_path(body).contains("/wall_"):
		return true
	if normal.length_squared() > 0.01:
		return absf(normal.y) <= 0.58
	return _side_hit(body, at)


static func _is_punchable(body: StaticBody3D) -> bool:
	if body is TreeProp or body is JumpRamp or body is FoldingSteps:
		return false
	if body is GrapplePoint or body is HexBarrierFace:
		return false
	if body.is_in_group("fairway_field"):
		return false
	if (body.collision_layer & Layers.BARRIER) != 0:
		return false
	if (body.collision_layer & (Layers.WORLD | Layers.PROP)) == 0:
		return false
	return not _has_heightmap(body)


static func _has_heightmap(body: StaticBody3D) -> bool:
	for child in body.get_children():
		var node := child as CollisionShape3D
		if node != null and node.shape is HeightMapShape3D:
			return true
	return false


static func _near_volume(body: StaticBody3D, at: Vector3, pad: float) -> bool:
	return _world_aabb(body).grow(pad).has_point(at)


static func _side_hit(body: StaticBody3D, at: Vector3) -> bool:
	var box := _world_aabb(body)
	if box.size.length() < 0.05 or not box.grow(0.45).has_point(at):
		return false
	var local := at - box.get_center()
	var half := box.size * 0.5
	var dx := half.x - absf(local.x)
	var dy := half.y - absf(local.y)
	var dz := half.z - absf(local.z)
	return dy >= dx or dy >= dz


static func _face_near(body: StaticBody3D, at: Vector3) -> Vector3:
	var box := _world_aabb(body)
	var local := at - box.get_center()
	if absf(local.x) > absf(local.z):
		return Vector3(signf(local.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(local.z) if absf(local.z) > 0.001 else 1.0)


static func _query_walls(from: Node, at: Vector3) -> Array[StaticBody3D]:
	var world := _world_3d(from)
	if world == null:
		return []
	var sphere := SphereShape3D.new()
	sphere.radius = REACH
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = Layers.WORLD | Layers.PROP
	var walls: Array[StaticBody3D] = []
	for hit in world.direct_space_state.intersect_shape(query, 16):
		var body := _body_of(hit.get("collider"))
		if body != null and not walls.has(body):
			walls.append(body)
	return walls


static func _body_of(node: Object) -> StaticBody3D:
	var step := node as Node
	while step != null:
		var body := step as StaticBody3D
		if body != null:
			return body
		step = step.get_parent()
	return null


static func _obstacle_path(node: Node) -> String:
	var step := node
	while step != null:
		var path := String(step.get("scene_file_path"))
		if path.begins_with("res://assets/obstacles/"):
			return path
		step = step.get_parent()
	return ""


static func _static_count(host: Node) -> int:
	var n := 1 if host is StaticBody3D else 0
	for child in host.get_children():
		if child is StaticBody3D:
			n += 1
	return n


static func _world_3d(from: Node) -> World3D:
	var node := from as Node3D
	if node != null:
		return node.get_world_3d()
	var tree := from.get_tree()
	if tree != null and tree.root != null:
		return tree.root.get_world_3d()
	return null


static func _world_aabb(body: StaticBody3D) -> AABB:
	return _xform_aabb(body.global_transform, _local_aabb(body))


static func _local_aabb(body: StaticBody3D) -> AABB:
	var box := AABB()
	var any := false
	for owner_id in body.get_shape_owners():
		for i in body.shape_owner_get_shape_count(owner_id):
			var local := _shape_aabb(body.shape_owner_get_shape(owner_id, i))
			var xf := body.shape_owner_get_transform(owner_id)
			var world := _xform_aabb(xf, local)
			if not any:
				box = world
				any = true
			else:
				box = box.merge(world)
	return box


static func _shape_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is ConvexPolygonShape3D:
		var pts := (shape as ConvexPolygonShape3D).points
		if pts.is_empty():
			return AABB()
		var box := AABB(pts[0], Vector3.ZERO)
		for point in pts:
			box = box.expand(point)
		return box
	var mesh := shape.get_debug_mesh()
	return mesh.get_aabb() if mesh != null else AABB()


static func _xform_aabb(xf: Transform3D, box: AABB) -> AABB:
	var out := AABB(xf * box.position, Vector3.ZERO)
	for i in 8:
		out = out.expand(xf * box.get_endpoint(i))
	return out

