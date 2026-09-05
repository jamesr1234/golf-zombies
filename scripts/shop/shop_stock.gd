class_name ShopStock
extends Object
## Department shelves. Shop owns buy/listing; this file is just what is for sale.

const ROCKET: WeaponStats = preload("res://resources/weapons/rocket.tres")
const FLARE_DRIVER: WeaponStats = preload("res://resources/weapons/flare_driver.tres")
const CART_NAILER: WeaponStats = preload("res://resources/weapons/cart_nailer.tres")
const WARP_DOOR: WeaponStats = preload("res://resources/weapons/warp_door.tres")

static func wear_by_id(item_id: String) -> Dictionary:
	for item in apparel():
		if String(item["id"]) == item_id:
			return item
	return {}


static func apparel() -> Array[Dictionary]:
	return [
		_wear("band_cyan", "Cyan Headband", 25, "headband", "", Palette.CYAN),
		_wear("band_lime", "Lime Headband", 25, "headband", "", Palette.LIME),
		_wear("shorts_amber", "Amber Shorts", 35, "bottom", "shorts", Palette.AMBER),
		_wear("shorts_pink", "Hot Pink Shorts", 35, "bottom", "shorts", Palette.HOT_PINK),
		_wear("shirt_cyan", "Cyan Shirt", 40, "shirt", "", Palette.CYAN),
		_wear("shirt_violet", "Violet Shirt", 40, "shirt", "", Palette.VIOLET),
		_wear("pants_ice", "Ice Pants", 45, "bottom", "pants", Palette.ICE),
		_wear("pants_magenta", "Magenta Pants", 45, "bottom", "pants", Palette.MAGENTA),
	]


static func clubs() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for kit_id in ClubKit.shop_ids():
		var kit := ClubKit.by_id(kit_id)
		items.append({
			"id": kit.id,
			"name": kit.display_name,
			"price": kit.price,
			"kind": "club",
		})
	return items


static func weapons() -> Array[Dictionary]:
	return [
		{
			"id": "rocket",
			"name": "Rocket Launcher",
			"price": 400,
			"kind": "weapon",
			"stats": ROCKET,
			"info": "A slow single shot that explodes in a six-metre blast. One in the bag is enough.",
		},
		{
			"id": "flare_driver",
			"name": "Flare Driver",
			"price": 280,
			"kind": "weapon",
			"stats": FLARE_DRIVER,
			"info": "A mid-range club gun. Hits light zombies up for seven seconds so tower snipers and night packs stay visible.",
		},
		{
			"id": "cart_nailer",
			"name": "Cart Nailer",
			"price": 320,
			"kind": "weapon",
			"stats": CART_NAILER,
			"info": "A fast SMG that hits harder near the golf cart, or while you are riding it.",
		},
		{
			"id": "warp_door",
			"name": "Warp Door",
			"price": 350,
			"kind": "weapon",
			"stats": WARP_DOOR,
			"info": "Shoots a neon doorway one metre out. Walk through and you stand next to your ball.",
		},
	]

static func items() -> Array[Dictionary]:
	return [
		{
			"id": "ammo", "name": "Ammo Crate", "price": Shop.AMMO_PRICE, "kind": "ammo",
			"info": "Forty rounds for every gun you and your partner carry.",
		},
		{
			"id": "barrier", "name": "Hex Barrier", "price": Shop.BARRIER_PRICE, "kind": "fort",
			"info": "Two hex forts you drop with gear. Charges stack across holes.",
		},
		{
			"id": "ladder", "name": "Lean Ladder", "price": Shop.LADDER_PRICE, "kind": "ladder",
			"info": "One ladder you lean on a wall with gear. Walk in to climb instead of hopping blocks.",
		},
		{
			"id": "mech", "name": "Mech Suit", "price": Shop.MECH_PRICE, "kind": "mech",
			"info": "One giant suit for this hole. Climb in, press Circle to seal. Eight rockets, then reload. One per round.",
		},
	]


static func cart() -> Array[Dictionary]:
	return [
		{
			"id": "cart_turbo", "name": "Cart Turbo", "price": 100, "kind": "cart_turbo",
			"info": "Raises top speed and boost. Stays on the cart for the rest of the round.",
		},
		{
			"id": "cart_ram", "name": "Ram Plate", "price": 110, "kind": "cart_ram",
			"info": "Hits harder when you run them down. Stays on the cart.",
		},
		{
			"id": "cart_armor", "name": "Cart Armor", "price": 90, "kind": "cart_armor",
			"info": "Halves damage while you are riding. Stays on the cart.",
		},
	]


static func _wear(
	id: String, name: String, price: int, slot: String, style: String, color: Color
) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"price": price,
		"kind": "apparel",
		"slot": slot,
		"style": style,
		"color": color,
	}
