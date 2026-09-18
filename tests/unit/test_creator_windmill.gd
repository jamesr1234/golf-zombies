extends GutTest
## Dropping a mill opens the speed dial. A tap nudges. A long hold cranks.

const _Dial := preload("res://scripts/creator/creator_windmill.gd")


func before_each() -> void:
	HoleStore.clear_sandbox()
	GameSettings.reset()


func after_all() -> void:
	before_each()


func test_the_speed_dial_clamps_and_confirms() -> void:
	var dialog := _Dial.create()
	add_child_autofree(dialog)
	await wait_physics_frames(1)
	dialog.open()
	await wait_physics_frames(1)
	assert_true(dialog.is_open())
	assert_almost_eq(dialog.spin_deg(), CartPathWindmill.SPIN_DEFAULT, 0.001)
	dialog.nudge(20)
	assert_almost_eq(dialog.spin_deg(), CartPathWindmill.SPIN_DEFAULT + 20.0, 0.001)
	dialog.nudge(int(CartPathWindmill.SPIN_MAX))
	assert_almost_eq(dialog.spin_deg(), CartPathWindmill.SPIN_MAX, 0.001)
	dialog.nudge(-int(CartPathWindmill.SPIN_MAX) - 40)
	assert_almost_eq(dialog.spin_deg(), CartPathWindmill.SPIN_MIN, 0.001)
	var got: Array = []
	dialog.picked.connect(func(deg: float) -> void: got.append(deg))
	dialog.nudge(90)
	dialog.confirm()
	assert_false(dialog.is_open())
	assert_eq(got.size(), 1)
	assert_almost_eq(float(got[0]), 90.0, 0.001)


func test_a_long_hold_cranks_the_dial_faster() -> void:
	var dialog := _Dial.create()
	add_child_autofree(dialog)
	await wait_physics_frames(1)
	dialog.open()
	await wait_physics_frames(1)
	dialog.crank(1, 0.0)
	var after_tap := dialog.spin_deg()
	dialog.crank(1, _Dial.FIRST_WAIT + 0.2)
	var after_short := dialog.spin_deg() - after_tap
	dialog.crank(1, 1.4)
	var after_long := dialog.spin_deg() - after_tap - after_short
	assert_gt(after_short, 0.0, "a held d-pad has to keep climbing")
	assert_gt(after_long, after_short, "the longer it is held, the faster it climbs")


func test_dropping_a_windmill_asks_for_its_speed() -> void:
	var creator: CreatorMode = load("res://scenes/creator/hole_creator.tscn").instantiate()
	add_child_autofree(creator)
	await wait_physics_frames(1)
	creator.switch_tool(CreatorMode.Tool.PLACE)
	_pick_mill(creator._place)
	creator._place.aim(creator._held, creator._world.nav(), Vector3(0.0, 0.0, -20.0))
	creator.confirm()
	assert_eq(creator.hole.placements.size(), 1)
	assert_true(creator._ui.picking_mill(), "R2 drops the mill and asks how fast")
	assert_almost_eq(
		CustomHole.spin_of(creator.hole.placements[0]), CartPathWindmill.SPIN_DEFAULT, 0.001
	)
	await wait_physics_frames(1)
	creator._ui._mill.nudge(200)
	creator._ui._mill.confirm()
	assert_false(creator._ui.picking_mill())
	assert_almost_eq(CustomHole.spin_of(creator.hole.placements[0]), 232.0, 0.001)
	var overlay := creator._world.nav()
	var mill: CartPathWindmill = null
	if overlay != null:
		for child in overlay.find_children("*", "CartPathWindmill", true, false):
			mill = child
	assert_not_null(mill)
	assert_almost_eq(mill.spin_deg, 232.0, 0.001)


func test_backing_out_of_the_speed_dial_keeps_the_mill() -> void:
	var creator: CreatorMode = load("res://scenes/creator/hole_creator.tscn").instantiate()
	add_child_autofree(creator)
	await wait_physics_frames(1)
	creator.switch_tool(CreatorMode.Tool.PLACE)
	_pick_mill(creator._place)
	creator._place.aim(creator._held, creator._world.nav(), Vector3(0.0, 0.0, -20.0))
	creator.confirm()
	assert_true(creator._ui.picking_mill())
	await wait_physics_frames(1)
	creator._ui._mill.nudge(80)
	creator._ui._mill._cancel()
	assert_false(creator._ui.picking_mill())
	assert_eq(creator.hole.placements.size(), 1)
	assert_almost_eq(
		CustomHole.spin_of(creator.hole.placements[0]), CartPathWindmill.SPIN_DEFAULT, 0.001
	)


func test_place_writes_the_chosen_speed() -> void:
	var hole := CustomHole.create("Mill")
	var tool := PlaceTool.new(hole)
	var host := Node3D.new()
	add_child_autofree(host)
	_pick_mill(tool)
	tool.aim(host, host, Vector3(0.0, 0.0, -20.0))
	assert_true(tool.place())
	assert_almost_eq(CustomHole.spin_of(hole.placements[0]), CartPathWindmill.SPIN_DEFAULT, 0.001)
	assert_true(tool.finish_spin(900.0))
	assert_almost_eq(CustomHole.spin_of(hole.placements[0]), 900.0, 0.001)
	assert_true(tool.finish_spin(CartPathWindmill.SPIN_MAX + 50.0))
	assert_almost_eq(CustomHole.spin_of(hole.placements[0]), CartPathWindmill.SPIN_MAX, 0.001)


func _pick_mill(tool: PlaceTool) -> void:
	while tool.shelf() != PieceCatalog.PROPS:
		tool.step_shelf(1)
	var seen: PackedStringArray = []
	while tool.picked_path() != CustomHole.WINDMILL:
		var path := tool.picked_path()
		assert_false(seen.has(path), "the props shelf has to list the windmill")
		seen.append(path)
		tool.step_piece(1)
