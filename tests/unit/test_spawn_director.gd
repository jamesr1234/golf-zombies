extends GutTest
## Zombies should walk in from down the hole, not pop in next to a player.

const ZOMBIE := preload("res://scenes/zombies/zombie.tscn")
const WALKER := preload("res://resources/zombies/walker.tres")
const PLAYER := preload("res://scenes/players/player.tscn")


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
	assert_eq(director.live_count(), 0, "the burst does not land on the hole-out frame")
	assert_eq(director._burst_left, SpawnDirector.TRANSIT_BURST)
	assert_lt(SpawnDirector.BURST_PER_FRAME, SpawnDirector.TRANSIT_BURST)


func test_the_arena_spawns_tighter_than_a_fairway() -> void:
	var director := SpawnDirector.new()
	add_child_autofree(director)
	var player := Node3D.new()
	player.add_to_group("players")
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	director.begin_hole(ArenaHole.INDEX, [
		Vector3(12.0, 0.0, 0.0),
		Vector3(30.0, 0.0, 0.0),
	])
	assert_eq(director.cap(), ArenaHole.SPAWN_CAP)
	assert_almost_eq(director.interval(), ArenaHole.SPAWN_INTERVAL, 0.001)
	assert_eq(director._burst_left, ArenaHole.SPAWN_BURST)
	var candidates := director._candidate_points()
	assert_eq(candidates.size(), 2, "keep-away is short enough that the rim still feeds")
	for point in candidates:
		assert_gte(point.distance_to(player.global_position), ArenaHole.SPAWN_KEEP_AWAY)


func test_a_leashed_zombie_ignores_players_outside_the_yard() -> void:
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.global_position = Vector3.ZERO
	zombie.roam = AABB(Vector3(-8.0, -4.0, -8.0), Vector3(16.0, 8.0, 16.0))
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.global_position = Vector3(40.0, 0.0, 0.0)
	await wait_physics_frames(2)
	assert_null(zombie.ai.pick_target(zombie), "they do not chase out of the maze")
	player.global_position = Vector3(2.0, 0.0, 0.0)
	assert_eq(zombie.ai.pick_target(zombie), player)


func test_a_leashed_zombie_walks_home_if_it_leaves_the_yard() -> void:
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.roam = AABB(Vector3(-8.0, -4.0, -8.0), Vector3(16.0, 8.0, 16.0))
	zombie.global_position = Vector3(30.0, 0.0, 0.0)
	await wait_physics_frames(2)
	var home := zombie.ai.steer(zombie)
	assert_lt(home.x, -0.5, "outside the maze they turn back in")


func test_a_maze_zombie_only_chases_inside_seven_metres() -> void:
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.global_position = Vector3.ZERO
	zombie.roam = AABB(Vector3(-40.0, -4.0, -40.0), Vector3(80.0, 8.0, 80.0))
	zombie.aggro_range = Maze.AGGRO
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)
	player.global_position = Vector3(Maze.AGGRO + 2.0, 0.0, 0.0)
	assert_null(zombie.ai.pick_target(zombie), "they keep the beat until you are close")
	player.global_position = Vector3(Maze.AGGRO - 1.0, 0.0, 0.0)
	assert_eq(zombie.ai.pick_target(zombie), player)


func test_a_patrol_turns_around_at_the_end_of_the_aisle() -> void:
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.patrol_a = Vector3(-4.0, 0.0, 0.0)
	zombie.patrol_b = Vector3(4.0, 0.0, 0.0)
	zombie.patrol_goal_b = true
	zombie.global_position = Vector3(3.8, 0.0, 0.0)
	await wait_physics_frames(2)
	var step := zombie.ai.steer(zombie)
	assert_lt(step.x, -0.5, "reaching the end of the aisle turns them around")
