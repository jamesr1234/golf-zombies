extends GutTest
## A rocket punches a lumpy hole through a wall, not a cube, with flying debris.


func before_each() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)


func after_each() -> void:
	for group in [WallBreak.GROUP, WallDebris.GROUP, "rockets"]:
		for node in get_tree().get_nodes_in_group(group):
			node.queue_free()


func test_the_crater_is_lumpy_not_a_cube() -> void:
	var bites := WallBreak.crater(Vector3.ZERO, Vector3.FORWARD, 11)
	assert_gt(bites.size(), 6)
	var radii: Array[float] = []
	for bite in bites:
		if bite.get("kind", "ball") == "ball":
			radii.append(float(bite["radius"]))
	var main: Vector3 = bites[0]["scale"]
	assert_true(
		not is_equal_approx(main.x, main.y) or not is_equal_approx(main.y, main.z),
		"the opening is an ellipsoid, not a cube"
	)
	assert_false(_all_close(radii), "the rim is chewed, not a clean ring")
	assert_true(WallBreak.in_crater(Vector3(0.0, 1.15, 0.0), Vector3.ZERO, Vector3.FORWARD, 11))
	assert_false(WallBreak.in_crater(Vector3(3.4, 1.15, 0.0), Vector3.ZERO, Vector3.FORWARD, 11))


func test_two_shots_chew_the_inside_differently() -> void:
	var a := WallBreak.crater(Vector3.ZERO, Vector3.FORWARD, 11)
	var b := WallBreak.crater(Vector3.ZERO, Vector3.FORWARD, 99)
	assert_ne(_crater_key(a), _crater_key(b), "every shot has to leave a new interior")
	assert_almost_eq(float(a[0]["radius"]), WallBreak.HOLE_R, 0.001)
	assert_almost_eq(float(b[0]["radius"]), WallBreak.HOLE_R, 0.001)


func test_a_rocket_opens_a_walkable_gap() -> void:
	var wall := _wall(Vector3.ZERO)
	await wait_physics_frames(1)
	var at := Vector3(0.0, 1.2, 0.3)
	assert_false(_ray_clear(wall, Vector3(0.0, 1.2, 2.0), Vector3(0.0, 1.2, -2.0)))
	assert_eq(WallBreak.punch(wall, at, wall, Vector3.BACK, 21), 1)
	await wait_physics_frames(3)
	assert_true(
		_ray_clear(wall, Vector3(0.0, 1.2, 2.0), Vector3(0.0, 1.2, -2.0)),
		"the blast has to open the wall"
	)
	assert_false(
		_ray_clear(wall, Vector3(2.85, 1.2, 2.0), Vector3(2.85, 1.2, -2.0)),
		"the rest of the wall stays up"
	)
	assert_true(_player_fits(wall, Vector3(0.0, 0.9, 0.0)), "a standing player walks through")


func test_the_blast_throws_debris() -> void:
	var wall := _wall(Vector3.ZERO)
	WallBreak.punch(wall, Vector3(0.0, 1.2, 0.3), wall, Vector3.BACK, 4)
	assert_eq(get_tree().get_nodes_in_group(WallDebris.GROUP).size(), WallDebris.COUNT)
	var first := get_tree().get_nodes_in_group(WallDebris.GROUP)[0] as RigidBody3D
	assert_not_null(first)
	assert_eq(first.collision_layer, 0)
	assert_gt(first.linear_velocity.length(), 5.0)


func test_the_same_seed_does_not_carve_twice() -> void:
	var wall := _wall(Vector3.ZERO)
	assert_eq(WallBreak.punch(wall, Vector3(0.0, 1.2, 0.3), wall, Vector3.BACK, 9), 1)
	assert_eq(WallBreak.punch(wall, Vector3(0.0, 1.2, 0.3), wall, Vector3.BACK, 9), 0)
	assert_eq(get_tree().get_nodes_in_group(WallDebris.GROUP).size(), WallDebris.COUNT)


func test_a_visual_rocket_leaves_the_wall_up() -> void:
	var wall := _wall(Vector3.ZERO)
	var rocket := Rocket.spawn_flight(self, Vector3(0.0, 1.2, 2.0), Vector3.FORWARD, 110.0, 6.5, 90.0, true)
	rocket._explode(Vector3(0.0, 1.2, 0.3), wall, Vector3.BACK)
	assert_eq(wall.get_node_or_null("WallCrater"), null)
	assert_eq(get_tree().get_nodes_in_group(WallDebris.GROUP).size(), 0)


func test_detonate_punches_the_wall_it_hit() -> void:
	var wall := _wall(Vector3.ZERO)
	Rocket.detonate(
		get_tree(), Vector3(0.0, 1.2, 0.3), 110.0, 6.5, self, null, wall, Vector3.BACK
	)
	assert_not_null(wall.get_node_or_null("WallCrater"))


func test_an_obstacle_wall_opens_too() -> void:
	var wall: Node3D = (load("res://assets/obstacles/wall_medium.glb") as PackedScene).instantiate()
	add_child_autofree(wall)
	await wait_physics_frames(1)
	var body := _first_body(wall)
	assert_not_null(body)
	var at := Vector3(2.0, 1.3, 0.0)
	assert_eq(WallBreak.punch(wall, at, body, Vector3.BACK, 8), 1)
	await wait_physics_frames(3)
	assert_true(
		_ray_clear(wall, Vector3(2.0, 1.3, 2.0), Vector3(2.0, 1.3, -2.0)),
		"the kit wall has to blow through"
	)


func test_the_ground_does_not_open() -> void:
	var ground := _heightmap()
	add_child_autofree(ground)
	assert_eq(WallBreak.punch(ground, Vector3.ZERO, ground, Vector3.UP, 3), 0)
	assert_eq(ground.get_node_or_null("WallCrater"), null)


func _wall(at: Vector3) -> BoxProp:
	var wall := BoxProp.create({
		"kind": "wall",
		"position": at,
		"size": Vector3(6.0, 2.8, 0.6),
		"yaw": 0.0,
	})
	add_child_autofree(wall)
	return wall


func _heightmap() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var node := CollisionShape3D.new()
	var map := HeightMapShape3D.new()
	map.map_width = 3
	map.map_depth = 3
	map.map_data = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
	node.shape = map
	body.add_child(node)
	return body


func _ray_clear(from: Node3D, a: Vector3, b: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(a, b, Layers.WORLD | Layers.PROP)
	return from.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _player_fits(from: Node3D, at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = Layers.WORLD | Layers.PROP
	return from.get_world_3d().direct_space_state.intersect_shape(query, 8).is_empty()


func _first_body(node: Node) -> StaticBody3D:
	if node is StaticBody3D:
		return node as StaticBody3D
	for child in node.get_children():
		var body := _first_body(child)
		if body != null:
			return body
	return null


func _crater_key(bites: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for bite in bites:
		parts.append("%s" % bite)
	return ",".join(parts)


func _all_close(values: Array[float]) -> bool:
	if values.is_empty():
		return true
	for value in values:
		if not is_equal_approx(value, values[0]):
			return false
	return true
