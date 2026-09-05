class_name PlayerInteract
extends RefCounted
## Interact button routing: shop, talk, cart, mill, beer, CPU shot hold, revive.

const CPU_SHOT_HOLD := 0.45
const _MillDesk := preload("res://scripts/course/windmill_control.gd")
const _Elevator := preload("res://scripts/shop/clubhouse_elevator.gd")
const _Escalator := preload("res://scripts/course/escalator.gd")
const _FoldSteps := preload("res://scripts/course/folding_steps.gd")
const _Zip := preload("res://scripts/course/zipline.gd")

var cpu_shot_hold := 0.0
var cpu_shot_latched := false


func tick(player: Player, delta: float) -> void:
	if player.is_climbing() or player.is_ziplining():
		return
	if player.is_grappling() and player.input.just_pressed("interact"):
		player._drop_grapple()
	if player.is_milling():
		if player.input.just_pressed("interact"):
			player.mill_desk.try_toggle(player)
		return
	if player.is_poker_seated():
		if player.input.just_pressed("interact"):
			player.poker.use(player)
			cpu_shot_latched = true
		return
	if player.shopping and (
		player.input.just_pressed("swap_gear") or player.input.just_pressed("swap_gear_prev")
	):
		player.close_shop()
	if player.talking and player.npc() == null:
		player.stop_talk()
	if player.is_swimming() and player.input.just_pressed("grab"):
		if player.swim.can_grab_ball(player):
			player.swim.try_grab_ball(player)
		else:
			player.swim.try_climb_out(player)
	elif player.orders_cpu_shots():
		tick_cpu_shot(player, delta)
	elif not player.is_swimming() and player.health.is_alive() and player.input.just_pressed("interact"):
		use(player)
	if player.state == Player.State.GOLFING and player.input.just_pressed("swing"):
		player.golf.click()
	if player.partner == null:
		return
	if player.health.is_alive() and player.partner_needs_revive() and player.input.pressed("revive"):
		if NetSession.defers_world():
			player._request_revive.rpc_id(1, player.partner.peer_id)
		else:
			player.partner.health.add_revive_progress(delta)
	elif player.partner.health.revive_progress > 0.0 and not NetSession.is_active():
		player.partner.health.reset_revive_progress()


func tick_cpu_shot(player: Player, delta: float) -> void:
	if player.shopping or player.talking or not player.health.is_alive() or player.is_swimming():
		if (player.shopping or player.talking) and player.input.just_pressed("interact"):
			use(player)
			cpu_shot_latched = true
		if not player.input.pressed("interact"):
			cpu_shot_hold = 0.0
			cpu_shot_latched = false
		return
	if not cpu_shot_hold_applies(player):
		if player.input.just_pressed("interact"):
			use(player)
			cpu_shot_latched = true
		elif not player.input.pressed("interact"):
			cpu_shot_hold = 0.0
			cpu_shot_latched = false
		return
	if player.input.pressed("interact"):
		if cpu_shot_latched:
			return
		cpu_shot_hold += delta
		if cpu_shot_hold >= CPU_SHOT_HOLD:
			cpu_shot_latched = true
			if player.partner != null and player.partner.brain != null:
				player.partner.brain.request_shot()
	elif player.input.just_released("interact"):
		if not cpu_shot_latched:
			use(player)
		cpu_shot_hold = 0.0
		cpu_shot_latched = false
	else:
		cpu_shot_hold = 0.0
		cpu_shot_latched = false


## Hold vs tap is only for "you take this shot or the CPU does". Cart, shop,
## retrieve, and hop-out stay on press so a release cannot undo them.
func cpu_shot_hold_applies(player: Player) -> bool:
	if player.state != Player.State.NORMAL or player.shopping or player.talking or player.is_milling() or player.is_poker_seated():
		return false
	if (
		player.can_open_doors() or player.can_open_exit() or player.station() != null
		or player.npc() != null or player.can_retrieve_ball()
	):
		return false
	if player.can_start_play() or player.beer.cart_for(player) != null or mill_control(player) != null:
		return false
	if _Escalator.nearest(player) != null:
		return false
	if _FoldSteps.nearest(player) != null:
		return false
	if _Zip.nearest(player) != null:
		return false
	if _Elevator.nearest(player) != null:
		return false
	if (
		player.active_cart() != null
		and (
			player.active_cart().can_right(player)
			or player.active_cart().can_board(player)
		)
		and (player.golf == null or not player.golf.can_claim(player))
	):
		return false
	if player.ready_mech() != null:
		return false
	if LeanLadder.nearest_throw(player) != null:
		return false
	return true


## One button covers the ball, the cart, and the clubhouse. Hop out if you are
## riding; shop if the pavilion is open; pick the ball out of the cup after a
## hole-out; else play the ball; else climb in.
func use(player: Player) -> void:
	if player.is_climbing() or player.is_ziplining():
		return
	if player.is_grappling():
		player._drop_grapple()
	if player.shopping:
		player.shop.confirm(player)
	elif player.talking:
		player.stop_talk()
	elif player.state == Player.State.RIDING:
		player.cart.eject(player)
	elif player.is_in_mech():
		if player.golf != null and (player.golf.golfer == player or player.golf.can_claim(player)):
			player.golf.try_toggle(player)
	elif player.can_open_doors():
		player.open_doors()
	elif player.poker.use(player):
		pass
	elif player.station() != null:
		player.open_station(player.station())
	elif player.npc() != null:
		player.start_talk(player.npc())
	elif player.can_open_exit():
		player.flow.leave_clubhouse()
	elif player.can_start_play():
		player.flow.start_play()
	elif player.beer.cart_for(player) != null:
		player.beer.use_cart(player)
	elif player.can_retrieve_ball():
		player.flow.retrieve_ball(player)
	elif mill_control(player) != null:
		mill_control(player).try_toggle(player)
	elif escalator_button(player) != null:
		escalator_button(player).try_reverse(player)
	elif steps_lever(player) != null:
		steps_lever(player).try_toggle(player)
	elif _Zip.nearest(player) != null:
		_Zip.nearest(player).try_board(player)
	elif _Elevator.nearest(player) != null:
		_Elevator.nearest(player).try_ride(player)
	elif LeanLadder.nearest_throw(player) != null:
		LeanLadder.nearest_throw(player).try_throw(player)
	elif player.golf != null and (player.golf.golfer == player or player.golf.can_claim(player)):
		player.golf.try_toggle(player)
	elif player.ready_mech() != null:
		player.ready_mech().try_close(player)
	elif player.active_cart() != null and player.active_cart().can_right(player):
		player.active_cart().try_right(player)
	elif player.active_cart() != null and player.active_cart().can_board(player):
		player.active_cart().board(player)
	elif player.is_holding_beer():
		player.chug()


func mill_control(player: Player):
	return _MillDesk.nearest(player)


func escalator_button(player: Player):
	return _Escalator.nearest(player)


func steps_lever(player: Player):
	return _FoldSteps.nearest(player)
