extends GutTest
## Shared wallet purchases across clubhouse departments.

const ROCKET: WeaponStats = preload("res://resources/weapons/rocket.tres")
const PLAYER := preload("res://scenes/players/player.tscn")
const InspectScript := preload("res://scripts/shop/shop_inspect.gd")

var shop: Shop
var score: GameState
var gun: Weapon
var buyer: Player
var cart: GolfCart


func before_each() -> void:
	shop = Shop.new()
	score = GameState.new(PackedInt32Array([4, 3, 5]))
	gun = Weapon.new()
	add_child_autofree(gun)
	buyer = PLAYER.instantiate()
	add_child_autofree(buyer)
	cart = GolfCart.new()
	await wait_physics_frames(2)


func after_each() -> void:
	if cart != null and is_instance_valid(cart):
		cart.free()
		cart = null


func test_the_rocket_is_on_the_armory_shelf() -> void:
	var item := shop.item_at(0, Shop.Dept.WEAPONS)
	assert_eq(String(item["id"]), "rocket")
	assert_eq(int(item["price"]), Shop.ROCKET_PRICE)
	assert_gt(ROCKET.blast_radius, 5.0)
	assert_eq(ROCKET.visual, "rocket")


func test_the_flare_driver_and_cart_nailer_are_on_the_armory_shelf() -> void:
	var flare := _find("flare_driver")
	var nailer := _find("cart_nailer")
	assert_eq(String(flare["name"]), "Flare Driver")
	assert_eq(int(flare["price"]), 280)
	assert_true((flare["stats"] as WeaponStats).is_flare())
	assert_eq(String(nailer["name"]), "Cart Nailer")
	assert_eq(int(nailer["price"]), 320)
	assert_true((nailer["stats"] as WeaponStats).has_cart_bonus())
	assert_eq(shop.count(Shop.Dept.WEAPONS), 3)


func test_buying_the_flare_driver_puts_it_in_the_bag() -> void:
	var flare: WeaponStats = _find("flare_driver")["stats"]
	assert_false(gun.has_gun(flare))
	score.credit(280)
	assert_true(shop.buy("flare_driver", score, _loadout()))
	assert_true(gun.has_gun(flare))
	assert_eq(score.money, 0)
	assert_false(shop.buy("flare_driver", score, _loadout()), "owning it once is enough")


func test_buying_the_cart_nailer_puts_it_in_the_bag() -> void:
	var nailer: WeaponStats = _find("cart_nailer")["stats"]
	assert_false(gun.has_gun(nailer))
	score.credit(320)
	assert_true(shop.buy("cart_nailer", score, _loadout()))
	assert_true(gun.has_gun(nailer))
	assert_eq(gun.stats(), nailer)


func test_the_rocket_starts_in_the_bag() -> void:
	assert_true(gun.has_gun(ROCKET))
	score.credit(Shop.ROCKET_PRICE)
	assert_false(shop.buy("rocket", score, _loadout()), "owning it once is enough")
	assert_eq(score.money, Shop.ROCKET_PRICE)


func test_the_rocket_cannot_be_bought_twice() -> void:
	score.credit(Shop.ROCKET_PRICE * 2)
	assert_false(shop.buy("rocket", score, _loadout()))
	assert_eq(score.money, Shop.ROCKET_PRICE * 2)


func test_a_short_wallet_cannot_buy_the_rocket() -> void:
	score.credit(Shop.ROCKET_PRICE - 1)
	assert_false(shop.buy("rocket", score, _loadout()))
	assert_true(gun.has_gun(ROCKET))


func test_ammo_restocks_the_magazines() -> void:
	score.credit(Shop.AMMO_PRICE)
	var before := gun.reserve()
	assert_true(shop.buy("ammo", score, _loadout()))
	assert_gt(gun.reserve(), before)
	assert_eq(score.money, 0)


func test_no_department_lists_next_hole() -> void:
	for dept in [Shop.Dept.APPAREL, Shop.Dept.CLUBS, Shop.Dept.WEAPONS, Shop.Dept.ITEMS, Shop.Dept.CART]:
		for item in shop.catalog(dept):
			assert_ne(String(item["kind"]), "next")
			assert_ne(String(item["id"]), "next")
	assert_false(shop.buy("next", score, _loadout()))


func test_the_listing_marks_the_cursor_and_owned_guns() -> void:
	var text := shop.listing(0, 0, _loadout(), Shop.Dept.WEAPONS, score)
	assert_string_contains(text, "> Rocket Launcher")
	assert_string_contains(text, "owned")


func test_the_barrier_is_on_the_item_shelf() -> void:
	var item := _find("barrier")
	assert_eq(String(item["kind"]), "fort")
	assert_eq(int(item["price"]), Shop.BARRIER_PRICE)
	assert_eq(Shop.BARRIER_AMOUNT, 2)


func test_buying_a_barrier_adds_charges_and_can_stack() -> void:
	score.credit(Shop.BARRIER_PRICE * 2)
	assert_eq(score.barrier_charges, 0)
	assert_true(shop.buy("barrier", score, _loadout()))
	assert_eq(score.barrier_charges, Shop.BARRIER_AMOUNT)
	assert_eq(score.money, Shop.BARRIER_PRICE)
	assert_true(shop.buy("barrier", score, _loadout()))
	assert_eq(score.barrier_charges, Shop.BARRIER_AMOUNT * 2)
	assert_eq(score.money, 0)


func test_the_barrier_listing_is_not_owned_and_shows_stock() -> void:
	var index := _index("barrier", Shop.Dept.ITEMS)
	var text := shop.listing(index, 0, _loadout(), Shop.Dept.ITEMS, score)
	assert_string_contains(text, "> Hex Barrier")
	assert_string_contains(text, "$150")
	assert_false(text.contains("owned"))
	score.credit(Shop.BARRIER_PRICE)
	shop.buy("barrier", score, _loadout())
	text = shop.listing(index, score.money, _loadout(), Shop.Dept.ITEMS, score)
	assert_string_contains(text, "$150")
	assert_string_contains(text, "2 held")
	assert_false(text.contains("owned"))


func test_club_sets_replace_the_starter() -> void:
	score.credit(120)
	assert_eq(score.club_id, ClubKit.STARTER_ID)
	assert_true(shop.buy("tour", score, _loadout()))
	assert_eq(score.club_id, ClubKit.TOUR_ID)
	assert_false(shop.buy("tour", score, _loadout()))
	score.credit(220)
	assert_true(shop.buy("pro", score, _loadout()))
	assert_eq(score.club_id, ClubKit.PRO_ID)
	assert_false(shop.buy("tour", score, _loadout()), "you cannot downgrade")


func test_apparel_is_per_player_and_shorts_replace_pants() -> void:
	score.credit(200)
	var shirt := _find("shirt_cyan")
	assert_true(shop.buy("shirt_cyan", score, _loadout(), buyer, cart))
	assert_true(buyer.is_wearing("shirt_cyan"))
	assert_eq(buyer.body.worn["shirt"], "shirt_cyan")
	assert_true(shop.buy("shorts_amber", score, _loadout(), buyer, cart))
	assert_eq(buyer.body.worn["bottom"], "shorts_amber")
	assert_true(shop.buy("pants_ice", score, _loadout(), buyer, cart))
	assert_eq(buyer.body.worn["bottom"], "pants_ice")
	assert_false(buyer.is_wearing("shorts_amber"))
	assert_eq(shirt["slot"], "shirt")


func test_previewing_apparel_is_not_owning_it() -> void:
	buyer.body.try_on(_find("shirt_cyan"))
	assert_true(buyer.body.is_trying_on("shirt_cyan"))
	assert_false(buyer.is_wearing("shirt_cyan"))
	assert_false(shop.is_owned("shirt_cyan", _loadout(), score, buyer, cart))
	var text := shop.listing(_index("shirt_cyan", Shop.Dept.APPAREL), 0, _loadout(), Shop.Dept.APPAREL, score, buyer)
	assert_string_contains(text, "> Cyan Shirt")
	assert_false(text.contains("owned"))


func test_walking_off_the_rack_puts_your_clothes_back() -> void:
	score.credit(40)
	assert_true(shop.buy("shirt_cyan", score, _loadout(), buyer, cart))
	buyer.body.try_on(_find("shirt_violet"))
	assert_true(buyer.body.is_trying_on("shirt_violet"))
	buyer.close_shop()
	assert_true(buyer.is_wearing("shirt_cyan"))
	assert_false(buyer.body.is_trying_on("shirt_violet"))


func test_scrolling_the_apparel_shelf_tries_it_on() -> void:
	var stub := _FakeShopFlow.new()
	stub.shop = shop
	stub.score = score
	stub.guns = _loadout()
	stub.cart = cart
	buyer.flow = stub
	var station := ShopStation.create(Shop.Dept.APPAREL, "Apparel", Vector3.ZERO, 0.0)
	add_child_autofree(station)
	buyer.open_station(station)
	assert_true(buyer.trying_on_apparel())
	var first := shop.item_at(0, Shop.Dept.APPAREL)
	assert_true(buyer.body.is_trying_on(String(first["id"])))
	buyer._cycle_shop(1)
	var second := shop.item_at(1, Shop.Dept.APPAREL)
	assert_true(buyer.body.is_trying_on(String(second["id"])))
	assert_false(buyer.body.is_trying_on(String(first["id"])))


func test_the_right_stick_spins_hovered_stock_a_full_turn() -> void:
	var inspect = InspectScript.new()
	add_child_autofree(inspect)
	inspect.show_item(_find("rocket"))
	assert_true(inspect.visible)
	assert_gt(inspect.get_child_count(), 0)
	inspect.spin(Vector2(90.0, 0.0))
	assert_almost_eq(inspect.yaw, -90.0, 0.01)
	inspect.spin(Vector2(300.0, 45.0))
	assert_almost_eq(inspect.yaw, wrapf(-390.0, -180.0, 180.0), 0.01)
	assert_almost_eq(inspect.pitch, 45.0, 0.01)
	assert_almost_eq(inspect._pose.rotation_degrees.y, inspect.yaw, 0.01)


func test_scrolling_the_armory_shows_the_gun_you_can_spin() -> void:
	var stub := _FakeShopFlow.new()
	stub.shop = shop
	stub.score = score
	stub.guns = _loadout()
	stub.cart = cart
	buyer.flow = stub
	var station := ShopStation.create(Shop.Dept.WEAPONS, "Armory", Vector3.ZERO, 0.0)
	add_child_autofree(station)
	buyer.open_station(station)
	assert_true(buyer.shopping)
	assert_eq(buyer._inspect.item_id, "rocket")
	assert_true(buyer._inspect.visible)
	buyer._turn_shop(Vector2(120.0, 0.0), 0.0)
	assert_almost_eq(buyer._inspect.yaw, -120.0, 0.01)
	buyer.close_shop()
	assert_eq(buyer._inspect.item_id, "")
	assert_false(buyer._inspect.visible)


func test_the_right_stick_spins_a_try_on_without_pitching_the_robot() -> void:
	var stub := _FakeShopFlow.new()
	stub.shop = shop
	stub.score = score
	stub.guns = _loadout()
	stub.cart = cart
	buyer.flow = stub
	var station := ShopStation.create(Shop.Dept.APPAREL, "Apparel", Vector3.ZERO, 0.0)
	add_child_autofree(station)
	buyer.open_station(station)
	buyer._turn_shop(Vector2(90.0, 40.0), 0.0)
	assert_almost_eq(buyer.body.rotation.y, deg_to_rad(-90.0), 0.01)
	assert_almost_eq(buyer.body.rotation.x, 0.0, 0.01)
	assert_almost_eq(buyer._inspect.pitch, 0.0, 0.01)


func test_a_medkit_heals_the_buyer() -> void:
	buyer.health.hp = 40.0
	score.credit(100)
	assert_true(shop.buy("medkit", score, _loadout(), buyer, cart))
	assert_almost_eq(buyer.health.hp, buyer.health.max_hp, 0.001)
	assert_eq(score.money, 50)
	assert_false(shop.buy("medkit", score, _loadout(), buyer, cart), "full health cannot restock")
	assert_eq(score.money, 50)


func test_a_revive_kit_charges_the_buyer() -> void:
	score.credit(90)
	assert_true(shop.buy("revive", score, _loadout(), buyer, cart))
	assert_eq(buyer.health.auto_revives, 1)


func test_cart_upgrades_stick_and_cannot_be_bought_twice() -> void:
	score.credit(400)
	assert_true(shop.buy("cart_turbo", score, _loadout(), buyer, cart))
	assert_true(cart.turbo)
	assert_false(shop.buy("cart_turbo", score, _loadout(), buyer, cart))
	assert_true(shop.buy("cart_ram", score, _loadout(), buyer, cart))
	assert_true(cart.ram_plate)
	assert_true(shop.buy("cart_armor", score, _loadout(), buyer, cart))
	assert_true(cart.armored)
	buyer.cart = cart
	buyer.state = Player.State.RIDING
	assert_almost_eq(buyer.incoming_damage(20.0), 10.0, 0.001)


func test_cart_upgrades_live_in_the_garage() -> void:
	var shelf := shop.catalog(Shop.Dept.CART)
	assert_eq(shelf.size(), 3)
	assert_eq(String(shelf[0]["id"]), "cart_turbo")
	assert_eq(String(shop.dept_title(Shop.Dept.CART)), "Cart")
	for item in shop.catalog(Shop.Dept.ITEMS):
		assert_false(String(item["id"]).begins_with("cart_"), "the items counter no longer sells cart parts")


func test_time_items_wait_for_the_next_hole() -> void:
	score.credit(200)
	assert_true(shop.buy("time_bonus", score, _loadout()))
	assert_eq(score.bonus_seconds, Shop.TIME_BONUS_SECONDS)
	assert_true(shop.buy("time_freeze", score, _loadout()))
	assert_almost_eq(score.freeze_seconds, Shop.FREEZE_SECONDS, 0.001)


func test_the_mech_is_one_per_round() -> void:
	score.credit(Shop.MECH_PRICE * 2)
	var item := _find("mech")
	assert_eq(String(item["kind"]), "mech")
	assert_eq(int(item["price"]), Shop.MECH_PRICE)
	assert_string_contains(shop.info(item), "One giant")
	assert_true(shop.buy("mech", score, _loadout(), buyer))
	assert_true(score.mech_bought)
	assert_eq(score.money, Shop.MECH_PRICE)
	assert_false(shop.buy("mech", score, _loadout(), buyer), "one per round even after it is gone")
	assert_eq(score.money, Shop.MECH_PRICE)


func test_every_shelf_item_has_a_blurb() -> void:
	for dept in [Shop.Dept.APPAREL, Shop.Dept.CLUBS, Shop.Dept.WEAPONS, Shop.Dept.ITEMS, Shop.Dept.CART]:
		for item in shop.catalog(dept):
			assert_gt(shop.info(item).length(), 12, "%s needs a sentence of info" % item["id"])


func test_the_hovered_item_details_explain_the_rocket() -> void:
	var text := shop.details(0, 0, _loadout(), Shop.Dept.WEAPONS, score)
	assert_string_contains(text, "Rocket Launcher")
	assert_string_contains(text, "blast")
	assert_string_contains(text, "owned")
	assert_string_contains(text, "Bank")
	var listing := shop.listing(0, 0, _loadout(), Shop.Dept.WEAPONS, score)
	assert_false(listing.contains("blast"), "the shelf stays a list; info is a hold")


func test_club_and_kit_blurbs_say_what_they_do() -> void:
	assert_string_contains(shop.info(_find("tour")), "Forgives")
	assert_string_contains(shop.info(_find("barrier")), "hex")
	assert_string_contains(shop.info(_find("shirt_cyan")), "Looks")
	assert_string_contains(shop.info(_find("shorts_amber")), "replace pants")
	assert_string_contains(shop.info(_find("cart_armor")), "Halves")


func test_the_shop_prompt_offers_info_on_the_hovered_item() -> void:
	var stub := _FakeShopFlow.new()
	stub.shop = shop
	stub.score = score
	stub.guns = _loadout()
	stub.cart = cart
	buyer.flow = stub
	buyer.shopping = true
	buyer.shop_dept = Shop.Dept.WEAPONS
	buyer.shop_choice = 0
	var prompt := buyer.get_prompt()
	assert_string_contains(prompt, "info")
	assert_string_contains(prompt, buyer.input.hint("map"))
	assert_string_contains(prompt, "browse")
	assert_string_contains(prompt, "turn")
	assert_false(buyer.wants_shop_info(), "info is hold, not a leftover toggle")
	assert_false(buyer.wants_map(), "the hole map waits until you leave the counter")


func _loadout() -> Array[Weapon]:
	return [gun]


func _find(item_id: String) -> Dictionary:
	for dept in [Shop.Dept.APPAREL, Shop.Dept.CLUBS, Shop.Dept.WEAPONS, Shop.Dept.ITEMS, Shop.Dept.CART]:
		for item in shop.catalog(dept):
			if String(item["id"]) == item_id:
				return item
	return {}


func _index(item_id: String, dept: int) -> int:
	var items := shop.catalog(dept)
	for i in items.size():
		if String(items[i]["id"]) == item_id:
			return i
	return 0


class _FakeShopFlow:
	extends RefCounted
	var shop: Shop
	var score: GameState
	var guns: Array[Weapon] = []
	var cart: GolfCart

	func has_shop() -> bool:
		return true

	func shop_item(choice: int, dept: int) -> Dictionary:
		return shop.item_at(choice, dept)

	func shop_owned(item_id: String, who: Player) -> bool:
		return shop.is_owned(item_id, guns, score, who, cart)

	func shop_can_buy(item_id: String, who: Player) -> bool:
		return shop.can_buy(item_id, score, guns, who, cart)

	func shop_count(dept: int) -> int:
		return shop.count(dept)
