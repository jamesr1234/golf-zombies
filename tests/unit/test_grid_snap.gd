extends GutTest
## Shared placement math. The hole creator and the fs_pin editor plugin both
## come through here, so a piece lands in the same cell either way.

const _Snap := preload("res://addons/fs_pin/fs_snap.gd")


func test_the_cell_is_the_extra_small_cube() -> void:
	assert_almost_eq(GridSnap.CELL, 1.35, 0.001)


func test_a_position_rounds_onto_the_cell_grid() -> void:
	assert_eq(GridSnap.to_grid(Vector3(-10.0, 0.2, -7.0)), Vector3(-9.45, 0.0, -6.75))
	for axis in GridSnap.to_grid(Vector3(-2.0, 8.0, 3.3)):
		assert_almost_eq(fmod(absf(axis), GridSnap.CELL), 0.0, 0.001)


func test_only_obstacle_instances_snap() -> void:
	var block := Node3D.new()
	add_child_autofree(block)
	block.scene_file_path = "res://assets/obstacles/cube_small.glb"
	assert_true(GridSnap.is_obstacle(block))
	var prop := Node3D.new()
	add_child_autofree(prop)
	prop.scene_file_path = "res://scenes/course/props/rock.tscn"
	assert_false(GridSnap.is_obstacle(prop))


## A ghost is measured before it is ever shown, so the size has to be readable
## without a world pose.
func test_a_piece_is_anchored_on_its_footprint_middle() -> void:
	var cube: Node3D = _cube("medium")
	autofree(cube)
	var box := GridSnap.local_aabb(cube)
	var pivot := GridSnap.pivot_xz(box)
	assert_gt(pivot.length(), 0.1, "obstacle meshes sit on a ground corner")
	var centered := GridSnap.footprint_centered(box)
	assert_almost_eq(centered.get_center().x, 0.0, 0.01)
	assert_almost_eq(centered.get_center().z, 0.0, 0.01)
	var at := Vector3(0.0, 0.0, -20.0)
	for yaw in [0.0, 45.0, 90.0]:
		var pos := GridSnap.anchored_at(cube, at, yaw)
		var mid := pos + Basis(Vector3.UP, deg_to_rad(yaw)) * pivot
		assert_almost_eq(mid.x, at.x, 0.01)
		assert_almost_eq(mid.z, at.z, 0.01)


func test_a_piece_can_be_measured_before_it_joins_the_tree() -> void:
	var cube: Node3D = _cube("extra_small")
	autofree(cube)
	var box := GridSnap.local_aabb(cube)
	assert_gt(box.size.x, 0.0)
	assert_gt(box.size.y, 0.0)
	assert_gt(box.size.z, 0.0)
	assert_eq(GridSnap.world_aabb(cube).size, Vector3.ZERO)


func test_a_measured_ghost_matches_the_same_piece_in_the_world() -> void:
	var loose: Node3D = _cube("medium")
	autofree(loose)
	var placed: Node3D = _cube("medium")
	add_child_autofree(placed)
	assert_almost_eq(GridSnap.local_aabb(loose).size.x, GridSnap.world_aabb(placed).size.x, 0.01)


func test_a_drop_toward_a_side_sits_flush_instead_of_overlapping() -> void:
	var other := _cell(Vector3.ZERO)
	var from := Vector3(0.4, 0.0, 0.0)
	var at := GridSnap.place(from, _cell(from), [other])
	assert_eq(at, Vector3(GridSnap.CELL, 0.0, 0.0))
	assert_false(_cell(at).grow(-0.01).intersects(other))


func test_a_real_cube_dropped_on_another_cannot_stay_inside() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var first: Node3D = _cube("medium")
	host.add_child(first)
	var second: Node3D = _cube("extra_small")
	host.add_child(second)
	second.position = Vector3(0.3, 0.2, -0.1)
	second.global_position = GridSnap.placed(second, host)
	assert_false(
		GridSnap.world_aabb(second).grow(-0.01).intersects(GridSnap.world_aabb(first)),
		str(second.global_position)
	)


## The editor plugin still calls through fs_snap, and it must not drift from
## the shared math.
func test_rest_on_drops_a_piece_onto_the_surface() -> void:
	var at := GridSnap.rest_on(Vector3(0.2, 10.0, 0.2), 0.0, _cell(Vector3.ZERO), [])
	assert_almost_eq(at.y, 0.0, 0.001)
	assert_almost_eq(fmod(absf(at.x), GridSnap.CELL), 0.0, 0.001)


func test_a_world_pose_is_stored_as_height_above_the_fairway() -> void:
	var field := CustomLayout.build(CustomHole.create("Offset")).height
	var lift := GridSnap.CELL
	var at := Vector3(0.0, field.height_at(0.0, -20.0) + lift, -20.0)
	assert_almost_eq(GridSnap.stored_offset(at, field).y, lift, 0.02)


func test_rest_on_sits_a_piece_on_top_of_another() -> void:
	var other := _cell(Vector3.ZERO)
	var at := GridSnap.rest_on(
		Vector3(0.2, 10.0, 0.2), other.end.y, _cell(Vector3(0.2, 10.0, 0.2)), [other]
	)
	assert_almost_eq(at.y, GridSnap.CELL, 0.001)
	assert_false(_cell(at).grow(-0.01).intersects(other), str(at))


func test_the_editor_plugin_reads_the_same_answers() -> void:
	assert_almost_eq(_Snap.CELL, GridSnap.CELL, 0.0001)
	assert_eq(_Snap.ASSET_DIR, GridSnap.ASSET_DIR)
	var from := Vector3(0.4, 0.0, 0.0)
	assert_eq(_Snap.to_grid(from), GridSnap.to_grid(from))
	assert_eq(_Snap.place(from, _cell(from), [_cell(Vector3.ZERO)]), Vector3(GridSnap.CELL, 0.0, 0.0))


func _cell(origin: Vector3) -> AABB:
	return AABB(Vector3(origin.x, origin.y, origin.z - GridSnap.CELL), Vector3.ONE * GridSnap.CELL)


func _cube(size: String) -> Node3D:
	return (load("res://assets/obstacles/cube_%s.glb" % size) as PackedScene).instantiate()
