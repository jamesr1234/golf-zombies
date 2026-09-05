extends GutTest
## Gear-select the packed suit, then jump off a real drop.

const PLAYER := preload("res://scenes/players/player.tscn")
const STEP := 1.0 / 60.0


func test_no_suit_does_not_deploy_from_a_tower() -> void:
	var player := await _on_tower()
	var pad := _pad(player)
	pad.tap("jump")
	player._move(STEP)
	assert_false(player.is_gliding())


func test_owned_but_not_equipped_does_not_deploy() -> void:
	var player := await _on_tower()
	_own(player)
	var pad := _pad(player)
	pad.tap("jump")
	player._move(STEP)
	assert_false(player.is_gliding())
	assert_false(player.glide.equipped)


func test_owned_flat_jump_does_not_deploy() -> void:
	var player := await _on_floor()
	_equip(player)
	var pad := _pad(player)
	pad.tap("jump")
	player._move(STEP)
	assert_false(player.is_gliding())
	assert_gt(player.velocity.y, 2.0)


func test_equipped_tower_jump_deploys_that_frame() -> void:
	var player := await _on_tower()
	_equip(player)
	assert_true(_wings_mode(player) == PlayerBody.WINGS_PACKED)
	var pad := _pad(player)
	pad.tap("jump")
	player._move(STEP)
	assert_true(player.is_gliding(), "the wings open on the jump, not after the apex")
	assert_true(_wings_mode(player) == PlayerBody.WINGS_OPEN)
	var flat := Vector2(player.velocity.x, player.velocity.z)
	assert_gt(flat.length(), 7.0)


func test_swap_gear_puts_the_packed_suit_on() -> void:
	var player := await _on_floor()
	_own(player)
	player._swap_gear()
	assert_true(player.glide.equipped)
	assert_true(_wings_mode(player) == PlayerBody.WINGS_PACKED)
	assert_string_contains(player.get_prompt(), "Glide Suit")
	player._swap_gear()
	assert_false(player.glide.equipped)
	assert_true(_wings_mode(player) == PlayerBody.WINGS_OFF)


func test_swap_gear_picks_the_suit_before_place() -> void:
	var player := await _on_floor()
	_own(player)
	player.score.add_barrier_charges(2)
	player._swap_gear()
	assert_true(player.glide.equipped)
	assert_false(player.is_placing())
	player._swap_gear()
	assert_false(player.glide.equipped)
	assert_true(player.is_placing())
	player._swap_gear()
	assert_false(player.glide.equipped)
	assert_false(player.is_placing())


func test_flat_cruise_covers_much_more_forward_than_down() -> void:
	var player := await _in_air()
	_own(player)
	player.set_look_pitch(0.0)
	player.glide.start(player)
	player.velocity = Vector3(0.0, -1.2, -16.0)
	var start := player.global_position
	for _frame in 60:
		player._move(STEP)
	var moved := player.global_position - start
	assert_true(player.is_gliding())
	assert_gt(-moved.z, 10.0, "flat flight still carries forward")
	assert_gt(-moved.z, -moved.y * 8.0, "at least 8:1 when you stay level")


func test_flat_look_accelerates_more_than_a_steep_look() -> void:
	var flat := await _in_air(Vector3(4.0, 28.0, 0.0))
	_own(flat)
	flat.set_look_pitch(0.0)
	flat.glide.start(flat)
	flat.velocity = Vector3(0.0, -1.2, -12.0)
	var steep := await _in_air(Vector3(-4.0, 28.0, 0.0))
	_own(steep)
	steep.set_look_pitch(-50.0)
	steep.glide.start(steep)
	steep.velocity = Vector3(0.0, -1.2, -12.0)
	for _frame in 70:
		flat._move(STEP)
		steep._move(STEP)
	var flat_fwd := absf(flat.velocity.z)
	var steep_fwd := absf(steep.velocity.z)
	assert_gt(flat_fwd, steep_fwd, "level wings keep adding speed")
	assert_lt(steep.global_position.y, flat.global_position.y, "a steep look dumps height")


func test_look_up_holds_more_height_than_look_down() -> void:
	var up := await _in_air(Vector3(4.0, 28.0, 0.0))
	_own(up)
	up.set_look_pitch(28.0)
	up.glide.start(up)
	up.velocity = Vector3(0.0, -1.2, -16.0)
	var down := await _in_air(Vector3(-4.0, 28.0, 0.0))
	_own(down)
	down.set_look_pitch(-28.0)
	down.glide.start(down)
	down.velocity = Vector3(0.0, -1.2, -16.0)
	for _frame in 50:
		up._move(STEP)
		down._move(STEP)
	assert_gt(up.global_position.y, down.global_position.y)


func test_jump_cuts_the_wings() -> void:
	var player := await _in_air()
	_own(player)
	player.glide.equip(player)
	player.glide.start(player)
	player.velocity = Vector3(0.0, -2.0, -10.0)
	player._move(STEP)
	assert_true(player.is_gliding())
	var pad := _pad(player)
	pad.begin_frame()
	pad.tap("jump")
	player._move(STEP)
	assert_false(player.is_gliding())
	assert_true(player.glide.equipped)
	assert_true(_wings_mode(player) == PlayerBody.WINGS_PACKED)


func test_landing_cancels_the_glide() -> void:
	var player := await _in_air(Vector3(0.0, 2.4, 0.0))
	_own(player)
	player.glide.start(player)
	player.velocity = Vector3(0.0, -8.0, -4.0)
	for _frame in 40:
		player._move(STEP)
		if not player.is_gliding():
			break
	assert_false(player.is_gliding())
	assert_true(player.is_on_floor())


func test_takeoff_pad_does_not_cancel_an_upward_glide() -> void:
	var player := await _on_floor()
	_own(player)
	player.glide.equip(player)
	player.glide.start(player)
	player.velocity.y = 4.0
	player._move(STEP)
	assert_true(player.is_gliding(), "still leaving the pad is not a landing")


func test_a_pawn_sync_includes_glide() -> void:
	var pawn := Node3D.new()
	add_child_autofree(pawn)
	var sync := NetSync.attach_pawn(pawn, 1)
	assert_true(sync.replication_config.has_property(NodePath(":sync_glide")))
	assert_true(sync.replication_config.has_property(NodePath(":sync_glide_worn")))


func test_the_glide_pose_spreads_the_arms() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.pose(0.0)
	body.glide()
	assert_gt(rad_to_deg(body.torso.rotation.x), 30.0)
	assert_lt(rad_to_deg(body.arms[0].rotation.z), -50.0)
	assert_gt(rad_to_deg(body.arms[1].rotation.z), 50.0)
	body.show_wings(PlayerBody.WINGS_PACKED)
	var wings := body.torso.get_node("Wings") as Node3D
	assert_true(wings.visible)
	assert_true(wings.get_node("Packed").visible)
	assert_false(wings.get_node("Open").visible)
	body.show_wings(PlayerBody.WINGS_OPEN)
	assert_false(wings.get_node("Packed").visible)
	assert_true(wings.get_node("Open").visible)
	body.show_wings(PlayerBody.WINGS_OFF)
	assert_false(wings.visible)


func _on_floor() -> Player:
	_box(Vector3(20.0, 0.4, 20.0), Vector3(0.0, -0.2, 0.0))
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 0.05, 0.0)
	await wait_physics_frames(1)
	_land(player)
	assert_true(player.is_on_floor(), "the dummy has to land before it can jump")
	return player


func _on_tower() -> Player:
	_box(Vector3(40.0, 0.4, 40.0), Vector3(0.0, -0.2, 0.0))
	_box(Vector3(4.0, 1.0, 4.0), Vector3(0.0, 8.5, 0.0))
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 9.2, -1.6)
	player.set_look_yaw(0.0)
	await wait_physics_frames(1)
	_land(player)
	assert_true(player.is_on_floor(), "the dummy has to stand on the tower")
	assert_gt(player.glide.drop_height(player), PlayerGlide.MIN_HEIGHT)
	return player


func _in_air(at := Vector3(0.0, 28.0, 0.0)) -> Player:
	_box(Vector3(40.0, 0.4, 40.0), Vector3(0.0, -0.2, 0.0))
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = at
	player.set_look_yaw(0.0)
	await wait_physics_frames(1)
	return player


func _own(player: Player) -> void:
	var card := GameState.new(PackedInt32Array([4]))
	card.glide_bought = true
	player.score = card


func _equip(player: Player) -> void:
	_own(player)
	player._swap_gear()
	assert_true(player.glide.equipped)


func _pad(player: Player) -> CpuInput:
	var pad := CpuInput.new("p1", true)
	player.input = pad
	return pad


func _wings_mode(player: Player) -> int:
	var wings := player.body.torso.get_node_or_null("Wings") as Node3D
	if wings == null or not wings.visible:
		return PlayerBody.WINGS_OFF
	var open := wings.get_node_or_null("Open") as Node3D
	if open != null and open.visible:
		return PlayerBody.WINGS_OPEN
	return PlayerBody.WINGS_PACKED


func _land(player: Player) -> void:
	for _i in 20:
		player.velocity.y = -12.0
		player._move(STEP)
		if player.is_on_floor():
			break


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	body.position = at
	add_child_autofree(body)
	return body
