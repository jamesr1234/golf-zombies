extends GutTest
## Extra lot cars keep the GolfCart contract and drive like their body style.

const RACE := preload("res://scenes/vehicles/race_car.tscn")
const WAGON := preload("res://scenes/vehicles/station_wagon.tscn")
const TRUCK := preload("res://scenes/vehicles/pickup_truck.tscn")
const VAN := preload("res://scenes/vehicles/panel_van.tscn")
const SUV := preload("res://scenes/vehicles/suv.tscn")
const CART := preload("res://scenes/vehicles/golf_cart.tscn")
const _Lot := preload("res://scripts/vehicles/vehicle_lot.gd")


func test_each_car_is_a_boardable_golf_cart() -> void:
	for packed in [RACE, WAGON, TRUCK, VAN, SUV]:
		var car: GolfCart = packed.instantiate()
		add_child_autofree(car)
		assert_true(car is GolfCart)
		assert_true(car.is_in_group("golf_carts"))
		assert_not_null(car.visual_scene)
		assert_eq(car.mines, CartMines.LOAD)


func test_the_race_car_outruns_the_truck_and_the_van() -> void:
	var race: GolfCart = RACE.instantiate()
	var truck: GolfCart = TRUCK.instantiate()
	var van: GolfCart = VAN.instantiate()
	add_child_autofree(race)
	add_child_autofree(truck)
	add_child_autofree(van)
	assert_gt(race.max_drive_speed(), truck.max_drive_speed())
	assert_gt(truck.max_drive_speed(), van.max_drive_speed())
	assert_gt(race.max_drive_speed(), GolfCart.MAX_SPEED)


func test_the_truck_and_van_shove_harder_than_the_race_car() -> void:
	var race: GolfCart = RACE.instantiate()
	var truck: GolfCart = TRUCK.instantiate()
	var van: GolfCart = VAN.instantiate()
	add_child_autofree(race)
	add_child_autofree(truck)
	add_child_autofree(van)
	assert_gt(truck.crush_push, race.crush_push)
	assert_gt(van.crush_push, race.crush_push)
	assert_gt(truck.crate_impulse, race.crate_impulse)
	assert_lt(truck.impact_decay, race.impact_decay, "a truck keeps rolling through a hit")


func test_a_heavy_hit_hurts_more_than_a_race_clip() -> void:
	var cruise := 12.0
	assert_gt(
		GolfCart.crush_damage(cruise, 1.0, 32.0),
		GolfCart.crush_damage(cruise, 1.0, 18.0)
	)


func test_the_golf_cart_keeps_stock_handling() -> void:
	var cart: GolfCart = CART.instantiate()
	add_child_autofree(cart)
	assert_eq(cart.top_speed, GolfCart.MAX_SPEED)
	assert_eq(cart.crush_push, GolfCart.CRUSH_PUSH)
	assert_eq(cart.crate_impulse, 0.0)
	assert_null(cart.visual_scene)
	assert_eq(cart.mines, CartMines.LOAD)


func test_the_lot_parks_beside_the_assigned_cart() -> void:
	var lead: GolfCart = CART.instantiate()
	var lot := _Lot.new()
	var extra: GolfCart = RACE.instantiate()
	add_child_autofree(lead)
	add_child_autofree(lot)
	lot.add_child(extra)
	lead.place_at(Vector3(10.0, 0.4, 4.0), 90.0)
	lot.park_with(lead)
	assert_gt(extra.global_position.distance_to(lead.global_position), 4.0)
	assert_almost_eq(extra.rotation.y, lead.rotation.y, 0.01)


func test_tinting_a_skinned_car_does_not_crash() -> void:
	var car: GolfCart = RACE.instantiate()
	add_child_autofree(car)
	car.apply_tint(Palette.CYAN)
	assert_true(car.has_node("Body"))


func test_car_markers_match_blender_suffixes() -> void:
	var root := Node3D.new()
	var tagged := Node3D.new()
	root.add_child(tagged)
	tagged.name = "SteeringWheel_002"
	add_child_autofree(root)
	assert_eq(CarVisuals.find_named(root, "SteeringWheel"), tagged)
