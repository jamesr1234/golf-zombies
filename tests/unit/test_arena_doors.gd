extends GutTest
## Hole 5's gate is a pair of giant leaves that swing into the pit.

const SEED := 20260816


func test_the_doors_sit_on_the_gate_and_start_shut() -> void:
	var data := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	var doors := ArenaDoors.of(root)
	assert_not_null(doors)
	assert_eq(doors.name, ArenaDoors.NAME)
	assert_almost_eq(doors.amount(), 0.0, 0.001)
	assert_false(doors.is_open())
	assert_gt(doors.global_position.distance_to(data.cup), ArenaHole.floor_radius() + 8.0)
	var along := ArenaHole.leave_along(data)
	var outward: Vector3 = doors.global_position - data.cup
	outward.y = 0.0
	assert_gt(
		outward.normalized().dot(along), 0.7,
		"the porta faces the tee"
	)


func test_the_leaves_swing_into_the_pit() -> void:
	var data := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	var doors := ArenaDoors.of(root)
	var left := doors.get_node("Left") as Node3D
	var sample := Vector3(8.0, 8.0, 0.0)
	var shut_at := left.to_global(sample)
	var shut_to_cup := shut_at.distance_to(data.cup)
	doors.apply(1.0)
	assert_true(doors.is_open())
	var open_at := left.to_global(sample)
	assert_lt(
		open_at.distance_to(data.cup), shut_to_cup - 2.0,
		"the leaf has to swing toward the cup"
	)
	doors.snap(false)
	assert_false(doors.is_open())
	assert_almost_eq(doors.amount(), 0.0, 0.001)


func test_the_open_camera_stands_outside_the_gate() -> void:
	var data := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	var doors := ArenaDoors.of(root)
	var lens := doors.view(true, 0.0)
	var to_doors := doors.global_position - lens.origin
	to_doors.y = 0.0
	var inward := data.cup - doors.global_position
	inward.y = 0.0
	assert_gt(
		to_doors.normalized().dot(inward.normalized()), 0.6,
		"the open shot looks through the doors into the pit"
	)
	assert_gt(
		lens.origin.distance_to(data.cup), doors.global_position.distance_to(data.cup),
		"the open shot stands outside"
	)


func test_the_close_camera_stands_in_the_pit() -> void:
	var data := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	var doors := ArenaDoors.of(root)
	var lens := doors.view(false, 0.4)
	assert_lt(
		lens.origin.distance_to(data.cup), doors.global_position.distance_to(data.cup),
		"the close shot watches from inside"
	)
