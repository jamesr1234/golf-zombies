extends GutTest
## Obstacle GLBs import with convex collision so a ball can bounce off them.
## Every edge is an integer multiple of the extra-small cube (1.35 m).
## Ramps are the exception: height is half a cube so the slope is a jump.

const CELL := 1.35
const _SIZES := ["extra_small", "small", "medium", "large", "extra_large"]
const _CELLS: Array[float] = [1.0, 2.0, 3.0, 5.0, 7.0]


func test_every_obstacle_glb_has_static_collision() -> void:
	var checked := 0
	for path in _glb_paths():
		var packed := load(path) as PackedScene
		assert_not_null(packed, path)
		var node: Node = packed.instantiate()
		add_child_autofree(node)
		assert_gt(_shape_count(node), 0, path)
		assert_true(_has_static_body(node), path)
		checked += 1
	assert_eq(checked, 46)


func test_a_tunnel_is_four_walls_not_a_solid_box() -> void:
	var node: Node = _spawn("res://assets/obstacles/tunnel_small.glb")
	assert_eq(_shape_count(node), 4)


func test_an_arch_is_two_posts_and_a_lintel() -> void:
	var node: Node = _spawn("res://assets/obstacles/arch_medium.glb")
	assert_eq(_shape_count(node), 3)


func test_the_extra_small_cube_is_the_grid_cell() -> void:
	var box := _mesh_aabb(_spawn("res://assets/obstacles/cube_extra_small.glb"))
	assert_almost_eq(box.size.x, CELL, 0.01)
	assert_almost_eq(box.size.y, CELL, 0.01)
	assert_almost_eq(box.size.z, CELL, 0.01)


func test_two_extra_small_cubes_meet_at_one_cell() -> void:
	var first := _mesh_aabb(_spawn("res://assets/obstacles/cube_extra_small.glb"))
	var second := _mesh_aabb(_spawn("res://assets/obstacles/cube_extra_small.glb"))
	second.position.x += CELL
	assert_almost_eq(first.end.x, second.position.x, 0.01)
	assert_almost_eq(first.size.x + second.size.x, CELL * 2.0, 0.01)


func test_every_edge_is_a_multiple_of_the_smallest_cube() -> void:
	for path in _glb_paths():
		var box := _mesh_aabb(_spawn(path))
		## Ramps drop to half height so the slope is a driveable jump.
		var step := CELL * 0.5 if path.contains("/ramp_") else CELL
		for axis in range(3):
			var size := box.size[axis]
			var steps := roundf(size / step)
			assert_almost_eq(size, steps * step, 0.02, "%s axis %s" % [path, axis])
			assert_gt(steps, 0.0, "%s axis %s" % [path, axis])


## A centered origin puts odd-cell pieces half a cell off even-cell ones, so
## every piece grows from its ground corner instead.
func test_every_origin_sits_on_a_ground_corner() -> void:
	for path in _glb_paths():
		var box := _mesh_aabb(_spawn(path))
		assert_almost_eq(box.position.x, 0.0, 0.01, "%s min x" % path)
		assert_almost_eq(box.position.y, 0.0, 0.01, "%s min y" % path)
		assert_almost_eq(box.end.z, 0.0, 0.01, "%s max z" % path)


func test_any_two_cubes_meet_flush_a_whole_number_of_cells_apart() -> void:
	var sizes := ["extra_small", "small", "medium", "large", "extra_large"]
	for first_name in sizes:
		for second_name in sizes:
			var first := _mesh_aabb(_spawn("res://assets/obstacles/cube_%s.glb" % first_name))
			var second := _mesh_aabb(_spawn("res://assets/obstacles/cube_%s.glb" % second_name))
			var steps := roundf(first.size.x / CELL)
			second.position.x += steps * CELL
			assert_almost_eq(
				first.end.x, second.position.x, 0.01, "%s then %s" % [first_name, second_name]
			)


func test_a_medium_cube_and_a_large_cube_meet_flush() -> void:
	var medium := _mesh_aabb(_spawn("res://assets/obstacles/cube_medium.glb"))
	var large := _mesh_aabb(_spawn("res://assets/obstacles/cube_large.glb"))
	large.position.x += medium.size.x
	assert_almost_eq(medium.end.x, large.position.x, 0.01)
	assert_almost_eq(medium.size.x, CELL * 3.0, 0.01)
	assert_almost_eq(large.size.x, CELL * 5.0, 0.01)


func test_every_type_uses_the_same_size_cube() -> void:
	for i in _SIZES.size():
		var size: String = _SIZES[i]
		var n := _CELLS[i] * CELL
		var cube := _mesh_aabb(_spawn("res://assets/obstacles/cube_%s.glb" % size))
		assert_almost_eq(cube.size.x, n, 0.01, "cube %s" % size)
		var wall := _mesh_aabb(_spawn("res://assets/obstacles/wall_%s.glb" % size))
		assert_almost_eq(wall.size.x, n, 0.01, "wall %s length" % size)
		assert_almost_eq(wall.size.y, n, 0.01, "wall %s height" % size)
		assert_almost_eq(wall.size.z, CELL, 0.01, "wall %s thick" % size)
		var platform := _mesh_aabb(_spawn("res://assets/obstacles/platform_%s.glb" % size))
		assert_almost_eq(platform.size.x, n, 0.01, "platform %s x" % size)
		assert_almost_eq(platform.size.z, n, 0.01, "platform %s z" % size)
		assert_almost_eq(platform.size.y, CELL, 0.01, "platform %s thick" % size)
		var pillar := _mesh_aabb(_spawn("res://assets/obstacles/pillar_%s.glb" % size))
		assert_almost_eq(pillar.size.x, CELL, 0.01, "pillar %s x" % size)
		assert_almost_eq(pillar.size.z, CELL, 0.01, "pillar %s z" % size)
		assert_almost_eq(pillar.size.y, n, 0.01, "pillar %s height" % size)
		var ramp := _mesh_aabb(_spawn("res://assets/obstacles/ramp_%s.glb" % size))
		assert_almost_eq(ramp.size.x, n, 0.01, "ramp %s x" % size)
		assert_almost_eq(ramp.size.y, n * 0.5, 0.01, "ramp %s y" % size)
		assert_almost_eq(ramp.size.z, n, 0.01, "ramp %s z" % size)
		var steps := _mesh_aabb(_spawn("res://assets/obstacles/steps_%s.glb" % size))
		assert_almost_eq(steps.size.x, n, 0.01, "steps %s x" % size)
		assert_almost_eq(steps.size.y, n, 0.01, "steps %s y" % size)
		assert_almost_eq(steps.size.z, n, 0.01, "steps %s z" % size)
		var tunnel := _mesh_aabb(_spawn("res://assets/obstacles/tunnel_%s.glb" % size))
		assert_almost_eq(tunnel.size.x, n, 0.01, "tunnel %s length" % size)
		assert_almost_eq(tunnel.size.y, n + CELL * 2.0, 0.01, "tunnel %s height" % size)
		assert_almost_eq(tunnel.size.z, n + CELL * 2.0, 0.01, "tunnel %s width" % size)
		var arch := _mesh_aabb(_spawn("res://assets/obstacles/arch_%s.glb" % size))
		assert_almost_eq(arch.size.x, n + CELL * 2.0, 0.01, "arch %s width" % size)
		assert_almost_eq(arch.size.y, n + CELL, 0.01, "arch %s height" % size)
		assert_almost_eq(arch.size.z, CELL, 0.01, "arch %s depth" % size)
		var ladder := _mesh_aabb(_spawn("res://assets/obstacles/ladder_%s.glb" % size))
		assert_almost_eq(ladder.size.x, CELL, 0.01, "ladder %s width" % size)
		assert_almost_eq(ladder.size.y, n, 0.01, "ladder %s height" % size)
		assert_almost_eq(ladder.size.z, CELL, 0.01, "ladder %s depth" % size)


func test_a_wall_meets_the_same_size_cube() -> void:
	for i in _SIZES.size():
		var size: String = _SIZES[i]
		var cube := _mesh_aabb(_spawn("res://assets/obstacles/cube_%s.glb" % size))
		var wall := _mesh_aabb(_spawn("res://assets/obstacles/wall_%s.glb" % size))
		wall.position.x += cube.size.x
		assert_almost_eq(cube.end.x, wall.position.x, 0.01, size)
		assert_almost_eq(cube.size.y, wall.size.y, 0.01, "%s height" % size)


func test_the_large_escalator_is_two_by_five_by_ten_cells() -> void:
	var box := _mesh_aabb(_spawn("res://assets/obstacles/escalator_large.glb"))
	assert_almost_eq(box.size.x, CELL * 2.0, 0.02)
	assert_almost_eq(box.size.y, CELL * 5.0, 0.02)
	assert_almost_eq(box.size.z, CELL * 10.0, 0.02)


func test_a_ladder_has_rungs_you_can_latch() -> void:
	var node: Node3D = _spawn("res://assets/obstacles/ladder_medium.glb")
	var climb := ClimbLadder.attach(node)
	assert_not_null(climb)
	assert_gte(climb.hold_locals().size(), 6)
	var dummy := Node3D.new()
	add_child_autofree(dummy)
	dummy.global_position = climb.to_global(Vector3(0.0, -climb._h * 0.35, -0.7))
	assert_true(climb.can_latch(dummy), "walk up to the rungs to start climbing")


func test_a_platform_covers_the_same_size_cube() -> void:
	for i in _SIZES.size():
		var size: String = _SIZES[i]
		var cube := _mesh_aabb(_spawn("res://assets/obstacles/cube_%s.glb" % size))
		var platform := _mesh_aabb(_spawn("res://assets/obstacles/platform_%s.glb" % size))
		platform.position.y += cube.size.y
		assert_almost_eq(cube.end.y, platform.position.y, 0.01, size)
		assert_almost_eq(cube.size.x, platform.size.x, 0.01, "%s x" % size)
		assert_almost_eq(cube.size.z, platform.size.z, 0.01, "%s z" % size)


func _spawn(path: String) -> Node:
	var node: Node = (load(path) as PackedScene).instantiate()
	add_child_autofree(node)
	return node


func _glb_paths() -> PackedStringArray:
	var paths: PackedStringArray = []
	var dir := DirAccess.open("res://assets/obstacles")
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".glb"):
			paths.append("res://assets/obstacles/%s" % name)
		name = dir.get_next()
	paths.sort()
	return paths


func _shape_count(node: Node) -> int:
	var n := 0
	var shape := node as CollisionShape3D
	if shape != null and shape.shape != null:
		n += 1
	for child in node.get_children():
		n += _shape_count(child)
	return n


func _has_static_body(node: Node) -> bool:
	if node is StaticBody3D:
		return true
	for child in node.get_children():
		if _has_static_body(child):
			return true
	return false


func _mesh_aabb(node: Node) -> AABB:
	var box := AABB()
	var started := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if ObstacleLeds.is_led(current):
			continue
		var mesh_node := current as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			var local := mesh_node.mesh.get_aabb()
			for i in 8:
				var point: Vector3 = mesh_node.global_transform * local.get_endpoint(i)
				if not started:
					box = AABB(point, Vector3.ZERO)
					started = true
				else:
					box = box.expand(point)
		for child in current.get_children():
			stack.append(child)
	return box
