extends GutTest
## A lesson playtest only sends you back after the drill is done.

const _Tutorial := preload("res://scripts/creator/tutorial_playtest.gd")


func after_each() -> void:
	GameSettings.reset()


func test_a_cart_path_and_a_ramp_path_are_known() -> void:
	assert_true(_Tutorial.is_cart("res://scenes/vehicles/golf_cart.tscn"))
	assert_false(_Tutorial.is_cart("res://scenes/vehicles/race_car.tscn"))
	assert_true(_Tutorial.is_ramp("res://assets/obstacles/ramp_small.glb"))
	assert_false(_Tutorial.is_ramp("res://assets/obstacles/cube_small.glb"))


func test_the_pack_drill_waits_until_they_have_all_been_seen() -> void:
	var drill = _Tutorial.new()
	drill.start(GameSettings.TutorialGoal.CLEAR_PACK)
	assert_false(drill.can_leave())
	assert_false(drill.note_zombies(false, 0))
	assert_false(drill.note_zombies(true, 0), "empty grass before the pack lands is not a wipe")
	assert_false(drill.note_zombies(true, 4))
	assert_true(drill.note_zombies(true, 0))
	assert_true(drill.can_leave())


func test_the_ramp_drill_waits_for_a_landed_jump() -> void:
	var drill = _Tutorial.new()
	drill.start(GameSettings.TutorialGoal.DRIVE_RAMP)
	assert_false(drill.can_leave())
	assert_true(_Tutorial.banner_body(GameSettings.TutorialGoal.DRIVE_RAMP).contains("jump"))
	assert_true(drill.pause_leave_copy().to_lower().contains("jump"))
	assert_false(drill.note_cart(false, 1.0), "rolling on the grass is not a jump")
	assert_false(drill.note_cart(true, 0.1))
	assert_false(drill.note_cart(false, 0.1), "the landing still has to sit for a beat")
	assert_false(drill.can_leave())
	assert_false(drill.note_cart(false, _Tutorial.LAND_HOLD - 0.2))
	assert_true(drill.note_cart(false, 0.3))
	assert_true(drill.can_leave())


func test_a_second_jump_restarts_the_landing_wait() -> void:
	var drill = _Tutorial.new()
	drill.start(GameSettings.TutorialGoal.DRIVE_RAMP)
	drill.note_cart(true, 0.0)
	drill.note_cart(false, 2.5)
	assert_false(drill.note_cart(true, 0.1), "leaving the ground again wipes the wait")
	assert_false(drill.note_cart(false, 2.5))
	assert_true(drill.note_cart(false, 0.6))


func test_the_lesson_picks_the_right_playtest_job() -> void:
	var lesson := CreatorLesson.new()
	lesson.start(null)
	lesson.resume_at(null, CreatorLesson.ids().find("place_obstacles"))
	lesson._waiting = true
	assert_eq(lesson.playtest_goal(), GameSettings.TutorialGoal.DRIVE_RAMP)
	assert_true(lesson.launches_playtest())
	lesson.resume_at(null, CreatorLesson.ids().find("set_counts"))
	lesson._waiting = true
	assert_eq(lesson.playtest_goal(), GameSettings.TutorialGoal.CLEAR_PACK)
