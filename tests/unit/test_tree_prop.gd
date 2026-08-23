extends GutTest
## Trees should read as woods, not a row of glowing bulbs.

const _Tree := preload("res://scripts/course/tree_prop.gd")


func test_woods_are_not_one_color() -> void:
	var seen := {}
	for x in 8:
		for z in 8:
			var tint := _Tree.canopy_tint(Vector3(float(x) * 11.0, 0.0, float(z) * 13.0))
			seen[str(tint)] = true
	assert_gt(seen.size(), 3, "the canopy palette has to mix")
	assert_eq(_Tree.canopy_tint(Vector3(4.0, 0.0, 9.0)), _Tree.canopy_tint(Vector3(4.0, 0.0, 9.0)))


func test_a_tree_has_a_crown_not_a_bulb() -> void:
	var tree := _make(Vector3(3.0, 0.0, 8.0), Vector3(0.8, 8.0, 0.0))
	var canopy := tree.get_node("Canopy") as Node3D
	assert_not_null(canopy)
	assert_gt(canopy.get_child_count(), 2, "foliage is a cluster, not one sphere")
	var trunk := tree.get_node("Trunk") as MeshInstance3D
	assert_not_null(trunk)
	var mesh := trunk.mesh as CylinderMesh
	assert_not_null(mesh)
	assert_lt(mesh.top_radius, mesh.bottom_radius, "the trunk tapers like a tree")
	assert_lt(mesh.bottom_radius, 0.5, "a stem, not a lightbulb body")


func test_the_crown_tilts_in_the_wind() -> void:
	var still := _Tree.crown_tilt(0.0, 0.0)
	var later := _Tree.crown_tilt(0.4, 0.0)
	assert_gt(
		absf(later.x - still.x) + absf(later.y - still.y), 0.01,
		"the canopy has to rock over time"
	)
	var other := _Tree.crown_tilt(0.4, 2.2)
	assert_ne(later.x, other.x, "trees along the path should not sway in lockstep")


func test_foliage_uses_a_leaf_shader() -> void:
	var tree := _make(Vector3(12.0, 0.0, 5.0), Vector3(0.9, 9.0, 0.0))
	var puff := tree.get_node("Canopy").get_child(0) as MeshInstance3D
	var mat := puff.material_override as ShaderMaterial
	assert_not_null(mat)
	assert_gt(float(mat.get_shader_parameter("sway_amp")), 0.05)
	assert_gt(Palette.TREE_CANOPIES.size(), 4)


func test_a_cheap_tree_is_a_look_not_a_body() -> void:
	var tree := _Tree.create({
		"kind": "tree",
		"position": Vector3(2.0, 0.0, 4.0),
		"size": Vector3(0.8, 8.0, 0.0),
		"yaw": 10.0,
		"cheap": true,
	})
	add_child_autofree(tree)
	assert_false(tree is StaticBody3D, "the joiner does not need a collider per tree")
	assert_not_null(tree.get_node_or_null("Trunk"))
	assert_not_null(tree.get_node_or_null("Canopy"))
	assert_eq(tree.get_child_count(), 2, "one trunk and one puff, not a crown of meshes")


func _make(at: Vector3, size: Vector3) -> Node3D:
	var tree := _Tree.create({
		"kind": "tree",
		"position": at,
		"size": size,
		"yaw": 20.0,
	})
	add_child_autofree(tree)
	return tree
