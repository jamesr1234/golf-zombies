extends GutTest
## A placeable concrete helix the carts climb, then a ski-jump off the top.

const _Track := preload("res://scripts/course/spiral_track.gd")


func test_the_helix_is_a_cart_grade() -> void:
	assert_lt(_Track.grade_deg(), GolfCart.FLOOR_MAX_DEG * 0.25)
	assert_gt(_Track.WIDTH, CartVisuals.WHEEL_X * 4.0, "two carts can race")
	assert_gt(_Track.RADIUS * 2.0, 40.0, "big enough to read as a track")
	assert_gt(_Track.height(), 80.0, "it keeps climbing")


func test_the_lip_is_a_kicker() -> void:
	assert_gt(_Track.launch_deg(), _Track.grade_deg() + 15.0)
	assert_gt(_Track.launch_deg(), JumpRamp.ANGLE_DEG)
	assert_gt(_Track.launch_rise(), 4.0)


func test_the_prop_builds_a_solid_floor() -> void:
	var track: StaticBody3D = _Track.create()
	add_child_autofree(track)
	assert_eq(track.collision_layer, Layers.WORLD)
	assert_eq(track.collision_mask, 0)
	var tris := 0
	var hulls := 0
	var faces := 0
	var steep := 0
	var min_y := cos(deg_to_rad(GolfCart.FLOOR_MAX_DEG))
	for child in track.get_children():
		var shape := child as CollisionShape3D
		if shape == null or shape.shape == null:
			continue
		if shape.shape is ConcavePolygonShape3D:
			tris += 1
			var data: PackedVector3Array = (shape.shape as ConcavePolygonShape3D).data
			var i := 0
			while i + 2 < data.size():
				faces += 1
				var normal: Vector3 = (data[i + 1] - data[i]).cross(data[i + 2] - data[i])
				if normal.length() > 0.0001 and normal.y < min_y * normal.length():
					steep += 1
				i += 3
		elif shape.shape is ConvexPolygonShape3D:
			hulls += 1
	assert_eq(tris, 2, "deck and lip only, not rails or pillars")
	assert_eq(hulls, 0, "Jolt's character body ignores convex hulls")
	assert_gt(faces, 100, "the ribbon is a triangle mesh")
	assert_eq(steep, 0, "sides and underside must not be solid")


func test_the_entry_sits_on_the_turf() -> void:
	var track: StaticBody3D = _Track.create()
	add_child_autofree(track)
	var hull := GridSnap.local_aabb(track)
	assert_gt(hull.size.x, 50.0)
	assert_gt(hull.size.z, 50.0)
	assert_gt(hull.size.y, 80.0)
	assert_eq(_Track.LIFT, 0.0)
	assert_gt(hull.position.y, -0.2, "does not sink under the grass")
	assert_lt(hull.position.y, 0.05, "the approach starts on the ground")


func test_the_catalog_offers_it_as_a_prop() -> void:
	var path := "%s/spiral_track.tscn" % PieceCatalog.PROP_DIR
	assert_true(PieceCatalog.entries(PieceCatalog.PROPS).has(path))
	var node := CustomOverlay.instantiate(path)
	add_child_autofree(node)
	assert_not_null(node)
	assert_eq(node.get_script(), _Track)
	assert_gt(node.get_child_count(), 0)
