extends GutTest
## The fairway a player lays down. A ribbon has to stay a ribbon: no strip
## folding back through an earlier one, and par has to follow its length.


func test_there_are_eight_shapes_to_choose_from() -> void:
	assert_eq(FairwayPiece.count(), 8)
	var ids := {}
	for i in FairwayPiece.count():
		var piece := FairwayPiece.at(i)
		assert_false(ids.has(piece["id"]), "duplicate %s" % piece["id"])
		ids[piece["id"]] = true
		assert_gt(float(piece["length"]), 0.0)
		assert_lte(absf(float(piece["turn"])), 90.0)
	for id in ["straight", "long_straight", "gentle_left", "gentle_right",
			"sharp_left", "sharp_right", "dogleg_left", "dogleg_right"]:
		assert_true(ids.has(id), id)


func test_a_left_turn_bends_the_way_the_engine_turns() -> void:
	var line := FairwayPiece.points(PackedInt32Array([
		FairwayPiece.index_of("straight"), FairwayPiece.index_of("dogleg_left")
	]))
	assert_lt(line[2].x, line[1].x, "left is negative X when facing down negative Z")
	var right := FairwayPiece.points(PackedInt32Array([
		FairwayPiece.index_of("straight"), FairwayPiece.index_of("dogleg_right")
	]))
	assert_gt(right[2].x, right[1].x)


func test_the_tee_is_the_origin_and_each_piece_adds_a_corner() -> void:
	var pieces := PackedInt32Array([0, 2, 4])
	var line := FairwayPiece.points(pieces)
	assert_eq(line.size(), 4)
	assert_eq(line[0], Vector3.ZERO)
	for i in pieces.size():
		assert_almost_eq(
			line[i].distance_to(line[i + 1]), float(FairwayPiece.at(pieces[i])["length"]), 0.01
		)


func test_a_straight_runs_down_negative_z() -> void:
	var line := FairwayPiece.points(PackedInt32Array([FairwayPiece.index_of("straight")]))
	assert_almost_eq(line[1].x, 0.0, 0.001)
	assert_lt(line[1].z, 0.0)


func test_par_follows_how_far_the_hole_runs() -> void:
	var short := PackedInt32Array([FairwayPiece.index_of("straight")])
	var long := PackedInt32Array()
	for i in 8:
		long.append(FairwayPiece.index_of("long_straight"))
	assert_eq(FairwayPiece.par_for(short), HoleGenerator.par_for_length(FairwayPiece.total_length(short)))
	assert_gte(FairwayPiece.par_for(long), FairwayPiece.par_for(short))
	assert_gt(FairwayPiece.width_for(short), 0.0)


func test_fairway_sizes_scale_from_the_regular_strip() -> void:
	var pieces := FairwayPiece.starter()
	var small := FairwayPiece.width_for(pieces, FairwayPiece.Width.SMALL)
	assert_almost_eq(small, HoleGenerator.fairway_width(FairwayPiece.par_for(pieces), FairwayPiece.INDEX), 0.01)
	assert_almost_eq(FairwayPiece.width_for(pieces, FairwayPiece.Width.MEDIUM), small * 1.5, 0.01)
	assert_almost_eq(FairwayPiece.width_for(pieces, FairwayPiece.Width.LARGE), small * 2.0, 0.01)
	assert_almost_eq(FairwayPiece.width_for(pieces, FairwayPiece.Width.EXTRA_LARGE), small * 3.0, 0.01)
	assert_almost_eq(FairwayPiece.width_for(pieces, FairwayPiece.Width.GIGANTIC), small * 4.0, 0.01)
	assert_eq(FairwayPiece.width_label(FairwayPiece.Width.SMALL), "SMALL")
	assert_eq(FairwayPiece.width_label(FairwayPiece.Width.MEDIUM), "MEDIUM")
	assert_eq(FairwayPiece.width_label(FairwayPiece.Width.LARGE), "LARGE")
	assert_eq(FairwayPiece.width_label(FairwayPiece.Width.EXTRA_LARGE), "EXTRA LARGE")
	assert_eq(FairwayPiece.width_label(FairwayPiece.Width.GIGANTIC), "GIGANTIC")


func test_the_starter_hole_is_already_playable() -> void:
	var pieces := FairwayPiece.starter()
	assert_true(FairwayPiece.is_playable(pieces))
	assert_gte(pieces.size(), FairwayPiece.MIN_PIECES)


## Three doglegs the same way wrap the ribbon back onto its own opening
## straight, which would leave two sets of lip walls sharing ground.
func test_a_ribbon_cannot_fold_back_over_itself() -> void:
	var dogleg := FairwayPiece.index_of("dogleg_left")
	var pieces := PackedInt32Array([FairwayPiece.index_of("long_straight")])
	var refused := false
	for i in 5:
		if not FairwayPiece.can_append(pieces, dogleg):
			refused = true
			break
		pieces.append(dogleg)
	assert_true(refused, "a loop back onto the opening straight has to be turned away")
	assert_true(FairwayPiece.is_clear(pieces))


func test_a_rejected_piece_is_never_added() -> void:
	var dogleg := FairwayPiece.index_of("dogleg_right")
	var pieces := PackedInt32Array([0, dogleg, dogleg, dogleg, dogleg])
	var before := pieces.size()
	if not FairwayPiece.can_append(pieces, dogleg):
		assert_eq(pieces.size(), before, "the check must not touch the list it is asked about")


func test_gentle_bends_can_be_strung_together() -> void:
	var gentle := FairwayPiece.index_of("gentle_right")
	var pieces := PackedInt32Array([FairwayPiece.index_of("straight")])
	for i in 3:
		assert_true(FairwayPiece.can_append(pieces, gentle), "bend %d" % i)
		pieces.append(gentle)
	assert_true(FairwayPiece.is_playable(pieces))


func test_a_hole_cannot_run_past_the_piece_limit() -> void:
	var pieces := PackedInt32Array()
	var straight := FairwayPiece.index_of("straight")
	for i in FairwayPiece.MAX_PIECES:
		pieces.append(straight)
	assert_false(FairwayPiece.can_append(pieces, straight))
	assert_true(FairwayPiece.is_playable(pieces))


func test_the_palette_reports_which_shapes_still_fit() -> void:
	var pieces := FairwayPiece.starter()
	var allowed := FairwayPiece.allowed(pieces)
	assert_eq(allowed.size(), FairwayPiece.count())
	assert_true(allowed[FairwayPiece.index_of("straight")])


func test_a_wide_starter_can_still_take_another_piece() -> void:
	var pieces := FairwayPiece.starter()
	for size in [
		FairwayPiece.Width.MEDIUM, FairwayPiece.Width.LARGE,
		FairwayPiece.Width.EXTRA_LARGE, FairwayPiece.Width.GIGANTIC,
	]:
		var allowed := FairwayPiece.allowed(pieces, size)
		assert_true(allowed[FairwayPiece.index_of("straight")], FairwayPiece.width_label(size))
		assert_true(allowed[FairwayPiece.index_of("long_straight")], FairwayPiece.width_label(size))
		assert_true(FairwayPiece.can_append(pieces, FairwayPiece.index_of("gentle_right"), size))


func test_a_wide_ribbon_still_cannot_fold_back() -> void:
	var dogleg := FairwayPiece.index_of("dogleg_left")
	var pieces := PackedInt32Array([FairwayPiece.index_of("long_straight")])
	var refused := false
	for i in 5:
		if not FairwayPiece.can_append(pieces, dogleg, FairwayPiece.Width.LARGE):
			refused = true
			break
		pieces.append(dogleg)
	assert_true(refused, "a wide loop back onto the opening straight has to be turned away")


func test_an_empty_hole_is_not_playable_yet() -> void:
	assert_false(FairwayPiece.is_playable(PackedInt32Array()))
	assert_false(FairwayPiece.can_pop(PackedInt32Array()))
	assert_true(FairwayPiece.can_pop(FairwayPiece.starter()))


## Custom holes are laid out as hole 1 so no setpiece hole claims them.
func test_a_custom_hole_never_lands_on_a_setpiece_index() -> void:
	var data := HoleData.new()
	data.index = FairwayPiece.INDEX
	assert_false(MountainHole.applies(data))
	assert_false(CulvertHole.applies(data))
	assert_false(ArenaHole.applies(data))
	assert_false(RaceHole.applies(data))
	assert_false(SoccerHole.applies(data))
	data.index = ArenaHole.INDEX
	data.custom = CustomHole.create("Hole 5")
	assert_false(ArenaHole.applies(data), "a named replacement is still a regular hole")
	assert_eq(data.layout_index(), FairwayPiece.INDEX)
