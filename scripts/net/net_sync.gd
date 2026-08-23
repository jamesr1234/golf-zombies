class_name NetSync
extends Object
## Builds a MultiplayerSynchronizer with a modest send rate.

## Seconds between sends. The synchronizer only sends on a physics tick, so a
## value is really the next whole tick at or above it: at 60 Hz two ticks is
## 33.3 ms and three is 50 ms. Sit clear of a boundary rather than on it, since
## 0.034 reads as just past two ticks and silently costs a third one, halving the
## rate to 20 Hz.
## Two ticks, 30 Hz.
const PAWN_HZ := 0.03
## Three ticks, 20 Hz.
const BALL_HZ := 0.04
const ZOMBIE_HZ := 0.045
## Two ticks, 30 Hz. Carts cover ground fast enough that a missed send shows.
const CART_HZ := 0.03

## How far behind the newest snapshot a watched puppet is drawn, so a clump of
## late packets still has one queued ahead of it. Measured wifi jitter reaches
## roughly this far, and a queue shorter than the jitter runs dry.
##
## Only pawns and carts pay it. Zombies are what you shoot, the host scores shots
## against where they really are, and drawing them a tenth of a second behind
## would just make you miss. Nothing you aim at is buffered.
const WATCH_DELAY := 0.1


static func attach(
	node: Node, paths: PackedStringArray, interval := PAWN_HZ, authority := -1
) -> MultiplayerSynchronizer:
	var existing := node.get_node_or_null("Sync") as MultiplayerSynchronizer
	if existing != null:
		if authority >= 0:
			existing.set_multiplayer_authority(authority)
		return existing
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for path in paths:
		var node_path := NodePath(path)
		cfg.add_property(node_path)
		cfg.property_set_replication_mode(
			node_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS
		)
	sync.replication_config = cfg
	sync.replication_interval = interval
	node.add_child(sync)
	if authority >= 0:
		sync.set_multiplayer_authority(authority)
	return sync


static func attach_pawn(node: Node, authority := 1) -> MultiplayerSynchronizer:
	return attach(node, PackedStringArray([
		":sync_xform", ":sync_pace", ":aiming",
		":sync_gun", ":holding_beer",
		":sync_state", ":sync_dive", ":sync_firing", ":sync_reload", ":sync_scoped",
		":sync_pitch",
	]), PAWN_HZ, authority)


static func attach_health(node: Node) -> MultiplayerSynchronizer:
	return attach(node, PackedStringArray([
		":hp", ":state",
	]), 0.1, 1)


static func attach_ball(node: Node) -> MultiplayerSynchronizer:
	return attach(node, PackedStringArray([
		":sync_xform", ":linear_velocity",
	]), BALL_HZ)


static func attach_zombie(node: Node) -> MultiplayerSynchronizer:
	return attach(node, PackedStringArray([
		":sync_xform",
		":allied", ":sync_netted", ":sync_drink", ":sync_dying", ":sync_yaw",
	]), ZOMBIE_HZ)


static func attach_cart(node: Node) -> MultiplayerSynchronizer:
	return attach(node, PackedStringArray([
		":sync_xform",
		":turbo", ":ram_plate", ":armored",
	]), CART_HZ)


static func attach_cart_girl(node: Node) -> MultiplayerSynchronizer:
	return attach(node, PackedStringArray([
		":sync_xform",
		":visit", ":cooler_open", ":tending",
	]), CART_HZ)
