class_name PlayerPrompt
extends RefCounted
## Context-sensitive prompt text for the HUD. Pure readout over Player state.

const _Elevator := preload("res://scripts/shop/clubhouse_elevator.gd")
const _Escalator := preload("res://scripts/course/escalator.gd")
const _FoldSteps := preload("res://scripts/course/folding_steps.gd")
const _GrapplePoint := preload("res://scripts/course/grapple_point.gd")
const _Zip := preload("res://scripts/course/zipline.gd")


func text(player: Player) -> String:
	if player.talking:
		return "%s to move on" % player.input.hint("interact")
	if player.is_ziplining():
		return "Riding the line   %s to drop" % player.input.hint("jump")
	if player.is_grappling():
		if player.grappler.is_point():
			return "Reeling in   %s to let go" % player.input.hint("jump")
		return "Riding the hook   %s to let go   hold %s to reel in" % [
			player.input.hint("jump"), player.input.hint("sprint")
		]
	if player.is_climbing():
		if player.climber.wall is LeanLadder:
			return "stick up the ladder   jump to hop off"
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
	var poker := player.poker.prompt(player)
	if poker != "":
		return poker
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
			var gear := "lean the ladder" if player.place.kind == "ladder" else "place"
			return "%s to %s   %s to cancel" % [
				player.input.hint("shoot"), gear, player.input.hint("swap_gear")
			]
		return "No room to place   %s to cancel" % player.input.hint("swap_gear")
	if player.glide.equipped and not player.is_gliding() and player.health.is_alive():
		return "Glide Suit   jump off a drop   %s to put away" % player.input.hint("swap_gear")
	if player.state == Player.State.RIDING:
		if player.cart.driver == player:
			return "Drive with %s   %s boost / drift   %s brake   %s view   %s to hop out" % [
				player.input.hint("move"), player.input.hint("shoot"), player.input.hint("aim"),
				player.input.hint("melee"), player.input.hint("interact")
			]
		if player.is_holding_mines():
			return "Mines x%d   %s to drop   %s for gun   %s to hop out" % [
				player.cart.mines, player.input.hint("shoot"), player.input.hint("swap_weapon"),
				player.input.hint("interact")
			]
		if player.cart.mines > 0:
			return "Riding along   %s mines   %s to hop out" % [
				player.input.hint("swap_weapon"), player.input.hint("interact")
			]
		return "Riding along   %s to hop out" % player.input.hint("interact")
	if LeanLadder.nearest_throw(player) != null:
		return "%s to throw the ladder" % player.input.hint("interact")
	if _Escalator.nearest(player) != null:
		return "%s to reverse the escalator" % player.input.hint("interact")
	var stairs = _FoldSteps.nearest(player)
	if stairs != null:
		if stairs.is_folded():
			return "%s to swing the steps back" % player.input.hint("interact")
		return "%s to drop the steps into a slope" % player.input.hint("interact")
	if _Zip.nearest(player) != null:
		return "%s to ride the zipline" % player.input.hint("interact")
	if player.motion.can_latch_climb(player):
		var wall := ClimbingWall.nearest(player)
		if wall is LeanLadder:
			return "walk in to climb   %s or %s to grab" % [
				player.input.hint("melee"), player.input.hint("shield")
			]
		return "%s or %s to climb" % [player.input.hint("melee"), player.input.hint("shield")]
	if player.mill_control() != null:
		return "%s to run the mill" % player.input.hint("interact")
	var lift = _Elevator.nearest(player)
	if lift != null:
		return "%s to ride to %s" % [player.input.hint("interact"), lift.dest_name(player)]
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
		return "%s to play the ball" % player.input.hint("interact")
	if player.active_cart() != null and player.active_cart().can_right(player):
		return "%s to flip the cart" % player.input.hint("interact")
	if player.active_cart() != null and player.active_cart().can_board(player):
		return "%s to hop in the cart" % player.input.hint("interact")
	if player.ready_mech() != null:
		return "%s to seal the mech" % player.input.hint("interact")
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
	if player._can_fire_grapple() and _GrapplePoint.nearest(player) != null:
		return "%s to grapple the target" % player.input.hint("grapple")
	return ""
