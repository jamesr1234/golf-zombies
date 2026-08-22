extends GutTest
## How hard a hit shoves a zombie. Pure maths, so it can be checked without
## standing a horde up.

const WALKER_RESISTANCE := 1.0
const BRUTE_RESISTANCE := 2.8


func test_a_hit_shoves_the_zombie_the_way_the_bullet_was_going() -> void:
	var push := Zombie.knockback(Vector3.FORWARD, 24.0, WALKER_RESISTANCE)
	assert_almost_eq(push.normalized().dot(Vector3.FORWARD), 1.0, 0.001)
	assert_gt(push.length(), 2.0, "the bounce has to be worth seeing")


func test_a_shot_from_above_still_shoves_sideways_not_downwards() -> void:
	var push := Zombie.knockback(Vector3(0.0, -0.9, -0.4).normalized(), 24.0, WALKER_RESISTANCE)
	assert_eq(push.y, 0.0)
	assert_gt(push.length(), 2.0, "aiming down should not soak up the push")


func test_a_bigger_hit_shoves_harder() -> void:
	var light := Zombie.knockback(Vector3.FORWARD, 8.0, WALKER_RESISTANCE)
	var heavy := Zombie.knockback(Vector3.FORWARD, 60.0, WALKER_RESISTANCE)
	assert_gt(heavy.length(), light.length())


func test_a_brute_barely_moves() -> void:
	var walker := Zombie.knockback(Vector3.FORWARD, 24.0, WALKER_RESISTANCE)
	var brute := Zombie.knockback(Vector3.FORWARD, 24.0, BRUTE_RESISTANCE)
	assert_lt(brute.length(), walker.length() * 0.5)


func test_a_hit_with_no_direction_does_not_move_anything() -> void:
	assert_eq(Zombie.knockback(Vector3.ZERO, 24.0, WALKER_RESISTANCE), Vector3.ZERO)


func test_a_shotgun_full_of_pellets_cannot_launch_a_zombie() -> void:
	var pellet := Zombie.knockback(Vector3.FORWARD, 11.0, WALKER_RESISTANCE)
	var total := Vector3.ZERO
	for i in 9:
		total = Zombie.stack_knockback(total, pellet, WALKER_RESISTANCE)
	assert_almost_eq(total.length(), Zombie.MAX_KNOCKBACK, 0.001)


func test_sustained_fire_pins_a_walker_but_never_stops_a_brute() -> void:
	var walker := Vector3.ZERO
	var brute := Vector3.ZERO
	for i in 30:
		walker = Zombie.stack_knockback(
			walker, Zombie.knockback(Vector3.FORWARD, 24.0, WALKER_RESISTANCE), WALKER_RESISTANCE
		)
		brute = Zombie.stack_knockback(
			brute, Zombie.knockback(Vector3.FORWARD, 24.0, BRUTE_RESISTANCE), BRUTE_RESISTANCE
		)
	assert_eq(Zombie.walk_scale(walker.length()), 0.0, "holding fire on a walker holds it off")
	assert_gt(Zombie.walk_scale(brute.length()), 0.5, "a brute keeps coming regardless")


func test_a_fresh_hit_interrupts_the_walk() -> void:
	assert_eq(Zombie.walk_scale(0.0), 1.0, "unhurt zombies walk at full speed")
	var walker_hit := Zombie.knockback(Vector3.FORWARD, 24.0, WALKER_RESISTANCE)
	assert_lt(Zombie.walk_scale(walker_hit.length()), 0.7, "being shot has to break its stride")
	assert_eq(Zombie.walk_scale(Zombie.MAX_KNOCKBACK), 0.0, "a full blast stops it dead")


func test_walkers_start_a_little_faster_than_a_shuffle() -> void:
	var walker: ZombieStats = preload("res://resources/zombies/walker.tres")
	var runner: ZombieStats = preload("res://resources/zombies/runner.tres")
	assert_gt(walker.speed, 3.0, "green walkers should close ground on hole one")
	assert_lt(walker.speed, runner.speed, "they still should not outrun the pink ones")


func test_walking_on_a_slope_follows_the_turf() -> void:
	var wish := Vector3(0.0, 0.0, -3.4)
	var flat := Zombie.ground_velocity(wish, Vector3.UP)
	assert_almost_eq(flat.x, wish.x, 0.001)
	assert_almost_eq(flat.z, wish.z, 0.001)
	assert_almost_eq(flat.y, 0.0, 0.001)
	var uphill := Vector3(0.0, 1.0, 1.0).normalized()
	var along := Zombie.ground_velocity(wish, uphill)
	assert_gt(along.y, 0.15, "they have to climb instead of driving into the face")
	assert_almost_eq(along.length(), wish.length(), 0.001)
	assert_lt(absf(along.dot(uphill)), 0.001, "motion stays on the plane")


func test_a_zombie_snaps_to_the_floor_instead_of_bouncing() -> void:
	var zombie: Zombie = preload("res://scenes/zombies/zombie.tscn").instantiate()
	zombie.stats = preload("res://resources/zombies/walker.tres")
	add_child_autofree(zombie)
	assert_almost_eq(zombie.floor_snap_length, Zombie.FLOOR_SNAP, 0.001)
	assert_almost_eq(zombie.floor_max_angle, deg_to_rad(Zombie.FLOOR_MAX_DEG), 0.001)
	assert_gt(zombie.floor_max_angle, deg_to_rad(50.0), "mounds must count as floor, not walls")


func test_a_brute_keeps_walking_through_a_hit() -> void:
	var brute_hit := Zombie.knockback(Vector3.FORWARD, 24.0, BRUTE_RESISTANCE)
	assert_gt(Zombie.walk_scale(brute_hit.length()), 0.75)


func test_stacked_hits_still_add_up_below_the_cap() -> void:
	var pellet := Zombie.knockback(Vector3.FORWARD, 11.0, BRUTE_RESISTANCE)
	var one := Zombie.stack_knockback(Vector3.ZERO, pellet, BRUTE_RESISTANCE)
	var two := Zombie.stack_knockback(one, pellet, BRUTE_RESISTANCE)
	assert_gt(two.length(), one.length())
	assert_lt(two.length(), Zombie.MAX_KNOCKBACK)


func test_a_head_hit_launches_higher_than_a_knee_hit() -> void:
	var origin := Vector3(0.0, 1.4, 2.0)
	var body := Vector3.ZERO
	var head := Melee.hit_point(origin + Vector3.UP * 0.4, body, 1.8, 0.42)
	var knee := Melee.hit_point(origin - Vector3.UP * 1.0, body, 1.8, 0.42)
	assert_gt(Melee.hit_height(head, body, 1.8), Melee.hit_height(knee, body, 1.8))
	var high := Melee.impulse(origin + Vector3.UP * 0.4, head, body, 1.8, WALKER_RESISTANCE)
	var low := Melee.impulse(origin - Vector3.UP * 1.0, knee, body, 1.8, WALKER_RESISTANCE)
	assert_gt(high.y, low.y, "a blow to the head should pop them up")
	assert_gt(low.length(), 10.0, "even a low hit still throws them")
	var high_flat := Vector3(high.x, 0.0, high.z)
	var low_flat := Vector3(low.x, 0.0, low.z)
	assert_gt(low_flat.length(), high_flat.length(), "a low blow should send them sliding")


func test_a_blow_off_to_the_side_kicks_that_way() -> void:
	var origin := Vector3(0.0, 1.0, 2.0)
	var body := Vector3.ZERO
	var left := Vector3(-0.4, 1.0, 0.3)
	var right := Vector3(0.4, 1.0, 0.3)
	var shove_left := Melee.impulse(origin, left, body, 1.8, WALKER_RESISTANCE)
	var shove_right := Melee.impulse(origin, right, body, 1.8, WALKER_RESISTANCE)
	assert_lt(shove_left.x, shove_right.x, "hitting the left side should send them left")


func test_a_drunk_shove_throws_further() -> void:
	var origin := Vector3(0.0, 1.2, 2.0)
	var body := Vector3.ZERO
	var hit := Melee.hit_point(origin, body, 1.8, 0.42)
	var sober := Melee.impulse(origin, hit, body, 1.8, WALKER_RESISTANCE)
	var drunk := Melee.impulse(origin, hit, body, 1.8, WALKER_RESISTANCE, 1.36)
	assert_gt(drunk.length(), sober.length())
	assert_almost_eq(drunk.length() / sober.length(), 1.36, 0.001)


func test_melee_throws_a_zombie_much_further_than_a_bullet() -> void:
	var origin := Vector3(0.0, 1.2, 2.0)
	var body := Vector3.ZERO
	var hit := Melee.hit_point(origin, body, 1.8, 0.42)
	var melee := Melee.impulse(origin, hit, body, 1.8, WALKER_RESISTANCE)
	var bullet := Zombie.knockback(Vector3.BACK, 24.0, WALKER_RESISTANCE)
	assert_gt(melee.length(), bullet.length() * 2.0)


func test_a_gun_kill_bursts_without_ragdoll() -> void:
	var zombie: Zombie = preload("res://scenes/zombies/zombie.tscn").instantiate()
	zombie.stats = preload("res://resources/zombies/walker.tres")
	add_child_autofree(zombie)
	zombie.take_damage(500.0, Vector3.FORWARD)
	assert_true(zombie.is_dying())
	assert_false(zombie.visual.is_limp(), "a killing shot should skip the ragdoll")
	assert_gt(get_tree().get_nodes_in_group("fireworks").size(), 0, "the burst should be in the world")


func test_a_melee_kill_is_still_airborne_when_the_fireworks_go() -> void:
	assert_almost_eq(Zombie.MELEE_EXPLODE_DELAY, 1.0, 0.001)
	var t := Zombie.MELEE_EXPLODE_DELAY
	var height := Zombie.MELEE_SKY_LIFT * t - 0.5 * 9.8 * t * t
	assert_gt(height, 6.0, "the burst has to happen in the air, not on the turf")


func test_fireworks_burst_outward_and_up() -> void:
	var first := Fireworks.spark_velocity(0, Fireworks.SPARK_COUNT)
	var last := Fireworks.spark_velocity(Fireworks.SPARK_COUNT - 1, Fireworks.SPARK_COUNT)
	assert_gt(first.length(), 18.0, "the shell should throw sparks a long way")
	assert_ne(first.normalized().dot(last.normalized()), 1.0, "sparks should not all fly the same way")
	var up := 0.0
	for i in Fireworks.SPARK_COUNT:
		up += Fireworks.spark_velocity(i, Fireworks.SPARK_COUNT).y
	assert_gt(up, 0.0, "the burst should read as fireworks, not a puddle")


func test_a_burst_is_a_loud_show() -> void:
	assert_gt(Fireworks.SPARK_COUNT + Fireworks.STREAK_COUNT, 40)
	assert_gt(Fireworks.LIFE, 1.4)
	var root := Node3D.new()
	add_child_autofree(root)
	var burst := Fireworks.spawn(root, Vector3.ZERO, Palette.LIME)
	assert_not_null(burst)
	assert_gt(burst.piece_count(), 40, "a pop should fill the sky, not a handful of cubes")
	assert_gt(burst.get_child_count(), 40)


func test_hit_push_slides_away_from_the_attacker() -> void:
	var push := Player.hit_push(Vector3(0.0, 1.0, -2.0), Vector3.ZERO)
	assert_gt(push.z, 2.0, "a hit from in front knocks them back")
	assert_eq(push.y, 0.0, "the shove stays on the turf")
	assert_eq(Player.hit_push(Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
