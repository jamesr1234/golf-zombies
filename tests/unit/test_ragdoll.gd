extends GutTest
## Hit location picks a limb, that limb takes the spin, and a living hit
## ragdolls. Pure maths plus a built body, so it does not need a live hole.

const WALKER := preload("res://resources/zombies/walker.tres")
const STEP := 1.0 / 60.0
const ORIGIN := Vector3.ZERO
const HEIGHT := 1.8
const RADIUS := 0.42
const RIGHT := Vector3.RIGHT


func test_the_hit_spot_picks_the_limb() -> void:
	assert_almost_eq(Zombie.HEAD_RATIO, Ragdoll.HEAD_RATIO, 0.001)
	assert_eq(
		Ragdoll.region(Vector3(0.0, HEIGHT * 0.9, -0.2), ORIGIN, HEIGHT, RADIUS, RIGHT),
		Ragdoll.Region.HEAD
	)
	assert_eq(
		Ragdoll.region(Vector3(-0.25, HEIGHT * 0.18, -0.2), ORIGIN, HEIGHT, RADIUS, RIGHT),
		Ragdoll.Region.LEG_L
	)
	assert_eq(
		Ragdoll.region(Vector3(0.25, HEIGHT * 0.18, -0.2), ORIGIN, HEIGHT, RADIUS, RIGHT),
		Ragdoll.Region.LEG_R
	)
	assert_eq(
		Ragdoll.region(Vector3(0.38, HEIGHT * 0.55, -0.15), ORIGIN, HEIGHT, RADIUS, RIGHT),
		Ragdoll.Region.ARM_R
	)
	assert_eq(
		Ragdoll.region(Vector3(0.0, HEIGHT * 0.5, -0.2), ORIGIN, HEIGHT, RADIUS, RIGHT),
		Ragdoll.Region.TORSO
	)
	assert_eq(
		Ragdoll.region(Vector3.INF, ORIGIN, HEIGHT, RADIUS, RIGHT),
		Ragdoll.Region.TORSO,
		"a blast with no contact point still hits the chest"
	)


func test_a_planted_shot_keeps_the_hips_and_legs_quiet() -> void:
	var flying := Ragdoll.spins_for(Ragdoll.Region.HEAD, Vector3.FORWARD, 1.8)
	var planted := Ragdoll.spins_for(Ragdoll.Region.HEAD, Vector3.FORWARD, 1.8, true)
	assert_lt(planted[&"hips"].length(), flying[&"hips"].length() * 0.25)
	assert_lt(planted[&"leg_l"].length(), flying[&"leg_l"].length() * 0.3)
	assert_gt(planted[&"head"].length(), planted[&"hips"].length())


func test_a_head_shot_spins_the_skull_harder_than_the_chest() -> void:
	var head := Ragdoll.spins_for(Ragdoll.Region.HEAD, Vector3.FORWARD, 1.0)
	var chest := Ragdoll.spins_for(Ragdoll.Region.TORSO, Vector3.FORWARD, 1.0)
	assert_gt(
		head[&"head"].length(), chest[&"head"].length(),
		"a skull hit has to snap the head"
	)
	var left := Ragdoll.spins_for(Ragdoll.Region.ARM_L, Vector3.FORWARD, 1.0)
	var right := Ragdoll.spins_for(Ragdoll.Region.ARM_R, Vector3.FORWARD, 1.0)
	assert_gt(left[&"arm_l"].length(), left[&"arm_r"].length())
	assert_gt(right[&"arm_r"].length(), right[&"arm_l"].length())


func test_a_built_zombie_goes_limp_from_a_hit() -> void:
	var body := ZombieBody.new()
	add_child_autofree(body)
	body.build(WALKER)
	var rest := body.arms[0].rotation
	body.flop(Ragdoll.Region.ARM_L, Vector3.FORWARD, 1.8)
	assert_true(body.is_limp())
	for _frame in 8:
		body.tick_limp(STEP, true)
	assert_false(
		body.arms[0].rotation.is_equal_approx(rest),
		"the hit arm has to fly, not stay in the walk pose"
	)


func test_a_player_head_snaps_on_a_skull_hit() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	assert_not_null(body.head)
	var rest := body.head.rotation
	body.flop(Ragdoll.Region.HEAD, Vector3.FORWARD, 2.0)
	for _frame in 8:
		body.tick_limp(STEP, true)
	assert_false(body.head.rotation.is_equal_approx(rest), "the visor has to whip back")


func test_a_limp_recovers_but_a_downed_flop_stays_down() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.flop(Ragdoll.Region.TORSO, Vector3.FORWARD, 1.0)
	assert_true(body.is_limp())
	assert_false(body.is_locked_limp())
	body.tick_limp(Ragdoll.RECOVER + 0.05, false)
	assert_false(body.is_limp(), "a living hit has to stand back up")
	body.flop(Ragdoll.Region.TORSO, Vector3.FORWARD, 1.4, true)
	assert_true(body.is_locked_limp())
	body.tick_limp(2.0, false)
	assert_true(body.is_limp(), "a downed robot stays on the turf")
	assert_lt(body.hips.position.y, PlayerBody.HIP_HEIGHT, "the heap sits on the ground")
	assert_gt(body.hips.position.y, 0.5, "hips have to stay above the turf")


func test_a_grounded_flop_stays_on_the_turf() -> void:
	var body := ZombieBody.new()
	add_child_autofree(body)
	body.build(WALKER)
	body.flop(Ragdoll.Region.HEAD, Vector3.FORWARD, 2.6, true, true)
	for _frame in 40:
		body.tick_limp(STEP, false)
	assert_true(body.is_limp())
	assert_almost_eq(body.position.y, 0.0, 0.001, "shots must not lift the mesh off the turf")
	for mesh in body.meshes:
		var aabb := mesh.get_aabb()
		var xf := mesh.global_transform
		for i in 8:
			assert_gt(
				(xf * aabb.get_endpoint(i)).y, -0.05,
				"no piece of a ragdoll should sink under the floor"
			)


func test_a_shot_does_not_take_their_feet_off_the_turf() -> void:
	var zombie: Zombie = preload("res://scenes/zombies/zombie.tscn").instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	var skull := zombie.global_position + Vector3.UP * WALKER.height * 0.9
	zombie.take_damage(26.0, Vector3.FORWARD, skull)
	assert_false(zombie.is_launched(), "gunfire should shove, not throw")
	assert_true(zombie.velocity.y <= 0.001)
	zombie.take_damage(500.0, Vector3.FORWARD, skull)
	assert_true(zombie.is_dying())
	assert_false(zombie.is_launched(), "a gun kill should not throw them")
	assert_true(zombie.velocity.y <= 0.001)
