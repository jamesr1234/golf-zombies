class_name PlayerPrompt
extends RefCounted
## Context-sensitive prompt text for the HUD. Pure readout over Player state.


func text(player: Player) -> String:
	if player.talking:
		return "%s to move on" % player.input.hint("interact")
	if player.is_grappling():
		return "Riding the hook   %s to let go   hold %s to reel in" % [
			player.input.hint("jump"), player.input.hint("sprint")
		]
	if player.is_climbing():
		return "hold %s left   hold %s right   sticks reach   jump drop" % [
			player.input.hint("melee"), player.input.hint("shield")
		]
	if player.is_in_mech() and player.state != Player.State.GOLFING:
		if player.mech != null and player.mech.is_reloading():
			return "Mech   reloading   %s camera   %s to golf" % [
				player.input.hint("melee"), player.input.hint("interact")
			]
		var shells := 0 if player.mech == null else player.mech.shells()
		return "Mech   %d / 8   %s rockets   %s camera   %s to golf" % [
			shells, player.input.hint("shoot"), player.input.hint("melee"), player.input.hint("interact")
		]
	if player.is_milling():
		return "Rotate %s   %s to step away" % [
			player.input.hint("move"), player.input.hint("interact")
		]
	if player.shopping:
		return player.shop.prompt(player)
	if player.is_cpu() and player.health.is_alive() and player.state == Player.State.NORMAL:
		if player.partner_needs_revive():
			return "CPU reviving"
		if player.brain != null and player.brain.is_taking_shot():
			return "CPU taking the shot"
		return "CPU partner"
	if player.health.is_downed():
		return "Downed - hold on for your partner"
	if player.partner_needs_revive():
		return "Hold %s to revive" % player.input.hint("revive")
	if player.state == Player.State.SWIMMING:
		return player.swim.prompt(player)
	if player.state == Player.State.GOLFING:
		return "%s to swing   stick up/down for height   %s to leave the ball" % [
			player.input.hint("swing"), player.input.hint("interact")
		]
	if player.state == Player.State.SHIELDING:
		return "Shield up   look to cover   release %s to drop" % player.input.hint("shield")
	if player.state == Player.State.PLACING:
		if player.place.ok:
			return "%s to place   %s to cancel" % [
				player.input.hint("shoot"), player.input.hint("swap_gear")
			]
		return "No room to place   %s to cancel" % player.input.hint("swap_gear")
	if player.state == Player.State.RIDING:
		if player.cart.driver == player:
			return "Drive with %s   %s boost / drift   %s view   %s to hop out" % [
				player.input.hint("move"), player.input.hint("shoot"), player.input.hint("melee"),
				player.input.hint("interact")
			]
		return "Riding along   %s to hop out" % player.input.hint("interact")
	if player.motion.can_latch_climb(player):
		return "%s or %s to climb" % [player.input.hint("melee"), player.input.hint("shield")]
	if player.mill_control() != null:
		return "%s to run the mill" % player.input.hint("interact")
	if player.can_start_play():
		return "%s to start the hole" % player.input.hint("interact")
	if player.can_open_doors():
		return "%s to enter the clubhouse" % player.input.hint("interact")
	if player.can_open_exit():
		return "%s to the next hole" % player.input.hint("interact")
	if player.station() != null:
		return "%s to shop %s" % [player.input.hint("interact"), player.station().title]
	if player.npc() != null:
		return "%s to talk to %s" % [player.input.hint("interact"), player.npc().npc_name]
	if player.beer.cart_for(player) != null:
		return player.beer.prompt(player)
	if player.can_retrieve_ball():
		return "%s to pick up your ball" % player.input.hint("interact")
	if player.golf != null and player.golf.can_claim(player):
		if player.orders_cpu_shots():
			return "%s to play the ball   hold %s for CPU shot" % [
				player.input.hint("interact"), player.input.hint("interact")
			]
		return "%s to play the ball" % player.input.hint("interact")
	if player.active_cart() != null and player.active_cart().can_board(player):
		return "%s to hop in the cart" % player.input.hint("interact")
	if player.ready_mech() != null:
		return "%s to seal the mech" % player.input.hint("interact")
	if player.orders_cpu_shots() and player.golf != null and player.golf.is_available():
		return "Hold %s for CPU to take the shot" % player.input.hint("interact")
	if player.is_holding_beer():
		return "%s to drink   %s to throw   beer x%d" % [
			player.input.hint("interact"), player.input.hint("shoot"), player.buzz.held
		]
	if player.buzz.held > 0:
		return "%s for beer" % player.input.hint("swap_weapon")
	if (
		player._can_fire_grapple() and player.active_cart() != null
		and player.global_position.distance_to(player.active_cart().global_position) < Grappler.RANGE
	):
		return "%s to grapple the cart" % player.input.hint("grapple")
	return ""
