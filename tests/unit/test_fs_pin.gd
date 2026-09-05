extends GutTest
## Pinned FileSystem listing and native editor drag payload.

const _Listing := preload("res://addons/fs_pin/fs_listing.gd")
const _Snap := preload("res://addons/fs_pin/fs_snap.gd")


func test_lists_obstacle_glbs() -> void:
	var paths := _Listing.list_dir("res://assets/obstacles")
	assert_true(paths.has("res://assets/obstacles/arch_large.glb"), "arch_large.glb")
	assert_true(paths.has("res://assets/obstacles/cube_small.glb"), "cube_small.glb")
	for path in paths:
		assert_false(path.ends_with(".import"), path)
		assert_false(path.ends_with(".uid"), path)


func test_lists_course_prop_scenes() -> void:
	var paths := _Listing.list_dir("res://scenes/course/props")
	assert_true(paths.has("res://scenes/course/props/rock.tscn"), "rock.tscn")
	assert_true(paths.has("res://scenes/course/props/jump_ramp.tscn"), "jump_ramp.tscn")


func test_lists_structure_scenes() -> void:
	var paths := _Listing.list_dir("res://scenes/course/structures")
	assert_true(paths.has("res://scenes/course/structures/watchtower.tscn"), "watchtower.tscn")
	assert_true(paths.has("res://scenes/course/structures/plaza.tscn"), "plaza.tscn")


func test_hides_dotfiles_and_import_sidecars() -> void:
	assert_true(_Listing.is_hidden(".godot"))
	assert_true(_Listing.is_hidden("arch_large.glb.import"))
	assert_true(_Listing.is_hidden("plugin.gd.uid"))
	assert_false(_Listing.is_hidden("arch_large.glb"))


func test_default_expand_includes_assets_and_props() -> void:
	var expand := _Listing.default_expand_paths()
	assert_true(expand.has("res://assets"))
	assert_true(expand.has("res://scenes"))
	assert_true(expand.has("res://scenes/course"))
	assert_true(expand.has("res://scenes/course/props"))
	assert_true(expand.has("res://scenes/course/structures"))
	assert_true(_Listing.should_expand("res://"))
	assert_true(_Listing.should_expand("res://assets"))
	assert_true(_Listing.should_expand("res://scenes/course/structures"))
	assert_false(_Listing.should_expand("res://addons"))


func test_drag_payload_matches_filesystem_dock() -> void:
	var paths := PackedStringArray(["res://assets/obstacles/cube_large.glb"])
	var payload := _Listing.drag_payload(paths)
	assert_eq(payload["type"], "files")
	assert_eq(payload["files"], paths)


func test_joins_res_root_without_stripping_a_slash() -> void:
	assert_eq(_Listing.join("res://", "assets"), "res://assets")
	assert_eq(_Listing.join("res://assets", "obstacles"), "res://assets/obstacles")
	var root := _Listing.list_dir("res://")
	assert_true(root.has("res://assets"), "res://assets")
	assert_true(root.has("res://scenes"), "res://scenes")
	assert_false(root.has("res:/assets"), "must not emit res:/assets")


func test_files_are_not_treated_as_folders() -> void:
	assert_true(_Listing.is_dir("res://assets"))
	assert_true(_Listing.is_dir("res://assets/obstacles"))
	assert_false(_Listing.is_dir("res://assets/obstacles/arch_large.glb"))


func test_panel_is_immersive_only_in_fullscreen_or_dfm() -> void:
	assert_false(_Listing.is_immersive(DisplayServer.WINDOW_MODE_WINDOWED, false))
	assert_false(_Listing.is_immersive(DisplayServer.WINDOW_MODE_MAXIMIZED, false))
	assert_true(_Listing.is_immersive(DisplayServer.WINDOW_MODE_FULLSCREEN, false))
	assert_true(_Listing.is_immersive(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, false))
	assert_true(_Listing.is_immersive(DisplayServer.WINDOW_MODE_WINDOWED, true))


func test_placeable_covers_images_and_meshes() -> void:
	assert_true(_Listing.is_placeable("res://assets/cards/AH.png"))
	assert_true(_Listing.is_placeable("res://assets/obstacles/cube_small.glb"))
	assert_true(_Listing.is_placeable("res://scenes/course/props/rock.tscn"))
	assert_false(_Listing.is_placeable("res://addons/fs_pin/fs_listing.gd"))


func test_assets_folder_lists_images_under_it() -> void:
	var files := _Listing.list_files_under("res://assets")
	assert_true(files.has("res://assets/obstacles/arch_large.glb"), "arch_large.glb")
	assert_true(files.has("res://assets/cards/AH.png"), "AH.png")
	assert_true(files.has("res://assets/mechs/mech_suit.glb"), "mech_suit.glb")


func test_obstacles_folder_lists_only_its_own_files() -> void:
	var files := _Listing.list_files_under("res://assets/obstacles")
	assert_true(files.has("res://assets/obstacles/cube_small.glb"))
	assert_false(files.has("res://assets/cards/AH.png"))


func test_name_sort_is_alphabetical() -> void:
	var files := _Listing.list_files_under("res://assets/obstacles", _Listing.SORT_NAME)
	var cubes := _cube_names(files)
	assert_eq(cubes[0], "cube_extra_large.glb")
	assert_eq(cubes[1], "cube_extra_small.glb")
	assert_eq(cubes, _Listing.sort_paths(cubes, _Listing.SORT_NAME))


func test_size_sort_is_extra_small_to_extra_large_per_type() -> void:
	var files := _Listing.list_files_under("res://assets/obstacles", _Listing.SORT_SIZE)
	assert_eq(
		_cube_names(files),
		PackedStringArray(
			[
				"cube_extra_small.glb",
				"cube_small.glb",
				"cube_medium.glb",
				"cube_large.glb",
				"cube_extra_large.glb",
			]
		)
	)
	assert_eq(files[0], "res://assets/obstacles/arch_extra_small.glb")
	assert_eq(files[files.size() - 1], "res://assets/obstacles/wall_extra_large.glb")


func test_panel_sort_dropdown_switches_name_and_size() -> void:
	var panel: Control = preload("res://addons/fs_pin/fs_panel.gd").new()
	add_child_autofree(panel)
	panel._select_path("res://assets/obstacles")
	var menu := _sort_menu(panel)
	assert_not_null(menu, "sort dropdown")
	assert_eq(menu.get_item_text(0), "Alphabetical")
	assert_eq(menu.get_item_text(1), "Size")
	var list := _file_list(panel)
	assert_eq(list.get_item_text(0), "arch_extra_large")
	menu.select(1)
	menu.item_selected.emit(1)
	assert_eq(list.get_item_text(0), "arch_extra_small")
	menu.select(0)
	menu.item_selected.emit(0)
	assert_eq(list.get_item_text(0), "arch_extra_large")


func _cube_names(files: PackedStringArray) -> PackedStringArray:
	var cubes: PackedStringArray = []
	for path in files:
		if path.get_file().begins_with("cube_"):
			cubes.append(path.get_file())
	return cubes


func _sort_menu(host: Node) -> OptionButton:
	for child in host.get_children():
		if child is OptionButton:
			return child
		var nested := _sort_menu(child)
		if nested:
			return nested
	return null


func _file_list(host: Node) -> ItemList:
	for child in host.get_children():
		if child is ItemList:
			return child
	return null


func test_editor_translate_snap_is_the_extra_small_cube() -> void:
	assert_almost_eq(_Snap.CELL, 1.35, 0.001)


func test_finds_the_3d_snap_settings_dialog() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var other := ConfirmationDialog.new()
	other.title = "Not Snap"
	host.add_child(other)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Snap Settings"
	host.add_child(dialog)
	assert_eq(_Snap.find_snap_dialog(host), dialog)
	assert_true(_Snap.is_snap_dialog(dialog))
	assert_false(_Snap.is_snap_dialog(other))


func test_the_use_snap_toggle_is_the_magnet_button() -> void:
	var button := Button.new()
	add_child_autofree(button)
	button.toggle_mode = true
	button.accessibility_name = "Use Snap"
	assert_true(_Snap.is_use_snap_button(button))
	assert_eq(_Snap.find_use_snap_button(button.get_parent()), button)


func test_apply_is_quiet_when_the_3d_editor_is_missing() -> void:
	var host := Node.new()
	add_child_autofree(host)
	assert_false(_Snap.apply(host))


func test_a_dropped_position_rounds_onto_the_cell_grid() -> void:
	assert_eq(_Snap.to_grid(Vector3(-10.0, 0.2, -7.0)), Vector3(-9.45, 0.0, -6.75))
	assert_eq(_Snap.to_grid(Vector3(4.05, 4.05, -1.35)), Vector3(4.05, 4.05, -1.35))
	for axis in _Snap.to_grid(Vector3(-2.0, 8.0, 3.3)):
		assert_almost_eq(fmod(absf(axis), _Snap.CELL), 0.0, 0.001)


func test_only_obstacle_instances_are_snapped_on_drop() -> void:
	var block := Node3D.new()
	add_child_autofree(block)
	block.scene_file_path = "res://assets/obstacles/cube_small.glb"
	assert_true(_Snap.is_obstacle(block))
	var prop := Node3D.new()
	add_child_autofree(prop)
	prop.scene_file_path = "res://scenes/course/props/rock.tscn"
	assert_false(_Snap.is_obstacle(prop))
	var plain := Node.new()
	add_child_autofree(plain)
	plain.scene_file_path = "res://assets/obstacles/cube_small.glb"
	assert_false(_Snap.is_obstacle(plain), "a 2D or plain node has no position to snap")


func test_a_drop_toward_a_side_sits_flush_instead_of_overlapping() -> void:
	var other := _cell(Vector3.ZERO)
	var from := Vector3(0.4, 0.0, 0.0)
	var at := _Snap.place(from, _cell(from), [other])
	assert_eq(at, Vector3(_Snap.CELL, 0.0, 0.0))
	assert_false(_cell(at).grow(-0.01).intersects(other))


func test_a_drop_toward_the_top_stacks_instead_of_overlapping() -> void:
	var other := _cell(Vector3.ZERO)
	var from := Vector3(0.1, 0.9, 0.0)
	var at := _Snap.place(from, _cell(from), [other])
	assert_eq(at, Vector3(0.0, _Snap.CELL, 0.0))
	assert_false(_cell(at).grow(-0.01).intersects(other))


## The face has to be the same answer every time the same pose is asked about,
## or a piece flips between the top and a side.
func test_the_same_pose_always_picks_the_same_face() -> void:
	var other := _cell(Vector3.ZERO)
	var from := Vector3(0.1, 0.9, 0.0)
	var first := _Snap.place(from, _cell(from), [other])
	for i in 5:
		assert_eq(_Snap.place(from, _cell(from), [other]), first)


func test_a_flush_side_or_top_is_left_alone() -> void:
	var other := _cell(Vector3.ZERO)
	assert_eq(
		_Snap.place(Vector3(_Snap.CELL, 0.0, 0.0), _cell(Vector3(_Snap.CELL, 0.0, 0.0)), [other]),
		Vector3(_Snap.CELL, 0.0, 0.0)
	)
	assert_eq(
		_Snap.place(Vector3(0.0, _Snap.CELL, 0.0), _cell(Vector3(0.0, _Snap.CELL, 0.0)), [other]),
		Vector3(0.0, _Snap.CELL, 0.0)
	)


func test_a_drop_inside_a_taller_block_still_picks_a_free_face() -> void:
	var other := AABB(Vector3(0.0, 0.0, -_Snap.CELL * 3.0), Vector3(_Snap.CELL * 3.0, _Snap.CELL * 3.0, _Snap.CELL * 3.0))
	var from := Vector3(0.2, 1.0, -0.1)
	var at := _Snap.place(from, _cell(from), [other])
	assert_false(_cell(at).grow(-0.01).intersects(other), str(at))
	assert_true(
		is_equal_approx(at.x, _Snap.CELL * 3.0)
		or is_equal_approx(at.y, _Snap.CELL * 3.0)
		or is_equal_approx(at.z, 0.0)
		or is_equal_approx(at.x, -_Snap.CELL)
		or is_equal_approx(at.z, _Snap.CELL),
		str(at)
	)


func test_neighbor_boxes_skip_the_piece_being_placed() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var first: Node3D = _cube("medium")
	host.add_child(first)
	var second: Node3D = _cube("extra_small")
	host.add_child(second)
	second.position = first.position
	var boxes: Array = _Snap.neighbor_boxes(host, second)
	assert_eq(boxes.size(), 1)
	assert_almost_eq(boxes[0].size.x, _Snap.CELL * 3.0, 0.01)


func test_world_aabb_skips_meshes_that_are_off_the_tree() -> void:
	var cube: Node3D = _cube("extra_small")
	assert_eq(_Snap.world_aabb(cube).size, Vector3.ZERO)
	add_child_autofree(cube)
	assert_gt(_Snap.world_aabb(cube).size.x, 0.0)


func test_a_real_cube_dropped_on_another_cannot_stay_inside() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var first: Node3D = _cube("medium")
	host.add_child(first)
	var second: Node3D = _cube("extra_small")
	host.add_child(second)
	second.position = Vector3(0.3, 0.2, -0.1)
	second.global_position = _Snap.placed(second, host)
	assert_false(
		_Snap.world_aabb(second).grow(-0.01).intersects(_Snap.world_aabb(first)),
		str(second.global_position)
	)


func _cell(origin: Vector3) -> AABB:
	return AABB(Vector3(origin.x, origin.y, origin.z - _Snap.CELL), Vector3.ONE * _Snap.CELL)


func _cube(size: String) -> Node3D:
	return (load("res://assets/obstacles/cube_%s.glb" % size) as PackedScene).instantiate()
