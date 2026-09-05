class_name PlayerPlace
extends RefCounted
## Hex-barrier and lean-ladder aiming ghosts. Player keeps the RPC that asks
## the host to spawn, so authority stays on the CharacterBody3D.

const _HexBarrier := preload("res://scripts/player/hex_barrier.gd")
const _LeanLadder := preload("res://scripts/player/lean_ladder.gd")
const _WorldFx := preload("res://scripts/net/world_fx.gd")
const PLACE_WATER := 0.3

var ghost: _HexBarrier
var ladder_ghost: _LeanLadder
var at := Vector3.ZERO
var ok := false
var kind := "fort"
var length := _LeanLadder.MIN_LEN
var yaw := 0.0


func has_charges(player: Player) -> bool:
	return has_barriers(player) or has_ladders(player)


func has_barriers(player: Player) -> bool:
	var card = player.wallet()
	return card != null and card.barrier_charges > 0


func has_ladders(player: Player) -> bool:
	var card = player.wallet()
	return card != null and card.ladder_charges > 0


func begin(player: Player) -> void:
	if not has_charges(player) or not player.health.is_alive():
		return
	player.state = Player.State.PLACING
	tick(player)


func cancel(player: Player) -> void:
	if ghost != null:
		ghost.queue_free()
		ghost = null
	if ladder_ghost != null:
		ladder_ghost.queue_free()
		ladder_ghost = null
	ok = false
	if player.state == Player.State.PLACING:
		player.state = Player.State.NORMAL


func confirm(player: Player) -> void:
	if not ok or not has_charges(player):
		return
	if kind == "ladder":
		if NetSession.defers_world():
			player._request_place_ladder.rpc_id(1, at, yaw, length)
			cancel(player)
			return
		host_place_ladder(player, at, yaw, length)
		return
	if NetSession.defers_world():
		player._request_place.rpc_id(1, at, player.look_yaw())
		cancel(player)
		return
	host_place(player, at, player.look_yaw())


func host_place(player: Player, point: Vector3, yaw_deg: float) -> void:
	if not has_barriers(player):
		return
	if not player.wallet().try_place_barrier():
		cancel(player)
		return
	var parent := _hole(player)
	_HexBarrier.spawn(parent, point, yaw_deg)
	_WorldFx.announce_barrier(player, point, yaw_deg)
	cancel(player)


func host_place_ladder(player: Player, foot: Vector3, yaw_deg: float, span: float) -> void:
	if not has_ladders(player):
		return
	if not player.wallet().try_place_ladder():
		cancel(player)
		return
	var parent := _hole(player)
	_LeanLadder.spawn(parent, foot, yaw_deg, span)
	_WorldFx.announce_ladder(player, foot, yaw_deg, span)
	cancel(player)


func tick(player: Player) -> void:
	if not has_charges(player):
		cancel(player)
		return
	var look := -player.head.global_transform.basis.z
	var from := player.head.global_position
	var world := player.get_world_3d()
	var wall := _LeanLadder.plant_point(world, from, look)
	var floor := _HexBarrier.aim_point(world, from, look)
	if bool(wall.get("ok", false)) and has_ladders(player):
		kind = "ladder"
		at = wall["foot"]
		length = float(wall["length"])
		yaw = float(wall["yaw"])
		ok = not in_water(player, at)
		_show_ladder(player, ok, yaw)
	elif bool(floor.get("ok", false)) and has_barriers(player):
		kind = "fort"
		at = floor["point"]
		ok = not in_water(player, at)
		_show_hex(player, ok)
	else:
		ok = false
		_hide_ghosts()


func look_at(player: Player) -> Vector3:
	if ghost != null or ladder_ghost != null:
		return at
	return (
		player.global_position
		+ Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(player.look_yaw())) * 6.0
	)


func in_water(player: Player, point: Vector3) -> bool:
	if player.flow == null or player.flow.hole == null:
		return false
	return player.flow.hole.water_depth_at(point) >= PLACE_WATER


func swap_gear(player: Player) -> void:
	var branch := "none"
	if player.is_placing():
		cancel(player)
		branch = "place_off"
	elif player.glide.equipped:
		player.glide.unequip(player)
		if has_charges(player):
			begin(player)
			branch = "glide_to_place"
		else:
			branch = "unequip"
	elif player.glide.owns(player):
		player.glide.equip(player)
		branch = "equip"
	elif has_charges(player):
		begin(player)
		branch = "place_on"
	# #region agent log
	player.glide._dbg("B", "player_place.gd:swap_gear", "gear cycle", {
		"branch": branch,
		"owns": player.glide.owns(player),
		"equipped": player.glide.equipped,
		"placing": player.is_placing(),
		"charges": has_charges(player),
	})
	# #endregion


func _hole(player: Player) -> Node:
	if player.flow != null and player.flow.has_method("hole_node"):
		var parent: Node = player.flow.hole_node()
		if parent != null:
			return parent
	return player.get_parent()


func _show_hex(player: Player, valid: bool) -> void:
	_free_ladder()
	if ghost == null:
		ghost = _HexBarrier.preview()
		player.add_child(ghost)
	ghost.global_position = at
	ghost.rotation.y = deg_to_rad(player.look_yaw())
	ghost.set_ghost_visible(valid)


func _show_ladder(player: Player, valid: bool, yaw_deg: float) -> void:
	_free_hex()
	if ladder_ghost == null:
		ladder_ghost = _LeanLadder.preview()
		player.add_child(ladder_ghost)
	ladder_ghost.global_transform = _LeanLadder.pose_at(at, yaw_deg)
	ladder_ghost.set_span(length)
	ladder_ghost.set_ghost_visible(valid)


func _hide_ghosts() -> void:
	if ghost != null:
		ghost.set_ghost_visible(false)
	if ladder_ghost != null:
		ladder_ghost.set_ghost_visible(false)


func _free_hex() -> void:
	if ghost != null:
		ghost.queue_free()
		ghost = null


func _free_ladder() -> void:
	if ladder_ghost != null:
		ladder_ghost.queue_free()
		ladder_ghost = null
