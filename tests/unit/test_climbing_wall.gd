extends GutTest
## Hold L1 / R1 to grip; one hand swings you, both hands lock you. Jump lets go.

const SEED := 20260816
const PLAYER := preload("res://scenes/players/player.tscn")
const STEP := 1.0 / 60.0


func test_hole_one_has_no_climb_wall() -> void:
	var hole := HoleGenerator.generate(0, SEED)
	assert_eq(_climb_props(hole).size(), 0, "hole 1 no longer opens with a wall")
	var later := HoleGenerator.generate(3, SEED)
	assert_eq(_climb_props(later).size(), 0, "later holes stay off the wall")


func test_the_builder_skips_the_wall_on_hole_one() -> void:
	var root := HoleBuilder.build(HoleGenerator.generate(0, SEED))
	add_child_autofree(root)
	var built := root.find_children("*", "ClimbingWall", true, false)
	assert_eq(built.size(), 0)


func test_the_wall_is_a_full_face() -> void:
	assert_gt(ClimbingWall.HEIGHT, 18.0, "tall enough to climb, not a garden fence")
	assert_gt(ClimbingWall.WIDTH, 12.0)
	assert_gt(ClimbingWall.COLS * ClimbingWall.ROWS, 80)


func test_the_holds_sit_on_the_front_face() -> void:
	var wall := ClimbingWall.create(_prop())
	add_child_autofree(wall)
	var locals := wall.hold_locals()
	assert_eq(locals.size(), wall._cols * wall._rows)
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for hold in locals:
		assert_lt(hold.z, 0.0, "jugs belong on the climb face")
		min_x = minf(min_x, hold.x)
		max_x = maxf(max_x, hold.x)
		min_y = minf(min_y, hold.y)
		max_y = maxf(max_y, hold.y)
	assert_gt(max_x - min_x, wall._w * 0.88, "holds run the width of the wall")
	assert_gt(max_y - min_y, wall._h * 0.88, "holds run the height of the wall")
	var chest := wall.global_position + wall.face_normal() * 0.8
	assert_ne(wall.nearest_hold(chest), Vector3.INF)


func test_you_can_latch_from_the_ground_in_front() -> void:
	var wall := ClimbingWall.create(_prop())
	add_child_autofree(wall)
	var dummy := Node3D.new()
	add_child_autofree(dummy)
	dummy.global_position = _latch_spot(wall)
	assert_true(wall.can_latch(dummy))
	dummy.global_position += -wall.face_normal() * 6.0
	assert_false(wall.can_latch(dummy), "the latch is at the face, not across the green")


func test_climbing_pulls_the_camera_behind_you() -> void:
	var wall := ClimbingWall.create(_prop())
	add_child_autofree(wall)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	player.input = CpuInput.new("p1", true)
	player.global_position = _latch_spot(wall)
	assert_true(player._start_climb())
	var view := player.get_view_transform()
	assert_gt(
		view.origin.distance_to(player.global_position), 2.5,
		"third person, so you see the robot on the wall"
	)
	var to_cam := view.origin - player.global_position
	to_cam.y = 0.0
	var back := player.global_transform.basis.z
	back.y = 0.0
	assert_gt(to_cam.normalized().dot(back.normalized()), 0.6, "the lens sits behind you")
	assert_almost_eq(player.get_view_fov(), Climber.CAM_FOV, 0.001)
	assert_ne(player.view_cull_mask() & player.cabin_layer(), 0, "the robot has to stay in frame")


func test_you_face_the_holds_when_you_latch() -> void:
	var wall := ClimbingWall.create(_prop())
	add_child_autofree(wall)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	player.input = CpuInput.new("p1", true)
	player.global_position = _latch_spot(wall)
	assert_true(player.climber.latch(player, wall))
	var look := -player.global_transform.basis.z
	look.y = 0.0
	var into := -wall.face_normal()
	into.y = 0.0
	assert_gt(
		look.normalized().dot(into.normalized()), 0.85,
		"the camera has to look at the wall, not away from it"
	)


func test_holding_a_bumper_keeps_that_hand_on() -> void:
	var pair := await _latched()
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	_hold_for(player, pad, ["melee"], 25)
	assert_ne(player.climber.left, Vector3.INF, "L1 keeps the left hand planted")
	assert_eq(player.climber.right, Vector3.INF, "a released R1 lets the right hand go")
	pad.begin_frame()
	player.climber.tick(player, STEP)
	assert_eq(player.climber.left, Vector3.INF, "letting go of L1 opens the left hand")


func test_both_hands_hold_you_still() -> void:
	var pair := await _latched()
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	_hold_for(player, pad, ["melee", "shield"], 8)
	var planted := player.global_position
	_hold_for(player, pad, ["melee", "shield"], 20)
	assert_almost_eq(
		player.global_position.distance_to(planted), 0.0, 0.08,
		"two grips pin you to the wall"
	)


func test_one_hand_lets_you_swing() -> void:
	var pair := await _latched()
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	_hold_for(player, pad, ["melee"], 25)
	assert_eq(player.climber.right, Vector3.INF, "R1 is up, so the right hand is free")
	var start_angle := player.climber._angle
	for _frame in 40:
		pad.begin_frame()
		pad.hold("melee")
		pad.move = Vector2(1.0, 0.0)
		player.climber.tick(player, STEP)
	assert_gt(
		absf(player.climber._angle - start_angle), 0.12,
		"hanging from one hand you can swing along the wall"
	)


func test_stick_right_aims_the_free_hand_to_the_right() -> void:
	var pair := await _latched()
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	_hold_for(player, pad, ["shield"], 25)
	pad.begin_frame()
	pad.hold("shield")
	pad.move = Vector2(1.0, 0.0)
	player.climber.tick(player, STEP)
	var along := player.climber.left_aim - player.global_position
	along.y = 0.0
	var right := player.global_transform.basis.x
	right.y = 0.0
	assert_gt(
		along.normalized().dot(right.normalized()), 0.35,
		"left stick right reaches to your right"
	)


func test_a_free_hand_reaches_above_the_body() -> void:
	var pair := await _latched()
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	_hold_for(player, pad, ["melee"], 25)
	pad.begin_frame()
	pad.hold("melee")
	pad.look = Vector2(0.0, -1.0)
	player.climber.tick(player, STEP)
	assert_gt(
		player.climber.right_aim.y, player.global_position.y + 1.6,
		"the free arm has to reach a hold above your head"
	)


func test_the_free_hand_can_grab_a_higher_hold() -> void:
	var pair := await _latched()
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	_hold_for(player, pad, ["melee"], 25)
	var planted := player.climber.left
	pad.begin_frame()
	pad.hold("melee")
	pad.look = Vector2(0.0, -1.0)
	player.climber.tick(player, STEP)
	pad.begin_frame()
	pad.hold("melee")
	pad.hold("shield")
	pad.look = Vector2(0.0, -1.0)
	player.climber.tick(player, STEP)
	assert_ne(player.climber.right, Vector3.INF)
	assert_gt(
		player.climber.right.y, planted.y + 0.4,
		"reach up, then R1 plants the higher hold"
	)


func test_the_pegs_are_blue() -> void:
	var wall := ClimbingWall.create(_prop())
	add_child_autofree(wall)
	var seen := 0
	for child in wall.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null or not String(mesh.name).begins_with("Hold_"):
			continue
		seen += 1
		assert_eq(mesh.material_override.albedo_color, Palette.CYAN)
	assert_gt(seen, 80)


func test_the_top_has_a_standable_deck() -> void:
	var wall := ClimbingWall.create(_prop())
	add_child_autofree(wall)
	var deck := wall.get_node_or_null("Deck") as Node3D
	assert_not_null(deck, "the wall finishes with a platform")
	assert_gt(deck.position.y, wall._h * 0.45)
	var stand := wall.ledge_stand()
	assert_gt(stand.y, wall.top_y(), "the stand point is on top of the wall")
	assert_gt(wall.to_local(stand).z, 0.0, "you land on the deck, not the climb face")


func test_a_mid_wall_hold_does_not_mantle() -> void:
	var pair := await _latched()
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	var wall: ClimbingWall = player.climber.wall
	var holds: Array[Vector3] = wall.holds()
	holds.sort_custom(func(a, b): return a.y > b.y)
	var mid: Vector3 = holds[holds.size() / 2]
	player.climber.left = mid
	player.climber.right = mid
	player.climber._snap_to_hang(player)
	pad.begin_frame()
	pad.hold("melee")
	pad.hold("shield")
	assert_true(player.climber.tick(player, STEP), "mid holds keep you on the wall")
	assert_false(player.climber.is_mantling())


func test_reaching_the_top_plays_a_third_person_mantle() -> void:
	var pair := await _latched()
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	var wall: ClimbingWall = player.climber.wall
	var top: Array[Vector3] = wall.holds()
	top.sort_custom(func(a, b): return a.y > b.y)
	player.climber.left = top[0]
	player.climber.right = top[1]
	player.climber._snap_to_hang(player)
	pad.begin_frame()
	pad.hold("melee")
	pad.hold("shield")
	assert_true(player.climber.tick(player, STEP), "a lip grab starts the pull-up")
	assert_true(player.climber.is_mantling())
	assert_gt(
		player.get_view_transform().origin.distance_to(player.global_position), 2.5,
		"the pull-up stays third person"
	)
	assert_lt(player.global_position.y, wall.ledge_stand(player).y - 0.2, "not snapped onto the deck yet")
	for _frame in int(ceil(Climber.MANTLE_TIME / STEP)) + 2:
		pad.begin_frame()
		if not player.climber.tick(player, STEP):
			break
	player._drop_climb()
	var local := wall.to_local(player.global_position)
	assert_gt(player.global_position.y, wall.top_y(), "you stand on top of the wall")
	assert_gt(local.z, 0.0, "you land on the deck, not hanging on the face")
	assert_false(player.climber.is_active())
	assert_false(player.climber.is_mantling(), "first person resumes on the deck")


func test_jump_lets_go() -> void:
	var pair := await _latched()
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	pad.begin_frame()
	pad.hold("melee")
	pad.tap("jump")
	assert_false(player.climber.tick(player, STEP), "jump drops you off the wall")
	player._drop_climb()
	assert_eq(player.state, Player.State.NORMAL)
	assert_false(player.climber.is_active())


func test_the_prompt_names_the_shoulders() -> void:
	var wall := ClimbingWall.create(_prop())
	add_child_autofree(wall)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	player.input = CpuInput.new("p1", true)
	player.global_position = _latch_spot(wall)
	var ready := player.get_prompt().to_lower()
	assert_string_contains(ready, "climb")
	assert_string_contains(ready, player.input.hint("melee").to_lower())
	assert_string_contains(ready, player.input.hint("shield").to_lower())
	assert_false(ready.contains("circle"), "circle is not how you get on")
	assert_true(player._start_climb())
	assert_string_contains(player.get_prompt().to_lower(), "left")
	assert_string_contains(player.get_prompt().to_lower(), "right")


func test_r1_at_the_wall_climbs_instead_of_shielding() -> void:
	var pair := await _ready_to_climb()
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	pad.begin_frame()
	pad.tap("shield")
	player._update_shield()
	assert_false(player.is_shielding(), "R1 at the face is a grab, not cover")
	assert_true(player._try_latch_climb())
	assert_true(player.is_climbing())


func test_l1_or_r1_latches_you_on() -> void:
	for button in ["melee", "shield"]:
		var pair := await _ready_to_climb()
		var player: Player = pair[0]
		var pad: CpuInput = pair[1]
		pad.begin_frame()
		pad.tap(button)
		assert_true(player._try_latch_climb(), "%s grabs the wall" % button)
		assert_true(player.is_climbing())
		player._drop_climb()


func test_circle_does_not_latch() -> void:
	var pair := await _ready_to_climb()
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	pad.begin_frame()
	pad.tap("interact")
	player._interact(STEP)
	assert_false(player.is_climbing(), "circle is no longer the latch")
	assert_false(player._try_latch_climb())


func test_jump_does_not_latch() -> void:
	var pair := await _ready_to_climb()
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	pad.begin_frame()
	pad.tap("jump")
	assert_false(player._try_latch_climb(), "jump only drops you once you are on")
	assert_false(player.is_climbing())


func _ready_to_climb() -> Array:
	var wall := ClimbingWall.create(_prop())
	add_child_autofree(wall)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	var pad := CpuInput.new("p1", true)
	player.input = pad
	player.global_position = _latch_spot(wall)
	return [player, pad]


func _latched() -> Array:
	var pair := await _ready_to_climb()
	var player: Player = pair[0]
	assert_true(player.climber.latch(player, ClimbingWall.nearest(player)))
	player.state = Player.State.CLIMBING
	return pair


func _hold_for(player: Player, pad: CpuInput, buttons: Array, frames: int) -> void:
	for _frame in frames:
		pad.begin_frame()
		for name in buttons:
			pad.hold(String(name))
		player.climber.tick(player, STEP)


func _climb_props(hole: HoleData) -> Array:
	var walls: Array = []
	for prop in hole.props:
		if String(prop.get("kind", "")) == "climb_wall":
			walls.append(prop)
	return walls


func _prop() -> Dictionary:
	return {
		"kind": "climb_wall",
		"position": Vector3.ZERO,
		"size": Vector3(ClimbingWall.WIDTH, ClimbingWall.HEIGHT, ClimbingWall.THICK),
		"yaw": 0.0,
	}


func _latch_spot(wall: ClimbingWall) -> Vector3:
	var at := wall.global_position + wall.face_normal() * 1.15
	at.y = wall.global_position.y - ClimbingWall.HEIGHT * 0.5
	return at
