extends GutTest
## Overlay scenes hold ramps, rocks, walls, towers. Trees stay generated.

const _Overlay := preload("res://scripts/course/hole_overlay.gd")
const _Box := preload("res://scripts/course/box_prop.gd")
const _Tree := preload("res://scripts/course/tree_prop.gd")


func test_there_is_no_tree_scene() -> void:
	assert_false(
		ResourceLoader.exists("res://scenes/course/props/tree.tscn"),
		"woods stay in CourseTrees, not as placeable nodes"
	)


func test_prop_scenes_exist_for_the_sparse_setpieces() -> void:
	for path in [
		"res://scenes/course/props/rock.tscn",
		"res://scenes/course/props/wall.tscn",
		"res://scenes/course/props/jump_ramp.tscn",
		"res://scenes/course/props/sniper_tower.tscn",
		"res://scenes/course/props/climbing_wall.tscn",
		"res://scenes/course/props/culvert.tscn",
		"res://scenes/course/props/windmill.tscn",
		"res://scenes/course/props/windmill_control.tscn",
	]:
		assert_true(ResourceLoader.exists(path), path)


func test_collect_reads_a_ramp_and_a_rock_and_skips_trees() -> void:
	var overlay := Node3D.new()
	add_child_autofree(overlay)
	var ramp := JumpRamp.create({
		"position": Vector3(12.0, 0.0, 40.0),
		"yaw": 25.0,
		"width": JumpRamp.WIDTH,
		"length": JumpRamp.LENGTH,
		"angle_deg": JumpRamp.ANGLE_DEG,
		"role": "takeoff",
	})
	ramp.name = "JumpRamp"
	overlay.add_child(ramp)
	var rock := _Box.create({
		"kind": "rock",
		"position": Vector3(-8.0, 0.0, 22.0),
		"size": Vector3(2.0, 1.2, 2.0),
		"yaw": 40.0,
	})
	rock.name = "Rock"
	overlay.add_child(rock)
	var tree := _Tree.create({
		"kind": "tree",
		"position": Vector3(6.0, 0.0, 18.0),
		"size": Vector3(0.8, 8.0, 0.0),
		"yaw": 10.0,
	})
	tree.name = "Tree"
	overlay.add_child(tree)
	var data := HoleData.new()
	_Overlay.collect_into(data, overlay)
	assert_eq(data.jumps.size(), 1)
	assert_true(data.jumps[0]["authored"])
	assert_almost_eq(data.jumps[0]["position"].x, 12.0, 0.001)
	assert_eq(data.props.size(), 1)
	assert_eq(String(data.props[0]["kind"]), "rock")
	assert_true(data.props[0]["authored"])


func test_lifted_positions_move_the_overlay_nodes() -> void:
	var overlay := Node3D.new()
	add_child_autofree(overlay)
	var rock := _Box.create({
		"kind": "rock",
		"position": Vector3(4.0, 0.0, 9.0),
		"size": Vector3(2.0, 1.0, 2.0),
		"yaw": 0.0,
	})
	rock.name = "Rock"
	overlay.add_child(rock)
	var data := HoleData.new()
	_Overlay.collect_into(data, overlay)
	data.props[0]["position"] = Vector3(4.0, 3.5, 9.0)
	_Overlay.apply_lifted(overlay, data)
	assert_almost_eq(rock.position.y, 3.5, 0.001)


func test_the_builder_does_not_duplicate_authored_props() -> void:
	var data := HoleGenerator.generate(0, 20260816)
	data.props.append({
		"kind": "rock",
		"position": data.tee + Vector3(2.0, 0.0, 2.0),
		"size": Vector3(2.0, 1.0, 2.0),
		"yaw": 0.0,
		"authored": true,
		"overlay_path": "Missing",
	})
	var before := 0
	for prop in data.props:
		if String(prop["kind"]) == "rock" and not bool(prop.get("authored", false)):
			before += 1
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	var rocks := 0
	for node in root.find_children("*", "", true, false):
		if node.get_script() == _Box and String(node.get("kind")) == "rock":
			rocks += 1
	assert_eq(rocks, before, "authored rocks come from the overlay scene, not create_prop")


func test_generated_holes_still_plant_trees_in_code() -> void:
	var data := HoleGenerator.generate(0, 20260816)
	var trees := 0
	for prop in data.props:
		if String(prop["kind"]) == "tree":
			trees += 1
			assert_false(bool(prop.get("authored", false)))
	assert_gt(trees, 8)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	assert_gt(root.find_children("*", "TreeProp", true, false).size(), 8)
	assert_not_null(root.find_child("Windmill", true, false), "hole one authors the mill")
	var empty := HoleGenerator.generate(1, 20260816)
	var empty_root := HoleBuilder.build(empty)
	add_child_autofree(empty_root)
	assert_null(empty_root.find_child("Overlay", true, false), "empty hole scenes stay out of the tree")


func test_collect_skips_the_editor_preview() -> void:
	var overlay := Node3D.new()
	add_child_autofree(overlay)
	var preview := Node3D.new()
	preview.name = "Preview"
	preview.set_meta("overlay_preview", true)
	overlay.add_child(preview)
	var buried := JumpRamp.create({
		"position": Vector3(99.0, 0.0, 99.0),
		"yaw": 0.0,
		"width": JumpRamp.WIDTH,
		"length": JumpRamp.LENGTH,
		"angle_deg": JumpRamp.ANGLE_DEG,
		"role": "takeoff",
	})
	buried.name = "BuriedRamp"
	preview.add_child(buried)
	var ramp := JumpRamp.create({
		"position": Vector3(12.0, 0.0, 40.0),
		"yaw": 25.0,
		"width": JumpRamp.WIDTH,
		"length": JumpRamp.LENGTH,
		"angle_deg": JumpRamp.ANGLE_DEG,
		"role": "takeoff",
	})
	ramp.name = "JumpRamp"
	overlay.add_child(ramp)
	var data := HoleData.new()
	_Overlay.collect_into(data, overlay)
	assert_eq(data.jumps.size(), 1)
	assert_almost_eq(data.jumps[0]["position"].x, 12.0, 0.001)


func test_hole_one_wires_the_desk_to_the_mill() -> void:
	var packed := load("res://scenes/course/holes/hole_1.tscn") as PackedScene
	var root: Node = packed.instantiate()
	add_child_autofree(root)
	var desk := root.get_node_or_null("WindmillControl") as WindmillControl
	var mill := root.get_node_or_null("Windmill") as CartPathWindmill
	assert_not_null(desk)
	assert_not_null(mill)
	assert_eq(desk.mill(), mill, "Computer 2 has to turn the same mill the host is steering")


func test_hole_one_does_not_embed_a_mech() -> void:
	var packed := load("res://scenes/course/holes/hole_1.tscn") as PackedScene
	var root: Node = packed.instantiate()
	add_child_autofree(root)
	assert_eq(
		root.find_children("*", "MechSuit", true, false).size(),
		0,
		"the overlay must not spawn a local unsynced suit"
	)
	assert_not_null(root.get_node_or_null("MechPad"), "hole 1 marks where the host plants the suit")


func test_hole_one_harvests_a_mech_pad() -> void:
	var hole := HoleGenerator.generate(0, 20260816)
	assert_true(hole.has_mech_pad(), "Computer 2 has to receive a host-spawned suit on hole 1")
	assert_lt(hole.mech_pad.x, -8.0, "the pad sits beside the mill desk, not on the tee")


func test_a_baked_suit_is_stripped_before_the_hole_goes_live() -> void:
	var overlay := Node3D.new()
	add_child_autofree(overlay)
	var suit: MechSuit = preload("res://scenes/course/items/mech_suit.tscn").instantiate()
	overlay.add_child(suit)
	assert_eq(_Overlay.strip_suits(overlay), 1)
	assert_eq(overlay.find_children("*", "MechSuit", true, false).size(), 0)
	assert_false(is_instance_valid(suit))


func test_the_nav_region_has_a_stable_name() -> void:
	var data := HoleGenerator.generate(0, 20260816)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	var nav := root.get_node_or_null(HoleBuilder.NAV_NAME) as NavigationRegion3D
	assert_not_null(nav, "Computer 2 looks up Overlay RPCs by path")
	assert_false(String(nav.name).begins_with("@"), "generated @ names differ on each machine")
	assert_not_null(nav.get_node_or_null("Overlay/WindmillControl"))


func test_an_editor_preview_is_the_generated_hole() -> void:
	var preview := _Overlay.preview(0, 20260816)
	add_child_autofree(preview)
	assert_eq(preview.name, "Preview")
	assert_true(bool(preview.get_meta("overlay_preview")))
	assert_gt(preview.find_children("*", "TreeProp", true, false).size(), 8)
	assert_eq(preview.find_children("*", "JumpRamp", true, false).size(), 0)
	assert_null(preview.find_child("Overlay", true, false), "preview must not nest the overlay scene")
