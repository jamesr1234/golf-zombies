extends GutTest
## Two decks and a cable. Grab at the high end, slide to the low deck, jump to drop.

const PLAYER := preload("res://scenes/players/player.tscn")
const SCENE := preload("res://scenes/course/props/zipline.tscn")
const _Zip := preload("res://scripts/course/zipline.gd")


func before_each() -> void:
	Sfx.clear_log()


func test_the_scene_is_a_placeable_prop() -> void:
	assert_true(ResourceLoader.exists("res://scenes/course/props/zipline.tscn"))
	var line := _spawn()
	assert_true(line is Zipline)
	assert_true(line.is_in_group("ziplines"))
	assert_not_null(line.start_mark())
	assert_not_null(line.end_mark())
	assert_not_null(line.start_mark().get_node_or_null("Deck"))
	assert_not_null(line.end_mark().get_node_or_null("Deck"))
	assert_not_null(line.get_node_or_null("Cable"))
	assert_eq(line.start_mark().get_node("Deck").collision_layer, Layers.WORLD)


func test_the_cable_spans_the_hang_points() -> void:
	var line := _spawn()
	var cable := line.get_node("Cable") as MeshInstance3D
	var mesh := cable.mesh as CylinderMesh
	assert_not_null(mesh)
	assert_almost_eq(mesh.height, line.cable_length(), 0.05)
	var half := mesh.height * 0.5
	var a := cable.to_global(Vector3(0.0, half, 0.0))
	var b := cable.to_global(Vector3(0.0, -half, 0.0))
	var start := line.hang_at(line.start_mark())
	var finish := line.hang_at(line.end_mark())
	var hits_start := a.distance_to(start) < 0.08 or b.distance_to(start) < 0.08
	var hits_end := a.distance_to(finish) < 0.08 or b.distance_to(finish) < 0.08
	assert_true(hits_start, "the cable meets the start hang")
	assert_true(hits_end, "the cable meets the end hang")


func test_the_high_end_follows_marker_height() -> void:
	var line := _spawn()
	assert_eq(line.high_mark(), line.start_mark())
	assert_eq(line.low_mark(), line.end_mark())
	line.end_mark().position.y = 6.0
	assert_eq(line.high_mark(), line.end_mark())
	assert_eq(line.low_mark(), line.start_mark())


func test_you_can_only_grab_from_the_high_deck() -> void:
	var line := _spawn()
	var hand := _hand_at(line.board_at())
	assert_true(line.can_use(hand))
	assert_eq(_Zip.nearest(hand), line)
	hand.global_position = line.land_at()
	assert_false(line.can_use(hand), "the latch is at the high deck")
	assert_null(_Zip.nearest(hand))


func test_boarding_puts_you_on_the_line() -> void:
	var line := _spawn()
	var player := _player_at(line.board_at())
	assert_true(line.try_board(player))
	assert_true(player.is_ziplining())
	assert_eq(player.state, Player.State.ZIPLINING)
	assert_eq(player.zipliner.line, line)
	assert_almost_eq(player.zipliner.t, 0.0, 0.001)
	assert_eq(Sfx.last_cue, "zipline_grab")
	assert_almost_eq(player.global_position.distance_to(line.ride_at(0.0)), 0.0, 0.02)


func test_the_ride_slides_toward_the_low_deck() -> void:
	var line := _spawn()
	var player := _player_at(line.board_at())
	assert_true(line.try_board(player))
	var from := player.global_position.distance_to(line.land_at())
	player.motion.tick(player, 0.2)
	assert_true(player.is_ziplining())
	assert_gt(player.zipliner.t, 0.0)
	assert_lt(player.global_position.distance_to(line.land_at()), from)


func test_jump_drops_you_with_the_line_speed() -> void:
	var line := _spawn()
	var player := _player_at(line.board_at())
	player.input = CpuInput.new("p1", true)
	assert_true(line.try_board(player))
	player.motion.tick(player, 0.1)
	(player.input as CpuInput).tap("jump")
	player.motion.tick(player, 0.05)
	assert_false(player.is_ziplining())
	assert_eq(player.state, Player.State.NORMAL)
	assert_gt(player.velocity.length(), 4.0)
	assert_eq(Sfx.last_cue, "zipline_drop")


func test_arrival_stands_you_on_the_low_deck() -> void:
	var line := _spawn()
	var player := _player_at(line.board_at())
	assert_true(line.try_board(player))
	player.motion.tick(player, 2.0)
	assert_false(player.is_ziplining())
	assert_almost_eq(player.global_position.distance_to(line.land_at()), 0.0, 0.05)
	assert_eq(player.velocity, Vector3.ZERO)


func test_the_rider_sees_themselves_on_the_line() -> void:
	var line := _spawn()
	var player := _player_at(line.board_at())
	assert_true(line.try_board(player))
	var eye := player.get_view_transform().origin
	assert_gt(
		eye.distance_to(player.global_position), 2.5,
		"pulled back so you see the grab and the ride"
	)
	assert_almost_eq(player.get_view_fov(), Zipliner.CAM_FOV, 0.001)
	assert_false(player.look.hides_own_cabin(player), "the whole robot stays on camera")


func test_you_can_look_around_on_the_line() -> void:
	var line := _spawn()
	var player := _player_at(line.board_at())
	player.input = CpuInput.new("p1", true)
	assert_true(line.try_board(player))
	var yaw := player.look_yaw()
	var eye := player.get_view_transform().origin
	(player.input as CpuInput).look = Vector2(1.0, -0.35)
	player.look.tick(player, 0.25)
	assert_ne(player.look_yaw(), yaw, "the stick orbits the camera on the ride")
	assert_gt(player.look_pitch(), 0.0)
	assert_gt(
		player.get_view_transform().origin.distance_to(eye), 0.2,
		"looking around moves the chase cam"
	)


func test_both_hands_hold_a_triangle_on_the_cable() -> void:
	var line := _spawn()
	var player := _player_at(line.board_at())
	assert_true(line.try_board(player))
	player.anim.tick(player, 0.05)
	var trolley := line.get_node_or_null("Trolley") as Node3D
	assert_not_null(trolley)
	assert_lt(trolley.global_position.distance_to(line.point_on_cable(0.0)), 0.08)
	assert_eq(trolley.get_child_count(), 4, "two rails, a handle, and a pulley")
	assert_lt(
		player.body.arm_hands[0].global_position.distance_to(player.zipliner.grip_left()),
		0.7,
		"free hand on the left corner"
	)
	assert_lt(
		player.body.arm_hands[1].global_position.distance_to(player.zipliner.grip_right()),
		0.7,
		"gun hand on the right corner"
	)
	player.motion.tick(player, 2.0)
	assert_false(player.is_ziplining())
	assert_null(line.get_node_or_null("Trolley"))


func test_a_placed_zipline_spans_the_two_points() -> void:
	var hole := CustomHole.create("Span")
	var start := Vector3(0.0, 5.4, -20.0)
	var finish := Vector3(8.1, 0.0, -28.0)
	hole.add_placement(CustomHole.ZIPLINE, start, 0.0, CustomHole.NO_GATE, finish)
	var overlay := CustomOverlay.build(hole)
	add_child_autofree(overlay)
	assert_eq(overlay.get_child_count(), 1)
	var line := overlay.get_child(0) as Zipline
	assert_not_null(line)
	assert_almost_eq(line.start_mark().global_position.distance_to(start), 0.0, 0.05)
	assert_almost_eq(line.end_mark().global_position.distance_to(finish), 0.0, 0.05)
	assert_eq(line.high_mark(), line.start_mark())
	assert_eq(line.low_mark(), line.end_mark())


func test_the_prompt_names_the_zipline() -> void:
	var line := _spawn()
	var player := _player_at(line.board_at())
	var prompt := player.get_prompt()
	assert_true(prompt.contains("zipline"), prompt)
	assert_true(line.try_board(player))
	prompt = player.get_prompt()
	assert_true(prompt.contains("line"), prompt)
	assert_true(prompt.contains("drop"), prompt)


func _spawn() -> Zipline:
	var line: Zipline = SCENE.instantiate()
	add_child_autofree(line)
	return line


func _player_at(at: Vector3) -> Player:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.global_position = at
	return player


func _hand_at(at: Vector3) -> Node3D:
	var hand := Node3D.new()
	add_child_autofree(hand)
	hand.global_position = at
	return hand
