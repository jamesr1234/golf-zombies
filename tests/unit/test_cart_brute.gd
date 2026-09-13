extends GutTest
## Driving into a brute throws the cart. You have to fight it on foot.


const BRUTE := preload("res://resources/zombies/brute.tres")
const WALKER := preload("res://resources/zombies/walker.tres")
const RUNNER := preload("res://resources/zombies/runner.tres")
const GUNNER := preload("res://resources/zombies/gunner.tres")
const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")


func test_only_a_brute_shrugs_off_the_cart() -> void:
	assert_true(CartBrute.ignores_crush(BRUTE))
	assert_false(CartBrute.ignores_crush(WALKER))
	assert_false(CartBrute.ignores_crush(RUNNER))
	assert_false(CartBrute.ignores_crush(GUNNER))
	assert_false(CartBrute.ignores_crush(null))


func test_the_swat_throws_the_cart_off_the_brute() -> void:
	var away := CartBrute.away(Vector3.ZERO, Vector3(0.0, 1.0, 3.0), Vector3.FORWARD)
	assert_almost_eq(away.z, 1.0, 0.001)
	assert_eq(away.y, 0.0)
	var stacked := CartBrute.away(Vector3.ZERO, Vector3.ZERO, Vector3.BACK)
	assert_almost_eq(stacked.z, 1.0, 0.001)


func test_a_brute_swat_kills_drive_and_puts_the_cart_in_the_air() -> void:
	var cart := GolfCart.new()
	cart.position = Vector3(0.0, 0.0, 2.0)
	cart.drive_speed = 18.0
	var brute: Zombie = ZOMBIE_SCENE.instantiate()
	brute.stats = BRUTE
	add_child_autofree(brute)
	brute.global_position = Vector3.ZERO
	var hp := brute.hp
	assert_true(CartBrute.try_swat(cart, brute))
	assert_true(cart.is_flung())
	assert_eq(cart.drive_speed, 0.0)
	assert_gt(cart.velocity.y, 10.0, "the cart has to leave the turf")
	assert_gt(cart.velocity.z, 0.0, "away from the brute")
	assert_eq(brute.hp, hp, "the cart never pays")
	assert_true(brute.visual.is_meleeing())
	cart.free()


func test_a_walker_still_takes_the_cart() -> void:
	var cart := GolfCart.new()
	var walker: Zombie = ZOMBIE_SCENE.instantiate()
	walker.stats = WALKER
	add_child_autofree(walker)
	assert_false(CartBrute.try_swat(cart, walker))
	assert_false(cart.is_flung())
	cart.free()
