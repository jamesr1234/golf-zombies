extends GutTest
## Bought beers sit in inventory until you scroll onto them. Circle drinks,
## R2 throws, and a hit zombie joins your side after it finishes the can.

const PLAYER := preload("res://scenes/players/player.tscn")
const ZOMBIE := preload("res://scenes/zombies/zombie.tscn")
const WALKER := preload("res://resources/zombies/walker.tres")
const _BeerCan := preload("res://scripts/player/beer_can.gd")
const _ThrownBeer := preload("res://scripts/player/thrown_beer.gd")


func test_allies_hunt_hostiles_and_hostiles_hunt_everyone_else() -> void:
	assert_true(Zombie.hunts(true, false, false), "converted zombies fight the rest of the horde")
	assert_false(Zombie.hunts(true, true, false), "they do not turn on the players")
	assert_false(Zombie.hunts(true, false, true), "they do not fight other converts")
	assert_true(Zombie.hunts(false, true, false))
	assert_true(Zombie.hunts(false, false, true), "the horde treats converts as enemies")
	assert_false(Zombie.hunts(false, false, false))


func test_a_bought_beer_is_not_in_hand_until_you_scroll_to_it() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.buzz.take()
	assert_false(player.is_holding_beer())
	assert_false(player.chug(), "Circle does nothing until the can is selected")
	assert_eq(player.buzz.held, 1)
	player.weapon.index = player.weapon.loadout.size() - 1
	player._cycle_held(1)
	assert_true(player.is_holding_beer())
	player._animate(1.0 / 60.0)
	assert_true(player._beer.visible)
	assert_false(player.raygun.visible)
	assert_true(player.chug())
	assert_eq(player.buzz.held, 0)
	assert_eq(player.buzz.active(), 1)
	assert_true(player._beer.is_busy())


func test_scrolling_off_beer_puts_the_rifle_back() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.buzz.take()
	player.weapon.index = player.weapon.loadout.size() - 1
	player._cycle_held(1)
	assert_true(player.is_holding_beer())
	player._cycle_held(1)
	assert_false(player.is_holding_beer())
	assert_eq(player.weapon.index, 0)


func test_a_throw_spends_a_can_without_starting_a_buzz() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.buzz.take(2)
	player.weapon.index = player.weapon.loadout.size() - 1
	player._cycle_held(1)
	assert_true(player.throw_beer())
	assert_eq(player.buzz.held, 1)
	assert_eq(player.buzz.active(), 0)
	assert_eq(fx.get_child_count(), 1)


func test_the_can_is_grey_with_blue_writing() -> void:
	var can := _BeerCan.create()
	add_child_autofree(can)
	var copies := can.find_children("*", "Label3D", true, false)
	assert_eq(copies.size(), 1)
	var copy := copies[0] as Label3D
	assert_eq(copy.text, "beer")
	assert_eq(copy.modulate, Palette.BEER_INK)
	assert_gt(copy.position.z, 0.0, "the print sits on the camera-facing wall")
	assert_almost_eq(
		copy.rotation.y, 0.0, 0.01,
		"Label3D reads from +Z; spinning it hides the word in the can"
	)
	var paints: Array[Color] = []
	for child in can.find_children("*", "MeshInstance3D", true, false):
		var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null:
			paints.append(mat.albedo_color)
	assert_true(paints.has(Palette.BEER_CAN))
	assert_true(paints.has(Palette.BEER_INK))
	assert_true(paints.has(Palette.BEER_LID))
	assert_false(paints.has(Palette.BEER), "the held can is aluminium, not gold")


func test_a_sip_tips_the_opening_toward_the_camera() -> void:
	var can := _BeerCan.create()
	add_child_autofree(can)
	can.drink()
	can.animate(_BeerCan.DRINK_TIME * 0.4, true)
	assert_gt(
		can.rotation.x, 0.4,
		"the opening has to come toward the player, not pour away from them"
	)
	assert_almost_eq(can.rotation.y, 0.0, 0.05)


func test_a_zombie_catches_a_beer_then_fights_for_you() -> void:
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	assert_true(zombie.can_catch())
	assert_true(zombie.catch_beer())
	assert_true(zombie.is_drinking())
	assert_false(zombie.is_allied())
	assert_false(zombie.can_catch(), "they only take one can")
	zombie._sip(Zombie.DRINK_TIME * 0.4)
	assert_gt(
		rad_to_deg(zombie.visual.arms[1].rotation.x), 90.0,
		"they raise the can to their mouth while sipping"
	)
	zombie._sip(Zombie.DRINK_TIME)
	assert_true(zombie.is_allied())
	assert_true(zombie.is_in_group("allies"))
	assert_not_null(zombie.visual._ally_cap)
	var cheer := zombie.visual.get_node_or_null("Cheer") as Label3D
	assert_not_null(cheer, "they say delicious after the sip")
	assert_eq(cheer.text, "delicious!")
	var timer := cheer.get_child(0) as Timer
	assert_not_null(timer)
	assert_almost_eq(timer.wait_time, ZombieBody.CHEER_TIME, 0.01)
	assert_false(timer.is_stopped())
	var hp := zombie.hp
	zombie.melee_hit(Vector3(0.0, 1.0, 2.0))
	assert_eq(zombie.hp, hp, "player melee does not pop a convert")
	assert_true(zombie.is_allied())


func test_a_convert_pops_hostiles_with_the_player_shove() -> void:
	var ally: Zombie = ZOMBIE.instantiate()
	ally.stats = WALKER
	add_child_autofree(ally)
	var foe: Zombie = ZOMBIE.instantiate()
	foe.stats = WALKER
	add_child_autofree(foe)
	ally.catch_beer()
	ally._sip(Zombie.DRINK_TIME)
	assert_true(ally.is_allied())
	ally.global_position = Vector3.ZERO
	foe.global_position = Vector3(0.0, 0.0, -1.5)
	ally._target = foe
	ally._ally_shove()
	assert_true(foe.is_dying() or foe.is_launched(), "the convert uses the fireworks melee")
	assert_true(ally.visual.is_meleeing())
	assert_false(ally.is_dying())


func test_a_flying_can_picks_the_nearest_catcher() -> void:
	var near: Zombie = ZOMBIE.instantiate()
	near.stats = WALKER
	add_child_autofree(near)
	near.global_position = Vector3(0.0, 0.0, -1.0)
	var far: Zombie = ZOMBIE.instantiate()
	far.stats = WALKER
	add_child_autofree(far)
	far.global_position = Vector3(0.0, 0.0, -8.0)
	var catcher := _ThrownBeer.catcher_near(get_tree(), Vector3(0.0, 1.0, -1.0))
	assert_eq(catcher, near)
	near.catch_beer()
	near._sip(Zombie.DRINK_TIME)
	assert_null(_ThrownBeer.catcher_near(get_tree(), Vector3(0.0, 1.0, -1.0)), "allies do not recatch")
