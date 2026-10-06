extends GutTest
## Custom sandtraps are a free circle, then a depth. Play paints bunker sand
## and bowls the heightmap; the overlay never instances a prop.


func before_each() -> void:
	HoleStore.clear_sandbox()


func test_radius_and_depth_stay_in_range() -> void:
	assert_almost_eq(SandTrap.clamp_radius(0.2), SandTrap.RADIUS_MIN, 0.001)
	assert_almost_eq(SandTrap.clamp_radius(80.0), SandTrap.RADIUS_MAX, 0.001)
	assert_almost_eq(SandTrap.clamp_depth(0.01), SandTrap.DEPTH_MIN, 0.001)
	assert_almost_eq(SandTrap.clamp_depth(12.0), SandTrap.DEPTH_MAX, 0.001)
	assert_gt(SandTrap.DEFAULT_RADIUS, SandTrap.RADIUS_MIN)
	assert_lt(SandTrap.DEFAULT_RADIUS, SandTrap.RADIUS_MAX)
	assert_gt(SandTrap.DEFAULT_DEPTH, SandTrap.DEPTH_MIN)
	assert_lt(SandTrap.DEFAULT_DEPTH, SandTrap.DEPTH_MAX)


func test_a_circle_covers_its_inside_and_nothing_outside() -> void:
	var entry := CustomHole.placement(CustomHole.SANDTRAP, Vector3(0.0, 0.0, -20.0))
	entry[CustomHole.RADIUS] = 6.0
	assert_true(SandTrap.covers(entry, Vector3(0.0, 2.0, -20.0)))
	assert_true(SandTrap.covers(entry, Vector3(5.5, 0.0, -20.0)))
	assert_false(SandTrap.covers(entry, Vector3(7.0, 0.0, -20.0)))
	assert_false(SandTrap.covers(CustomHole.placement(CustomHole.SPAWN, Vector3.ZERO), Vector3.ZERO))


func test_the_layout_paints_a_round_bunker() -> void:
	var hole := CustomHole.create("Painted Sand")
	hole.add_placement(CustomHole.SANDTRAP, Vector3(0.0, 0.0, -24.0))
	hole.placements[0][CustomHole.RADIUS] = 8.0
	hole.placements[0][CustomHole.DEPTH] = 1.6
	var data := CustomLayout.build(hole)
	var bunker := {}
	for patch in data.patches:
		if patch["type"] == Surface.Type.BUNKER:
			bunker = patch
			break
	assert_false(bunker.is_empty())
	assert_true(bool(bunker["round"]))
	assert_almost_eq(float(bunker["size"].x), 16.0, 0.01)
	assert_almost_eq(float(bunker.get(SandTrap.DEPTH, 0.0)), 1.6, 0.001)
	assert_true(HoleGenerator.patch_covers(bunker, Vector3(0.0, 0.0, -24.0)))
	assert_false(HoleGenerator.patch_covers(bunker, Vector3(10.0, 0.0, -24.0)))


func test_the_bowl_sits_below_the_rim() -> void:
	var hole := CustomHole.create("Bowl")
	var at := Vector3(0.0, 0.0, -24.0)
	hole.add_placement(CustomHole.SANDTRAP, at)
	hole.placements[0][CustomHole.RADIUS] = 8.0
	hole.placements[0][CustomHole.DEPTH] = 1.8
	var data := CustomLayout.build(hole)
	var floor := data.height.height_at(at.x, at.z)
	var rim := data.height.height_at(at.x + 8.0, at.z)
	var outside := data.height.height_at(at.x + 12.0, at.z)
	assert_lt(floor, rim - 0.6, "the middle has to be a hollow")
	assert_almost_eq(rim, HeightField.DECK, 0.35)
	assert_almost_eq(outside, HeightField.DECK, 0.2)


func test_a_painted_bunker_without_depth_does_not_sink() -> void:
	var hole := CustomHole.create("Flat Sand")
	var data := CustomLayout.build(hole)
	var mid: Vector3 = data.centerline[0].lerp(data.centerline[1], 0.5)
	data.patches.append(HoleGenerator.surface_patch(
		Surface.Type.BUNKER, mid, Vector2(10.0, 10.0), 0.0, true
	))
	SandTrap.sink(data.height, data)
	assert_almost_eq(data.height.height_at(mid.x, mid.z), HeightField.DECK, 0.05)


func test_the_fairway_opens_over_the_bowl() -> void:
	var hole := CustomHole.create("Cut")
	var at := Vector3(0.0, 0.0, -24.0)
	hole.add_placement(CustomHole.SANDTRAP, at)
	hole.placements[0][CustomHole.RADIUS] = 6.0
	hole.placements[0][CustomHole.DEPTH] = 1.2
	var data := CustomLayout.build(hole)
	var patch := {}
	for row in data.patches:
		if row["type"] == Surface.Type.FAIRWAY and HoleGenerator.patch_covers(row, at):
			patch = row
			break
	assert_false(patch.is_empty())
	var cuts := SandTrap.cuts_from(data)
	assert_false(cuts.is_empty())
	assert_true(SurfacePatch.cut_covers(at, cuts))
	assert_false(SurfacePatch.cut_covers(at + Vector3(20.0, 0.0, 0.0), cuts))
	var fine := SurfacePatch.create(patch, data.height, [Vector3(9999.0, 0.0, 9999.0)])
	var opened := SurfacePatch.create(patch, data.height, cuts)
	add_child_autofree(fine)
	add_child_autofree(opened)
	assert_gt(
		_face_count(fine), _face_count(opened),
		"the painted lie leaves a hole so the sand shows"
	)


func test_a_group_refuses_a_sandtrap() -> void:
	var hole := CustomHole.create("No Merge")
	hole.add_placement(CustomHole.SANDTRAP, Vector3(0.0, 0.0, -20.0))
	hole.add_placement("res://assets/obstacles/cube_large.glb", Vector3(1.35, 0.0, -20.0))
	var tool := GroupTool.new(hole)
	tool.selected.clear()
	tool.selected.append(0)
	tool.selected.append(1)
	var reasons: Array[String] = []
	tool.refused.connect(func(reason: String) -> void: reasons.append(reason))
	assert_false(tool.save("Sand Pair"))
	assert_eq(reasons.size(), 1)
	assert_true(reasons[0].contains("SANDTRAP"))


func test_the_marks_draw_a_circle() -> void:
	var marks := CreatorMarks.create()
	add_child_autofree(marks)
	marks.begin()
	marks.disk(Vector3.ZERO, 6.0, Palette.AMBER)
	marks.finish()
	assert_gt(marks.get_aabb().size.length(), 6.0)


func _face_count(node: SurfacePatch) -> int:
	for child in node.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			return mesh_node.mesh.get_faces().size()
	return 0
