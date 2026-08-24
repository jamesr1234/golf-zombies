class_name PlayerCombat
extends RefCounted
## Shield raise, scope, melee, and the fight tick that drives Weapon. Fire /
## reload / melee RPCs stay on Player so authority checks stay on the body.

const _Shield := preload("res://scripts/player/shield.gd")

var shield: _Shield


func setup(player: Player) -> void:
	shield = _Shield.new()
	player.add_child(shield)


func update_shield(player: Player) -> void:
	if (
		player.is_placing() or player.is_climbing() or player.is_grappling()
		or player.is_milling() or player.is_in_mech()
	):
		return
	var was_up := player.state == Player.State.SHIELDING
	if player.state == Player.State.SHIELDING and not wants_shield(player):
		player.state = Player.State.NORMAL
	elif player.state == Player.State.NORMAL and wants_shield(player):
		player.state = Player.State.SHIELDING
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	if shield != null:
		shield.set_raised(player.state == Player.State.SHIELDING)
	if player.state == Player.State.SHIELDING and not was_up:
		Sfx.play("shield_up", player)
	elif was_up and player.state != Player.State.SHIELDING:
		Sfx.play("shield_down", player)


func wants_shield(player: Player) -> bool:
	return (
		player.health.is_alive()
		and player.input.pressed("shield")
		and not player.shopping
		and not player.talking
		and not player._in_clubhouse()
		and not player.is_carrying_ball()
		and not player.is_climbing()
		and not player.is_grappling()
		and not player.is_milling()
		and not player.motion.can_latch_climb(player)
	)


func tick_scope(player: Player) -> void:
	if player.weapon.stats().has_scope():
		if player.input.just_pressed("zoom"):
			player.weapon.cycle_zoom()
			Sfx.play("scope", player)
		player.aiming = player.weapon.is_scoped()
		return
	player.weapon.zoom_step = -1
	player.aiming = player.input.pressed("aim")


func tick(player: Player, delta: float) -> void:
	player.melee.tick(delta)
	if player.shopping:
		player.aiming = false
		if player.weapon != null:
			player.weapon.zoom_step = -1
		player.weapon.tick(delta, player.head.global_transform, false, false, false)
		if player.input.just_pressed("swap_weapon") or player.input.just_pressed("swap_weapon_prev"):
			player.shop.cycle(player, -1 if player.input.just_pressed("swap_weapon_prev") else 1)
		return
	if player.is_placing():
		player.aiming = false
		if player.weapon != null:
			player.weapon.zoom_step = -1
		player.weapon.tick(delta, player.head.global_transform, false, false, false)
		player.place.tick(player)
		if player.input.just_pressed("swap_gear") or player.input.just_pressed("swap_gear_prev"):
			player.place.cancel(player)
		elif player.input.just_pressed("swap_weapon"):
			player.beer.cycle_held(player, 1)
		elif player.input.just_pressed("swap_weapon_prev"):
			player.beer.cycle_held(player, -1)
		elif player.input.just_pressed("shoot"):
			player.place.confirm(player)
		return
	# Riding shotgun you can still shoot. The driver is on the wheel. Grappling
	# tows you along the rope but your hands are free. Water is a swim: R2 dives
	# or throws the ball instead of firing.
	var can_fight := (
		player.health.is_alive() and player.state != Player.State.GOLFING and not player.is_driving()
		and not player.is_swimming() and not player.is_carrying_ball() and not player.is_shielding()
		and not player.is_climbing()
		and not player.is_milling()
		and not player.is_in_mech()
		and not player._in_clubhouse() and not player.is_celebrating()
	)
	if player.is_in_mech() and not player.is_golfing():
		player.aiming = player.input.pressed("aim")
		if player.weapon != null:
			player.weapon.zoom_step = -1
			player.weapon.tick(delta, player.head.global_transform, false, false, false)
		return
	if not can_fight:
		player.aiming = false
		if player.weapon != null:
			player.weapon.zoom_step = -1
		player.weapon.tick(delta, player.head.global_transform, false, false, false)
		# Clubhouse still lets you flip the bag so new guns are visible at the armory.
		if (
			player._in_clubhouse() and not player.shopping and player.health.is_alive()
			and not player.is_celebrating()
		):
			if player.input.just_pressed("swap_weapon"):
				player.beer.cycle_held(player, 1)
			elif player.input.just_pressed("swap_weapon_prev"):
				player.beer.cycle_held(player, -1)
		if player.is_carrying_ball() and not player.is_underwater() and player.input.just_pressed("shoot"):
			player.swim.throw_ball(player)
		return
	if player.is_holding_beer():
		player.aiming = false
		player.weapon.tick(delta, player.head.global_transform, false, false, false)
		if player.input.just_pressed("shoot"):
			player.throw_beer()
		if player.input.just_pressed("swap_weapon"):
			player.beer.cycle_held(player, 1)
		elif player.input.just_pressed("swap_weapon_prev"):
			player.beer.cycle_held(player, -1)
		if player.input.just_pressed("swap_gear") or player.input.just_pressed("swap_gear_prev"):
			player.place.swap_gear(player)
		return
	tick_scope(player)
	player.weapon.tick(
		delta, player.head.global_transform,
		player.input.pressed("shoot"), player.input.just_pressed("shoot"), player.aiming
	)
	if player.input.just_pressed("reload"):
		player.weapon.start_reload()
	if player.input.just_pressed("swap_weapon"):
		player.beer.cycle_held(player, 1)
	if player.input.just_pressed("swap_weapon_prev"):
		player.beer.cycle_held(player, -1)
	if player.input.just_pressed("swap_gear") or player.input.just_pressed("swap_gear_prev"):
		player.place.swap_gear(player)
	if player.input.just_pressed("melee"):
		try_melee(player)


func try_melee(player: Player) -> void:
	var origin := player.head.global_position
	var forward := -player.head.global_transform.basis.z
	var strength := player.buzz.strength_mult()
	if NetSession.is_active() and not player.multiplayer.is_server():
		player._request_melee.rpc_id(1, origin, forward, strength)
		play_melee(player)
		return
	if player.melee.shove(origin, forward, strength, player):
		play_melee(player)


func play_melee(player: Player) -> void:
	if player.body != null:
		player.body.start_melee()
	if player.raygun != null:
		player.raygun.start_melee()
	player.add_view_kick(PlayerLook.MELEE_VIEW_KICK)
	Sfx.play("melee_swing", player)
	if NetSession.is_active() and player.is_multiplayer_authority():
		player._replicate_melee.rpc()


func on_fired(player: Player) -> void:
	var kick := player.weapon.stats().kick
	player.raygun.kick(kick)
	player.add_view_kick(kick * PlayerLook.VIEW_KICK_DEG)
