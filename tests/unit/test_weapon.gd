extends GutTest
## Shotgun pairs and rifle cadence. The wait after a pair is the old shotgun
## interval; the two shots inside a pair are the short gap.

const RIFLE: WeaponStats = preload("res://resources/weapons/rifle.tres")
const SHOTGUN: WeaponStats = preload("res://resources/weapons/shotgun.tres")
const SNIPER: WeaponStats = preload("res://resources/weapons/sniper.tres")
const ROCKET: WeaponStats = preload("res://resources/weapons/rocket.tres")
const NET: WeaponStats = preload("res://resources/weapons/net.tres")
const FLARE: WeaponStats = preload("res://resources/weapons/flare_driver.tres")
const NAILER: WeaponStats = preload("res://resources/weapons/cart_nailer.tres")
const DOOR: WeaponStats = preload("res://resources/weapons/warp_door.tres")
const REMOTE: WeaponStats = preload("res://resources/weapons/shape_remote.tres")


func test_the_rifle_still_waits_its_full_interval_after_every_shot() -> void:
	assert_eq(RIFLE.burst, 1)
	assert_almost_eq(Weapon.cooldown_after_shot(RIFLE, 0), RIFLE.shot_interval(), 0.0001)
	assert_eq(Weapon.pair_shots_after(RIFLE, 0), 0)


func test_the_shotgun_fires_two_quick_shots_then_waits() -> void:
	assert_eq(SHOTGUN.burst, 2)
	assert_almost_eq(Weapon.cooldown_after_shot(SHOTGUN, 0), SHOTGUN.burst_gap, 0.0001)
	assert_eq(Weapon.pair_shots_after(SHOTGUN, 0), 1)
	assert_almost_eq(Weapon.cooldown_after_shot(SHOTGUN, 1), SHOTGUN.shot_interval(), 0.0001)
	assert_eq(Weapon.pair_shots_after(SHOTGUN, 1), 0)
	assert_lt(SHOTGUN.burst_gap, SHOTGUN.shot_interval() * 0.4, "the pair should feel like a double tap")


func test_waiting_out_the_interval_gives_the_pair_back() -> void:
	assert_true(Weapon.pair_expired(SHOTGUN, 1, SHOTGUN.shot_interval()))
	assert_false(Weapon.pair_expired(SHOTGUN, 1, SHOTGUN.burst_gap))
	assert_false(Weapon.pair_expired(SHOTGUN, 0, SHOTGUN.shot_interval()))


func test_the_shotgun_can_dump_a_pair_then_must_wait() -> void:
	var gun := _gun()
	_hold(gun, SHOTGUN)
	var mag := gun.mag()
	_pull(gun)
	assert_eq(gun.mag(), mag - 1)
	_pull(gun)
	assert_eq(gun.mag(), mag - 1, "the second click is too soon")
	gun.tick(SHOTGUN.burst_gap, Transform3D.IDENTITY, false, true, false)
	assert_eq(gun.mag(), mag - 2, "the second barrel follows quickly")
	gun.tick(SHOTGUN.burst_gap, Transform3D.IDENTITY, false, true, false)
	assert_eq(gun.mag(), mag - 2, "after the pair you wait the old shotgun interval")
	gun.tick(SHOTGUN.shot_interval(), Transform3D.IDENTITY, false, true, false)
	assert_eq(gun.mag(), mag - 3)
	gun.tick(SHOTGUN.burst_gap, Transform3D.IDENTITY, false, true, false)
	assert_eq(gun.mag(), mag - 4, "another pair is waiting after the pause")


func test_a_lone_first_shot_does_not_spend_the_second_barrel() -> void:
	var gun := _gun()
	_hold(gun, SHOTGUN)
	var mag := gun.mag()
	_pull(gun)
	gun.tick(SHOTGUN.shot_interval(), Transform3D.IDENTITY, false, false, false)
	_pull(gun)
	assert_eq(gun.mag(), mag - 2)
	gun.tick(SHOTGUN.burst_gap, Transform3D.IDENTITY, false, true, false)
	assert_eq(gun.mag(), mag - 3, "after a long wait you still get two quick shots")


func test_a_boosted_shot_pays_the_scaled_damage() -> void:
	assert_almost_eq(Weapon.scaled_stats(RIFLE, 1.0).damage, RIFLE.damage, 0.001)
	var hot := Weapon.scaled_stats(RIFLE, 1.24)
	assert_almost_eq(hot.damage, RIFLE.damage * 1.24, 0.001)
	assert_almost_eq(RIFLE.damage, hot.damage / 1.24, 0.001)


func test_a_bought_gun_is_added_to_the_loadout() -> void:
	var gun := _gun()
	assert_false(gun.has_weapon())
	assert_true(gun.add_gun(ROCKET))
	assert_true(gun.has_gun(ROCKET))
	assert_eq(gun.stats(), ROCKET)
	assert_false(gun.add_gun(ROCKET), "owning it once is enough")
	var spare := WeaponStats.new()
	spare.display_name = "Spare"
	assert_true(gun.add_gun(spare))
	assert_eq(gun.stats(), spare)


func test_the_starter_stash_holds_every_gun() -> void:
	var gun := _gun()
	gun.fill_stash()
	assert_eq(gun.loadout.size(), Weapon.STARTER_GUNS.size())
	assert_eq(gun.stats(), RIFLE, "the rifle is first in the bag")
	for stats in Weapon.STARTER_GUNS:
		assert_true(gun.has_gun(stats), stats.display_name)
	gun.fill_stash()
	assert_eq(gun.loadout.size(), Weapon.STARTER_GUNS.size(), "filling twice does not duplicate")


func test_the_bag_starts_empty() -> void:
	var gun := _gun()
	assert_false(gun.has_weapon())
	assert_eq(gun.stats(), null)
	assert_eq(gun.mag(), 0)
	assert_eq(gun.reserve(), 0)
	gun.swap(1)
	assert_eq(gun.stats(), null)
	assert_true(gun.add_gun(RIFLE))
	assert_eq(gun.stats(), RIFLE)
	gun.swap(1)
	assert_eq(gun.stats(), RIFLE, "one gun cannot swap")
	assert_true(gun.add_gun(SHOTGUN))
	assert_eq(gun.stats(), SHOTGUN)
	gun.swap(1)
	assert_eq(gun.stats(), RIFLE)


func test_swapping_steps_forward_and_back_through_the_loadout() -> void:
	var gun := _gun()
	for stats in [FLARE, NAILER, NET, ROCKET, RIFLE, SHOTGUN, SNIPER, DOOR, REMOTE]:
		assert_true(gun.add_gun(stats))
	gun.index = 0
	assert_eq(gun.stats(), FLARE)
	gun.swap(1)
	assert_eq(gun.stats(), NAILER)
	gun.swap(1)
	assert_eq(gun.stats(), NET)
	gun.swap(1)
	assert_eq(gun.stats(), ROCKET)
	gun.swap(1)
	assert_eq(gun.stats(), RIFLE)
	gun.swap(1)
	assert_eq(gun.stats(), SHOTGUN)
	gun.swap(1)
	assert_eq(gun.stats(), SNIPER)
	gun.swap(1)
	assert_eq(gun.stats(), DOOR)
	gun.swap(1)
	assert_eq(gun.stats(), REMOTE)
	gun.swap(1)
	assert_eq(gun.stats(), FLARE)
	gun.swap(-1)
	assert_eq(gun.stats(), REMOTE)
	gun.swap(-1)
	assert_eq(gun.stats(), DOOR)
	gun.swap(-1)
	assert_eq(gun.stats(), SNIPER)


func test_the_warp_door_is_a_gun_you_can_add() -> void:
	var gun := _gun()
	assert_true(DOOR.is_door())
	assert_false(DOOR.is_net())
	assert_false(DOOR.is_explosive())
	assert_eq(DOOR.visual, "door")
	assert_true(gun.add_gun(DOOR))
	assert_true(gun.has_gun(DOOR))
	assert_false(gun.add_gun(DOOR), "owning it once is enough")


func test_the_shape_remote_is_a_gun_you_can_add() -> void:
	var gun := _gun()
	assert_true(REMOTE.is_drop())
	assert_false(REMOTE.is_net())
	assert_false(REMOTE.is_door())
	assert_eq(REMOTE.visual, "remote")
	assert_true(gun.add_gun(REMOTE))
	assert_true(gun.has_gun(REMOTE))
	assert_false(gun.add_gun(REMOTE), "owning it once is enough")


func test_the_warp_door_starts_in_the_bag() -> void:
	var gun := _gun()
	assert_true(gun.has_gun(DOOR))
	assert_true(DOOR.is_door())
	assert_false(DOOR.is_net())
	assert_false(DOOR.is_explosive())
	assert_eq(DOOR.visual, "door")
	assert_false(gun.add_gun(DOOR), "owning it once is enough")


func test_the_sniper_cycles_2x_5x_10x_then_hip() -> void:
	assert_true(SNIPER.has_scope())
	assert_eq(SNIPER.zoom_levels.size(), 3)
	assert_eq(Weapon.zoom_after(-1, SNIPER), 0)
	assert_almost_eq(SNIPER.zoom_at(0), 2.0, 0.001)
	assert_eq(Weapon.zoom_after(0, SNIPER), 1)
	assert_almost_eq(SNIPER.zoom_at(1), 5.0, 0.001)
	assert_eq(Weapon.zoom_after(1, SNIPER), 2)
	assert_almost_eq(SNIPER.zoom_at(2), 10.0, 0.001)
	assert_eq(Weapon.zoom_after(2, SNIPER), -1)
	assert_almost_eq(SNIPER.zoom_at(-1), 1.0, 0.001)
	assert_eq(Weapon.zoom_after(0, RIFLE), -1)


func test_swapping_off_the_sniper_drops_the_scope() -> void:
	var gun := _gun()
	_hold(gun, SNIPER)
	gun.add_gun(RIFLE)
	gun.index = gun.loadout.find(SNIPER)
	gun.cycle_zoom()
	assert_almost_eq(gun.zoom_mult(), 2.0, 0.001)
	gun.swap(1)
	assert_almost_eq(gun.zoom_mult(), 1.0, 0.001)
	assert_false(gun.is_scoped())


func test_the_flare_driver_marks_and_is_semi_auto() -> void:
	assert_true(FLARE.is_flare())
	assert_gt(FLARE.flare_mark, 5.0)
	assert_false(FLARE.automatic)
	assert_eq(FLARE.visual, "flare")
	assert_gt(FLARE.damage, RIFLE.damage)
	assert_lt(FLARE.rounds_per_minute, RIFLE.rounds_per_minute)


func test_the_cart_nailer_pays_extra_near_a_golf_cart() -> void:
	assert_true(NAILER.has_cart_bonus())
	assert_eq(NAILER.visual, "nailer")
	assert_true(NAILER.automatic)
	assert_lt(NAILER.damage, RIFLE.damage)
	assert_gt(NAILER.rounds_per_minute, RIFLE.rounds_per_minute)
	assert_false(Weapon.cart_bonus_applies(Vector3.ZERO, null, NAILER, null))
	var cart := Node3D.new()
	cart.add_to_group("golf_carts")
	add_child_autofree(cart)
	cart.global_position = Vector3(2.0, 0.0, 0.0)
	assert_true(Weapon.near_golf_cart(Vector3.ZERO, NAILER.cart_bonus_range, get_tree()))
	assert_true(Weapon.cart_bonus_applies(Vector3.ZERO, null, NAILER, get_tree()))
	assert_false(Weapon.near_golf_cart(Vector3(40.0, 0.0, 0.0), NAILER.cart_bonus_range, get_tree()))
	var gun := _gun()
	gun.power_mult = 1.0
	assert_almost_eq(gun.shot_damage(NAILER, Vector3.ZERO), NAILER.damage * NAILER.cart_damage_mult, 0.001)
	assert_almost_eq(gun.shot_damage(NAILER, Vector3(40.0, 0.0, 0.0)), NAILER.damage, 0.001)
	assert_almost_eq(gun.shot_damage(RIFLE, Vector3.ZERO), RIFLE.damage, 0.001)


func _gun() -> Weapon:
	var gun := Weapon.new()
	add_child_autofree(gun)
	return gun


func _hold(gun: Weapon, current: WeaponStats) -> void:
	if not gun.has_gun(current):
		gun.add_gun(current)
	gun.index = gun.loadout.find(current)
	assert_eq(gun.stats(), current)


func _pull(gun: Weapon) -> void:
	gun.tick(0.0, Transform3D.IDENTITY, false, true, false)
