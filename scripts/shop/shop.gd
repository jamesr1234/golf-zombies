class_name Shop
extends RefCounted
## Clubhouse catalogues. Shared wallet; apparel and medkits apply to the buyer.
## A bought gun still goes into both loadouts.

signal purchased(item_id: String)

enum Dept { APPAREL, CLUBS, WEAPONS, ITEMS, CART }

const ROCKET: WeaponStats = preload("res://resources/weapons/rocket.tres")
const ROCKET_PRICE := 400
const AMMO_PRICE := 60
const AMMO_AMOUNT := 40
const BARRIER_PRICE := 150
const MECH_PRICE := 500
const BARRIER_AMOUNT := 2
const TIME_BONUS_SECONDS := 30
const FREEZE_SECONDS := 15.0
const TITLES: PackedStringArray = ["Apparel", "Club Sets", "Armory", "Items", "Cart"]


func catalog(dept: int = Dept.WEAPONS) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	match dept:
		Dept.APPAREL:
			items.append_array(ShopStock.apparel())
		Dept.CLUBS:
			items.append_array(ShopStock.clubs())
		Dept.ITEMS:
			items.append_array(ShopStock.items())
		Dept.CART:
			items.append_array(ShopStock.cart())
		_:
			items.append_array(ShopStock.weapons())
	return items


func dept_title(dept: int) -> String:
	return TITLES[clampi(dept, 0, TITLES.size() - 1)]


func item_at(index: int, dept: int = Dept.WEAPONS) -> Dictionary:
	var items := catalog(dept)
	if items.is_empty():
		return {}
	return items[posmod(index, items.size())]


func count(dept: int = Dept.WEAPONS) -> int:
	return catalog(dept).size()


func is_owned(item_id: String, weapons: Array[Weapon], score: GameState = null, buyer: Player = null, cart: GolfCart = null) -> bool:
	var item := _find(item_id)
	if item.is_empty():
		return false
	match String(item["kind"]):
		"weapon":
			var stats: WeaponStats = item.get("stats")
			if stats == null:
				return false
			for gun in weapons:
				if gun.has_gun(stats):
					return true
			return false
		"club":
			return score != null and score.club_id == item_id
		"apparel":
			return buyer != null and buyer.is_wearing(item_id)
		"cart_turbo":
			return cart != null and cart.turbo
		"cart_ram":
			return cart != null and cart.ram_plate
		"cart_armor":
			return cart != null and cart.armored
		"mech":
			return score != null and score.mech_bought
		_:
			return false


func can_buy(item_id: String, score: GameState, weapons: Array[Weapon], buyer: Player = null, cart: GolfCart = null) -> bool:
	var item := _find(item_id)
	if item.is_empty() or score == null:
		return false
	if is_owned(item_id, weapons, score, buyer, cart):
		return false
	if String(item["kind"]) == "club":
		if ClubKit.by_id(item_id).tier() <= score.club_kit().tier():
			return false
	if String(item["kind"]) == "medkit":
		if buyer == null or not buyer.health.is_alive():
			return false
		if buyer.health.hp >= buyer.health.max_hp:
			return false
	return score.money >= int(item["price"])


func buy(item_id: String, score: GameState, weapons: Array[Weapon], buyer: Player = null, cart: GolfCart = null) -> bool:
	if not can_buy(item_id, score, weapons, buyer, cart):
		Sfx.play("ui_deny")
		return false
	var item := _find(item_id)
	if not score.try_spend(int(item["price"])):
		Sfx.play("ui_deny")
		return false
	_grant(item, score, weapons, buyer, cart)
	purchased.emit(item_id)
	Sfx.play("purchase")
	return true


func info(item: Dictionary) -> String:
	var text := String(item.get("info", ""))
	if text != "":
		return text
	match String(item.get("kind", "")):
		"apparel":
			return _apparel_info(item)
		"club":
			return _club_info(String(item.get("id", "")))
		_:
			return ""


func details(
	choice: int, money: int, weapons: Array[Weapon], dept: int = Dept.WEAPONS,
	score: GameState = null, buyer: Player = null, cart: GolfCart = null
) -> String:
	var item := item_at(choice, dept)
	if item.is_empty():
		return ""
	var barrier := 0 if score == null else score.barrier_charges
	var lines: PackedStringArray = [
		String(item["name"]),
		info(item),
		"",
		_extra(item, weapons, score, buyer, cart, barrier).strip_edges(),
		"Bank %s" % GameState.format_money(money),
	]
	return "\n".join(lines)


func listing(
	choice: int, money: int, weapons: Array[Weapon], dept: int = Dept.WEAPONS,
	score: GameState = null, buyer: Player = null, cart: GolfCart = null
) -> String:
	var lines: PackedStringArray = []
	var items := catalog(dept)
	var barrier := 0 if score == null else score.barrier_charges
	for i in items.size():
		var item: Dictionary = items[i]
		var mark := ">" if i == posmod(choice, items.size()) else " "
		var extra := _extra(item, weapons, score, buyer, cart, barrier)
		lines.append("%s %s%s" % [mark, String(item["name"]), extra])
	lines.append("")
	lines.append("Bank %s" % GameState.format_money(money))
	return "\n".join(lines)


func _apparel_info(item: Dictionary) -> String:
	var slot := String(item.get("slot", ""))
	var style := String(item.get("style", ""))
	match slot:
		"headband":
			return "Colour for the skull. Looks, not armour."
		"shirt":
			return "Colour for the chest. Looks, not armour."
		_:
			if style == "shorts":
				return "Shorts. They replace pants on the buyer."
			return "Pants. They replace shorts on the buyer."


func _club_info(kit_id: String) -> String:
	match kit_id:
		ClubKit.TOUR_ID:
			return "Forgives a fat swing, carries a little farther, and putts run out less."
		ClubKit.PRO_ID:
			return "A lot more forgiveness and carry. Lag putting is easier."
		ClubKit.FORGED_ID:
			return "The straightest mishits, the longest carry, and putts that stay put."
		_:
			return "The clubs you walked in with."


func _extra(
	item: Dictionary, weapons: Array[Weapon], score: GameState, buyer: Player,
	cart: GolfCart, barrier: int
) -> String:
	var kind := String(item["kind"])
	if is_owned(String(item["id"]), weapons, score, buyer, cart):
		return "   owned" if kind != "club" else "   equipped"
	if kind == "fort" and barrier > 0:
		return "   $%d   (%d held)" % [int(item["price"]), barrier]
	return "   $%d" % int(item["price"])


func _grant(
	item: Dictionary, score: GameState, weapons: Array[Weapon], buyer: Player, cart: GolfCart
) -> void:
	match String(item["kind"]):
		"weapon":
			for gun in weapons:
				gun.add_gun(item["stats"])
		"ammo":
			for gun in weapons:
				gun.add_ammo(AMMO_AMOUNT)
		"fort":
			score.add_barrier_charges(BARRIER_AMOUNT)
		"club":
			score.equip_club(String(item["id"]))
		"apparel":
			if buyer != null:
				buyer.wear_apparel(item)
		"medkit":
			if buyer != null:
				buyer.health.heal()
		"revive":
			_grant_revive(buyer)
		"cart_turbo":
			if cart != null:
				cart.install_turbo()
		"cart_ram":
			if cart != null:
				cart.install_ram()
		"cart_armor":
			if cart != null:
				cart.install_armor()
		"time_bonus":
			score.add_bonus_seconds(TIME_BONUS_SECONDS)
		"time_freeze":
			score.add_freeze_seconds(FREEZE_SECONDS)
		"mech":
			score.mech_bought = true


func _grant_revive(buyer: Player) -> void:
	if buyer == null:
		return
	if buyer.partner != null and buyer.partner.health.is_downed():
		buyer.partner.health.revive_now()
		return
	buyer.health.add_auto_revive()


func _find(item_id: String) -> Dictionary:
	for dept in [Dept.APPAREL, Dept.CLUBS, Dept.WEAPONS, Dept.ITEMS, Dept.CART]:
		for item in catalog(dept):
			if String(item["id"]) == item_id:
				return item
	return {}
