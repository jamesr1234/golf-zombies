extends GutTest
## A thrown net roots a whole pack. A rocket on anyone in that net wipes them.

const WALKER: ZombieStats = preload("res://resources/zombies/walker.tres")
const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")
const NET: WeaponStats = preload("res://resources/weapons/net.tres")
const ROCKET: WeaponStats = preload("res://resources/weapons/rocket.tres")


func before_each() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)


func after_each() -> void:
	for group in ["net_shots", "net_traps", "rockets", "fireworks"]:
		for node in get_tree().get_nodes_in_group(group):
			node.queue_free()


func test_the_net_is_a_giant_trap_not_an_explosive() -> void:
	assert_true(NET.is_net())
	assert_false(NET.is_explosive())
	assert_gt(NET.trap_radius, 15.0)
	assert_gt(NET.trap_duration, 5.0)
	assert_eq(NET.visual, "net")
	assert_false(NET.automatic)


func test_the_net_is_in_the_bag_once_you_pick_it_up() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	assert_false(gun.has_weapon())
	assert_true(gun.add_gun(NET))
	assert_true(gun.add_gun(ROCKET))
	assert_eq(gun.stats(), ROCKET)
	gun.swap(-1)
	assert_eq(gun.stats(), NET)


func test_the_reach_circle_has_a_hard_edge() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var zombie := _zombie(root, Vector3(20.0, 0.0, 0.0))
	assert_true(NetTrap.in_reach(Vector3.ZERO, zombie, 20.0))
	assert_false(NetTrap.in_reach(Vector3.ZERO, zombie, 19.9))


func test_a_net_roots_everyone_inside_the_radius() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var near_a := _zombie(root, Vector3.ZERO)
	var near_b := _zombie(root, Vector3(8.0, 0.0, 2.0))
	var far := _zombie(root, Vector3(40.0, 0.0, 0.0))
	var trap := NetTrap.deploy(root, Vector3.ZERO, 20.0, 10.0)
	assert_eq(trap.trapped_count(), 2)
	assert_true(near_a.is_netted())
	assert_true(near_b.is_netted())
	assert_eq(near_a.net_trap(), trap)
	assert_false(far.is_netted())


func test_a_netted_zombie_stops_moving() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var zombie := _zombie(root, Vector3.ZERO)
	zombie.velocity = Vector3(4.0, 0.0, 3.0)
	NetTrap.deploy(root, Vector3.ZERO, 20.0, 10.0)
	zombie._physics_process(0.016)
	assert_almost_eq(zombie.velocity.x, 0.0, 0.001)
	assert_almost_eq(zombie.velocity.z, 0.0, 0.001)
	assert_true(zombie.is_netted())


func test_the_net_expires_and_lets_them_go() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var zombie := _zombie(root, Vector3.ZERO)
	var trap := NetTrap.deploy(root, Vector3.ZERO, 20.0, 1.0)
	assert_true(zombie.is_netted())
	trap._physics_process(1.0)
	assert_false(zombie.is_netted())


func test_a_rocket_on_one_netted_zombie_destroys_the_whole_pack() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var near := _zombie(root, Vector3.ZERO)
	var packed := _zombie(root, Vector3(12.0, 0.0, 0.0))
	var free := _zombie(root, Vector3(40.0, 0.0, 0.0))
	NetTrap.deploy(root, Vector3.ZERO, 20.0, 10.0)
	assert_true(near.is_netted())
	assert_true(packed.is_netted())
	assert_false(Rocket.in_blast(12.0, 6.5), "the far netted one is outside the blast")
	var hits := Rocket.detonate(get_tree(), Vector3(0.0, 1.0, 0.0), 110.0, 6.5, root)
	assert_eq(hits, 1)
	assert_true(near.is_dying())
	assert_true(packed.is_dying(), "the rest of the net dies with the rocket hit")
	assert_false(free.is_dying())
	assert_gt(free.hp, 0.0)


func test_a_rocket_without_a_net_does_not_chain() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var near := _zombie(root, Vector3.ZERO)
	var packed := _zombie(root, Vector3(12.0, 0.0, 0.0))
	Rocket.detonate(get_tree(), Vector3(0.0, 1.0, 0.0), 110.0, 6.5, root)
	assert_true(near.is_dying())
	assert_false(packed.is_dying())
	assert_gt(packed.hp, 0.0)


func test_firing_the_net_spends_a_round_and_spawns_one() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	assert_true(gun.add_gun(NET))
	assert_eq(gun.stats(), NET)
	var before := get_tree().get_nodes_in_group("net_shots").size()
	gun.tick(0.0, Transform3D.IDENTITY, false, true, false)
	assert_eq(gun.mag(), NET.mag_size - 1)
	assert_eq(get_tree().get_nodes_in_group("net_shots").size(), before + 1)


func _zombie(root: Node, at: Vector3) -> Zombie:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	zombie.stats = WALKER
	root.add_child(zombie)
	zombie.global_position = at
	return zombie
