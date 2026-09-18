extends GutTest
## Driving into a brute wrecks every ride. You walk away; the cart does not.


const BRUTE := preload("res://resources/zombies/brute.tres")
const WALKER := preload("res://resources/zombies/walker.tres")
const RUNNER := preload("res://resources/zombies/runner.tres")
const GUNNER := preload("res://resources/zombies/gunner.tres")
const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")
const PLAYER_SCENE := preload("res://scenes/players/player.tscn")
const CART_SCENE := preload("res://scenes/vehicles/golf_cart.tscn")
const RACE := preload("res://scenes/vehicles/race_car.tscn")
const WAGON := preload("res://scenes/vehicles/station_wagon.tscn")
const TRUCK := preload("res://scenes/vehicles/pickup_truck.tscn")
const VAN := preload("res://scenes/vehicles/panel_van.tscn")
const SUV := preload("res://scenes/vehicles/suv.tscn")


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


func test_a_brute_swat_wrecks_the_cart() -> void:
	var cart := GolfCart.new()
	cart.position = Vector3(0.0, 0.0, 2.0)
	cart.drive_speed = 18.0
	var brute: Zombie = ZOMBIE_SCENE.instantiate()
	brute.stats = BRUTE
	add_child_autofree(brute)
	brute.global_position = Vector3.ZERO
	var hp := brute.hp
	assert_true(CartBrute.try_swat(cart, brute))
	assert_true(cart.is_wrecked())
	assert_false(cart.visible)
	assert_eq(cart.drive_speed, 0.0)
	assert_eq(brute.hp, hp, "the cart never pays")
	assert_true(brute.visual.is_meleeing())
	assert_false(CartBrute.try_swat(cart, brute), "already gone")
	cart.free()


func test_every_body_style_goes_the_same_way() -> void:
	for packed in [CART_SCENE, RACE, WAGON, TRUCK, VAN, SUV]:
		var cart: GolfCart = packed.instantiate()
		add_child_autofree(cart)
		cart.armored = true
		cart.ram_plate = true
		var brute := _brute_at(Vector3.ZERO)
		assert_true(CartBrute.try_swat(cart, brute), packed.resource_path)
		assert_true(cart.is_wrecked(), packed.resource_path)
		assert_false(cart.visible)


func test_a_walker_still_takes_the_cart() -> void:
	var cart := GolfCart.new()
	var walker: Zombie = ZOMBIE_SCENE.instantiate()
	walker.stats = WALKER
	add_child_autofree(walker)
	assert_false(CartBrute.try_swat(cart, walker))
	assert_false(cart.is_wrecked())
	cart.free()


func test_running_into_a_brute_ejects_you_unharmed_and_kills_the_cart() -> void:
	var cart: GolfCart = CART_SCENE.instantiate()
	add_child_autofree(cart)
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	await wait_frames(1)
	player.set_physics_process(false)
	cart.global_position = Vector3(0.0, 0.0, 2.0)
	player.global_position = cart.global_position
	cart.board(player)
	assert_true(player.is_riding())
	var hp := player.health.hp
	var brute := _brute_at(Vector3.ZERO)
	assert_true(CartBrute.try_swat(cart, brute))
	assert_false(player.is_riding())
	assert_true(player.health.is_alive())
	assert_false(player.health.is_downed())
	assert_eq(player.health.hp, hp)
	assert_gt(player.motion.fling_left, 0.0)
	assert_gt(player.velocity.y, 10.0, "clubbed into the air")
	assert_true(cart.is_wrecked())
	assert_false(cart.can_board(player))


func test_a_brute_melee_on_a_rider_wrecks_the_cart_instead_of_hurting_them() -> void:
	var cart: GolfCart = CART_SCENE.instantiate()
	add_child_autofree(cart)
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	await wait_frames(1)
	player.set_physics_process(false)
	cart.global_position = Vector3.ZERO
	player.global_position = Vector3.ZERO
	cart.board(player)
	var brute := _brute_at(Vector3(0.0, 0.0, -1.0))
	brute.ai.target = player
	brute.ai.land_melee(brute)
	assert_true(cart.is_wrecked())
	assert_false(player.is_riding())
	assert_true(player.health.is_alive())
	assert_eq(player.health.hp, player.health.max_hp)


func test_a_wrecked_cart_comes_back_on_the_next_hole() -> void:
	var cart := GolfCart.new()
	cart.sync_wrecked = true
	assert_true(cart.is_wrecked())
	cart.recover_at(Vector3(4.0, 0.4, -8.0), 90.0)
	assert_false(cart.is_wrecked())
	assert_true(cart.visible)
	cart.free()


func _brute_at(at: Vector3) -> Zombie:
	var brute: Zombie = ZOMBIE_SCENE.instantiate()
	brute.stats = BRUTE
	add_child_autofree(brute)
	brute.set_physics_process(false)
	brute.global_position = at
	return brute
