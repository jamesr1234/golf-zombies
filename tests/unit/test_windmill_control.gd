extends GutTest
## A table-side joystick. Analog rotation is the mill: one stick circle is one
## turn of the blades, and the world stick leans the same way.

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


func test_the_desk_is_a_table_with_a_joystick() -> void:
	var mill := _mill()
	add_child_autofree(mill)
	var desk := _Desk.create({
		"position": Vector3(2.0, 0.0, 4.0),
		"yaw": 0.0,
	})
	add_child_autofree(desk)
	assert_true(desk.is_in_group("mill_controls"))
	assert_eq(desk.collision_layer, Layers.PROP)
	assert_not_null(desk.get_node_or_null("StickPivot"))
	assert_not_null(desk.get_node_or_null("StickPivot/Shaft/Knob"))
	assert_eq(String(desk.to_prop()["kind"]), "mill_control")
	assert_eq(desk.mill(), mill)


func test_you_have_to_walk_up_to_use_it() -> void:
	var mill := _mill()
	add_child_autofree(mill)
	var desk := _Desk.create({
		"position": Vector3.ZERO,
		"yaw": 0.0,
	})
	add_child_autofree(desk)
	var dummy := Node3D.new()
	add_child_autofree(dummy)
	dummy.global_position = Vector3(0.0, 0.0, 1.0)
	assert_true(desk.can_use(dummy))
	dummy.global_position = Vector3(0.0, 0.0, 8.0)
	assert_false(desk.can_use(dummy), "the latch is at the table, not across the green")


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
	var pair := await _at_desk(desk)
	var player: Player = pair[0]
	desk.try_toggle(player)
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
	var pair := await _at_desk(desk)
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	desk.try_toggle(player)
	var start := mill.rotor_rad()
	var samples := 24
	for i in samples + 1:
		var t := TAU * float(i) / float(samples)
		pad.begin_frame()
		pad.move = Vector2(cos(t), -sin(t))
		desk.tick(player, STEP)
	assert_almost_eq(mill.rotor_rad() - start, -TAU, 0.12)
	var pivot := desk.get_node("StickPivot") as Node3D
	assert_almost_eq(pivot.rotation.z, -cos(TAU) * _Desk.MAX_TILT, 0.05)
	var knob := desk.get_node("StickPivot/Shaft/Knob") as Node3D
	assert_almost_eq(knob.rotation.y, mill.rotor_rad(), 0.05, "the ball marker sits on the mill")


func test_interact_takes_the_desk_and_steps_you_away() -> void:
	var mill := _mill()
	add_child_autofree(mill)
	var desk := _Desk.create({
		"position": Vector3(0.0, 0.0, 0.0),
		"yaw": 0.0,
	})
	add_child_autofree(desk)
	var pair := await _at_desk(desk)
	var player: Player = pair[0]
	var pad: CpuInput = pair[1]
	pad.begin_frame()
	pad.tap("interact")
	player._interact(STEP)
	assert_true(player.is_milling())
	assert_true(desk.is_used_by(player))
	pad.begin_frame()
	pad.tap("interact")
	player._interact(STEP)
	assert_false(player.is_milling())
	assert_false(mill.is_driven())


func test_the_builder_makes_a_desk_from_hole_data() -> void:
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
	var pivot := desk.get_node("StickPivot") as Node3D
	assert_almost_eq(pivot.rotation.z, -_Desk.MAX_TILT, 0.001, "the shaft leans with the analog")
	var knob := desk.get_node("StickPivot/Shaft/Knob") as Node3D
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


func _at_desk(desk) -> Array:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	var pad := CpuInput.new("p1", true)
	player.input = pad
	player.global_position = desk.stand_at()
	return [player, pad]
