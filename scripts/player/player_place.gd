class_name PlayerPlace
extends RefCounted
## Hex-barrier aiming ghost and plant confirmation. Player keeps the RPC that
## asks the host to spawn, so authority stays on the CharacterBody3D.

const _HexBarrier := preload("res://scripts/player/hex_barrier.gd")
const _WorldFx := preload("res://scripts/net/world_fx.gd")
const PLACE_WATER := 0.3

var ghost: _HexBarrier
var at := Vector3.ZERO
var ok := false


func has_charges(player: Player) -> bool:
	var card = player.wallet()
	return card != null and card.barrier_charges > 0


func begin(player: Player) -> void:
	if not has_charges(player) or not player.health.is_alive():
		return
	player.state = Player.State.PLACING
	if ghost == null:
		ghost = _HexBarrier.preview()
		player.add_child(ghost)
	tick(player)


func cancel(player: Player) -> void:
	if ghost != null:
		ghost.queue_free()
		ghost = null
	ok = false
	if player.state == Player.State.PLACING:
		player.state = Player.State.NORMAL


func confirm(player: Player) -> void:
	if not ok or not has_charges(player):
		return
	if NetSession.defers_world():
		player._request_place.rpc_id(1, at, player.look_yaw())
		cancel(player)
		return
	host_place(player, at, player.look_yaw())


func host_place(player: Player, point: Vector3, yaw_deg: float) -> void:
	if not has_charges(player):
		return
	if not player.wallet().try_place_barrier():
		cancel(player)
		return
	var parent: Node = player.flow.hole_node() if player.flow.has_method("hole_node") else null
	if parent == null:
		parent = player.get_parent()
	_HexBarrier.spawn(parent, point, yaw_deg)
	_WorldFx.announce_barrier(player, point, yaw_deg)
	cancel(player)


func tick(player: Player) -> void:
	if not has_charges(player):
		cancel(player)
		return
	var aimed := _HexBarrier.aim_point(
		player.get_world_3d(), player.head.global_position, -player.head.global_transform.basis.z
	)
	at = aimed["point"]
	ok = bool(aimed["ok"]) and not in_water(player, at)
	if ghost == null:
		return
	ghost.global_position = at
	ghost.rotation.y = deg_to_rad(player.look_yaw())
	ghost.set_ghost_visible(ok)


func look_at(player: Player) -> Vector3:
	if ghost != null:
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
	if player.is_placing():
		cancel(player)
		return
	if has_charges(player):
		begin(player)
