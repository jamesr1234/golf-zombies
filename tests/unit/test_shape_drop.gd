extends GutTest
## Shape Remote rains a crate pile you can L1 off the lie.

const REMOTE: WeaponStats = preload("res://resources/weapons/shape_remote.tres")
const Drop := preload("res://scripts/player/shape_drop.gd")


func before_each() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)


func after_each() -> void:
	for group in [Drop.GROUP, Drop.PILE_GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			node.queue_free()


func test_the_shape_remote_is_a_drop_not_a_net_or_door() -> void:
	assert_true(REMOTE.is_drop())
	assert_false(REMOTE.is_net())
	assert_false(REMOTE.is_door())
	assert_false(REMOTE.is_explosive())
	assert_eq(REMOTE.visual, "remote")
	assert_eq(REMOTE.drop_count, 30)
	assert_false(REMOTE.automatic)
	assert_eq(REMOTE.mag_size, 1)


func test_rain_dumps_thirty_prop_crates_around_the_aim() -> void:
	var at := Vector3(4.0, 0.0, -6.0)
	var pile := Drop.rain(self, at, Drop.COUNT, 7)
	assert_not_null(pile)
	var crates := get_tree().get_nodes_in_group(Drop.GROUP)
	assert_eq(crates.size(), 30)
	for node in crates:
		var crate := node as RigidBody3D
		assert_not_null(crate)
		assert_eq(crate.collision_layer, Layers.PROP)
		var flat := Vector3(crate.global_position.x - at.x, 0.0, crate.global_position.z - at.z)
		assert_lt(flat.length(), Drop.SCATTER + 0.05)
		assert_gt(crate.global_position.y, at.y + Drop.FALL_MIN - 0.05)
		assert_almost_eq(crate.gravity_scale, Drop.GRAVITY_SCALE, 0.01)
		assert_almost_eq(_crate_size(crate), Drop.SIZE, 0.5)


func test_a_third_dump_drops_the_oldest_pile() -> void:
	var first := Drop.rain(self, Vector3.ZERO, 4, 1)
	var second := Drop.rain(self, Vector3(2.0, 0.0, 0.0), 4, 2)
	assert_true(is_instance_valid(first))
	assert_true(is_instance_valid(second))
	Drop.rain(self, Vector3(4.0, 0.0, 0.0), 4, 3)
	await wait_idle_frames(1)
	assert_false(is_instance_valid(first), "only two piles stay live")
	assert_true(is_instance_valid(second))
	assert_eq(get_tree().get_nodes_in_group(Drop.PILE_GROUP).size(), 2)


func test_melee_yeets_a_crate_clear_of_the_lie() -> void:
	var crate := Drop.spawn_one(self, Vector3(0.0, 0.5, -1.4), 0)
	await wait_physics_frames(2)
	var melee := Melee.new()
	add_child_autofree(melee)
	assert_true(melee.shove(Vector3.ZERO, Vector3.FORWARD))
	assert_gt(crate.linear_velocity.length(), 20.0)
	assert_lt(crate.linear_velocity.z, -10.0, "L1 sends it the way you shoved")
	assert_gt(crate.linear_velocity.y, 4.0)


func test_firing_the_remote_spends_a_round_and_rains() -> void:
	var gun := Weapon.new()
	add_child_autofree(gun)
	assert_true(gun.add_gun(REMOTE))
	assert_eq(gun.stats(), REMOTE)
	var before := get_tree().get_nodes_in_group(Drop.GROUP).size()
	gun.tick(0.0, Transform3D.IDENTITY, false, true, false)
	assert_eq(gun.mag(), REMOTE.mag_size - 1)
	assert_eq(get_tree().get_nodes_in_group(Drop.GROUP).size(), before + 30)
	assert_eq(Sfx.last_cue, "remote_fire")


func _crate_size(crate: RigidBody3D) -> float:
	for child in crate.get_children():
		var col := child as CollisionShape3D
		if col == null or col.shape == null:
			continue
		if col.shape is BoxShape3D:
			return (col.shape as BoxShape3D).size.x
		if col.shape is CylinderShape3D:
			return (col.shape as CylinderShape3D).height
	return 0.0
