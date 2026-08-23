class_name WorldFx
extends Node
## Host copies short-lived world objects onto clients: walls, shots, cans, ammo,
## hitscan, hit flops, fireworks, and the one-shot looks that NetSync does not carry.
##
## Looks (tracers, flops, bangs, bursts) ride unreliable. They fire on every
## pellet, and a reliable queue of those is what parked Computer 2: the ordered
## channel backed up until clock and puppet traffic sat behind it. A dropped
## spark is invisible; a jammed link is a freeze. Things that must exist
## (walls, rockets, ammo, the cart girl) stay reliable.

var _ammo_seq := 0
var _ammo: Dictionary = {}


func _ready() -> void:
	add_to_group("world_fx")


static func find_in(from: Node) -> WorldFx:
	if from == null or not from.is_inside_tree():
		return null
	return from.get_tree().get_first_node_in_group("world_fx") as WorldFx


static func take_ammo_id(from: Node) -> int:
	var fx := find_in(from)
	if fx == null:
		return 0
	fx._ammo_seq += 1
	return fx._ammo_seq


static func announce_barrier(from: Node, at: Vector3, yaw_deg: float) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_barrier.rpc(at, yaw_deg)


static func announce_rocket(
	from: Node, origin: Vector3, fly: Vector3, damage: float, radius: float, range_m: float
) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_rocket.rpc(origin, fly, damage, radius, range_m)


static func announce_net(
	from: Node, origin: Vector3, fly: Vector3, radius: float, duration: float, range_m: float
) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_net.rpc(origin, fly, radius, duration, range_m)


static func announce_trap(from: Node, at: Vector3, radius: float, duration: float) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_trap.rpc(at, radius, duration)


static func announce_beer(from: Node, origin: Vector3, fly: Vector3) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_beer.rpc(origin, fly)


static func announce_ammo(from: Node, drop_id: int, at: Vector3, amount: int) -> void:
	if drop_id <= 0:
		return
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_ammo.rpc(drop_id, at, amount)


static func announce_ammo_gone(from: Node, drop_id: int) -> void:
	if drop_id <= 0:
		return
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_ammo_gone.rpc(drop_id)


static func announce_hitscan(
	from: Node, muzzle: Vector3, end: Vector3, kind: String, color: Color, skip_peer := 0
) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_hitscan.rpc(muzzle, end, kind, color, skip_peer)


static func announce_sfx(from: Node, cue: String, skip_peer := 0) -> void:
	if cue.is_empty():
		return
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_sfx.rpc(cue, skip_peer)


static func announce_zombie_hit(
	from: Node, region: int, direction: Vector3, strength: float, locked := false,
	planted := true, skip_peer := 0
) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_zombie_hit.rpc(
			from.get_path(), region, direction, strength, locked, planted, skip_peer
		)


static func announce_fireworks(from: Node, at: Vector3, color: Color) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_fireworks.rpc(at, color)


static func announce_cart_girl(from: Node, kind: String) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_cart_girl.rpc(kind)


func apply_barrier(at: Vector3, yaw_deg: float) -> Node:
	return HexBarrier.spawn(_fx_root(), at, yaw_deg)


func apply_rocket(
	origin: Vector3, fly: Vector3, damage: float, radius: float, range_m: float
) -> Rocket:
	return Rocket.spawn_flight(_fx_root(), origin, fly, damage, radius, range_m, true)


func apply_net_shot(
	origin: Vector3, fly: Vector3, radius: float, duration: float, range_m: float
) -> NetShot:
	return NetShot.spawn_flight(_fx_root(), origin, fly, radius, duration, range_m, true)


func apply_trap(at: Vector3, radius: float, duration: float) -> NetTrap:
	return NetTrap.deploy(_fx_root(), at, radius, duration, true)


func apply_beer(origin: Vector3, fly: Vector3) -> ThrownBeer:
	return ThrownBeer.spawn(_fx_root(), origin, fly, true)


func apply_ammo(drop_id: int, at: Vector3, amount: int) -> AmmoPickup:
	var pickup := AmmoPickup.spawn(_fx_root(), at, amount, drop_id, true)
	if pickup != null and drop_id > 0:
		_ammo[drop_id] = pickup
	return pickup


func remove_ammo(drop_id: int) -> void:
	var pickup := _ammo.get(drop_id) as AmmoPickup
	_ammo.erase(drop_id)
	if pickup != null and is_instance_valid(pickup):
		pickup.queue_free()


func apply_hitscan(muzzle: Vector3, end: Vector3, kind: String, color: Color, skip_peer := 0) -> void:
	if _skip(skip_peer):
		return
	var root := _fx_root()
	match kind:
		"sniper":
			HitFx.sniper_beam(root, muzzle, end, color)
		"sniper_hit":
			HitFx.sniper_beam(root, muzzle, end, HitFx.sniper_tint(true))
			HitFx.spark(root, end, color)
		_:
			HitFx.spawn(root, muzzle, end, color)


func apply_sfx(cue: String, skip_peer := 0) -> void:
	if _skip(skip_peer):
		return
	Sfx.play(cue)


func apply_zombie_hit(
	zombie_path: NodePath, region: int, direction: Vector3, strength: float,
	locked := false, planted := true, skip_peer := 0
) -> Zombie:
	if _skip(skip_peer):
		return null
	var zombie := get_tree().root.get_node_or_null(zombie_path) as Zombie
	if zombie == null:
		return null
	zombie.apply_hit_look(region as Ragdoll.Region, direction, strength, locked, planted)
	return zombie


func apply_fireworks(at: Vector3, color: Color) -> Node:
	return Fireworks.spawn(_fx_root(), at, color)


func apply_cart_girl(kind: String) -> void:
	var girl := get_tree().get_first_node_in_group("cart_girl")
	if girl == null or not girl.has_method("cheer"):
		return
	if kind == "cheer":
		girl.cheer("enjoy!")


@rpc("authority", "call_remote", "reliable")
func _replicate_barrier(at: Vector3, yaw_deg: float) -> void:
	apply_barrier(at, yaw_deg)


@rpc("authority", "call_remote", "reliable")
func _replicate_rocket(
	origin: Vector3, fly: Vector3, damage: float, radius: float, range_m: float
) -> void:
	apply_rocket(origin, fly, damage, radius, range_m)


@rpc("authority", "call_remote", "reliable")
func _replicate_net(
	origin: Vector3, fly: Vector3, radius: float, duration: float, range_m: float
) -> void:
	apply_net_shot(origin, fly, radius, duration, range_m)


@rpc("authority", "call_remote", "reliable")
func _replicate_trap(at: Vector3, radius: float, duration: float) -> void:
	apply_trap(at, radius, duration)


@rpc("authority", "call_remote", "reliable")
func _replicate_beer(origin: Vector3, fly: Vector3) -> void:
	apply_beer(origin, fly)


@rpc("authority", "call_remote", "reliable")
func _replicate_ammo(drop_id: int, at: Vector3, amount: int) -> void:
	apply_ammo(drop_id, at, amount)


@rpc("authority", "call_remote", "reliable")
func _replicate_ammo_gone(drop_id: int) -> void:
	remove_ammo(drop_id)


@rpc("authority", "call_remote", "unreliable")
func _replicate_hitscan(
	muzzle: Vector3, end: Vector3, kind: String, color: Color, skip_peer: int
) -> void:
	apply_hitscan(muzzle, end, kind, color, skip_peer)


@rpc("authority", "call_remote", "unreliable")
func _replicate_sfx(cue: String, skip_peer: int) -> void:
	apply_sfx(cue, skip_peer)


@rpc("authority", "call_remote", "unreliable")
func _replicate_zombie_hit(
	zombie_path: NodePath, region: int, direction: Vector3, strength: float, locked: bool,
	planted: bool, skip_peer: int
) -> void:
	apply_zombie_hit(zombie_path, region, direction, strength, locked, planted, skip_peer)


@rpc("authority", "call_remote", "unreliable")
func _replicate_fireworks(at: Vector3, color: Color) -> void:
	apply_fireworks(at, color)


@rpc("authority", "call_remote", "reliable")
func _replicate_cart_girl(kind: String) -> void:
	apply_cart_girl(kind)


static func _broadcaster(from: Node) -> WorldFx:
	if not NetSession.is_active() or from == null or not from.is_inside_tree():
		return null
	if not from.multiplayer.is_server():
		return null
	return find_in(from)


func _fx_root() -> Node:
	var root := get_tree().get_first_node_in_group("fx_root")
	return root if root != null else get_parent()


func _skip(skip_peer: int) -> bool:
	return skip_peer != 0 and skip_peer == multiplayer.get_unique_id()
