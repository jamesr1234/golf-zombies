extends GutTest
## The creator paints a pad on every full-swing landing so obstacles can be
## placed around where a good shot actually finishes.


func test_a_short_hole_has_no_layup_because_the_green_is_the_landing() -> void:
	var data := CustomLayout.build(CustomHole.create("Short"))
	assert_lt(data.length(), CreatorLandings.carry())
	assert_eq(CreatorLandings.spots(data).size(), 0)


func test_a_long_hole_marks_each_full_swing_before_the_green() -> void:
	var data := CustomLayout.build(_long_hole())
	var spots := CreatorLandings.spots(data)
	assert_gt(spots.size(), 0)
	var carry := CreatorLandings.carry()
	for i in spots.size():
		var expected := (i + 1) * carry
		assert_almost_eq(
			_along(data, spots[i]), expected, 0.6,
			"landing %d should sit one more full carry down the hole" % i
		)
		assert_gt(spots[i].distance_to(data.cup), data.green_radius * 0.5)
	assert_lt(spots[spots.size() - 1].distance_to(data.tee), data.length() - data.green_radius)


func test_landings_follow_the_fairway_not_the_chord() -> void:
	var hole := CustomHole.create("Dogleg")
	var bend := FairwayPiece.index_of("gentle_left")
	while hole.length() < CreatorLandings.carry() * 1.3:
		assert_true(hole.append_piece(bend))
	var data := CustomLayout.build(hole)
	var spots := CreatorLandings.spots(data)
	assert_gt(spots.size(), 0)
	var first := spots[0]
	assert_lt(HoleGenerator.distance_to_centerline(data, first), 0.6)
	var chord := data.tee + (data.cup - data.tee).normalized() * CreatorLandings.carry()
	chord.y = first.y
	assert_gt(first.distance_to(chord), 4.0, "a bent hole must not mark the crow-flies landing")


func test_the_pad_covers_a_good_shot_around_a_great_one() -> void:
	var pad := CreatorLandings.radius()
	assert_gt(pad, 3.0)
	assert_lt(pad, CreatorLandings.carry() * 0.25)
	var short := Shot.carry_to_height(0.0, CreatorLandings.GOOD_POWER)
	assert_almost_eq(pad * 2.0, CreatorLandings.carry() - short, 0.2)


func test_the_creator_builds_a_disk_for_each_landing() -> void:
	var data := CustomLayout.build(_long_hole())
	var pads := CreatorLandings.create()
	add_child_autofree(pads)
	pads.refresh(data)
	assert_eq(pads.get_child_count(), CreatorLandings.spots(data).size())
	assert_gt(pads.get_child_count(), 0)
	assert_true(pads.get_child(0) is MeshInstance3D)


func _long_hole() -> CustomHole:
	var hole := CustomHole.create("Long")
	var stretch := FairwayPiece.index_of("long_straight")
	while hole.length() < CreatorLandings.carry() * 2.3:
		assert_true(hole.append_piece(stretch), "the ribbon has to run past two carries")
	return hole


func _along(data: HoleData, point: Vector3) -> float:
	var closest := INF
	var best := 0.0
	var travelled := 0.0
	for i in range(1, data.centerline.size()):
		var a: Vector3 = data.centerline[i - 1]
		var b: Vector3 = data.centerline[i]
		var on := Geometry3D.get_closest_point_to_segment(point, a, b)
		var away := point.distance_to(on)
		if away < closest:
			closest = away
			best = travelled + a.distance_to(on)
		travelled += a.distance_to(b)
	return best
