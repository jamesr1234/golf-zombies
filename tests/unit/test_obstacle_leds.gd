extends GutTest
## Obstacle GLBs wear thin cyan bars on their hard edges.

const _Leds := preload("res://scripts/course/obstacle_leds.gd")


func test_a_cube_gets_twelve_led_edges() -> void:
	var node: Node3D = _spawn("res://assets/obstacles/cube_medium.glb")
	var leds := _Leds.attach(node)
	assert_not_null(leds)
	assert_eq(leds.name, "Leds")
	assert_eq(_edge_count(leds), 12)
	var mat := leds.material_override as ShaderMaterial
	assert_not_null(mat)
	assert_eq(mat.get_shader_parameter("tint"), Palette.CYAN)
	assert_gt(mat.get_shader_parameter("energy"), Palette.GLOW_MEDIUM)


## Nothing anti-aliases the world, so the shader widens a distant bar to keep it
## solid. It can only do that if every corner carries its offset from the centre.
func test_led_bars_carry_the_offset_the_shader_widens_from() -> void:
	var node: Node3D = _spawn("res://assets/obstacles/cube_medium.glb")
	var leds := _Leds.attach(node)
	var format: int = leds.mesh.surface_get_format(0)
	assert_ne(format & Mesh.ARRAY_FORMAT_CUSTOM0, 0)
	var offsets: PackedFloat32Array = leds.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	assert_gt(offsets.size(), 0)
	var longest := 0.0
	for value in offsets:
		longest = maxf(longest, absf(value))
	assert_almost_eq(longest, _Leds.THICK * 0.5, 0.0001)


func test_attach_does_not_stack_a_second_strip() -> void:
	var node: Node3D = _spawn("res://assets/obstacles/wall_small.glb")
	var first := _Leds.attach(node)
	assert_eq(_Leds.attach(node), first)
	assert_eq(_led_nodes(node), 1)


func test_attach_does_not_return_a_stripped_loose_led() -> void:
	var node: Node3D = _spawn("res://assets/obstacles/cube_medium.glb")
	var loose := MeshInstance3D.new()
	loose.name = "Leds"
	node.add_child(loose)
	var leds := _Leds.attach(node)
	assert_true(is_instance_valid(leds))
	assert_false(is_instance_valid(loose), "the host-level leftover is gone")
	assert_ne(leds, loose)
	assert_false(_Leds.is_led(leds.get_parent()))


func test_a_tunnel_outlines_each_slab() -> void:
	var node: Node3D = _spawn("res://assets/obstacles/tunnel_small.glb")
	_Leds.attach(node)
	assert_gt(_led_nodes(node), 1)
	assert_gt(_total_edges(node), 12)


func test_leds_follow_the_mesh_when_it_is_scaled() -> void:
	var node: Node3D = _spawn("res://assets/obstacles/cube_medium.glb")
	var leds := _Leds.attach(node)
	var mesh := leds.get_parent() as MeshInstance3D
	assert_not_null(mesh)
	assert_false(_Leds.is_led(mesh))
	assert_not_null(mesh.mesh)
	mesh.scale = Vector3(2.0, 0.5, 3.0)
	assert_almost_eq(leds.global_transform.basis.x.length(), mesh.global_transform.basis.x.length(), 0.01)
	assert_almost_eq(leds.global_transform.basis.y.length(), mesh.global_transform.basis.y.length(), 0.01)
	assert_almost_eq(leds.global_transform.basis.z.length(), mesh.global_transform.basis.z.length(), 0.01)


func test_every_obstacle_gets_leds() -> void:
	var checked := 0
	var dir := DirAccess.open("res://assets/obstacles")
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".glb"):
			var node: Node3D = _spawn("res://assets/obstacles/%s" % name)
			var leds := _Leds.attach(node)
			assert_not_null(leds, name)
			assert_gt(_edge_count(leds), 0, name)
			checked += 1
		name = dir.get_next()
	assert_eq(checked, 46)


func test_led_bars_sit_outside_the_mesh() -> void:
	var node: Node3D = _spawn("res://assets/obstacles/cube_medium.glb")
	var leds := _Leds.attach(node)
	var mesh := leds.get_parent() as MeshInstance3D
	var src := mesh.mesh.get_aabb()
	var outline := leds.mesh.get_aabb()
	assert_gt(outline.size.x, src.size.x)
	assert_gt(outline.size.y, src.size.y)
	assert_gt(outline.size.z, src.size.z)


func test_led_bars_do_not_count_as_collision() -> void:
	var node: Node3D = _spawn("res://assets/obstacles/cube_small.glb")
	_Leds.attach(node)
	assert_eq(node.find_children("*", "CollisionShape3D", true, false).size(), 1)


func _spawn(path: String) -> Node3D:
	var node: Node3D = (load(path) as PackedScene).instantiate()
	add_child_autofree(node)
	return node


func _led_nodes(root: Node) -> int:
	var n := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if _Leds.is_led(node):
			n += 1
	return n


func _edge_count(leds: MeshInstance3D) -> int:
	if leds == null or leds.mesh == null:
		return 0
	return leds.mesh.get_faces().size() / 36


func _total_edges(root: Node) -> int:
	var n := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if _Leds.is_led(node):
			n += _edge_count(node as MeshInstance3D)
	return n
