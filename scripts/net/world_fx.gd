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

const _ShapeDrop := preload("res://scripts/player/shape_drop.gd")

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


static func announce_ladder(from: Node, at: Vector3, yaw_deg: float, length: float) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_ladder.rpc(at, yaw_deg, length)


static func announce_ladder_fall(from: Node, at: Vector3) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_ladder_fall.rpc(at)


static func announce_rocket(
	from: Node, origin: Vector3, fly: Vector3, damage: float, radius: float, range_m: float
) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_rocket.rpc(origin, fly, damage, radius, range_m)


static func announce_wall_break(from: Node, at: Vector3, seed: int) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_wall_break.rpc(at, seed)


static func announce_net(
	from: Node, origin: Vector3, fly: Vector3, radius: float, duration: float, range_m: float
) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_net.rpc(origin, fly, radius, duration, range_m)


static func announce_door_shot(
	from: Node, origin: Vector3, fly: Vector3, duration: float, shooter_peer: int
) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_door_shot.rpc(origin, fly, duration, shooter_peer)


static func announce_door(
	from: Node, at: Vector3, face: Vector3, duration: float, shooter_peer: int
) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_door.rpc(at, face, duration, shooter_peer)


static func announce_shape_drop(from: Node, at: Vector3, count: int, seed: int) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_shape_drop.rpc(at, count, seed)


static func announce_shape_kick(
	from: Node, origin: Vector3, forward: Vector3, strength: float
) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_shape_kick.rpc(origin, forward, strength)


static func announce_grapple(
	from: Node, origin: Vector3, fly: Vector3, skip_peer := 0
) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_grapple.rpc(origin, fly, skip_peer)


static func announce_trap(from: Node, at: Vector3, radius: float, duration: float) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_trap.rpc(at, radius, duration)


static func announce_mine(from: Node, at: Vector3) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_mine.rpc(at)


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


static func announce_flare(from: Node, duration: float, skip_peer := 0) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_flare.rpc(from.get_path(), duration, skip_peer)


static func announce_fireworks(from: Node, at: Vector3, color: Color) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_fireworks.rpc(at, color)


static func announce_cart_girl(from: Node, kind: String) -> void:
	var fx := _broadcaster(from)
	if fx != null:
		fx._replicate_cart_girl.rpc(kind)


static func announce_mech(
	from: Node,
	owner_peer: int,
	origin: Vector3,
	yaw: float,
	stick: Vector2,
	sprint: bool,
	sealed: bool,
	pilot_id: int,
	reliable := false
) -> void:
	var fx := _broadcaster(from)
	if fx == null:
		return
	if reliable:
		fx._replicate_mech_seal.rpc(owner_peer, origin, yaw, stick, sprint, sealed, pilot_id)
	else:
		fx._replicate_mech.rpc(owner_peer, origin, yaw, stick, sprint, sealed, pilot_id)


static func announce_mill(
	from: Node, at: Vector3, stick: Vector2, rotor: float, driven: bool, reliable := false
) -> void:
	var fx := _broadcaster(from)
	if fx == null:
		return
	if reliable:
		fx._replicate_mill_latch.rpc(at, stick, rotor, driven)
	else:
		fx._replicate_mill.rpc(at, stick, rotor, driven)


func apply_barrier(at: Vector3, yaw_deg: float) -> Node:
	return HexBarrier.spawn(_fx_root(), at, yaw_deg)


func apply_ladder(at: Vector3, yaw_deg: float, length: float) -> Node:
	return LeanLadder.spawn(_fx_root(), at, yaw_deg, length)


func apply_ladder_fall(at: Vector3) -> Node:
	var best: LeanLadder
	var best_d := 1.6
	for node in get_tree().get_nodes_in_group("climb_walls"):
		var ladder := node as LeanLadder
		if ladder == null or not ladder.is_live():
			continue
		var d := ladder.global_position.distance_to(at)
		if d < best_d:
			best = ladder
			best_d = d
	if best != null:
		best.kick()
	return best


func apply_rocket(
	origin: Vector3, fly: Vector3, damage: float, radius: float, range_m: float
) -> Rocket:
	return Rocket.spawn_flight(_fx_root(), origin, fly, damage, radius, range_m, true)


func apply_wall_break(at: Vector3, seed: int) -> int:
	return WallBreak.punch(self, at, null, Vector3.ZERO, seed)


func apply_net_shot(
	origin: Vector3, fly: Vector3, radius: float, duration: float, range_m: float
) -> NetShot:
	return NetShot.spawn_flight(_fx_root(), origin, fly, radius, duration, range_m, true)


func apply_door_shot(
	origin: Vector3, fly: Vector3, duration: float, shooter_peer: int
) -> DoorShot:
	return DoorShot.spawn_flight(_fx_root(), origin, fly, duration, shooter_peer, true)


func apply_door(
	at: Vector3, face: Vector3, duration: float, shooter_peer: int
) -> WarpDoor:
	return WarpDoor.spawn_facing(_fx_root(), at, face, duration, shooter_peer, true)


func apply_shape_drop(at: Vector3, count: int, seed: int) -> Node3D:
	return _ShapeDrop.rain(_fx_root(), at, count, seed, true)


func apply_shape_kick(origin: Vector3, forward: Vector3, strength: float) -> int:
	return _ShapeDrop.yeet_in_arc(get_tree(), origin, forward, strength)


func apply_grapple(origin: Vector3, fly: Vector3, skip_peer := 0) -> GrappleHook:
	if _skip(skip_peer):
		return null
	var hook := GrappleHook.spawn(_fx_root(), origin, fly, null, true)
	if hook != null:
		hook.fly_to(origin + fly.normalized() * Grappler.RANGE)
	return hook


func apply_trap(at: Vector3, radius: float, duration: float) -> NetTrap:
	return NetTrap.deploy(_fx_root(), at, radius, duration, true)


func apply_mine(at: Vector3) -> CartMine:
	return CartMine.deploy(_fx_root(), at, true)


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


func apply_flare(zombie_path: NodePath, duration: float, skip_peer := 0) -> Zombie:
	if _skip(skip_peer):
		return null
	var zombie := get_tree().root.get_node_or_null(zombie_path) as Zombie
	if zombie == null:
		return null
	zombie.mark_flare(duration, false)
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
func _replicate_ladder(at: Vector3, yaw_deg: float, length: float) -> void:
	apply_ladder(at, yaw_deg, length)


@rpc("authority", "call_remote", "reliable")
func _replicate_ladder_fall(at: Vector3) -> void:
	apply_ladder_fall(at)


@rpc("authority", "call_remote", "reliable")
func _replicate_rocket(
	origin: Vector3, fly: Vector3, damage: float, radius: float, range_m: float
) -> void:
	apply_rocket(origin, fly, damage, radius, range_m)


@rpc("authority", "call_remote", "reliable")
func _replicate_wall_break(at: Vector3, seed: int) -> void:
	apply_wall_break(at, seed)


@rpc("authority", "call_remote", "reliable")
func _replicate_net(
	origin: Vector3, fly: Vector3, radius: float, duration: float, range_m: float
) -> void:
	apply_net_shot(origin, fly, radius, duration, range_m)


@rpc("authority", "call_remote", "reliable")
func _replicate_door_shot(
	origin: Vector3, fly: Vector3, duration: float, shooter_peer: int
) -> void:
	apply_door_shot(origin, fly, duration, shooter_peer)


@rpc("authority", "call_remote", "reliable")
func _replicate_door(
	at: Vector3, face: Vector3, duration: float, shooter_peer: int
) -> void:
	apply_door(at, face, duration, shooter_peer)


@rpc("authority", "call_remote", "reliable")
func _replicate_shape_drop(at: Vector3, count: int, seed: int) -> void:
	apply_shape_drop(at, count, seed)


@rpc("authority", "call_remote", "reliable")
func _replicate_shape_kick(origin: Vector3, forward: Vector3, strength: float) -> void:
	apply_shape_kick(origin, forward, strength)


@rpc("authority", "call_remote", "unreliable")
func _replicate_grapple(origin: Vector3, fly: Vector3, skip_peer: int) -> void:
	apply_grapple(origin, fly, skip_peer)


@rpc("authority", "call_remote", "reliable")
func _replicate_trap(at: Vector3, radius: float, duration: float) -> void:
	apply_trap(at, radius, duration)


@rpc("authority", "call_remote", "reliable")
func _replicate_mine(at: Vector3) -> void:
	apply_mine(at)


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
func _replicate_flare(zombie_path: NodePath, duration: float, skip_peer: int) -> void:
	apply_flare(zombie_path, duration, skip_peer)


@rpc("authority", "call_remote", "unreliable")
func _replicate_fireworks(at: Vector3, color: Color) -> void:
	apply_fireworks(at, color)


@rpc("authority", "call_remote", "reliable")
func _replicate_cart_girl(kind: String) -> void:
	apply_cart_girl(kind)


@rpc("authority", "call_remote", "unreliable")
func _replicate_mech(
	owner_peer: int, origin: Vector3, yaw: float, stick: Vector2, sprint: bool, sealed: bool, pilot_id: int
) -> void:
	apply_mech(owner_peer, origin, yaw, stick, sprint, sealed, pilot_id)


@rpc("authority", "call_remote", "reliable")
func _replicate_mech_seal(
	owner_peer: int, origin: Vector3, yaw: float, stick: Vector2, sprint: bool, sealed: bool, pilot_id: int
) -> void:
	apply_mech(owner_peer, origin, yaw, stick, sprint, sealed, pilot_id)


@rpc("authority", "call_remote", "unreliable")
func _replicate_mill(at: Vector3, stick: Vector2, rotor: float, driven: bool) -> void:
	apply_mill(at, stick, rotor, driven)


@rpc("authority", "call_remote", "reliable")
func _replicate_mill_latch(at: Vector3, stick: Vector2, rotor: float, driven: bool) -> void:
	apply_mill(at, stick, rotor, driven)


func apply_mill(at: Vector3, stick: Vector2, rotor: float, driven: bool) -> WindmillControl:
	return WindmillControl.take_replicated(get_tree(), at, stick, rotor, driven)


func apply_mech(
	owner_peer: int, origin: Vector3, yaw: float, stick: Vector2, sprint: bool, sealed: bool, pilot_id: int
) -> void:
	var mech := _mech_for(owner_peer)
	if mech == null:
		mech = _spawn_watch_mech(owner_peer, origin, yaw)
	elif owner_peer > 0 and int(mech.get("owner_peer")) <= 0:
		mech.set("owner_peer", owner_peer)
	if mech != null and mech.has_method("take_wire"):
		var pose := Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), origin)
		mech.take_wire(pose, stick, sprint, sealed, pilot_id)


func _mech_for(owner_peer: int) -> Node:
	var unclaimed: Node
	var loose := 0
	for node in get_tree().get_nodes_in_group("mechs"):
		var peer := int(node.get("owner_peer"))
		if owner_peer > 0 and peer == owner_peer:
			return node
		if peer <= 0:
			unclaimed = node
			loose += 1
	return unclaimed if loose == 1 else null


func _spawn_watch_mech(owner_peer: int, origin: Vector3, yaw: float) -> Node:
	var packed := load("res://scenes/course/items/mech_suit.tscn") as PackedScene
	if packed == null:
		return null
	var mech: Node = packed.instantiate()
	mech.set("owner_peer", owner_peer)
	_mech_root().add_child(mech)
	if mech is Node3D:
		(mech as Node3D).global_position = origin
		(mech as Node3D).rotation.y = yaw
	return mech


func _mech_root() -> Node:
	var world := get_parent()
	if world != null:
		var mechs := world.get_node_or_null("Mechs")
		if mechs != null:
			return mechs
	return _fx_root()


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
