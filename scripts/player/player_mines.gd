class_name PlayerMines
extends RefCounted
## Passenger-only mine rack. D-pad down selects it; R2 dumps one off the tail.


func can_select(player: Player) -> bool:
	if player == null or not player.health.is_alive():
		return false
	if player.cart == null or player.cart.passenger != player:
		return false
	return player.cart.mines > 0


func is_holding(player: Player) -> bool:
	if player.net_driven and not player.is_multiplayer_authority():
		return player.holding_mines
	if player.holding_mines and not can_select(player):
		player.holding_mines = false
	return player.holding_mines


func handle_cycle(player: Player, step: int) -> bool:
	if step == 0:
		return false
	if is_holding(player):
		clear(player)
		if step > 0 and player.weapon.has_weapon():
			player.weapon.index = 0
		return true
	if step > 0 and can_select(player):
		select(player)
		return true
	return false


func select(player: Player) -> void:
	player.holding_beer = false
	player.holding_mines = true
	Sfx.play("weapon_swap", player)


func clear(player: Player) -> void:
	if not player.holding_mines:
		return
	player.holding_mines = false
	Sfx.play("weapon_swap", player)


func deploy(player: Player) -> bool:
	if not is_holding(player) or player.cart == null:
		return false
	if not CartMines.can_drop(player.cart, player):
		return false
	Sfx.play("mine_drop", player)
	return CartMines.try_drop(player.cart, player)
