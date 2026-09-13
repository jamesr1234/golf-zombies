extends GutTest
## Shop mech is a gear drop, same aim-and-shoot as a hex fort.

const PLAYER_SCENE := preload("res://scenes/players/player.tscn")


func after_each() -> void:
	NetSession.close()
	for node in get_tree().get_nodes_in_group("mechs"):
		if is_instance_valid(node):
			node.queue_free()


func test_buying_the_mech_does_not_spawn_it() -> void:
	var shop := Shop.new()
	var score := GameState.new(PackedInt32Array([4]))
	score.credit(Shop.MECH_PRICE)
	var buyer: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(buyer)
	assert_true(shop.buy("mech", score, [], buyer))
	assert_eq(score.mech_charges, 1)
	assert_eq(get_tree().get_nodes_in_group("mechs").size(), 0)


func test_gear_drops_the_suit_on_the_aimed_floor() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var score := GameState.new(PackedInt32Array([4]))
	score.add_mech_charges(1)
	player.flow = _Flow.new(score, self)
	player.place.host_place_mech(player, Vector3(4.0, 0.4, -3.0), 20.0)
	var mechs := get_tree().get_nodes_in_group("mechs")
	assert_eq(mechs.size(), 1)
	assert_almost_eq(mechs[0].global_position.x, 4.0, 0.1)
	assert_almost_eq(mechs[0].global_position.z, -3.0, 0.1)
	assert_almost_eq(mechs[0].global_position.y, 0.4 + MechSuit.STAND_LIFT, 0.05)
	assert_almost_eq(rad_to_deg(mechs[0].rotation.y), 20.0, 0.1)
	assert_eq(score.mech_charges, 0)
	assert_false(player.is_placing())


func test_swap_gear_aims_the_mech() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var score := GameState.new(PackedInt32Array([4]))
	score.add_mech_charges(1)
	player.flow = _Flow.new(score, self)
	player._swap_gear()
	assert_true(player.is_placing())
	assert_true(player.place.has_mechs(player))
	player._cancel_place()
	assert_false(player.is_placing())


class _Flow extends RefCounted:
	var score: GameState
	var hole = null
	var _root: Node

	func _init(p_score: GameState, root: Node) -> void:
		score = p_score
		_root = root

	func hole_node() -> Node:
		return _root
