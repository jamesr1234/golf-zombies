extends GutTest
## Rocket blast is a sphere: everyone inside is hit, everyone outside is not.

const WALKER: ZombieStats = preload("res://resources/zombies/walker.tres")
const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")
const ROCKET: WeaponStats = preload("res://resources/weapons/rocket.tres")


func before_each() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)


func after_each() -> void:
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


func _zombie(root: Node, at: Vector3) -> Zombie:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	zombie.stats = WALKER
	root.add_child(zombie)
	zombie.global_position = at
	return zombie
