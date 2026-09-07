extends GutTest
## Zombies should walk in from down the hole, not pop in next to a player.

const ZOMBIE := preload("res://scenes/zombies/zombie.tscn")
const WALKER := preload("res://resources/zombies/walker.tres")
const PLAYER := preload("res://scenes/players/player.tscn")


func before_each() -> void:
	GameSettings.reset()


func test_a_fairway_does_not_feed_zombies() -> void:
	var director := SpawnDirector.new()
	add_child_autofree(director)
	director.begin_hole(0, [Vector3(80.0, 0.0, 0.0)])
	assert_false(director._running)
	assert_eq(director._burst_left, 0)


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


func test_transit_does_not_pack_the_road() -> void:
	var director := SpawnDirector.new()
	add_child_autofree(director)
	director.begin_hole(ArenaHole.INDEX, [Vector3(80.0, 0.0, 0.0)])
	assert_true(director._running)
	director.begin_transit(2, [Vector3(20.0, 0.0, 0.0), Vector3(40.0, 0.0, 0.0)])
	assert_false(director.is_transit())
	assert_false(director._running)
	assert_eq(director._burst_left, 0)
	assert_eq(director.live_count(), 0)


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
	assert_true(director._running, "the pit is the only hole that feeds")
	assert_eq(director.cap(), ArenaHole.SPAWN_CAP)
	assert_almost_eq(director.interval(), ArenaHole.SPAWN_INTERVAL, 0.001)
	assert_eq(director._burst_left, ArenaHole.SPAWN_BURST)
	var candidates := director._candidate_points()
	assert_eq(candidates.size(), 2, "keep-away is short enough that the rim still feeds")
	for point in candidates:
		assert_gte(point.distance_to(player.global_position), ArenaHole.SPAWN_KEEP_AWAY)


func test_planted_packs_stand_in_their_yard() -> void:
	var director := SpawnDirector.new()
	add_child_autofree(director)
	var root := Node3D.new()
	add_child_autofree(root)
	director.container = root
	var at := Vector3(12.0, 0.0, -20.0)
	director.plant_packs([{
		"position": at,
		"radius": 8.1,
		"aggro": 21.6,
		"roam": SpawnPack.roam_at(at, 8.1),
		"counts": {"walker": 3, "runner": 0, "brute": 1, "gunner": 0},
	}])
	assert_eq(director.live_count(), 4)
	var walkers := 0
	var brutes := 0
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		assert_true(zombie.has_roam())
		assert_true(zombie.roam_contains(at))
		assert_almost_eq(zombie.aggro_range, 21.6, 0.001)
		if zombie.stats.display_name == "Walker":
			walkers += 1
		elif zombie.stats.display_name == "Brute":
			brutes += 1
	assert_eq(walkers, 3)
	assert_eq(brutes, 1)


func test_each_pack_plants_on_its_own_spot() -> void:
	var director := SpawnDirector.new()
	add_child_autofree(director)
	var root := Node3D.new()
	add_child_autofree(root)
	director.container = root
	director.plant_packs([
		{"position": Vector3(0.0, 16.0, -20.0), "radius": 4.0, "counts": {"walker": 1}},
		{"position": Vector3(8.0, 16.0, -40.0), "radius": 4.0, "counts": {"walker": 1}},
		{"position": Vector3(-8.0, 16.0, -60.0), "radius": 4.0, "counts": {"walker": 1}},
	])
	assert_eq(director.live_count(), 3)
	var zs: Array[float] = []
	for node in get_tree().get_nodes_in_group("zombies"):
		zs.append((node as Node3D).global_position.z)
		assert_lt(absf((node as Node3D).global_position.y), 2.0, "a high saved point still stands on the turf")
	zs.sort()
	assert_almost_eq(zs[0], -60.0, 4.0)
	assert_almost_eq(zs[1], -40.0, 4.0)
	assert_almost_eq(zs[2], -20.0, 4.0)


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


func test_a_wanderer_turns_away_from_a_wall() -> void:
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.global_position = Vector3.ZERO
	zombie.roam = AABB(Vector3(-20.0, -4.0, -20.0), Vector3(40.0, 8.0, 40.0))
	zombie.wander_at = Vector3(12.0, 0.0, 0.0)
	await wait_physics_frames(2)
	zombie.ai.turn_from_wall(zombie, Vector3.LEFT)
	assert_lt(zombie.wander_at.x, -0.5, "they walk back into the open yard")


func test_a_wall_bounce_stays_inside_the_yard() -> void:
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.global_position = Vector3(7.0, 0.0, 0.0)
	zombie.roam = AABB(Vector3(-8.0, -4.0, -8.0), Vector3(16.0, 8.0, 16.0))
	await wait_physics_frames(2)
	zombie.ai.turn_from_wall(zombie, Vector3.RIGHT)
	assert_true(zombie.roam_contains(zombie.wander_at), "the bounce cannot leave the yard")


func test_a_chasing_zombie_does_not_bounce_off_a_wall() -> void:
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.roam = AABB(Vector3(-20.0, -4.0, -20.0), Vector3(40.0, 8.0, 40.0))
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.global_position = Vector3(2.0, 0.0, 0.0)
	await wait_physics_frames(2)
	zombie.ai.target = player
	zombie.wander_at = Vector3(10.0, 0.0, 0.0)
	assert_false(zombie.ai.bounce_off_wall(zombie))
	assert_almost_eq(zombie.wander_at.x, 10.0, 0.001)


func test_a_leashed_zombie_walks_home_if_it_leaves_the_yard() -> void:
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.roam = AABB(Vector3(-8.0, -4.0, -8.0), Vector3(16.0, 8.0, 16.0))
	zombie.global_position = Vector3(30.0, 0.0, 0.0)
	await wait_physics_frames(2)
	var home := zombie.ai.steer(zombie)
	assert_lt(home.x, -0.5, "outside the maze they turn back in")


func test_a_pack_zombie_only_chases_inside_its_detect_range() -> void:
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.global_position = Vector3.ZERO
	zombie.roam = AABB(Vector3(-8.0, -4.0, -8.0), Vector3(16.0, 8.0, 16.0))
	zombie.aggro_range = 12.0
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)
	player.global_position = Vector3(20.0, 0.0, 0.0)
	assert_null(zombie.ai.pick_target(zombie), "they keep walking the yard until you are close")
	player.global_position = Vector3(10.0, 0.0, 0.0)
	assert_eq(zombie.ai.pick_target(zombie), player, "they notice you outside the yard")


func test_a_pack_zombie_leaves_the_yard_once_it_is_chasing() -> void:
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.global_position = Vector3.ZERO
	zombie.roam = AABB(Vector3(-8.0, -4.0, -8.0), Vector3(16.0, 8.0, 16.0))
	zombie.aggro_range = 20.0
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.global_position = Vector3(14.0, 0.0, 0.0)
	await wait_physics_frames(2)
	zombie.ai.target = player
	var step := zombie.ai.steer(zombie)
	assert_gt(step.x, 0.5, "they walk out of the yard toward you")


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
