class_name PlayerBeerKit
extends RefCounted
## Cooler buys, cycle-to-beer, throw, and chug. The can mesh lives on the head;
## RPCs for host-authoritative buys / throws stay on Player.

const _BeerCan := preload("res://scripts/player/beer_can.gd")
const _ThrownBeer := preload("res://scripts/player/thrown_beer.gd")
const _WorldFx := preload("res://scripts/net/world_fx.gd")

var can: _BeerCan


func setup(player: Player) -> void:
	can = _BeerCan.create(1.2)
	can.paint_view()
	can.visible = false
	player.head.add_child(can)


func cart_for(player: Player):
	if player.flow == null or not player.flow.has_method("beer_cart_for"):
		return null
	return player.flow.beer_cart_for(player)


func prompt(player: Player) -> String:
	var girl = cart_for(player)
	if girl == null:
		return ""
	if not girl.cooler_open:
		return "%s to flip the cooler" % player.input.hint("interact")
	var cash := 0
	var card = player.wallet()
	if card != null:
		cash = card.money
	if not Buzz.can_afford(cash):
		return "Beer %s   need more cash" % GameState.format_money(Buzz.PRICE)
	return "%s to grab a beer %s" % [
		player.input.hint("interact"), GameState.format_money(Buzz.PRICE)
	]


func use_cart(player: Player) -> void:
	if NetSession.is_active() and not player.multiplayer.is_server():
		player._request_beer_cart.rpc_id(1)
		return
	commit_cart(player)


func commit_cart(player: Player) -> void:
	var girl = cart_for(player)
	if girl == null:
		return
	if not girl.cooler_open:
		girl.open_cooler()
		_WorldFx.announce_sfx(player, "cooler_open")
		return
	if not girl.sell_to(player):
		return
	_WorldFx.announce_sfx(player, "buy_beer")
	_WorldFx.announce_cart_girl(player, "cheer")
	if player.flow != null and player.flow.has_method("note_beer_sale"):
		player.flow.note_beer_sale(player)


func is_holding(player: Player) -> bool:
	if player.net_driven and not player.is_multiplayer_authority():
		return player.holding_beer
	var sipping: bool = can != null and can.is_busy()
	if player.holding_beer and player.buzz.held <= 0 and not sipping:
		player.holding_beer = false
	return player.holding_beer


func cycle_held(player: Player, step := 1) -> void:
	if step == 0:
		return
	if player.mine_kit.handle_cycle(player, step):
		return
	if is_holding(player):
		player.holding_beer = false
		Sfx.play("weapon_swap", player)
		if step > 0 and player.weapon.has_weapon():
			player.weapon.index = 0
		return
	if player.buzz.held > 0:
		if not player.weapon.has_weapon():
			player.holding_beer = true
			Sfx.play("weapon_swap", player)
			return
		if step > 0 and player.weapon.index == player.weapon.loadout.size() - 1:
			player.holding_beer = true
			Sfx.play("weapon_swap", player)
			return
		if step < 0 and player.weapon.index == 0:
			player.holding_beer = true
			Sfx.play("weapon_swap", player)
			return
	player.weapon.swap(step)


func throw_beer(player: Player) -> bool:
	if not is_holding(player) or (can != null and can.is_busy()):
		return false
	if not player.buzz.spend():
		player.holding_beer = false
		return false
	if can != null:
		can.toss()
	Sfx.play("throw_beer", player)
	var view := player.get_view_transform()
	var fly := -view.basis.z
	var muzzle := view.origin + fly * 0.7
	if NetSession.defers_world():
		player._request_throw_beer.rpc_id(1, muzzle, fly)
		return true
	spawn_thrown(player, muzzle, fly)
	return true


func spawn_thrown(player: Player, muzzle: Vector3, fly: Vector3) -> void:
	var root := player.get_tree().get_first_node_in_group("fx_root")
	if root == null:
		root = player.get_tree().current_scene
	_ThrownBeer.spawn(root, muzzle, fly)
	_WorldFx.announce_beer(player, muzzle, fly)


func chug(player: Player) -> bool:
	if not player.health.is_alive() or not is_holding(player):
		return false
	if can != null and can.is_busy():
		return false
	if not player.buzz.chug():
		player.holding_beer = false
		return false
	if can != null:
		can.drink()
	player.add_view_kick(Buzz.CHUG_KICK)
	Sfx.play("drink_beer", player)
	if NetSession.is_active() and not player.multiplayer.is_server():
		player._request_chug.rpc_id(1)
	return true


func animate(player: Player, delta: float) -> void:
	if can == null:
		return
	var show_beer := (
		is_holding(player) and player.health.is_alive() and player.state != Player.State.GOLFING
		and not player.is_driving() and not player.is_swimming() and not player.is_shielding()
		and not player.is_placing()
	)
	can.animate(delta, show_beer)


func wants_drunk_fx(player: Player) -> bool:
	if player.buzz.extra_beers() <= 0:
		return false
	if player.is_golfing():
		return false
	if player.is_driving() and player.is_chase_cam():
		return false
	if player.is_in_mech() and player.is_chase_cam():
		return false
	return true
