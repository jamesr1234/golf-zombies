extends GutTest
## The course-creator lesson is a forced walkthrough: only the asked-for action
## counts, a compliment follows, and the browser keeps that row above the rest.


func before_each() -> void:
	HoleStore.clear_sandbox()
	GameSettings.reset()


func after_all() -> void:
	before_each()


func test_the_lesson_walks_every_creator_step() -> void:
	var ids := CreatorLesson.ids()
	for needle in [
		"fly", "look", "climb", "drop", "cycle_fairway",
		"place_fairway", "take_back", "undo", "redo", "switch_place",
		"cycle_place", "surface_snap", "yaw_snap", "turn", "hold", "place_held",
		"shelf_vehicles", "place_cart", "place_obstacles", "shelf_props", "place_prop",
		"shelf_weapons", "place_weapon", "set_line",
		"shelf_spawns", "place_spawn", "set_yard", "set_chase", "set_counts",
		"switch_group", "grow", "select", "merge", "help", "menu", "save", "done",
	]:
		assert_true(ids.has(needle), needle)
	assert_false(ids.has("width"))
	assert_false(ids.has("reach"))
	assert_eq(ids[0], "fly")
	assert_eq(ids[ids.size() - 1], "done")


func test_every_step_comes_with_a_tip() -> void:
	for step_id in CreatorLesson.ids():
		if step_id == "done":
			continue
		assert_false(String(CreatorLesson.TIPS.get(step_id, "")).is_empty(), step_id)
	var undo := String(CreatorLesson.TIPS["undo"])
	assert_true(undo.contains("L1"))
	assert_true(undo.to_upper().contains("CIRCLE"))
	var lesson := CreatorLesson.new()
	lesson.start(null)
	assert_gt(lesson.icons().size(), 0)
	assert_eq(lesson.keys(), "WASD")
	assert_eq(lesson.id(), "fly")


func test_compliments_vary_and_do_not_repeat_back_to_back() -> void:
	var lesson := CreatorLesson.new()
	lesson.start(null)
	var seen := {}
	var last := ""
	for _i in 16:
		var line := lesson.compliment()
		assert_false(line.is_empty())
		assert_ne(line, last)
		seen[line] = true
		last = line
	assert_gt(seen.size(), 3)


func test_the_lesson_only_allows_the_current_action() -> void:
	var lesson := CreatorLesson.new()
	lesson.start(null)
	assert_eq(lesson.id(), "fly")
	assert_true(lesson.allows(CreatorLesson.Act.MENU))
	assert_false(lesson.allows(CreatorLesson.Act.CONFIRM))
	assert_false(lesson.allows(CreatorLesson.Act.SWITCH_TOOL))
	lesson.continue_tip(null)
	assert_eq(lesson.id(), "fly", "Enter does nothing until a tip is up")


func test_starting_a_tutorial_hands_the_creator_a_blank_hole() -> void:
	GameSettings.start_tutorial()
	assert_true(GameSettings.creator_tutorial)
	assert_not_null(GameSettings.creator_hole)
	assert_true(GameSettings.creator_hole.needs_width)
	assert_eq(GameSettings.creator_hole.title, "Tutorial")
	var hole := GameSettings.take_creator_hole()
	assert_true(GameSettings.take_creator_tutorial())
	assert_false(GameSettings.take_creator_tutorial())
	assert_true(hole.needs_width)
	GameSettings.reset()
	assert_false(GameSettings.creator_tutorial)


func test_the_browser_puts_the_tutorial_above_a_divider() -> void:
	HoleStore.save_hole(CustomHole.create("Mine"))
	var browser: HoleBrowser = load("res://scenes/creator/hole_browser.tscn").instantiate()
	add_child_autofree(browser)
	await wait_frames(1)
	assert_true(browser.picking_tutorial())
	assert_eq(browser._count(), 3)
	assert_eq(browser._list.get_child_count(), 4)
	assert_eq(browser._list.get_child(0).text, HudStyle.chrome("Tutorial"))
	assert_true(browser._list.get_child(1) is ColorRect)
	assert_eq(browser._list.get_child(2).text, HudStyle.chrome("New hole"))
	assert_eq(browser._list.get_child(3).text, HudStyle.chrome("Mine"))
	assert_eq(browser._blurb.text, HudStyle.chrome("Learn every tool by using it."))
	browser.erase()
	assert_eq(browser.rows.size(), 1, "the tutorial row cannot be deleted")


func test_the_tutorial_waits_until_the_width_is_picked() -> void:
	var creator := await _open_tutorial()
	assert_null(creator._lesson)
	assert_false(creator._ui.coach_is_visible())
	assert_true(creator._ui.picking_width())
	creator._ui._width._open = true
	creator._ui._width.confirm()
	assert_not_null(creator._lesson)
	assert_true(creator._ui.coach_is_visible())
	assert_eq(creator._lesson.id(), "fly")
	var pieces := creator.hole.pieces.size()
	creator.confirm()
	assert_eq(creator.hole.pieces.size(), pieces, "placing is locked until the lesson asks")
	creator.switch_tool(CreatorMode.Tool.PLACE)
	assert_eq(creator.tool, CreatorMode.Tool.FAIRWAY)
	creator.toggle_menu()
	assert_true(creator.menu_is_open(), "the menu stays available so they can quit")
	creator.toggle_menu()


func test_doing_the_asked_action_praises_and_continues() -> void:
	var creator := await _open_tutorial()
	creator._ui._width._open = true
	creator._ui._width.confirm()
	assert_false(creator.hole.needs_width)
	_advance(creator)
	assert_eq(creator._lesson.id(), "fly")
	assert_false(creator._lesson.praising())
	var praise: Array[String] = []
	creator._lesson.praised.connect(func(text: String) -> void: praise.append(text))
	assert_true(creator._ui._coach._hint.visible)
	assert_gt(creator._ui._coach._glyphs.get_child_count(), 0)
	creator._camera.global_position += Vector3(8.0, 0.0, 0.0)
	creator._lesson.tick(creator, CreatorLesson.FLY_SECONDS)
	assert_eq(praise.size(), 1)
	assert_true(CreatorLesson.PRAISE.has(praise[0]))
	assert_true(creator._lesson.praising())
	creator._process(0.016)
	assert_false(creator._camera.frozen)
	assert_true(creator._camera.drop_held(), "Cross that dismisses a tip must not descend")
	assert_true(creator._ui._coach._tip.visible)
	assert_true(creator._ui._coach._next.visible)
	assert_false(creator._ui._coach._hint.visible)
	assert_eq(creator._ui._coach._tip.text, HudStyle.chrome(creator._lesson.tip()))
	assert_eq(creator._ui._coach._next.text, HudStyle.chrome(CreatorLesson.NEXT_HINT))
	creator._lesson.tick(creator, 8.0)
	assert_eq(creator._lesson.id(), "fly", "the tip stays up until they press on")
	assert_true(creator._lesson.praising())
	creator._lesson.continue_tip(creator)
	assert_eq(creator._lesson.id(), "look")
	assert_false(creator._ui._coach._tip.visible)
	assert_false(creator._ui._coach._next.visible)
	assert_true(creator._ui._coach._hint.visible)
	assert_eq(CreatorLesson.NEXT, KEY_ENTER)


func test_the_lesson_can_be_walked_to_the_end() -> void:
	var creator := await _open_tutorial()
	_skip_to(creator, "done")
	assert_eq(creator._lesson.id(), "done")
	assert_false(creator._lesson.is_live())
	creator.switch_tool(CreatorMode.Tool.FAIRWAY)
	assert_eq(creator.tool, CreatorMode.Tool.FAIRWAY, "every command unlocks after the lesson")


func test_surface_snap_is_taught_before_ramps_and_stays_on() -> void:
	var ids := CreatorLesson.ids()
	assert_true(ids.find("surface_snap") < ids.find("place_obstacles"))
	assert_true(ids.find("yaw_snap") < ids.find("place_obstacles"))
	assert_true(ids.find("hold") < ids.find("place_obstacles"))
	assert_true(ids.find("shelf_vehicles") < ids.find("place_obstacles"))
	assert_true(ids.find("place_cart") < ids.find("place_obstacles"))
	var tip := String(CreatorLesson.TIPS["surface_snap"]).to_lower()
	assert_true(tip.contains("play") or tip.contains("dirt") or tip.contains("air"))
	var creator := await _open_tutorial()
	_skip_to(creator, "surface_snap")
	assert_false(creator._place.surface_snap)
	creator._place.surface_snap = true
	creator._lesson.tick(creator, 0.0)
	assert_true(creator._lesson.praising())
	creator._lesson.continue_tip(creator)
	assert_true(creator._lesson.allows(CreatorLesson.Act.SNAP_SURFACE))


func test_yaw_snap_needs_a_free_spin_before_it_locks_again() -> void:
	var creator := await _open_tutorial()
	_skip_to(creator, "yaw_snap")
	creator._place.yaw_snap = false
	creator._lesson.tick(creator, 0.0)
	creator._place.yaw_snap = true
	creator._lesson.tick(creator, 0.0)
	assert_false(creator._lesson.praising(), "toggling without spinning is not enough")
	creator._place.yaw_snap = false
	creator._place.yaw += 12.0
	creator._lesson.tick(creator, 0.0)
	assert_false(creator._lesson.praising(), "snap has to come back on")
	creator._place.yaw_snap = true
	creator._lesson.tick(creator, 0.0)
	assert_true(creator._lesson.praising())
	creator._lesson.continue_tip(creator)
	assert_true(creator._lesson.allows(CreatorLesson.Act.TURN))


func test_cart_and_ramp_drops_can_be_turned() -> void:
	var creator := await _open_tutorial()
	_skip_to(creator, "place_cart")
	assert_true(creator._lesson.allows(CreatorLesson.Act.TURN))
	_skip_to(creator, "place_obstacles")
	assert_true(creator._lesson.allows(CreatorLesson.Act.TURN))


func test_hold_needs_a_fly_around_before_it_counts() -> void:
	var creator := await _open_tutorial()
	_skip_to(creator, "hold")
	creator._place._holding = true
	creator._lesson.tick(creator, CreatorLesson.FLY_SECONDS)
	assert_false(creator._lesson.praising(), "parking without flying is not enough")
	_hold_move(creator, Vector3(8.0, 0.0, 0.0), CreatorLesson.FLY_SECONDS)
	assert_true(creator._lesson.praising())


func test_obstacle_drops_have_to_be_ramps() -> void:
	var creator := await _open_tutorial()
	_skip_to(creator, "place_obstacles")
	_drop_kinds(creator, [
		"res://assets/obstacles/cube_large.glb",
		"res://assets/obstacles/cube_small.glb",
	])
	assert_false(creator._lesson.praising())
	_drop_kinds(creator, [
		"res://assets/obstacles/ramp_small.glb",
		"res://assets/obstacles/ramp_medium.glb",
	])
	assert_true(creator._lesson.praising())
	assert_true(creator._lesson.launches_playtest())
	assert_eq(creator._lesson.playtest_goal(), GameSettings.TutorialGoal.DRIVE_RAMP)


func test_the_cart_has_to_snap_to_the_grass() -> void:
	var creator := await _open_tutorial()
	_skip_to(creator, "place_cart")
	creator._place.surface_snap = false
	creator.hole.add_placement(CreatorLesson.CART, Vector3(0.0, 4.0, -20.0))
	creator._lesson.tick(creator, 0.0)
	assert_false(creator._lesson.praising(), "a floating cart does not count")
	creator._place.surface_snap = true
	creator._lesson.tick(creator, 0.0)
	assert_true(creator._lesson.praising())


func test_the_weapon_step_wants_a_rocket_and_a_full_pack() -> void:
	var creator := await _open_tutorial()
	_skip_to(creator, "place_weapon")
	creator.hole.add_placement("res://resources/weapons/rifle.tres", Vector3(0.0, 0.0, -20.0))
	creator._lesson.tick(creator, 0.0)
	assert_false(creator._lesson.praising())
	creator.hole.add_placement(CreatorLesson.ROCKET, Vector3(0.0, 0.0, -20.0))
	creator._lesson.tick(creator, 0.0)
	assert_true(creator._lesson.praising())
	_skip_to(creator, "set_counts")
	creator._place.roaming = -1
	creator.hole.add_placement(CustomHole.SPAWN, Vector3.ZERO)
	creator._lesson.tick(creator, 0.0)
	assert_false(creator._lesson.praising(), "an empty yard is not a pack")
	creator.hole.placements[creator.hole.placements.size() - 1][CustomHole.COUNTS] = {
		"walker": 2, "runner": 1, "brute": 0, "gunner": 0
	}
	creator._lesson.tick(creator, 0.0)
	assert_true(creator._lesson.praising(), "a few walkers is already a pack")
	assert_true(creator._lesson.launches_playtest())
	assert_eq(creator._lesson.playtest_goal(), GameSettings.TutorialGoal.CLEAR_PACK)


func test_confirming_a_pack_does_not_ask_for_another_spawn() -> void:
	var creator := await _open_tutorial()
	_skip_to(creator, "set_chase")
	creator._ui.ask_spawn()
	creator._lesson.tick(creator, 0.0)
	assert_true(creator._lesson.praising())
	creator._ui._spawn._open = true
	creator._ui._spawn._counts = {"walker": 2, "runner": 1, "brute": 0, "gunner": 0}
	creator._ui._spawn.confirm()
	assert_false(creator._place.is_roaming())
	assert_false(creator._ui.picking_spawn())
	creator._lesson.continue_tip(creator)
	assert_eq(creator._lesson.id(), "set_counts")
	assert_true(creator._lesson.praising(), "the pack they just planted already counts")
	assert_true(creator._lesson.launches_playtest())
	assert_ne(creator._lesson.id(), "place_spawn")


func test_backing_out_of_the_pack_lets_them_drop_a_spawn_again() -> void:
	var creator := await _open_tutorial()
	_skip_to(creator, "set_counts")
	assert_true(creator._place.is_roaming())
	creator._ui.ask_spawn()
	creator._ui._spawn._open = true
	creator._ui._spawn._cancel()
	assert_eq(creator._lesson.id(), "place_spawn")
	assert_false(creator._place.is_roaming())
	assert_eq(_spawn_count(creator), 0)
	assert_true(creator._lesson.allows(CreatorLesson.Act.CONFIRM))
	creator.tool = CreatorMode.Tool.PLACE
	creator._place.category = creator._place.shelves().find(PlaceTool.SPAWNS)
	creator._place.aim(creator._held, creator._world.nav(), Vector3(0.0, 0.0, -20.0))
	creator.confirm()
	assert_true(creator._place.is_roaming(), "R2 has to plant a new spawn after a cancel")


func test_a_tutorial_playtest_hands_the_hole_back_on_the_next_step() -> void:
	var hole := CustomHole.create("Tutorial")
	GameSettings.play_tutorial_hole(hole, 20, CreatorMode.Tool.PLACE)
	assert_true(GameSettings.is_custom())
	assert_true(GameSettings.creator_tutorial)
	assert_true(GameSettings.return_to_creator)
	assert_eq(GameSettings.take_creator_lesson_at(), 20)
	assert_eq(GameSettings.take_creator_lesson_tool(), CreatorMode.Tool.PLACE)
	assert_true(GameSettings.take_return_to_creator())
	assert_false(GameSettings.take_return_to_creator())
	var lesson := CreatorLesson.new()
	lesson.start(null)
	lesson.resume_at(null, 20)
	assert_eq(lesson.id(), CreatorLesson.ids()[20])
	assert_false(lesson.praising())


func test_a_blocked_fairway_place_does_not_count() -> void:
	var creator := await _open_tutorial()
	_skip_to(creator, "fly")
	var pieces := creator.hole.pieces.size()
	creator._fairway.pick(FairwayPiece.index_of("straight"))
	creator.confirm()
	assert_eq(creator.hole.pieces.size(), pieces)
	assert_eq(creator._lesson.id(), "fly")


func _open_tutorial() -> CreatorMode:
	GameSettings.start_tutorial()
	var creator: CreatorMode = load("res://scenes/creator/hole_creator.tscn").instantiate()
	add_child_autofree(creator)
	await wait_frames(1)
	return creator


func _skip_to(creator: CreatorMode, want: String) -> void:
	if creator._ui.picking_width():
		creator._ui._width._open = true
		creator._ui._width.confirm()
	var guard := 0
	while creator._lesson != null and creator._lesson.id() != want and guard < 64:
		_force(creator)
		guard += 1
	assert_eq(creator._lesson.id(), want)


func _force(creator: CreatorMode) -> void:
	match creator._lesson.id():
		"fly":
			_hold_move(creator, Vector3(8.0, 0.0, 0.0), CreatorLesson.FLY_SECONDS)
		"look":
			_hold_look(creator, CreatorLesson.LOOK_SECONDS)
		"climb":
			_hold_move(creator, Vector3(0.0, 3.0, 0.0), CreatorLesson.LIFT_SECONDS)
		"drop":
			_hold_move(creator, Vector3(0.0, -3.0, 0.0), CreatorLesson.LIFT_SECONDS)
		"cycle_fairway":
			_cycle(creator, true)
		"place_fairway":
			_append_pieces(creator, CreatorLesson.NEED_FAIRWAY)
		"place_again":
			_append_pieces(creator, CreatorLesson.NEED_AGAIN)
		"redo":
			creator.hole.append_piece(FairwayPiece.index_of("straight"))
		"take_back", "undo":
			if not creator.hole.pieces.is_empty():
				creator.hole.pieces.remove_at(creator.hole.pieces.size() - 1)
		"switch_place":
			creator.tool = CreatorMode.Tool.PLACE
		"cycle_place":
			_cycle(creator, false)
		"turn":
			_nudge_turn(creator)
		"place_obstacles":
			_drop_kinds(creator, [
				"res://assets/obstacles/ramp_small.glb",
				"res://assets/obstacles/ramp_medium.glb",
			])
		"hold":
			creator._place._holding = true
			_hold_move(creator, Vector3(8.0, 0.0, 0.0), CreatorLesson.FLY_SECONDS)
		"place_held", "place_weapon", "place_cart":
			if creator._lesson.id() == "place_cart":
				creator._place.surface_snap = true
			creator.hole.add_placement(
				_path_for(creator._lesson.id()), Vector3(0.0, 0.0, -20.0)
			)
		"shelf_vehicles":
			creator._place.category = creator._place.shelves().find(PieceCatalog.VEHICLES)
		"place_prop":
			_drop_kinds(creator, [
				"res://scenes/course/props/rock.tscn",
				"res://scenes/course/props/windmill.tscn",
			])
		"grow":
			_nudge_grow(creator)
		"shelf_props":
			creator._place.category = creator._place.shelves().find(PieceCatalog.PROPS)
		"surface_snap":
			creator._place.surface_snap = true
		"yaw_snap":
			creator._place.yaw_snap = false
			creator._place.yaw += 12.0
			creator._lesson.tick(creator, 0.0)
			creator._place.yaw_snap = true
			creator._lesson.tick(creator, 0.0)
		"shelf_weapons":
			creator._place.category = creator._place.shelves().find(PieceCatalog.WEAPONS)
		"set_line":
			var armed := false
			for entry in creator.hole.placements:
				if CustomHole.is_weapon(String(entry[CustomHole.PATH])):
					entry[CustomHole.GATE] = 0.4
					armed = true
			if not armed:
				creator.hole.add_placement(
					"res://resources/weapons/rifle.tres", Vector3(0.0, 0.0, -20.0), 0.0, 0.4
				)
			creator._place.gating = -1
		"shelf_spawns":
			creator._place.category = creator._place.shelves().find(PlaceTool.SPAWNS)
		"place_spawn":
			creator.hole.add_placement(CustomHole.SPAWN, Vector3(0.0, 0.0, -20.0))
			creator._place.roaming = creator.hole.placements.size() - 1
		"set_yard":
			creator._place.hunting = true
		"set_chase":
			creator._ui.ask_spawn()
		"set_counts":
			creator._place.roaming = -1
			creator._place.hunting = false
			_give_counted_spawn(creator)
		"switch_group":
			creator.tool = CreatorMode.Tool.GROUP
		"select":
			creator._group.selected.clear()
			creator._group.selected.append(0)
			creator._group.selected.append(1)
		"merge":
			var parts: Array[Dictionary] = [
				CustomHole.placement("res://assets/obstacles/cube_large.glb", Vector3.ZERO),
				CustomHole.placement(
					"res://assets/obstacles/cube_large.glb", Vector3(1.0, 0.0, 0.0)
				),
			]
			HoleStore.save_structure("Pair", parts)
		"help":
			creator.toggle_help()
		"help_close":
			if creator.help_is_open():
				creator._ui.toggle_help()
		"menu":
			if not creator.menu_is_open():
				creator.toggle_menu()
		"menu_close":
			if creator.menu_is_open():
				creator.toggle_menu()
		"save":
			creator._lesson.note_saved()
		_:
			pass
	_advance(creator)


func _hold_move(creator: CreatorMode, step: Vector3, seconds: float) -> void:
	creator._camera.global_position += step
	creator._lesson.tick(creator, seconds)


func _hold_look(creator: CreatorMode, seconds: float) -> void:
	creator._camera.yaw += 25.0
	creator._lesson.tick(creator, seconds)


func _nudge_turn(creator: CreatorMode) -> void:
	for _i in CreatorLesson.NEED_NUDGE:
		creator._place.yaw += 45.0
		creator._lesson.tick(creator, 0.0)


func _nudge_grow(creator: CreatorMode) -> void:
	for _i in CreatorLesson.NEED_NUDGE:
		creator._group.radius += GroupTool.RADIUS_STEP
		creator._lesson.tick(creator, 0.0)


func _cycle(creator: CreatorMode, fairway: bool) -> void:
	for _i in CreatorLesson.NEED_CYCLE:
		if fairway:
			creator._fairway.step_pick(1)
		else:
			creator._place.picked += 1
		creator._lesson.tick(creator, 0.0)


func _append_pieces(creator: CreatorMode, count: int) -> void:
	for _i in count:
		creator.hole.append_piece(FairwayPiece.index_of("straight"))
	creator._lesson.tick(creator, 0.0)


func _drop_kinds(creator: CreatorMode, paths: Array) -> void:
	for path in paths:
		creator.hole.add_placement(String(path), Vector3(0.0, 0.0, -20.0))
	creator._lesson.tick(creator, 0.0)


func _spawn_count(creator: CreatorMode) -> int:
	var n := 0
	for entry in creator.hole.placements:
		if CustomHole.is_spawn(String(entry[CustomHole.PATH])):
			n += 1
	return n


func _give_counted_spawn(creator: CreatorMode) -> void:
	for entry in creator.hole.placements:
		if CustomHole.is_spawn(String(entry[CustomHole.PATH])):
			entry[CustomHole.COUNTS] = {
				"walker": 1, "runner": 1, "brute": 1, "gunner": 1
			}
			return
	creator.hole.add_placement(CustomHole.SPAWN, Vector3.ZERO)
	creator.hole.placements[creator.hole.placements.size() - 1][CustomHole.COUNTS] = {
		"walker": 1, "runner": 1, "brute": 1, "gunner": 1
	}


func _path_for(step: String) -> String:
	match step:
		"place_prop":
			return "res://scenes/course/props/rock.tscn"
		"place_weapon":
			return CreatorLesson.ROCKET
		"place_cart":
			return CreatorLesson.CART
		_:
			return "res://assets/obstacles/cube_large.glb"


func _advance(creator: CreatorMode) -> void:
	creator._lesson.tick(creator, 0.0)
	if creator._lesson.praising():
		creator._lesson.continue_tip(creator)
