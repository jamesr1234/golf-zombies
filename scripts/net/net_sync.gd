class_name NetSync
extends Object
## Builds a MultiplayerSynchronizer with a modest send rate.

const PAWN_HZ := 0.05
const BALL_HZ := 0.04
const ZOMBIE_HZ := 0.08
const CART_HZ := 0.05


static func attach(
	node: Node, paths: PackedStringArray, interval := PAWN_HZ
) -> MultiplayerSynchronizer:
	var existing := node.get_node_or_null("Sync") as MultiplayerSynchronizer
	if existing != null:
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
	return sync


static func attach_pawn(node: Node) -> MultiplayerSynchronizer:
	return attach(node, PackedStringArray([
		":position", ":rotation", ":sync_pace",
	]), PAWN_HZ)


static func attach_health(node: Node) -> MultiplayerSynchronizer:
	return attach(node, PackedStringArray([
		":hp", ":state",
	]), 0.1)


static func attach_ball(node: Node) -> MultiplayerSynchronizer:
	return attach(node, PackedStringArray([
		":position", ":rotation", ":linear_velocity",
	]), BALL_HZ)


static func attach_zombie(node: Node) -> MultiplayerSynchronizer:
	return attach(node, PackedStringArray([
		":position", ":rotation",
	]), ZOMBIE_HZ)


static func attach_cart(node: Node) -> MultiplayerSynchronizer:
	return attach(node, PackedStringArray([
		":position", ":rotation",
	]), CART_HZ)
