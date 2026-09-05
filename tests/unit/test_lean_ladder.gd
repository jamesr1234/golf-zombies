extends GutTest
## Purchased lean ladders: shop stock, wall aim, and a fast rail climb.

const PLAYER := preload("res://scenes/players/player.tscn")
const STEP := 1.0 / 60.0


func after_each() -> void:
	for child in get_children():
		if child is LeanLadder:
			child.free()


func test_a_spawned_ladder_leans_toward_the_wall() -> void:
	var ladder: LeanLadder = LeanLadder.spawn(self, Vector3.ZERO, 0.0, 5.0)
	assert_not_null(ladder)
	assert_gt(ladder.rotation.x, 0.2, "the rails tip into the wall")
	assert_gt(ladder.hold_locals().size(), 5)
	assert_almost_eq(ladder.rail_length(), 5.0, 0.001)
	var top := ladder.point_on_rail(1.0)
	assert_gt(top.y, 3.5, "tall enough to skip a stack of cubes")
	assert_gt(top.z, 1.0, "the top sits forward, against the wall")


func test_aim_leans_a_ladder_on_a_vertical_wall() -> void:
	var floor := _floor()
	_wall(Vector3(0.0, 3.0, -4.0))
	await wait_physics_frames(2)
	var aimed := LeanLadder.plant_point(
		floor.get_world_3d(), Vector3(0.0, 1.6, 2.0), Vector3(0.0, 0.2, -1.0)
	)
	assert_true(bool(aimed["ok"]), "a wall hit is a valid plant")
	assert_gt(float(aimed["length"]), LeanLadder.MIN_LEN - 0.01)
	assert_gt((aimed["foot"] as Vector3).z, -4.0, "the feet sit out from the wall")
	assert_almost_eq((aimed["foot"] as Vector3).y, 0.0, 0.15)


func test_a_tall_wall_gets_a_long_ladder() -> void:
	var floor := _floor()
	_box(Vector3(8.0, 16.0, 0.4), Vector3(0.0, 8.0, -8.0))
	await wait_physics_frames(2)
	var aimed := LeanLadder.plant_point(
		floor.get_world_3d(), Vector3(0.0, 1.6, 4.0), Vector3(0.0, 0.55, -1.0)
	)
	assert_true(bool(aimed["ok"]), "a high wall hit is a valid plant")
	assert_gt(float(aimed["length"]), 8.0, "the rails reach past the old one-storey cap")
	assert_lte(float(aimed["length"]), LeanLadder.MAX_LEN)


func test_aim_rejects_a_flat_floor() -> void:
	var floor := _floor()
	await wait_physics_frames(2)
	var aimed := LeanLadder.plant_point(
		floor.get_world_3d(), Vector3(0.0, 1.6, 2.0), Vector3.DOWN
	)
	assert_false(bool(aimed["ok"]))


func test_you_slide_up_the_rails() -> void:
	var ladder: LeanLadder = LeanLadder.spawn(self, Vector3.ZERO, 0.0, 5.0)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	player.input = CpuInput.new(player.input_prefix, false)
	player.global_position = ladder.point_on_rail(0.05)
	assert_true(ladder.can_latch(player))
	assert_true(player._start_climb())
	assert_true(player.is_climbing())
	assert_true(player.climber.wall is LeanLadder)
	var start_y := player.global_position.y
	var pad := player.input as CpuInput
	for _i in 20:
		pad.begin_frame()
		pad.move = Vector2(0.0, -1.0)
		player._move(STEP)
	assert_gt(player.global_position.y, start_y + 1.2, "stick up is a fast climb")
	assert_true(player.is_climbing())


func test_the_top_steps_you_onto_the_ledge() -> void:
	var ladder: LeanLadder = LeanLadder.spawn(self, Vector3.ZERO, 0.0, 4.0)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	player.input = CpuInput.new(player.input_prefix, false)
	player.global_position = ladder.point_on_rail(0.4)
	assert_true(player._start_climb())
	var pad := player.input as CpuInput
	for _i in 40:
		pad.begin_frame()
		pad.move = Vector2(0.0, -1.0)
		player._move(STEP)
	assert_false(player.is_climbing(), "the top lets go onto the ledge")
	assert_gt(player.global_position.y, 2.8)


func test_the_top_can_throw_the_ladder_off() -> void:
	var ladder: LeanLadder = LeanLadder.spawn(self, Vector3.ZERO, 0.0, 5.0)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	player.input = CpuInput.new(player.input_prefix, false)
	player.global_position = ladder.ledge_stand()
	assert_true(ladder.can_throw(player))
	assert_eq(LeanLadder.nearest_throw(player), ladder)
	assert_string_contains(player.get_prompt().to_lower(), "throw")
	var start_x := ladder.rotation.x
	ladder.kick()
	assert_true(ladder.is_falling())
	assert_false(ladder.is_live())
	assert_false(ladder.can_latch(player))
	ladder._process(LeanLadder.FALL)
	assert_lt(ladder.rotation.x, start_x, "the rails swing off the wall")
	assert_almost_eq(ladder.rotation.x, -PI * 0.5, 0.05)


func test_throwing_drops_a_climber() -> void:
	var ladder: LeanLadder = LeanLadder.spawn(self, Vector3.ZERO, 0.0, 5.0)
	var climber: Player = PLAYER.instantiate()
	var kicker: Player = PLAYER.instantiate()
	add_child_autofree(climber)
	add_child_autofree(kicker)
	await wait_physics_frames(1)
	climber.input = CpuInput.new(climber.input_prefix, false)
	climber.global_position = ladder.point_on_rail(0.2)
	assert_true(climber._start_climb())
	assert_true(climber.is_climbing())
	kicker.global_position = ladder.ledge_stand()
	assert_true(ladder.can_throw(kicker), "the top can kick it while they climb")
	ladder.kick()
	assert_false(climber.is_climbing(), "the rails leave them in the air")
	assert_false(ladder.can_throw(kicker))


func test_interact_throws_from_the_ledge() -> void:
	var ladder: LeanLadder = LeanLadder.spawn(self, Vector3.ZERO, 0.0, 5.0)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	player.input = CpuInput.new(player.input_prefix, false)
	player.global_position = ladder.ledge_stand()
	var pad := player.input as CpuInput
	pad.begin_frame()
	pad.tap("interact")
	player.interact.use(player)
	assert_true(ladder.is_falling())


func test_gear_swap_opens_ladder_placing() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.stand_at(Vector3.ZERO, 0.0)
	var score := GameState.new(PackedInt32Array([4]))
	score.add_ladder_charges(1)
	player.flow = _Flow.new(score)
	player._swap_gear()
	assert_true(player.is_placing())
	player._cancel_place()
	assert_false(player.is_placing())


func _floor() -> StaticBody3D:
	return _box(Vector3(20.0, 0.4, 20.0), Vector3(0.0, -0.2, 0.0))


func _wall(at: Vector3) -> StaticBody3D:
	return _box(Vector3(8.0, 6.0, 0.4), at)


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	add_child_autofree(body)
	return body


class _Flow extends RefCounted:
	var score: GameState
	var hole = null

	func _init(p_score: GameState) -> void:
		score = p_score

	func hole_node() -> Node3D:
		return null
