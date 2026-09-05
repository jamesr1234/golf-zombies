extends GutTest
## The creator end to end: a hole laid out with the tools has to build into the
## same kind of scene every other hole builds into, and play by the same rules.

const CUBE := "res://assets/obstacles/cube_large.glb"
const WALL := "res://assets/obstacles/wall_medium.glb"
const RIFLE := "res://resources/weapons/rifle.tres"
const ZIP := "res://scenes/course/props/zipline.tscn"


func before_each() -> void:
	HoleStore.clear_sandbox()
	GameSettings.reset()


func after_all() -> void:
	before_each()


func test_a_built_custom_hole_has_the_parts_every_hole_has() -> void:
	var hole := CustomHole.create("Built")
	hole.add_placement(CUBE, Vector3(0.0, 0.0, -20.0))
	var data := CustomLayout.build(hole)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	var nav := root.get_node_or_null(HoleBuilder.NAV_NAME) as NavigationRegion3D
	assert_not_null(nav, "zombies path through the nav region")
	assert_not_null(nav.get_node_or_null("FairwayField"), "the lip walls keep play on the strip")
	assert_not_null(nav.get_node_or_null(CustomOverlay.NAME), "placed pieces come in as the overlay")
	assert_eq(nav.get_node(CustomOverlay.NAME).get_child_count(), 1)
	# The hole itself plus the warm-up cup on the practice green behind the tee.
	assert_eq(root.find_children("*", "Cup", true, false).size(), 2)
	assert_gt(root.find_children("*", "SurfacePatch", true, false).size(), 0, "the grass is painted on")
	assert_gt(data.spawn_points.size(), 5, "walkers still come in on a custom hole")


## Leaving the rect is what the ball reads as out of bounds, so a custom hole
## has to carry one that actually contains the hole.
func test_the_out_of_bounds_rect_wraps_the_whole_ribbon() -> void:
	var hole := CustomHole.create("Bounds")
	for i in 4:
		hole.append_piece(FairwayPiece.index_of("gentle_left"))
	var data := CustomLayout.build(hole)
	for point in data.centerline:
		assert_true(data.bounds.has_point(Vector2(point.x, point.z)), str(point))


func test_the_tee_sign_reads_the_hole_name() -> void:
	var data := CustomLayout.build(CustomHole.create("Neon Alley"))
	assert_true(data.sign_text().begins_with("NEON ALLEY"), data.sign_text())
	assert_true(data.banner_title().begins_with("Neon Alley"), data.banner_title())


func test_the_fairway_tool_lays_pieces_and_takes_them_back() -> void:
	var hole := CustomHole.create("Shaping")
	var tool := FairwayTool.new(hole)
	var before := hole.pieces.size()
	tool.pick(FairwayPiece.index_of("straight"))
	assert_true(tool.place())
	assert_eq(hole.pieces.size(), before + 1)
	assert_true(tool.undo())
	assert_eq(hole.pieces.size(), before)
	assert_eq(tool.picked_label(), "STRAIGHT")


func test_the_fairway_tool_shows_where_the_next_piece_would_run() -> void:
	var hole := CustomHole.create("Preview")
	var tool := FairwayTool.new(hole)
	tool.pick(FairwayPiece.index_of("dogleg_right"))
	var ends := tool.preview()
	var line := hole.centerline()
	assert_almost_eq(ends[0].distance_to(line[line.size() - 1]), 0.0, 0.01, "it starts where the hole ends")
	assert_gt(ends[1].distance_to(ends[0]), 1.0)


func test_a_refused_turn_says_why() -> void:
	var hole := CustomHole.create("Refused")
	var tool := FairwayTool.new(hole)
	var reasons: Array[String] = []
	tool.refused.connect(func(reason: String) -> void: reasons.append(reason))
	tool.pick(FairwayPiece.index_of("dogleg_left"))
	for i in 8:
		if not tool.place():
			break
	assert_gt(reasons.size(), 0, "the player has to be told the turn was turned away")


func test_the_place_tool_drops_a_piece_where_it_is_aimed() -> void:
	var hole := CustomHole.create("Placing")
	var tool := PlaceTool.new(hole)
	var host := Node3D.new()
	add_child_autofree(host)
	tool.aim(host, host, Vector3(0.0, 0.0, -20.0))
	assert_true(tool.place())
	assert_eq(hole.placements.size(), 1)
	var at: Vector3 = hole.placements[0][CustomHole.POSITION]
	assert_almost_eq(fmod(absf(at.x), GridSnap.CELL), 0.0, 0.001, "pieces sit on the grid")
	tool.release()


func test_the_place_tool_will_not_drop_a_piece_off_the_fairway() -> void:
	var hole := CustomHole.create("Off Strip")
	var tool := PlaceTool.new(hole)
	var host := Node3D.new()
	add_child_autofree(host)
	var reasons: Array[String] = []
	tool.refused.connect(func(reason: String) -> void: reasons.append(reason))
	tool.aim(host, host, Vector3(600.0, 0.0, -20.0))
	assert_false(tool.place())
	assert_eq(hole.placements.size(), 0)
	assert_eq(reasons.size(), 1)
	tool.release()


func test_the_place_tool_walks_the_shelves_and_the_pieces_on_them() -> void:
	var tool := PlaceTool.new(CustomHole.create("Browsing"))
	assert_eq(tool.shelf(), PieceCatalog.OBSTACLES)
	var first := tool.picked_path()
	tool.step_piece(1)
	assert_ne(tool.picked_path(), first)
	tool.step_shelf(1)
	assert_eq(tool.shelf(), PieceCatalog.PROPS)
	assert_true(tool.picked_path().begins_with(PieceCatalog.PROP_DIR))
	tool.step_shelf(1)
	assert_eq(tool.shelf(), PieceCatalog.VEHICLES)
	assert_true(tool.picked_path().begins_with(PieceCatalog.VEHICLE_DIR))
	tool.step_shelf(-1)
	assert_eq(tool.shelf(), PieceCatalog.PROPS)
	tool.step_shelf(-1)
	assert_eq(tool.shelf(), PieceCatalog.OBSTACLES)
	assert_false(tool.picked_label().is_empty())
	assert_eq(tool.labels().size(), tool.pieces().size())
	assert_eq(tool.labels()[tool.picked_index()], tool.picked_label())


## Dropping a gun goes straight into drawing its line, because a gun with no
## line is the exception rather than the rule.
func test_dropping_a_weapon_asks_for_its_line() -> void:
	var hole := CustomHole.create("Armed")
	var tool := PlaceTool.new(hole)
	var host := Node3D.new()
	add_child_autofree(host)
	while tool.shelf() != PieceCatalog.WEAPONS:
		tool.step_shelf(1)
	tool.aim(host, host, Vector3(0.0, 0.0, -20.0))
	assert_true(tool.place())
	assert_true(tool.is_gating(), "the line comes next")
	assert_eq(hole.placements[0][CustomHole.GATE], CustomHole.NO_GATE)
	tool.aim_gate = 0.4
	assert_true(tool.set_gate())
	assert_almost_eq(float(hole.placements[0][CustomHole.GATE]), 0.4, 0.001)
	assert_false(tool.is_gating())
	tool.release()


## A zipline is two clicks: the start deck first, then a lower end.
func test_a_zipline_asks_for_its_lower_end() -> void:
	var hole := CustomHole.create("Zip")
	var tool := PlaceTool.new(hole)
	var host := Node3D.new()
	add_child_autofree(host)
	_pick_zip(tool)
	tool.aim(host, host, Vector3(0.0, 5.4, -20.0))
	assert_true(tool.place())
	assert_true(tool.is_zipping(), "the lower end comes next")
	assert_eq(hole.placements.size(), 0, "nothing is stored until both decks are down")
	tool.aim(host, host, Vector3(5.4, 0.0, -30.0))
	assert_true(tool.place())
	assert_false(tool.is_zipping())
	assert_eq(hole.placements.size(), 1)
	assert_eq(hole.placements[0][CustomHole.PATH], ZIP)
	assert_true(CustomHole.has_end(hole.placements[0]))
	assert_gt(
		(hole.placements[0][CustomHole.POSITION] as Vector3).y,
		(hole.placements[0][CustomHole.END] as Vector3).y
	)
	tool.release()


func test_a_zipline_end_has_to_sit_lower() -> void:
	var hole := CustomHole.create("Flat Zip")
	var tool := PlaceTool.new(hole)
	var host := Node3D.new()
	add_child_autofree(host)
	var reasons: Array[String] = []
	tool.refused.connect(func(reason: String) -> void: reasons.append(reason))
	_pick_zip(tool)
	tool.aim(host, host, Vector3(0.0, 0.0, -20.0))
	assert_true(tool.place())
	tool.aim(host, host, Vector3(5.4, 2.7, -30.0))
	assert_false(tool.place())
	assert_true(tool.is_zipping())
	assert_eq(hole.placements.size(), 0)
	assert_eq(reasons.size(), 1)
	tool.release()


func test_backing_out_of_a_zipline_drops_the_start() -> void:
	var hole := CustomHole.create("Zip Cancel")
	var tool := PlaceTool.new(hole)
	var host := Node3D.new()
	add_child_autofree(host)
	_pick_zip(tool)
	tool.aim(host, host, Vector3(0.0, 5.4, -20.0))
	assert_true(tool.place())
	assert_true(tool.clear_zip())
	assert_false(tool.is_zipping())
	assert_eq(hole.placements.size(), 0)
	tool.release()


## Backing out of the line leaves the gun live for the whole hole.
func test_a_weapon_with_no_line_lasts_the_whole_hole() -> void:
	var hole := CustomHole.create("No Line")
	hole.add_placement(RIFLE, Vector3(0.0, 0.0, -20.0), 0.0, 0.7)
	var tool := PlaceTool.new(hole)
	assert_true(tool.start_gate(Vector3(0.0, 0.0, -20.0)))
	assert_true(tool.clear_gate())
	assert_eq(float(hole.placements[0][CustomHole.GATE]), CustomHole.NO_GATE)


func test_only_a_weapon_takes_a_line() -> void:
	var hole := CustomHole.create("Unarmed")
	hole.add_placement(CUBE, Vector3(0.0, 0.0, -20.0))
	var tool := PlaceTool.new(hole)
	var reasons: Array[String] = []
	tool.refused.connect(func(reason: String) -> void: reasons.append(reason))
	assert_false(tool.start_gate(Vector3(0.0, 0.0, -20.0)))
	assert_eq(reasons.size(), 1)
	assert_false(tool.is_gating())


## The line is a creator guide. What gets played has a pickup and nothing else.
func test_the_line_is_never_built_into_the_played_hole() -> void:
	var hole := CustomHole.create("Gated")
	hole.add_placement(RIFLE, Vector3(0.0, 0.0, -20.0), 0.0, 0.55)
	var overlay := CustomOverlay.build(hole)
	add_child_autofree(overlay)
	assert_eq(overlay.get_child_count(), 1)
	var pickup := overlay.get_child(0) as GunPickup
	assert_not_null(pickup, "a weapon lands as the pickup every hole uses")
	assert_almost_eq(pickup.gate, 0.55, 0.001)
	assert_eq(pickup.stats, load(RIFLE))


func test_surface_snap_writes_height_as_an_offset() -> void:
	var hole := CustomHole.create("Snap")
	var tool := PlaceTool.new(hole)
	var host := Node3D.new()
	add_child_autofree(host)
	tool.height = CustomLayout.build(hole).height
	tool.surface_snap = true
	tool.aim(host, host, Vector3(0.0, 20.0, -20.0))
	assert_true(tool.place())
	var stored: Vector3 = hole.placements[0][CustomHole.POSITION]
	assert_almost_eq(stored.y, 0.0, 0.05, "fairway snap is stored as no lift")
	tool.release()


func test_turning_a_piece_stays_on_half_right_angles() -> void:
	var tool := PlaceTool.new(CustomHole.create("Turning"))
	tool.turn(1)
	assert_almost_eq(tool.yaw, 315.0, 0.01, "right is clockwise from above")
	tool.turn(-1)
	assert_almost_eq(tool.yaw, 0.0, 0.01)
	tool.turn(-1)
	assert_almost_eq(tool.yaw, 45.0, 0.01)


func test_turning_off_rotation_snap_still_returns_to_the_same_angles() -> void:
	var tool := PlaceTool.new(CustomHole.create("Free Yaw"))
	tool.turn(1)
	assert_almost_eq(tool.yaw, 315.0, 0.01)
	tool.toggle_yaw_snap()
	assert_false(tool.yaw_snap)
	tool.turn(1)
	assert_almost_eq(tool.yaw, 310.0, 0.01)
	tool.toggle_yaw_snap()
	assert_true(tool.yaw_snap)
	assert_almost_eq(tool.yaw, 315.0, 0.01, "the 45s are the same ones as before")


func test_free_yaw_spins_while_held_and_snap_does_not() -> void:
	var tool := PlaceTool.new(CustomHole.create("Hold Turn"))
	tool.toggle_yaw_snap()
	tool.spin(1.0, 0.2)
	assert_almost_eq(tool.yaw, 360.0 - PlaceTool.TURN_SPEED * 0.2, 0.05)
	var locked := tool.yaw
	tool.yaw_snap = true
	tool.spin(1.0, 0.2)
	assert_almost_eq(tool.yaw, locked, 0.01, "snap mode stays a click at a time")


func test_the_nearest_piece_is_the_one_removed() -> void:
	var hole := CustomHole.create("Erasing")
	hole.add_placement(CUBE, Vector3(0.0, 0.0, -18.0))
	hole.add_placement(WALL, Vector3(0.0, 0.0, -30.0))
	var tool := PlaceTool.new(hole)
	assert_true(tool.erase(Vector3(0.0, 0.0, -30.5)))
	assert_eq(hole.placements.size(), 1)
	assert_eq(hole.placements[0][CustomHole.PATH], CUBE)
	assert_false(tool.erase(Vector3(0.0, 0.0, -300.0)), "nothing near means nothing goes")


func test_the_group_tool_gathers_a_ring_and_saves_it() -> void:
	var hole := CustomHole.create("Grouping")
	hole.add_placement(CUBE, Vector3(0.0, 0.0, -20.0))
	hole.add_placement(CUBE, Vector3(GridSnap.CELL, 0.0, -20.0))
	hole.add_placement(WALL, Vector3(0.0, 0.0, -60.0))
	var tool := GroupTool.new(hole)
	tool.aim(Vector3(0.0, 0.0, -20.0))
	tool.toggle()
	assert_eq(tool.selected.size(), 2, "only what is inside the ring is picked up")
	assert_true(tool.can_save())
	assert_true(tool.save("Twin Blocks"))
	assert_eq(tool.selected.size(), 0, "saving clears the selection")
	assert_eq(HoleStore.list_structures().size(), 1)


## Merging is the whole point of the tool: the loose pieces go and the structure
## stands where they were, or nothing would look like it had happened.
func test_merging_swaps_the_loose_pieces_for_the_structure() -> void:
	var hole := CustomHole.create("Merging")
	hole.add_placement(CUBE, Vector3(0.0, 0.0, -20.0))
	hole.add_placement(CUBE, Vector3(GridSnap.CELL, 0.0, -20.0))
	hole.add_placement(WALL, Vector3(0.0, 0.0, -60.0))
	var tool := GroupTool.new(hole)
	tool.aim(Vector3(0.0, 0.0, -20.0))
	tool.toggle()
	assert_true(tool.save("Twin Blocks"))
	assert_eq(hole.placements.size(), 2, "two cubes left and one structure arrived")
	var paths := PackedStringArray()
	for entry in hole.placements:
		paths.append(String(entry[CustomHole.PATH]))
	assert_false(paths.has(CUBE), "the pieces it was made from are gone")
	assert_true(paths.has(WALL), "anything outside the ring is untouched")
	var made := HoleStore.list_structures()[0]
	assert_true(paths.has(made))
	var overlay := CustomOverlay.build(hole)
	add_child_autofree(overlay)
	assert_eq(overlay.get_child_count(), 3, "the merged group still puts three pieces down")


func test_a_weapon_cannot_be_merged_into_a_structure() -> void:
	var hole := CustomHole.create("Armed Group")
	hole.add_placement(CUBE, Vector3(0.0, 0.0, -20.0))
	hole.add_placement(RIFLE, Vector3(GridSnap.CELL, 0.0, -20.0), 0.0, 0.5)
	var tool := GroupTool.new(hole)
	var reasons: Array[String] = []
	tool.refused.connect(func(reason: String) -> void: reasons.append(reason))
	tool.aim(Vector3(0.0, 0.0, -20.0))
	tool.toggle()
	assert_false(tool.save("Armed"))
	assert_eq(reasons.size(), 1)
	assert_eq(hole.placements.size(), 2, "a refused merge leaves the hole alone")


func test_a_group_needs_more_than_one_piece() -> void:
	var hole := CustomHole.create("Too Small")
	hole.add_placement(CUBE, Vector3(0.0, 0.0, -20.0))
	var tool := GroupTool.new(hole)
	var reasons: Array[String] = []
	tool.refused.connect(func(reason: String) -> void: reasons.append(reason))
	tool.aim(Vector3(0.0, 0.0, -20.0))
	tool.toggle()
	assert_false(tool.can_save())
	assert_false(tool.save("Lonely"))
	assert_false(tool.save(""))
	assert_eq(reasons.size(), 2)


## A saved group is stored flat, so it can never end up holding a reference to
## another record that would have to be chased at load time.
func test_a_group_cannot_be_built_from_another_group() -> void:
	var hole := CustomHole.create("Nested")
	hole.add_placement(CUBE, Vector3(0.0, 0.0, -20.0))
	hole.add_placement(CUBE, Vector3(GridSnap.CELL, 0.0, -20.0))
	var first := GroupTool.new(hole)
	first.aim(Vector3(0.0, 0.0, -20.0))
	first.toggle()
	var path := HoleStore.save_structure("Base Pair", first.parts())
	hole.placements.clear()
	hole.add_placement(path, Vector3(0.0, 0.0, -20.0))
	hole.add_placement(CUBE, Vector3(GridSnap.CELL, 0.0, -20.0))
	var second := GroupTool.new(hole)
	second.aim(Vector3(0.0, 0.0, -20.0))
	second.toggle()
	assert_false(second.save("Nested Group"))


func test_the_camera_holds_a_piece_out_in_front_of_the_lens() -> void:
	var camera := CreatorCamera.create()
	add_child_autofree(camera)
	var data := CustomLayout.build(CustomHole.create("Framing"))
	camera.frame(data)
	assert_almost_eq(camera.global_position.distance_to(camera.aim_point()), camera.reach, 0.01)
	camera.nudge_reach(-100.0)
	assert_almost_eq(camera.reach, CreatorCamera.REACH_MIN, 0.01)
	camera.nudge_reach(100.0)
	assert_almost_eq(camera.reach, CreatorCamera.REACH_MAX, 0.01)


func test_the_overview_looks_down_on_the_hole() -> void:
	var camera := CreatorCamera.create()
	add_child_autofree(camera)
	var data := CustomLayout.build(CustomHole.create("Overview"))
	camera.overview(data)
	assert_lt(camera.pitch, -30.0)
	assert_gt(camera.global_position.y, data.tee.y + 20.0)


## Playing takes a copy, so a stroke on the hole can never write back into the
## one still open on the workbench.
func test_playing_a_hole_takes_a_copy_of_it() -> void:
	var hole := CustomHole.create("Handoff")
	GameSettings.play_custom(hole)
	assert_true(GameSettings.is_custom())
	assert_ne(GameSettings.custom_hole, hole)
	GameSettings.custom_hole.add_placement(CUBE, Vector3(0.0, 0.0, -20.0))
	assert_eq(hole.placements.size(), 0)
	assert_eq(GameSettings.creator_hole, hole, "the creator gets its own hole back")


func test_the_creator_opens_a_new_hole_when_none_was_handed_over() -> void:
	GameSettings.reset()
	var fresh := GameSettings.take_creator_hole()
	assert_not_null(fresh)
	assert_true(fresh.is_playable())
	var mine := CustomHole.create("Mine")
	GameSettings.edit_custom(mine)
	assert_eq(GameSettings.take_creator_hole(), mine)
	assert_null(GameSettings.creator_hole, "the handover is only read once")


func test_a_new_hole_asks_for_a_width_before_building() -> void:
	var hole := CustomHole.create()
	hole.needs_width = true
	GameSettings.edit_custom(hole)
	var creator: CreatorMode = load("res://scenes/creator/hole_creator.tscn").instantiate()
	add_child_autofree(creator)
	await wait_frames(1)
	assert_true(creator._ui.picking_width())
	assert_eq(creator.hole.fairway_size, FairwayPiece.Width.SMALL)
	creator._ui._width._open = true
	creator._ui._width._pick = 2
	creator._ui._width.confirm()
	assert_false(creator._ui.picking_width())
	assert_eq(creator.hole.fairway_size, FairwayPiece.Width.LARGE)
	assert_false(creator.hole.needs_width)
	assert_almost_eq(
		creator.hole.width(),
		FairwayPiece.width_for(creator.hole.pieces, FairwayPiece.Width.LARGE), 0.01
	)


func test_an_existing_hole_skips_the_width_pick() -> void:
	GameSettings.edit_custom(CustomHole.create("Mine"))
	var creator: CreatorMode = load("res://scenes/creator/hole_creator.tscn").instantiate()
	add_child_autofree(creator)
	await wait_frames(1)
	assert_false(creator._ui.picking_width())
	assert_eq(creator.hole.fairway_size, FairwayPiece.Width.SMALL)


## A player-made hole is a card of one, so holing out ends the round instead of
## sending you on to a hole that was never built.
func test_a_custom_round_is_a_card_of_one_hole() -> void:
	var hole := CustomHole.create("Single")
	GameSettings.play_custom(hole)
	var card := GameState.new(PackedInt32Array([GameSettings.custom_hole.par()]))
	assert_eq(card.pars.size(), 1)
	assert_eq(card.par(), hole.par())
	card.strokes = 3
	card.hole_out()
	assert_true(card.is_course_complete())


## WASD, space and Z are flying the camera. A command sharing one of those keys
## would fire every time the player moved.
func test_no_command_key_is_already_flying_the_camera() -> void:
	var creator: CreatorMode = load("res://scenes/creator/hole_creator.tscn").instantiate()
	add_child_autofree(creator)
	await wait_frames(1)
	var flying: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_Z, KEY_SHIFT]
	assert_gt(creator._pad._keys.size(), 0)
	for key in creator._pad._keys:
		if key == KEY_S:
			continue
		assert_false(flying.has(key), "key %d also moves the camera" % key)
	assert_true(creator._pad._keys.has(KEY_S), "ctrl+S still saves")


## The camera flies on the sticks, Triangle (up) and Cross (down). A command
## sharing one of those would fire every time the builder moved.
func test_no_pad_button_is_already_flying_the_camera() -> void:
	var flying: Array[String] = ["jump", "revive"]
	assert_gt(CreatorPad.BUTTONS.size(), 0)
	for suffix in CreatorPad.BUTTONS:
		assert_false(flying.has(suffix), "%s also moves the camera" % suffix)


## Every command reachable on a pad, either as a button or a menu row, so the
## creator never needs a keyboard halfway through.
func test_the_pad_reaches_every_command() -> void:
	var creator: CreatorMode = load("res://scenes/creator/hole_creator.tscn").instantiate()
	add_child_autofree(creator)
	await wait_frames(1)
	for command in ["confirm", "cancel", "step_piece", "step_shelf", "side", "cycle_tool",
			"draw_weapon_line", "ask_group", "ask_save", "playtest", "overview",
			"toggle_menu", "toggle_yaw_snap", "context", "snap_surface"]:
		assert_true(creator.has_method(command), command)
	creator.toggle_menu()
	assert_true(creator.menu_is_open())
	creator.move_menu(1)
	assert_eq(creator._ui._menu_pick, 1)
	creator.move_menu(-1)
	assert_eq(creator._ui._menu_pick, 0)


## Escape closes the name field. That has to stay quiet if the viewport is gone,
## which is what happens mid-scene-change.
func test_aiming_does_not_need_a_world() -> void:
	var creator: CreatorMode = load("res://scenes/creator/hole_creator.tscn").instantiate()
	add_child_autofree(creator)
	await wait_frames(1)
	creator.switch_tool(CreatorMode.Tool.PLACE)
	remove_child(creator)
	creator._aim()
	assert_true(is_instance_valid(creator))


func test_closing_the_name_field_does_not_need_a_viewport() -> void:
	var ui := CreatorUi.create()
	add_child_autofree(ui)
	await wait_frames(1)
	ui.ask_save("Test")
	assert_true(ui.is_typing())
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.physical_keycode = KEY_ESCAPE
	ui._unhandled_key_input(escape)
	assert_false(ui.is_typing())
	remove_child(ui)
	ui._mark_handled()


func test_a_bare_s_does_not_open_the_save_prompt() -> void:
	var creator: CreatorMode = load("res://scenes/creator/hole_creator.tscn").instantiate()
	add_child_autofree(creator)
	await wait_frames(1)
	var bare := InputEventKey.new()
	bare.physical_keycode = KEY_S
	creator._pad.on_key(bare)
	assert_false(creator._ui.is_typing())
	bare.ctrl_pressed = true
	creator._pad.on_key(bare)
	assert_true(creator._ui.is_typing())


func test_switching_tools_moves_the_creator_between_them() -> void:
	var creator: CreatorMode = load("res://scenes/creator/hole_creator.tscn").instantiate()
	add_child_autofree(creator)
	await wait_frames(1)
	for pair in [[KEY_2, CreatorMode.Tool.PLACE], [KEY_3, CreatorMode.Tool.GROUP],
			[KEY_1, CreatorMode.Tool.FAIRWAY]]:
		var press := InputEventKey.new()
		press.physical_keycode = pair[0]
		creator._pad.on_key(press)
		assert_eq(creator.tool, pair[1])
	creator.cycle_tool(1)
	assert_eq(creator.tool, CreatorMode.Tool.PLACE, "the pad walks the same three tools")
	creator.cycle_tool(-1)
	assert_eq(creator.tool, CreatorMode.Tool.FAIRWAY)


func test_forward_flight_follows_the_lens() -> void:
	var step := CreatorCamera.travel(Basis.IDENTITY, Vector2(0.0, -1.0))
	assert_lt(step.z, 0.0, "stick up walks the way the camera looks")
	var back := CreatorCamera.travel(Basis.IDENTITY, Vector2(0.0, 1.0))
	assert_gt(back.z, 0.0, "stick down walks away from the lens")


func test_the_place_shelf_is_listed_like_fairway() -> void:
	var creator: CreatorMode = load("res://scenes/creator/hole_creator.tscn").instantiate()
	add_child_autofree(creator)
	await wait_frames(1)
	assert_gt(creator._ui._palette.get_child_count(), 0, "fairway opens with its list")
	creator.switch_tool(CreatorMode.Tool.PLACE)
	await wait_frames(1)
	assert_eq(creator._ui._heading.text, HudStyle.chrome(creator._place.shelf()))
	assert_eq(creator._ui._palette.get_child_count(), creator._place.labels().size())
	assert_true(creator._ui._scroll.visible)


func test_a_held_stick_does_not_walk_a_menu_until_it_moves() -> void:
	var pad := PadInput.new()
	assert_eq(pad.repeat_dir(0.016), Vector2i.ZERO)


func test_a_button_held_from_the_last_screen_is_not_a_press() -> void:
	var pad := PadInput.new()
	assert_false(pad._rose("interact", true), "Circle is still down from the title")
	assert_false(pad._rose("interact", true), "held is not a new press")
	assert_false(pad._rose("interact", false))
	assert_true(pad._rose("interact", true), "a real press after release")


func test_the_name_pad_types_and_confirms() -> void:
	var pad := CreatorKeypad.create()
	add_child_autofree(pad)
	await wait_frames(1)
	var got: Array[String] = []
	pad.submitted.connect(func(text: String) -> void: got.append(text))
	pad.open("NAME THIS HOLE", "HOLE")
	assert_true(pad.is_open())
	assert_eq(CreatorKeypad.KEYS[pad._pick], "OK")
	var letter := InputEventKey.new()
	letter.pressed = true
	letter.unicode = "X".unicode_at(0)
	assert_true(pad.handle_key(letter))
	pad._hit(CreatorKeypad.KEYS.find("OK"))
	assert_false(pad.is_open())
	assert_eq(got.size(), 1)
	assert_eq(got[0], "HOLEX")


func test_circle_does_the_tool_in_hand() -> void:
	var creator: CreatorMode = load("res://scenes/creator/hole_creator.tscn").instantiate()
	add_child_autofree(creator)
	await wait_frames(1)
	creator.switch_tool(CreatorMode.Tool.GROUP)
	creator.context()
	assert_true(creator._ui.is_typing(), "group Circle opens the name pad")
	creator._ui._keypad.close()
	creator.switch_tool(CreatorMode.Tool.PLACE)
	creator.hole.add_placement(RIFLE, creator._camera.aim_point())
	creator._refresh_props()
	creator.context()
	assert_true(creator._place.is_gating(), "place Circle draws a weapon line")


func test_the_hints_stay_on() -> void:
	var ui := CreatorUi.create()
	add_child_autofree(ui)
	await wait_frames(1)
	assert_true(ui._key_hint.visible)
	assert_true(ui._pad_hint.visible)
	assert_true(ui._stat.visible)


func test_the_browser_ignores_the_click_that_opened_it() -> void:
	HoleStore.save_hole(CustomHole.create("Mine"))
	var browser: HoleBrowser = load("res://scenes/creator/hole_browser.tscn").instantiate()
	add_child_autofree(browser)
	assert_false(browser._open)
	browser._process(0.016)
	assert_false(browser._leaving, "leftover confirm must not open a blank hole")
	assert_eq(browser.rows.size(), 1)


func test_the_browser_lists_what_was_saved() -> void:
	var first := CustomHole.create("Alpha")
	HoleStore.save_hole(first)
	var second := CustomHole.create("Beta")
	second.created_at = first.created_at + 60
	HoleStore.save_hole(second)
	var browser: HoleBrowser = load("res://scenes/creator/hole_browser.tscn").instantiate()
	add_child_autofree(browser)
	await wait_frames(1)
	assert_eq(browser.rows.size(), 2)
	assert_eq(String(browser.rows[0]["title"]), "Beta", "the newest hole is at the top")
	assert_true(browser.picking_new(), "a new hole is always the first choice")
	assert_true(browser._open)
	assert_false(browser._leaving)
	browser.move(1)
	assert_eq(browser.picked, 1)
	assert_false(browser.picking_new())
	browser.erase()
	assert_eq(browser.rows.size(), 1)
	assert_false(browser.picking_new())
	assert_eq(String(browser.rows[browser.picked - 1]["title"]), "Alpha")


func _pick_zip(tool: PlaceTool) -> void:
	while tool.shelf() != PieceCatalog.PROPS:
		tool.step_shelf(1)
	var seen: PackedStringArray = []
	while tool.picked_path() != ZIP:
		var path := tool.picked_path()
		assert_false(seen.has(path), "the props shelf has to list the zipline")
		seen.append(path)
		tool.step_piece(1)
