extends GutTest
## A creator hole titled Hole 1..12 takes that slot in regular game modes.


func before_each() -> void:
	HoleStore.clear_sandbox()
	GameSettings.reset()


func after_all() -> void:
	before_each()


func test_hole_n_names_the_course_slot() -> void:
	assert_eq(HoleStore.course_slot("Hole 1"), 0)
	assert_eq(HoleStore.course_slot("HOLE 2"), 1)
	assert_eq(HoleStore.course_slot("  hole 12  "), 11)
	assert_eq(HoleStore.course_slot("Hole 13"), -1)
	assert_eq(HoleStore.course_slot("Hole 1 Extra"), -1)
	assert_eq(HoleStore.course_slot("Neon Alley"), -1)
	assert_eq(HoleStore.course_slot(CustomHole.UNTITLED), -1)


func test_a_saved_hole_1_replaces_the_opener() -> void:
	var made := CustomHole.create("Hole 1")
	assert_true(HoleStore.save_hole(made))
	var found := HoleStore.course_hole(0)
	assert_not_null(found)
	assert_eq(found.id, made.id)
	assert_null(HoleStore.course_hole(1), "other slots stay generated")


func test_the_newest_hole_1_wins() -> void:
	var older := CustomHole.create("Hole 1")
	older.created_at = 10
	var newer := CustomHole.create("Hole 1")
	newer.created_at = 20
	assert_true(HoleStore.save_hole(older))
	assert_true(HoleStore.save_hole(newer))
	assert_eq(HoleStore.course_hole(0).id, newer.id)


func test_an_unplayable_hole_1_does_not_replace() -> void:
	var hole := CustomHole.create("Hole 1")
	hole.pieces = PackedInt32Array([0])
	assert_false(hole.is_playable())
	assert_true(HoleStore.save_hole(hole))
	assert_null(HoleStore.course_hole(0))


func test_the_layout_uses_the_named_hole() -> void:
	var made := CustomHole.create("Hole 1")
	assert_true(HoleStore.save_hole(made))
	var data := HoleStore.layout(0, 20260816)
	assert_not_null(data.custom)
	assert_eq(data.custom.id, made.id)
	assert_eq(data.index, 0)
	assert_eq(data.par, made.par())


func test_an_untaken_slot_stays_generated() -> void:
	var data := HoleStore.layout(1, 20260816)
	assert_null(data.custom)
	assert_eq(data.index, 1)
	assert_true(data.has_culvert())


func test_replacing_a_setpiece_keeps_it_a_regular_hole() -> void:
	var made := CustomHole.create("Hole 5")
	assert_true(HoleStore.save_hole(made))
	var data := HoleStore.layout(ArenaHole.INDEX, 20260816)
	assert_not_null(data.custom)
	assert_eq(data.index, ArenaHole.INDEX)
	assert_false(ArenaHole.applies(data))
	assert_eq(data.layout_index(), FairwayPiece.INDEX)


func test_the_scorecard_takes_the_replacement_par() -> void:
	var made := CustomHole.create("Hole 1")
	assert_true(HoleStore.save_hole(made))
	var pars := HoleStore.course_pars()
	assert_eq(pars.size(), GameState.HOLE_COUNT)
	assert_eq(pars[0], made.par())
	assert_eq(pars[1], HoleGenerator.pars()[1])
