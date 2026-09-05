extends GutTest
## The committed manifest is what an exported build reads, so it has to still
## match what is actually on disk.

const _Listing := preload("res://addons/fs_pin/fs_listing.gd")


func test_the_manifest_matches_the_folders_on_disk() -> void:
	var built := PieceCatalog.build()
	for category in PieceCatalog.categories():
		assert_eq(
			Array(PieceCatalog.entries(category)),
			Array(built[category] as PackedStringArray),
			"%s drifted: run Project > Tools > %s" % [category, "Refresh Hole Creator Piece Catalog"]
		)


func test_the_catalog_holds_the_whole_obstacle_kit() -> void:
	var obstacles := PieceCatalog.entries(PieceCatalog.OBSTACLES)
	assert_eq(obstacles.size(), 46)
	for path in obstacles:
		assert_true(path.begins_with(PieceCatalog.OBSTACLE_DIR), path)
		assert_true(path.ends_with(".glb"), path)


## Bundled structures were pulled from the palette: a player builds their own by
## grouping obstacles instead.
func test_no_bundled_structure_is_offered() -> void:
	assert_false(PieceCatalog.categories().has("structures"))
	for category in PieceCatalog.categories():
		for path in PieceCatalog.entries(category):
			assert_false(path.begins_with("res://scenes/course/structures"), path)


func test_every_vehicle_can_be_dropped_on_a_hole() -> void:
	var vehicles := PieceCatalog.entries(PieceCatalog.VEHICLES)
	assert_eq(vehicles.size(), 6)
	for path in vehicles:
		assert_true(path.begins_with(PieceCatalog.VEHICLE_DIR), path)
		assert_true(path.ends_with(".tscn"), path)
		var node := CustomOverlay.instantiate(path)
		assert_true(node is GolfCart, path)
		node.free()


func test_every_gun_can_be_dropped_on_a_hole() -> void:
	var weapons := PieceCatalog.entries(PieceCatalog.WEAPONS)
	assert_eq(weapons.size(), 9)
	for path in weapons:
		assert_true(path.begins_with(PieceCatalog.WEAPON_DIR), path)
		assert_true(CustomHole.is_weapon(path), path)
		assert_not_null(load(path) as WeaponStats, path)


func test_a_speed_rectangle_is_a_placeable_boost_pad() -> void:
	var path := "%s/speed_rectangle.tscn" % PieceCatalog.PROP_DIR
	assert_true(PieceCatalog.entries(PieceCatalog.PROPS).has(path))
	var pad := CustomOverlay.instantiate(path) as SpeedRectangle
	add_child_autofree(pad)
	assert_not_null(pad)
	assert_true(pad.is_in_group("transit_boost"))
	assert_gt(pad.get_child_count(), 0)
	assert_almost_eq(pad.along.z, -1.0, 0.01)
	var hull := GridSnap.local_aabb(pad)
	assert_gt(hull.position.y, 0.1, "sits on the turf, not in it")
	assert_gt(hull.size.y, 0.25, "thick enough to read when floor-snapped")


## A prop that needs a partner or generator data would be dead on its own, so
## only the standalone ones reach the palette.
func test_only_standalone_props_are_offered() -> void:
	var props := PieceCatalog.entries(PieceCatalog.PROPS)
	assert_eq(props.size(), PieceCatalog.LOOSE_PROPS.size())
	for path in props:
		assert_true(PieceCatalog.LOOSE_PROPS.has(path.get_file().get_basename()), path)
	for skipped in ["jump_ramp", "culvert", "gun_pickup", "windmill_control"]:
		assert_false(props.has("%s/%s.tscn" % [PieceCatalog.PROP_DIR, skipped]), skipped)


## A weapon is listed as its stats resource but stands on the hole as a pickup,
## so the overlay is what has to hand back a node for every entry.
func test_every_listed_piece_loads() -> void:
	for category in PieceCatalog.categories():
		for path in PieceCatalog.entries(category):
			assert_true(ResourceLoader.exists(path), path)
			var node := CustomOverlay.instantiate(path)
			assert_not_null(node, path)
			node.free()


func test_obstacles_read_small_to_large_within_a_kind() -> void:
	var cubes: PackedStringArray = []
	for path in PieceCatalog.entries(PieceCatalog.OBSTACLES):
		if path.get_file().begins_with("cube_"):
			cubes.append(path)
	assert_eq(
		Array(cubes),
		[
			"res://assets/obstacles/cube_extra_small.glb",
			"res://assets/obstacles/cube_small.glb",
			"res://assets/obstacles/cube_medium.glb",
			"res://assets/obstacles/cube_large.glb",
			"res://assets/obstacles/cube_extra_large.glb",
		]
	)


## The pinned FileSystem panel sorts through the same helper, so the palette
## and the editor browser agree on the order.
func test_the_editor_panel_sorts_through_the_catalog() -> void:
	var files := _Listing.list_files_under("res://assets/obstacles", _Listing.SORT_SIZE)
	assert_eq(Array(files), Array(PieceCatalog.sort_by_size(files)))


func test_a_label_reads_as_chrome() -> void:
	assert_eq(PieceCatalog.label_for("res://assets/obstacles/cube_extra_small.glb"), "CUBE EXTRA SMALL")
