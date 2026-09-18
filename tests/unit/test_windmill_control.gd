extends GutTest
## A handheld mill remote. Analog rotation is the mill: one stick circle is one
## turn of the blades, and the stick on the remote leans the same way.

const PLAYER := preload("res://scenes/players/player.tscn")
const _Desk := preload("res://scripts/course/windmill_control.gd")
const _Overlay := preload("res://scripts/course/hole_overlay.gd")
const STEP := 1.0 / 60.0


func test_a_full_stick_circle_turns_the_mill_once() -> void:
	var angle := 0.0
	var last := 0.0
	var latched := false
	var samples := 32
	for i in samples + 1:
		var t := TAU * float(i) / float(samples)
		var stick := Vector2(cos(t), -sin(t))
		var next: Dictionary = _Desk.steer_angle(angle, last, latched, stick)
		angle = next["angle"]
		last = next["last"]
		latched = next["latched"]
	assert_almost_eq(angle, -TAU, 0.08, "one analog revolution is one mill revolution")


func test_deadzone_does_not_jump_the_mill() -> void:
	var next: Dictionary = _Desk.steer_angle(1.2, 0.4, true, Vector2(0.05, 0.02))
	assert_false(next["latched"])
	assert_almost_eq(next["angle"], 1.2, 0.001)
	var resume: Dictionary = _Desk.steer_angle(
		next["angle"], next["last"], next["latched"], Vector2(0.0, -1.0)
	)
	assert_true(resume["latched"])
	assert_almost_eq(resume["angle"], 1.2, 0.001, "coming back out does not snap the blades")


func test_stick_right_is_zero_and_forward_is_a_quarter_turn() -> void:
	assert_almost_eq(_Desk.angle_of(Vector2(1.0, 0.0)), 0.0, 0.001)
	assert_almost_eq(_Desk.angle_of(Vector2(0.0, -1.0)), PI * 0.5, 0.001)
	assert_almost_eq(_Desk.turn_delta(0.1, -0.1), -0.2, 0.001)


func test_the_control_is_a_handheld_pickup() -> void:
	var mill := _mill()
	add_child_autofree(mill)
	var desk := _Desk.create({
		"position": Vector3(2.0, 0.0, 4.0),
		"yaw": 0.0,
	})
	add_child_autofree(desk)
	assert_true(desk.is_in_group("mill_controls"))
	assert_true(desk is Area3D)
	assert_eq(desk.collision_layer, Layers.PICKUP)
	assert_eq(desk.collision_mask, Layers.PLAYER)
	assert_not_null(desk.find_child("StickPivot", true, false))
	assert_not_null(desk.find_child("Knob", true, false))
	assert_eq(String(desk.to_prop()["kind"]), "mill_control")
	assert_eq(desk.mill(), mill)
	assert_true(_Desk.STATS.is_mill())
	assert_eq(_Desk.STATS.visual, "mill")


func test_walking_in_puts_the_remote_in_the_bag() -> void:
	var mill := _mill()
	add_child_autofree(mill)
	var desk := _Desk.create({
		"position": Vector3.ZERO,
		"yaw": 0.0,
	})
	add_child_autofree(desk)
	var pair := await _with_player(desk)
	var player: Player = pair[0]
	assert_true(desk.try_pick(player))
	assert_true(player.weapon.has_gun(_Desk.STATS))
	assert_true(player.is_holding_mill())
	assert_true(desk.is_carried_by(player))
	assert_false(desk.get_node("Mesh").visible)


func test_a_second_touch_leaves_it_for_someone_else() -> void:
	var mill := _mill()
	add_child_autofree(mill)
	var desk := _Desk.create({
		"position": Vector3.ZERO,
		"yaw": 0.0,
	})
	add_child_autofree(desk)
	var pair := await _with_player(desk)
	var player: Player = pair[0]
	assert_true(player.weapon.add_gun(_Desk.STATS))
	assert_false(desk.try_pick(player), "the partner still needs a shot at it")
	assert_false(desk.is_carried_by(player))


func test_taking_control_stops_the_auto_spin() -> void:
	var mill := _mill()
	add_child_autofree(mill)
	var desk := _Desk.create({
		"position": Vector3(0.0, 0.0, 2.0),
		"yaw": 0.0,
	})
	add_child_autofree(desk)
	await wait_physics_frames(2)
	var before := mill.rotor_rad()
	mill._physics_process(STEP)
	assert_gt(mill.rotor_rad(), before, "idle mills keep turning")
	var pair := await _with_player(desk)
	var player: Player = pair[0]
	assert_true(desk.try_pick(player))
	player._sync_mill_remote(STEP)
	assert_true(player.is_milling())
	assert_true(mill.is_driven())
	var held := mill.rotor_rad()
	mill._physics_process(STEP)
	assert_almost_eq(mill.rotor_rad(), held, 0.0001, "driven mills wait on the stick")


func test_the_stick_and_the_mill_share_the_analog_turn() -> void:
	var mill := _mill()
	add_child_autofree(mill)
	var desk := _Desk.create({
		"position": Vector3(0.0, 0.0, 2.0),
		"yaw": 0.0,
	})
	add_child_autofree(desk)
	var pair := await _with_player(desk)
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	assert_true(desk.try_pick(player))
	player._sync_mill_remote(STEP)
	var start := mill.rotor_rad()
	var samples := 24
	for i in samples + 1:
		var t := TAU * float(i) / float(samples)
		pad.begin_frame()
		pad.move = Vector2(cos(t), -sin(t))
		desk.tick(player, STEP)
	assert_almost_eq(mill.rotor_rad() - start, -TAU, 0.12)
	var pivot := desk.find_child("StickPivot", true, false) as Node3D
	assert_almost_eq(pivot.rotation.z, -cos(TAU) * _Desk.MAX_TILT, 0.05)
	var knob := desk.find_child("Knob", true, false) as Node3D
	assert_almost_eq(knob.rotation.y, mill.rotor_rad(), 0.05, "the ball marker sits on the mill")


func test_selecting_the_remote_drives_the_mill() -> void:
	var mill := _mill()
	add_child_autofree(mill)
	var rifle: WeaponStats = preload("res://resources/weapons/rifle.tres")
	var desk := _Desk.create({
		"position": Vector3(0.0, 0.0, 0.0),
		"yaw": 0.0,
	})
	add_child_autofree(desk)
	var pair := await _with_player(desk)
	var player: Player = pair[0]
	assert_true(player.weapon.add_gun(rifle))
	assert_true(desk.try_pick(player))
	assert_true(player.is_holding_mill())
	player._sync_mill_remote(STEP)
	assert_true(player.is_milling())
	assert_true(desk.is_used_by(player))
	player.weapon.swap(1)
	assert_false(player.is_holding_mill())
	player._sync_mill_remote(STEP)
	assert_false(player.is_milling())
	assert_false(mill.is_driven())


func test_you_can_walk_while_running_the_mill() -> void:
	var mill := _mill()
	add_child_autofree(mill)
	var desk := _Desk.create({
		"position": Vector3(0.0, 0.0, 0.0),
		"yaw": 0.0,
	})
	add_child_autofree(desk)
	var pair := await _with_player(desk)
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	assert_true(desk.try_pick(player))
	player._sync_mill_remote(STEP)
	assert_true(player.is_milling())
	var start := player.global_position
	pad.begin_frame()
	pad.move = Vector2(0.0, -1.0)
	player.motion.tick(player, STEP)
	assert_gt(
		Vector2(player.velocity.x, player.velocity.z).length(),
		0.1,
		"the remote is mobile; the stick still walks you"
	)
	assert_false(start.is_equal_approx(player.global_position) and player.velocity.is_zero_approx())


func test_the_builder_makes_a_remote_from_hole_data() -> void:
	var desk := HoleBuilder.create_prop({
		"kind": "mill_control",
		"position": Vector3(3.0, 0.0, 5.0),
		"yaw": 25.0,
	})
	add_child_autofree(desk)
	assert_eq(desk.get_script(), _Desk)
	assert_almost_eq(desk.position.x, 3.0, 0.001)
	assert_almost_eq(rad_to_deg(desk.rotation.y), 25.0, 0.001)


func test_a_replicated_stick_turns_the_mill_and_the_knob() -> void:
	var mill := _mill()
	add_child_autofree(mill)
	var desk := _Desk.create({
		"position": Vector3(0.0, 0.0, 2.0),
		"yaw": 0.0,
	})
	add_child_autofree(desk)
	desk.take_wire(Vector2(1.0, 0.0), 1.25, true)
	assert_true(mill.is_driven())
	assert_almost_eq(mill.rotor_rad(), 1.25, 0.001)
	var pivot := desk.find_child("StickPivot", true, false) as Node3D
	assert_almost_eq(pivot.rotation.z, -_Desk.MAX_TILT, 0.001, "the shaft leans with the analog")
	var knob := desk.find_child("Knob", true, false) as Node3D
	assert_almost_eq(knob.rotation.y, 1.25, 0.001, "the ball marker sits on the mill")


func test_offline_physics_does_not_touch_the_net() -> void:
	var mill := _mill()
	add_child_autofree(mill)
	var desk := _Desk.create({
		"position": Vector3(0.0, 0.0, 2.0),
		"yaw": 0.0,
	})
	add_child_autofree(desk)
	assert_false(NetSession.is_active())
	assert_false(desk._watching(), "solo play is not a client watch")
	desk._publish_pose(1.0, true)
	desk._physics_process(STEP)
	assert_eq(desk.sync_stick, Vector2.ZERO)


func test_a_desk_beside_a_named_mill_wires_itself() -> void:
	var overlay := Node3D.new()
	add_child_autofree(overlay)
	var mill := CartPathWindmill.create(Vector3(8.0, 0.0, 12.0), Vector3.FORWARD)
	mill.name = "Windmill"
	overlay.add_child(mill)
	var desk := _Desk.create({
		"position": Vector3(6.0, 0.0, 12.0),
		"yaw": 90.0,
	})
	overlay.add_child(desk)
	assert_eq(desk.mill_path, NodePath("../Windmill"))
	assert_eq(desk.mill(), mill)


func test_overlay_collect_reads_the_desk() -> void:
	var overlay := Node3D.new()
	add_child_autofree(overlay)
	var mill := CartPathWindmill.create(Vector3(8.0, 0.0, 12.0), Vector3.FORWARD)
	mill.name = "Windmill"
	overlay.add_child(mill)
	var desk := _Desk.create({
		"position": Vector3(6.0, 0.0, 12.0),
		"yaw": 90.0,
	})
	desk.name = "WindmillControl"
	overlay.add_child(desk)
	var data := HoleData.new()
	_Overlay.collect_into(data, overlay)
	var kinds: Array[String] = []
	for prop in data.props:
		kinds.append(String(prop["kind"]))
	assert_true("windmill" in kinds)
	assert_true("mill_control" in kinds)


func _mill() -> CartPathWindmill:
	return CartPathWindmill.create(Vector3(6.0, 0.0, 0.0), Vector3.FORWARD)


func _with_player(desk) -> Array:
	var player: Player = PLAYER.instantiate()
	player.position = desk.global_position + Vector3(0.0, 0.0, 8.0)
	add_child_autofree(player)
	await wait_physics_frames(1)
	var pad := CpuInput.new("p1", true)
	player.input = pad
	return [player, pad]
