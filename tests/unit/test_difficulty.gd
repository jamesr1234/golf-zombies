extends GutTest
## Menu picks and spawn/clock knobs. Medium is the original course.

const GUNNER := preload("res://resources/zombies/gunner.tres")


func after_each() -> void:
	GameSettings.reset()
	InputActions.register_for_mode(GameSettings.Mode.SOLO)


func test_medium_keeps_the_original_clock_and_spawn_rate() -> void:
	assert_eq(GameSettings.seconds_for(GameSettings.Kind.MEDIUM), GameState.HOLE_SECONDS)
	assert_eq(GameSettings.interval_scale_for(GameSettings.Kind.MEDIUM), 1.0)
	assert_eq(GameSettings.cap_scale_for(GameSettings.Kind.MEDIUM), 1.0)
	assert_eq(GameSettings.hp_scale_for(GameSettings.Kind.MEDIUM), 1.0)
	assert_eq(GameSettings.speed_scale_for(GameSettings.Kind.MEDIUM), 1.0)
	assert_eq(GameSettings.gunner_unlock_for(GameSettings.Kind.MEDIUM, GUNNER.unlock_hole), 1)


func test_easy_is_looser_and_impossible_is_tighter() -> void:
	assert_gt(
		GameSettings.seconds_for(GameSettings.Kind.EASY),
		GameSettings.seconds_for(GameSettings.Kind.MEDIUM)
	)
	assert_lt(
		GameSettings.seconds_for(GameSettings.Kind.HARD),
		GameSettings.seconds_for(GameSettings.Kind.MEDIUM)
	)
	assert_eq(GameSettings.seconds_for(GameSettings.Kind.IMPOSSIBLE), 60.0)
	assert_gt(
		GameSettings.interval_scale_for(GameSettings.Kind.EASY),
		GameSettings.interval_scale_for(GameSettings.Kind.MEDIUM)
	)
	assert_lt(
		GameSettings.interval_scale_for(GameSettings.Kind.IMPOSSIBLE),
		GameSettings.interval_scale_for(GameSettings.Kind.HARD)
	)
	assert_lt(
		GameSettings.cap_scale_for(GameSettings.Kind.EASY),
		GameSettings.cap_scale_for(GameSettings.Kind.MEDIUM)
	)
	assert_gt(
		GameSettings.cap_scale_for(GameSettings.Kind.IMPOSSIBLE),
		GameSettings.cap_scale_for(GameSettings.Kind.HARD)
	)
	assert_gt(GameSettings.hp_scale_for(GameSettings.Kind.HARD), 1.0)
	assert_gt(
		GameSettings.speed_scale_for(GameSettings.Kind.IMPOSSIBLE),
		GameSettings.speed_scale_for(GameSettings.Kind.HARD)
	)


func test_gunners_unlock_earlier_on_hard() -> void:
	assert_eq(GameSettings.gunner_unlock_for(GameSettings.Kind.EASY, 1), 2)
	assert_eq(GameSettings.gunner_unlock_for(GameSettings.Kind.HARD, 1), 0)
	assert_eq(GameSettings.gunner_unlock_for(GameSettings.Kind.IMPOSSIBLE, 1), 0)


func test_spawn_director_uses_the_current_difficulty() -> void:
	var director := SpawnDirector.new()
	add_child_autofree(director)
	director.begin_hole(0, [Vector3(80.0, 0.0, 0.0)])
	GameSettings.difficulty = GameSettings.Kind.MEDIUM
	assert_eq(director.cap(), SpawnDirector.BASE_CAP)
	GameSettings.difficulty = GameSettings.Kind.EASY
	assert_lt(director.cap(), SpawnDirector.BASE_CAP)
	GameSettings.difficulty = GameSettings.Kind.IMPOSSIBLE
	assert_gt(director.cap(), SpawnDirector.BASE_CAP)
	assert_lt(director.interval(), SpawnDirector.BASE_INTERVAL)


func test_hard_lets_gunners_onto_the_first_tee() -> void:
	var director := SpawnDirector.new()
	add_child_autofree(director)
	director.begin_hole(0, [Vector3(80.0, 0.0, 0.0)])
	GameSettings.difficulty = GameSettings.Kind.MEDIUM
	assert_false(director._type_allowed(GUNNER))
	GameSettings.difficulty = GameSettings.Kind.HARD
	assert_true(director._type_allowed(GUNNER))
	director.begin_transit(0, [Vector3(20.0, 0.0, 0.0)])
	assert_false(director._type_allowed(GUNNER), "the cart path stays melee")
