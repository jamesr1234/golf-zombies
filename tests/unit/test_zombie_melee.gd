extends GutTest
## A brute's club is a one-swing down. Stay clear or shoot it first.

const BRUTE := preload("res://resources/zombies/brute.tres")
const WALKER := preload("res://resources/zombies/walker.tres")
const PLAYER_SCENE := preload("res://scenes/players/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")


func test_a_brute_swing_is_enough_to_down_you() -> void:
	assert_gte(BRUTE.damage, 100.0, "one club from a brute has to dump the bar")
	assert_gt(WALKER.damage, 0.0)
	assert_gt(BRUTE.damage, WALKER.damage)


func test_one_brute_contact_downs_you() -> void:
	var player := _player()
	var brute := _zombie(BRUTE)
	brute.ai.target = player
	brute.ai.land_melee(brute)
	assert_false(player.health.is_alive())
	assert_true(player.health.is_downed())
	assert_eq(player.health.hp, 0.0)


func test_a_brute_cannot_land_the_same_swing_again() -> void:
	var player := _player()
	for _i in 4:
		player.apply_hit(BRUTE.damage, Vector3.ZERO)
	assert_true(player.health.is_downed(), "follow-through contacts are the same swing")
	assert_eq(player.health.hp, 0.0)


func test_a_walker_still_needs_more_than_one_swing() -> void:
	var player := _player()
	var walker := _zombie(WALKER)
	walker.ai.target = player
	walker.ai.land_melee(walker)
	assert_true(player.health.is_alive())
	assert_false(player.health.is_downed())
	assert_almost_eq(player.health.hp, player.health.max_hp - WALKER.damage, 0.01)


func test_a_walker_cannot_hit_you_on_a_high_platform() -> void:
	var player := _player()
	var walker := _zombie(WALKER)
	player.global_position = Vector3(0.0, 6.0, -1.0)
	walker.ai.target = player
	walker.ai.try_attack(walker)
	assert_false(walker.visual.is_meleeing())
	assert_false(walker.ai.melee_pending)
	walker.ai.land_melee(walker)
	assert_almost_eq(player.health.hp, player.health.max_hp, 0.01)


func test_a_walker_can_still_hit_you_on_a_low_step() -> void:
	var player := _player()
	var walker := _zombie(WALKER)
	player.global_position = Vector3(0.0, 1.0, -1.5)
	walker.ai.target = player
	walker.ai.land_melee(walker)
	assert_almost_eq(player.health.hp, player.health.max_hp - WALKER.damage, 0.01)


func test_melee_reach_needs_height_as_well_as_ground_distance() -> void:
	assert_true(Melee.in_reach(Vector3.ZERO, Vector3(0.0, 0.0, -1.5), 2.0))
	assert_true(Melee.in_reach(Vector3.ZERO, Vector3(0.0, 1.2, -1.5), 2.0))
	assert_false(Melee.in_reach(Vector3.ZERO, Vector3(0.0, 6.0, -1.0), 2.0))
	assert_false(Melee.in_reach(Vector3.ZERO, Vector3(0.0, 6.0, -1.0), 2.0 * 1.35))
	var origin := Vector3(0.0, 1.7, 0.0)
	var forward := Vector3(0.0, 0.0, -1.0)
	assert_true(Melee.in_arc(origin, forward, Vector3(0.0, 0.9, -2.0), Melee.RANGE, Melee.ARC_DEG))
	assert_false(Melee.in_arc(origin, forward, Vector3(0.0, 8.0, -1.0), Melee.RANGE, Melee.ARC_DEG))


func _player() -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 0.0, -1.5)
	return player


func _zombie(stats: ZombieStats) -> Zombie:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	zombie.stats = stats
	add_child_autofree(zombie)
	zombie.set_physics_process(false)
	zombie.global_position = Vector3.ZERO
	return zombie
