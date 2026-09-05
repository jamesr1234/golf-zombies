class_name WeaponGate
extends Object
## A hole creator can pin a gun to the front half of their hole. Past the line
## the gun stops shooting and the only thing left to do with it is throw it at
## a rival, which floors them and costs you the gun. None of this is announced:
## the line is drawn in the creator and nowhere else.
##
## Who a thrown gun may floor belongs to ThrownGun, so this file only ever calls
## into it and never the other way about. The two referring to each other left
## both half-parsed whenever the editor resolved them early.


## Where the player stands down the hole, 0 at the tee and 1 at the cup.
static func progress(player: Player) -> float:
	if player == null or player.flow == null or player.flow.hole == null:
		return 0.0
	return HeightField.along_t(player.flow.hole, player.global_position)


static func past(gate: float, at: float) -> bool:
	return gate >= 0.0 and at > gate


## True once the gun in hand has been carried past its line. Almost every gun
## has no line, so the walk down the centreline only happens for the ones that do.
static func blocked(player: Player) -> bool:
	if player == null or player.weapon == null or player.weapon.stats() == null:
		return false
	var gate := player.weapon.gate()
	if gate < 0.0:
		return false
	return past(gate, progress(player))


## Lobs the held gun and takes it out of the bag. Gone either way: a miss is
## still a gun you no longer have.
static func throw_gun(player: Player) -> bool:
	if player == null or player.weapon == null or not blocked(player):
		return false
	var view := player.head.global_transform
	var direction := -view.basis.z
	var origin := view.origin + direction * 0.9
	if NetSession.defers_world():
		# The client shows its own throw straight away and lets the host say
		# who it landed on, the same split a shot takes.
		_lob(player, origin, direction, null)
		player.request_host_throw(origin, direction)
		return true
	_lob(player, origin, direction, player)
	return true


## Host side of a client's throw: judge it against the same gate, then lob.
static func host_throw(player: Player, origin: Vector3, direction: Vector3) -> bool:
	if player == null or player.weapon == null or not blocked(player):
		return false
	_lob(player, origin, direction, player)
	return true


static func _lob(player: Player, origin: Vector3, direction: Vector3, owner: Player) -> void:
	var stats := player.weapon.stats()
	ThrownGun.spawn(_fx_root(player), origin, direction, stats, owner)
	player.weapon.drop_gun(player.weapon.index)


static func _fx_root(player: Player) -> Node:
	var tree := player.get_tree()
	if tree == null:
		return player
	var root := tree.get_first_node_in_group("fx_root")
	if root != null:
		return root
	return tree.current_scene if tree.current_scene != null else tree.root
