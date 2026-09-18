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


func test_a_downward_hole_stays_local() -> void:
	var bites := WallBreak.crater(Vector3(0.0, 4.0, 0.0), Vector3.UP, 11, 1.35)
	var main: Vector3 = bites[0]["scale"]
	assert_gte(main.y, 1.1, "the blast has to punch through the slab")
	assert_lt(main.x, 2.0, "a deck hole must not stretch across the whole pad")
	assert_lt(main.z, 2.0)


func test_a_thin_deck_blows_through() -> void:
	var deck := BoxProp.create({
		"kind": "wall",
		"position": Vector3.ZERO,
		"size": Vector3(8.0, 0.4, 8.0),
		"yaw": 0.0,
	})
	add_child_autofree(deck)
	await wait_physics_frames(1)
	var at := Vector3(0.0, 0.4, 0.0)
	assert_eq(WallBreak.punch(deck, at, deck, Vector3.UP, 21), 1)
	await wait_physics_frames(3)
	assert_true(
		_ray_clear(deck, Vector3(0.0, 2.0, 0.0), Vector3(0.0, -1.0, 0.0)),
		"a thin deck has to blow through"
	)
	assert_false(
		_ray_clear(deck, Vector3(3.2, 2.0, 0.0), Vector3(3.2, -1.0, 0.0)),
		"the rest of the deck stays up"
	)


func test_a_thick_hit_stays_a_dent() -> void:
	var bites := WallBreak.crater(Vector3(0.0, 8.0, 0.0), Vector3.UP, 11, 12.0)
	var main: Vector3 = bites[0]["scale"]
	var centre: Vector3 = bites[0]["at"]
	assert_lt(main.y, 2.0, "a dent must not become a tunnel")
	assert_gt(centre.y, 7.0, "the bite stays near the face")


func test_a_thick_block_takes_a_dent() -> void:
	var block := BoxProp.create({
		"kind": "wall",
		"position": Vector3.ZERO,
		"size": Vector3(8.0, 8.0, 8.0),
		"yaw": 0.0,
	})
	add_child_autofree(block)
	await wait_physics_frames(1)
	var at := Vector3(0.0, 8.0, 0.0)
	assert_eq(WallBreak.punch(block, at, block, Vector3.UP, 21), 1)
	await wait_physics_frames(3)
	assert_not_null(block.get_node_or_null("WallCrater"))
	assert_true(
		_ray_clear(block, at + Vector3.UP * 0.3, at + Vector3.DOWN * 0.35),
		"the face has to take a scar"
	)
	assert_false(
		_ray_clear(block, at + Vector3.UP * 0.3, at + Vector3.DOWN * 8.5),
		"too thick to blow through"
	)


func test_an_extra_large_cube_dents_but_stays_up() -> void:
	var cube: Node3D = (load("res://assets/obstacles/cube_extra_large.glb") as PackedScene).instantiate()
	add_child_autofree(cube)
	await wait_physics_frames(1)
	var body := _first_body(cube)
	assert_not_null(body)
	var box := _body_box(body)
	var at := Vector3(box.get_center().x, box.end.y, box.get_center().z)
	assert_eq(WallBreak.punch(cube, at, body, Vector3.UP, 8), 1)
	await wait_physics_frames(3)
	assert_true(
		_ray_clear(cube, at + Vector3.UP * 0.3, at + Vector3.DOWN * 0.35),
		"the extra large cube has to take a scar"
	)
	assert_false(
		_ray_clear(cube, at + Vector3.UP * 0.3, at + Vector3.DOWN * (box.size.y + 1.0)),
		"a block this thick stays solid"
	)


func test_a_kit_ramp_stays_uncut() -> void:
	var ramp: Node3D = (load("res://assets/obstacles/ramp_small.glb") as PackedScene).instantiate()
	add_child_autofree(ramp)
	await wait_physics_frames(1)
	var body := _first_body(ramp)
	assert_not_null(body)
	var box := _body_box(body)
	assert_eq(WallBreak.punch(ramp, box.get_center(), body, Vector3.UP, 8), 0)
	assert_eq(body.get_node_or_null("WallCrater"), null)


func test_a_jump_ramp_stays_uncut() -> void:
	var ramp := JumpRamp.create({
		"position": Vector3.ZERO,
		"yaw": 0.0,
		"width": JumpRamp.WIDTH,
		"length": JumpRamp.LENGTH,
		"angle_deg": JumpRamp.ANGLE_DEG,
	})
	add_child_autofree(ramp)
	await wait_physics_frames(1)
	assert_eq(WallBreak.punch(ramp, ramp.global_position + Vector3.UP, ramp, Vector3.UP, 5), 0)
	assert_eq(ramp.get_node_or_null("WallCrater"), null)


func test_a_kit_platform_keeps_its_colour() -> void:
	var deck: Node3D = (load("res://assets/obstacles/platform_medium.glb") as PackedScene).instantiate()
	add_child_autofree(deck)
	await wait_physics_frames(1)
	var body := _first_body(deck)
	assert_not_null(body)
	var box := _body_box(body)
	var at := Vector3(box.get_center().x, box.end.y, box.get_center().z)
	assert_eq(WallBreak.punch(deck, at, body, Vector3.UP, 8), 1)
	await wait_physics_frames(3)
	assert_true(
		_ray_clear(deck, at + Vector3.UP * 2.0, at + Vector3.DOWN * 2.0),
		"the kit platform has to blow through"
	)
	var aside := at + Vector3(2.8, 0.0, 0.0)
	assert_false(
		_ray_clear(deck, aside + Vector3.UP * 2.0, aside + Vector3.DOWN * 2.0),
		"the rest of the deck stays up"
	)
	var crater := body.get_node_or_null("WallCrater") as CSGCombiner3D
	assert_not_null(crater)
	var hull := crater.get_child(0) as CSGShape3D
	assert_not_null(hull)
	var mat := hull.material as StandardMaterial3D
	assert_not_null(mat)
	assert_gt(mat.albedo_color.r, 0.5, "cream, not the black wall fill")
	assert_gt(mat.albedo_color.g, 0.4)


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


func _body_box(body: StaticBody3D) -> AABB:
	var box := AABB()
	var started := false
	for owner_id in body.get_shape_owners():
		for i in body.shape_owner_get_shape_count(owner_id):
			var shape := body.shape_owner_get_shape(owner_id, i)
			var local := shape.get_debug_mesh().get_aabb() if shape != null else AABB()
			var xf := body.global_transform * body.shape_owner_get_transform(owner_id)
			var world := AABB(xf * local.position, Vector3.ZERO)
			for e in 8:
				world = world.expand(xf * local.get_endpoint(e))
			if not started:
				box = world
				started = true
			else:
				box = box.merge(world)
	return box


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
