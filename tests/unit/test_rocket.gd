extends GutTest
## Rocket blast is a sphere: everyone inside is hit, everyone outside is not.

const WALKER: ZombieStats = preload("res://resources/zombies/walker.tres")
const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")
const CART_SCENE := preload("res://scenes/vehicles/golf_cart.tscn")
const ROCKET: WeaponStats = preload("res://resources/weapons/rocket.tres")


func before_each() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)


func after_each() -> void:
	GameSettings.reset()
	for group in ["rockets", "fireworks"]:
		for node in get_tree().get_nodes_in_group(group):
			node.queue_free()


func test_the_blast_sphere_has_a_hard_edge() -> void:
	assert_true(Rocket.in_blast(0.0, 6.5))
	assert_true(Rocket.in_blast(6.5, 6.5))
	assert_false(Rocket.in_blast(6.51, 6.5))


func test_the_rocket_is_an_explosive_single_shot() -> void:
	assert_true(ROCKET.is_explosive())
	assert_eq(ROCKET.mag_size, 1)
	assert_false(ROCKET.automatic)
	assert_gt(ROCKET.damage, 90.0)


func test_a_blast_drops_everyone_inside_the_radius() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var near_a := _zombie(root, Vector3.ZERO)
	var near_b := _zombie(root, Vector3(2.0, 0.0, 0.5))
	var far := _zombie(root, Vector3(20.0, 0.0, 0.0))
	var hits := Rocket.detonate(get_tree(), Vector3(0.0, 1.0, 0.0), 110.0, 6.5, root)
	assert_eq(hits, 2)
	assert_true(near_a.is_dying())
	assert_true(near_b.is_dying())
	assert_false(far.is_dying())
	assert_gt(far.hp, 0.0)


func test_a_blast_also_chips_a_mech() -> void:
	var mech: MechSuit = preload("res://scenes/course/items/mech_suit.tscn").instantiate()
	add_child_autofree(mech)
	await wait_physics_frames(1)
	mech.global_position = Vector3.ZERO
	var before := mech.hp
	Rocket.detonate(get_tree(), Vector3(0.0, 1.0, 0.0), 110.0, 6.5, self)
	assert_eq(mech.hp, before - 1)


func test_firing_the_rocket_spends_the_shell_and_spawns_one() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	assert_true(gun.add_gun(ROCKET))
	assert_true(gun.has_gun(ROCKET))
	var before := get_tree().get_nodes_in_group("rockets").size()
	gun.tick(0.0, Transform3D.IDENTITY, false, true, false)
	assert_eq(gun.mag(), 0)
	assert_eq(get_tree().get_nodes_in_group("rockets").size(), before + 1)


func test_the_flying_rocket_has_a_yellow_nose() -> void:
	var rocket := Rocket.spawn_flight(self, Vector3.ZERO, Vector3.FORWARD, 110.0, 6.5, 90.0)
	var nose := rocket.get_child(1) as MeshInstance3D
	assert_not_null(nose)
	assert_eq(nose.mesh.get_class(), "SphereMesh")
	assert_almost_eq(nose.material_override.albedo_color.r, Palette.AMBER.r, 0.01)
	assert_almost_eq(nose.material_override.albedo_color.g, Palette.AMBER.g, 0.01)
	rocket.free()


func test_rockets_stop_on_carts() -> void:
	assert_eq(Layers.ROCKET_MASK & Layers.VEHICLE, Layers.VEHICLE)
	assert_eq(Layers.BULLET_MASK & Layers.VEHICLE, 0, "hitscan still flies through the cabin")


func test_only_an_opposing_rocket_wrecks_a_cart() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	var cart := GolfCart.new()
	var foe := Player.new()
	var driver := Player.new()
	var partner := Player.new()
	driver.partner = partner
	partner.partner = driver
	cart.driver = driver
	assert_true(cart.hostile_rocket(foe))
	assert_false(cart.hostile_rocket(driver))
	assert_false(cart.hostile_rocket(partner))
	assert_false(cart.hostile_rocket(null))
	GameSettings.mode = GameSettings.Mode.SOLO
	assert_false(cart.hostile_rocket(foe), "no opposing players on a PvE hole")
	cart.free()
	foe.free()
	driver.free()
	partner.free()


func test_an_opposing_blast_blows_up_the_cart() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	var cart: GolfCart = CART_SCENE.instantiate()
	var foe := Player.new()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3.ZERO
	Rocket.detonate(get_tree(), Vector3(0.0, 1.0, 0.0), 110.0, 6.5, self, foe)
	assert_true(cart.is_wrecked())
	assert_false(cart.visible)
	foe.free()


func test_your_own_rocket_does_not_wreck_the_cart_you_are_in() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	var cart: GolfCart = CART_SCENE.instantiate()
	var driver := Player.new()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.driver = driver
	Rocket.detonate(get_tree(), Vector3(0.0, 1.0, 0.0), 110.0, 6.5, self, driver)
	assert_false(cart.is_wrecked())
	driver.free()


func test_a_solo_rocket_leaves_the_cart_up() -> void:
	var cart: GolfCart = CART_SCENE.instantiate()
	var player := Player.new()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	Rocket.detonate(get_tree(), Vector3(0.0, 1.0, 0.0), 110.0, 6.5, self, player)
	assert_false(cart.is_wrecked())
	player.free()


func test_a_rocket_aimed_at_an_enemy_cart_wrecks_it() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	var cart: GolfCart = CART_SCENE.instantiate()
	var foe := Player.new()
	add_child_autofree(cart)
	cart.set_physics_process(false)
	cart.global_position = Vector3(0.0, 0.0, -4.0)
	await wait_physics_frames(1)
	var rocket := Rocket.spawn_flight(self, Vector3(0.0, 0.8, 0.0), Vector3.FORWARD, 110.0, 6.5, 90.0)
	rocket.shooter = foe
	await wait_seconds(0.2)
	assert_true(cart.is_wrecked())
	foe.free()


func _zombie(root: Node, at: Vector3) -> Zombie:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	zombie.stats = WALKER
	root.add_child(zombie)
	zombie.global_position = at
	return zombie
