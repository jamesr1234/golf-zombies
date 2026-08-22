extends GutTest
## Lounge chatter is mostly how to play this game; one in three people is a hack.


func test_one_in_three_lounge_regulars_is_comedy() -> void:
	assert_eq(GolfAdvice.comedy_slots(6), 2)
	var comedy := 0
	for i in 6:
		if GolfAdvice.is_comedy_index(i):
			comedy += 1
	assert_eq(comedy, 2)


func test_useful_lines_are_about_this_game() -> void:
	assert_gt(GolfAdvice.USEFUL.size(), 8)
	for line in GolfAdvice.USEFUL:
		assert_true(GolfAdvice.is_useful_line(line), line)


func test_comedy_lines_are_generic_golf() -> void:
	assert_gt(GolfAdvice.COMEDY.size(), 5)
	for line in GolfAdvice.COMEDY:
		assert_false(line.to_lower().contains("double bogey"))
		assert_false(line.to_lower().contains("hex barrier"))


func test_pick_avoids_repeating_the_last_line() -> void:
	var first := GolfAdvice.pick(false)
	var second := GolfAdvice.pick(false, first)
	if GolfAdvice.USEFUL.size() > 1:
		assert_ne(second, first)


func test_a_built_clubhouse_matches_the_ratio() -> void:
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	assert_eq(house.npcs.size(), 6)
	assert_eq(house.comedy_count(), GolfAdvice.comedy_slots(6))
	assert_eq(house.stations.size(), 5)
	assert_gt(ClubhouseBuild.WIDTH, 20.0)
	assert_gt(ClubhouseBuild.DEPTH, 14.0)
	assert_false(house.doors_open)
	house.open_doors()
	assert_true(house.doors_open)
	assert_not_null(house.plaza)
	assert_eq(house.plaza.collision_layer, Layers.WORLD)
	assert_true(house.covers_local(Vector3(0.0, 0.0, ClubhouseBuild.DEPTH * 0.5)))
	assert_true(house.covers_local(Vector3(0.0, 0.0, MatchFlow.CLUBHOUSE_SIDE)))
	assert_false(house.covers_local(Vector3(0.0, 0.0, MatchFlow.CLUBHOUSE_SIDE + 20.0)))
