class_name PlayerVehicle
extends RefCounted
## Cart boarding and mech seal / eject. Keeps ride state transitions off the
## main Player tick so movement and combat stay readable.


func enter_ride(player: Player) -> void:
	player._drop_climb()
	player._cancel_place()
	player.state = Player.State.RIDING
	player.velocity = Vector3.ZERO
	player.look.cart_chase = false
	player._set_solid(false)
	if player._shield != null:
		player._shield.set_raised(false)


func exit_ride(player: Player) -> void:
	player.state = Player.State.NORMAL
	player.look.cart_chase = false
	player._set_solid(true)


func enter_mech(player: Player, suit: MechSuit) -> void:
	player._drop_climb()
	player._cancel_place()
	player.mech = suit
	player.state = Player.State.MECH
	player.velocity = Vector3.ZERO
	player._set_solid(false)
	player._set_hidden_in_mech(true)
	player.look.cart_chase = false
	if player._shield != null:
		player._shield.set_raised(false)


func eject_from_mech(player: Player, at: Vector3, facing_yaw: float) -> void:
	player.mech = null
	player.look.cart_chase = false
	player._set_hidden_in_mech(false)
	player._set_solid(true)
	if player.state == Player.State.MECH or player.state == Player.State.GOLFING:
		player.state = Player.State.NORMAL
	player.stand_at(at, facing_yaw)


func sit_in_mech(player: Player, sit_at: Vector3, facing_yaw: float, pitch_deg: float) -> void:
	player.global_position = sit_at
	player.velocity = Vector3.ZERO
	if player.is_multiplayer_authority():
		return
	player.set_look_yaw(facing_yaw)
	player.head.rotation.x = deg_to_rad(pitch_deg)


func drop_from_lost_ride(player: Player) -> void:
	var drop := player.global_position + Vector3.UP * 0.4
	if player.cart != null:
		drop = player.cart.exit_point(1.0 if player.cart.driver == player else -1.0)
	exit_ride(player)
	player.stand_at(drop, player.look_yaw())


func sit_as_driver(player: Player, sit_at: Vector3, facing_yaw: float) -> void:
	player.look.sit_driver(player, sit_at, facing_yaw)


func sit_as_passenger(player: Player, sit_at: Vector3) -> void:
	player.global_position = sit_at


func enter_golf(player: Player) -> void:
	player._drop_climb()
	player._cancel_place()
	player.state = Player.State.GOLFING
	player.velocity = Vector3.ZERO
	player.aiming = false
	if player.weapon != null:
		player.weapon.zoom_step = -1
	if player._shield != null:
		player._shield.set_raised(false)


func exit_golf(player: Player) -> void:
	if player.mech != null and player.mech.pilot == player:
		player.state = Player.State.MECH
		return
	player.state = Player.State.NORMAL


func active_cart(player: Player) -> GolfCart:
	if player.flow != null and player.flow.has_method("cart_for"):
		return player.flow.cart_for(player)
	return player.cart


func ready_mech(player: Player) -> MechSuit:
	if player.get_tree() == null:
		return null
	for node in player.get_tree().get_nodes_in_group("mechs"):
		var suit := node as MechSuit
		if suit != null and suit.can_close(player):
			return suit
	return null


func spawn_at(player: Player, position: Vector3, facing_yaw: float) -> void:
	if player.state == Player.State.GOLFING and player.golf != null:
		player.golf.release()
	if player.mech != null:
		player.mech.release_pilot()
	if player.cart != null and player.cart.is_riding(player):
		player.cart.eject(player)
	elif player.state == Player.State.RIDING:
		exit_ride(player)
	if player.state == Player.State.GOLFING and player.golf != null:
		player.golf.release()
	if player.is_placing():
		player._cancel_place()
	player.look.cheer_left = 0.0
	if player.combat.shield != null:
		player.combat.shield.set_raised(false)
	if player.state == Player.State.SHIELDING or player.state == Player.State.PLACING:
		player.state = Player.State.NORMAL
	player.stand_at(position, facing_yaw)
	player.look.pitch = 0.0
	player.swim.underwater = false
	if player.state == Player.State.SWIMMING or player.state == Player.State.CLIMBING:
		player._drop_climb()
		player.state = Player.State.NORMAL
	if player.is_milling():
		player.mill_desk.release(player)
