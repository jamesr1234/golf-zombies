extends GutTest
## A brute is heavy, but one swing cannot dump a full bar and end a solo run.

const BRUTE := preload("res://resources/zombies/brute.tres")
const WALKER := preload("res://resources/zombies/walker.tres")
const PLAYER_SCENE := preload("res://scenes/players/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")


func test_a_brute_swing_is_not_enough_to_down_you() -> void:
	assert_lt(BRUTE.damage, 100.0, "one club from a brute has to leave you standing")
	assert_gt(WALKER.damage, 0.0)
	assert_gt(BRUTE.damage, WALKER.damage)


func test_one_brute_contact_hurts_and_leaves_you_up() -> void:
	var player := _player()
	var brute := _zombie(BRUTE)
	brute.ai.target = player
	brute.ai.land_melee(brute)
	assert_true(player.health.is_alive())
	assert_false(player.health.is_downed())
	assert_almost_eq(player.health.hp, player.health.max_hp - BRUTE.damage, 0.01)


func test_a_brute_cannot_down_you_by_landing_the_same_swing_again() -> void:
	var player := _player()
	for _i in 4:
		player.apply_hit(BRUTE.damage, Vector3.ZERO)
	assert_true(player.health.is_alive(), "follow-through contacts are the same swing")
	assert_almost_eq(player.health.hp, player.health.max_hp - BRUTE.damage, 0.01)


func test_the_next_swing_can_hurt_again() -> void:
	var player := _player()
	player.apply_hit(BRUTE.damage, Vector3.ZERO)
	player.hit_fx.tick_flash(player, PlayerHitFx.HURT_LOCK)
	player.apply_hit(BRUTE.damage, Vector3.ZERO)
	assert_almost_eq(player.health.hp, player.health.max_hp - BRUTE.damage * 2.0, 0.01)
	assert_true(player.health.is_alive())


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
