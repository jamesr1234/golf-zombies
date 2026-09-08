extends GutTest
## The arena door cutscene eases the leaves and can be skipped.


func test_opening_eases_the_doors_then_holds_them_open() -> void:
	var doors := _doors()
	var preview := ArenaPreview.new()
	preview.start(doors, true)
	assert_true(preview.is_active())
	assert_true(preview.is_opening())
	assert_almost_eq(doors.amount(), 0.0, 0.001)
	preview.tick(ArenaPreview.OPEN_SEC * 0.5)
	assert_true(preview.is_active())
	assert_gt(doors.amount(), 0.2)
	assert_lt(doors.amount(), 0.9)
	preview.tick(ArenaPreview.OPEN_SEC)
	assert_false(preview.is_active())
	assert_true(doors.is_open())


func test_closing_starts_open_and_seals() -> void:
	var doors := _doors()
	doors.snap(true)
	var preview := ArenaPreview.new()
	preview.start(doors, false)
	assert_true(preview.is_closing())
	assert_almost_eq(doors.amount(), 1.0, 0.001)
	preview.tick(ArenaPreview.CLOSE_SEC)
	assert_false(preview.is_active())
	assert_false(doors.is_open())


func test_skip_snaps_to_the_end_of_the_move() -> void:
	var doors := _doors()
	var preview := ArenaPreview.new()
	preview.start(doors, true)
	preview.tick(0.2)
	preview.skip()
	assert_false(preview.is_active())
	assert_true(doors.is_open())
	preview.start(doors, false)
	preview.skip()
	assert_false(doors.is_open())
	assert_false(preview.tick(0.16))


func test_the_lens_moves_in_as_the_doors_open() -> void:
	var doors := _doors()
	var preview := ArenaPreview.new()
	preview.start(doors, true)
	var start_at := preview.view().origin
	preview.tick(ArenaPreview.OPEN_SEC * 0.7)
	var later := preview.view().origin
	assert_gt(start_at.distance_to(later), 4.0, "the open shot pushes in")


func _doors() -> ArenaDoors:
	var data := HoleGenerator.generate(ArenaHole.INDEX, 20260816)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	return ArenaDoors.of(root)
