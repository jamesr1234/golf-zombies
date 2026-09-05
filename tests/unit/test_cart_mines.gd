extends GutTest
## Passenger mine rack: five on every ride, D-pad down selects, R2 dumps them
## off the tail, and a walker on the puck pays the blast.

const CART := preload("res://scenes/vehicles/golf_cart.tscn")
const PLAYER := preload("res://scenes/players/player.tscn")
const ZOMBIE := preload("res://scenes/zombies/zombie.tscn")
const WALKER := preload("res://resources/zombies/walker.tres")
const RACE := preload("res://scenes/vehicles/race_car.tscn")


func after_each() -> void:
	for node in get_tree().get_nodes_in_group(CartMine.GROUP):
		node.queue_free()


func test_every_fresh_cart_is_loaded_with_five() -> void:
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	assert_eq(cart.mines, 5)
	assert_eq(cart.mines, CartMines.LOAD)


func test_the_passenger_selects_mines_with_dpad_down() -> void:
	var packed := _ride()
	var driver: Player = packed[0]
	var passenger: Player = packed[1]
	var cart: GolfCart = packed[2]
	assert_false(driver.mine_kit.can_select(driver), "the driver is on the boost")
	driver._cycle_held(1)
	assert_false(driver.is_holding_mines())
	passenger._cycle_held(1)
	assert_true(passenger.is_holding_mines())
	assert_eq(cart.passenger, passenger)


func test_dpad_down_again_puts_the_gun_back() -> void:
	var packed := _ride()
	var passenger: Player = packed[1]
	passenger._cycle_held(1)
	assert_true(passenger.is_holding_mines())
	passenger._cycle_held(1)
	assert_false(passenger.is_holding_mines())


func test_the_driver_cannot_dump_the_rack() -> void:
	var packed := _ride()
	var driver: Player = packed[0]
	var cart: GolfCart = packed[2]
	driver.holding_mines = true
	assert_false(driver.drop_mine())
	assert_eq(cart.mines, CartMines.LOAD)


func test_r2_drops_a_mine_behind_the_cart() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)
	var packed := _ride()
	var passenger: Player = packed[1]
	var cart: GolfCart = packed[2]
	cart.global_position = Vector3(0.0, 0.4, 0.0)
	cart.rotation = Vector3.ZERO
	passenger._cycle_held(1)
	assert_true(passenger.drop_mine())
	assert_eq(cart.mines, CartMines.LOAD - 1)
	assert_eq(fx.get_child_count(), 1)
	var mine := fx.get_child(0) as CartMine
	assert_not_null(mine)
	assert_gt(mine.global_position.z, cart.global_position.z, "off the tail, not the nose")
	assert_true(passenger.is_holding_mines(), "stay on mines so the next R2 dumps another")


func test_the_fifth_drop_empties_the_rack() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)
	var packed := _ride()
	var passenger: Player = packed[1]
	var cart: GolfCart = packed[2]
	passenger._cycle_held(1)
	for _i in CartMines.LOAD:
		assert_true(passenger.drop_mine())
	assert_eq(cart.mines, 0)
	assert_false(passenger.is_holding_mines(), "empty rack puts the gun back")
	assert_false(passenger.drop_mine())
	assert_eq(fx.get_child_count(), CartMines.LOAD)


func test_a_new_hole_restocks_and_a_crash_does_not() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)
	var packed := _ride()
	var passenger: Player = packed[1]
	var cart: GolfCart = packed[2]
	passenger._cycle_held(1)
	assert_true(passenger.drop_mine())
	cart.recover_at(Vector3(2.0, 0.4, 2.0), 0.0)
	assert_eq(cart.mines, CartMines.LOAD - 1, "a crash keeps what you have left")
	cart.place_at(Vector3(4.0, 0.4, 4.0), 90.0)
	assert_eq(cart.mines, CartMines.LOAD)


func test_a_walker_on_the_puck_eats_the_blast() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)
	var mine := CartMine.deploy(fx, Vector3.ZERO)
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.global_position = Vector3(0.4, 0.0, 0.0)
	mine._physics_process(0.016)
	assert_false(zombie.is_dying(), "it has to arm before it pops")
	assert_true(is_instance_valid(mine))
	mine._physics_process(CartMines.ARM_TIME)
	assert_true(zombie.is_dying())
	assert_true(mine.is_queued_for_deletion())


func test_allied_walkers_do_not_trip_a_mine() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)
	var mine := CartMine.deploy(fx, Vector3.ZERO)
	var zombie: Zombie = ZOMBIE.instantiate()
	zombie.stats = WALKER
	add_child_autofree(zombie)
	zombie.global_position = Vector3.ZERO
	zombie.allied = true
	mine._physics_process(CartMines.ARM_TIME)
	assert_false(zombie.is_dying())
	assert_false(mine.is_queued_for_deletion())


func test_hopping_out_deselects_mines() -> void:
	var packed := _ride()
	var passenger: Player = packed[1]
	var cart: GolfCart = packed[2]
	passenger._cycle_held(1)
	assert_true(passenger.is_holding_mines())
	cart.eject(passenger)
	assert_false(passenger.is_holding_mines())


func test_a_lot_car_carries_the_same_rack() -> void:
	var car: GolfCart = RACE.instantiate()
	add_child_autofree(car)
	assert_eq(car.mines, CartMines.LOAD)


func test_the_passenger_prompt_names_the_mine_buttons() -> void:
	var packed := _ride()
	var passenger: Player = packed[1]
	var text := passenger.get_prompt()
	assert_string_contains(text, passenger.input.hint("swap_weapon"))
	assert_string_contains(text, "mines")
	passenger._cycle_held(1)
	text = passenger.get_prompt()
	assert_string_contains(text, "Mines")
	assert_string_contains(text, passenger.input.hint("shoot"))


func _ride() -> Array:
	var cart: GolfCart = CART.instantiate()
	var driver: Player = PLAYER.instantiate()
	var passenger: Player = PLAYER.instantiate()
	add_child_autofree(cart)
	add_child_autofree(driver)
	add_child_autofree(passenger)
	cart.set_physics_process(false)
	driver.set_physics_process(false)
	driver.set_process(false)
	passenger.set_physics_process(false)
	passenger.set_process(false)
	driver.global_position = Vector3(1.0, 0.0, 0.0)
	passenger.global_position = Vector3(-1.0, 0.0, 0.0)
	cart.global_position = Vector3(0.0, 0.4, 0.0)
	cart.board(driver)
	cart.board(passenger)
	return [driver, passenger, cart]
