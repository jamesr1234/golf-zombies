class_name CartMines
extends Object
## Every ride starts with a short mine rack. The passenger dumps them off the
## tail; the driver never touches them because R2 is already the boost.

const LOAD := 5
const ARM_TIME := 0.4
const TRIGGER := 1.55
const DAMAGE := 110.0
const BLAST := 5.0
const DROP_PAD := 1.35
const LIFT := 0.08
const _WorldFx := preload("res://scripts/net/world_fx.gd")


static func can_drop(cart: GolfCart, player: Player) -> bool:
	if cart == null or player == null or cart.mines <= 0:
		return false
	if player.health == null or not player.health.is_alive():
		return false
	return cart.passenger == player


static func drop_point(cart: GolfCart) -> Vector3:
	var back := cart.global_transform.basis.z
	back.y = 0.0
	if back.length_squared() < 0.0001:
		back = Vector3.BACK
	else:
		back = back.normalized()
	return _ground_at(cart, cart.global_position + back * (cart.axle_z() + DROP_PAD))


static func try_drop(cart: GolfCart, player: Player) -> bool:
	if cart == null or player == null:
		return false
	if NetSession.is_active() and not cart.is_multiplayer_authority():
		cart._request_drop_mine.rpc_id(1, player.peer_id)
		return true
	return commit_drop(cart, player)


static func commit_drop(cart: GolfCart, player: Player) -> bool:
	if not can_drop(cart, player):
		return false
	cart.mines -= 1
	if cart.mines <= 0:
		player.holding_mines = false
	var at := drop_point(cart)
	var root := _fx_root(cart)
	CartMine.deploy(root, at)
	_WorldFx.announce_mine(cart, at)
	_WorldFx.announce_sfx(cart, "mine_drop", player.peer_id)
	return true


static func _fx_root(from: Node) -> Node:
	if from == null or from.get_tree() == null:
		return from
	var root := from.get_tree().get_first_node_in_group("fx_root")
	return root if root != null else from.get_tree().current_scene


static func _ground_at(cart: GolfCart, at: Vector3) -> Vector3:
	var lift := Vector3.UP * LIFT
	if cart == null or not cart.is_inside_tree() or cart.get_world_3d() == null:
		return at + lift
	var space := cart.get_world_3d().direct_space_state
	if space == null:
		return at + lift
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * 8.0, at + Vector3.DOWN * 10.0
	)
	query.collision_mask = Layers.WORLD | Layers.PROP
	query.exclude = [cart.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return at + lift
	return hit.position + lift
