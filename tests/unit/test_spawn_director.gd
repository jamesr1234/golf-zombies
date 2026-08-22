extends GutTest
## Zombies should walk in from down the hole, not pop in next to a player.


func before_each() -> void:
	GameSettings.reset()


func test_candidates_stay_away_from_players() -> void:
	var director := SpawnDirector.new()
	add_child_autofree(director)
	var player := Node3D.new()
	player.add_to_group("players")
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	director.begin_hole(0, [
		Vector3(10.0, 0.0, 0.0),
		Vector3(80.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 90.0),
	])
	var candidates := director._candidate_points()
	assert_eq(candidates.size(), 2)
	for point in candidates:
		assert_gte(
			point.distance_to(player.global_position),
			SpawnDirector.MIN_PLAYER_DISTANCE
		)


func test_a_crowded_short_hole_still_picks_the_farthest_spot() -> void:
	var director := SpawnDirector.new()
	add_child_autofree(director)
	var player := Node3D.new()
	player.add_to_group("players")
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	director.begin_hole(0, [
		Vector3(8.0, 0.0, 0.0),
		Vector3(18.0, 0.0, 0.0),
		Vector3(25.0, 0.0, 0.0),
	])
	var candidates := director._candidate_points()
	assert_eq(candidates.size(), 1)
	assert_almost_eq(candidates[0].x, 25.0, 0.001)


func test_transit_packs_the_road_tighter_than_a_hole() -> void:
	var director := SpawnDirector.new()
	add_child_autofree(director)
	director.begin_hole(0, [Vector3(80.0, 0.0, 0.0)])
	assert_eq(director.cap(), SpawnDirector.BASE_CAP)
	director.begin_transit(2, [Vector3(20.0, 0.0, 0.0), Vector3(40.0, 0.0, 0.0)])
	assert_true(director.is_transit())
	assert_eq(director.cap(), SpawnDirector.TRANSIT_CAP)
	assert_almost_eq(director.interval(), SpawnDirector.TRANSIT_INTERVAL, 0.001)
