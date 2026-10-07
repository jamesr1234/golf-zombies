extends GutTest
## The web demo: the bundled hole has to load and play from res:// alone, and
## the demo round has to drop the CPU partner before the world is ready.

const SEAT := "Screens/Top/Viewport/World/Players/"


func after_each() -> void:
	GameSettings.reset()


func test_bundled_hole_loads_and_is_playable() -> void:
	var hole := HoleStore.load_bundled(DemoBoot.HOLE)
	assert_not_null(hole)
	assert_true(hole.is_playable())
	assert_gt(hole.par(), 0)


func test_every_bundled_placement_ships_in_res() -> void:
	var hole := HoleStore.load_bundled(DemoBoot.HOLE)
	for entry in hole.placements:
		var path := String(entry[CustomHole.PATH])
		if path.begins_with("res://"):
			assert_true(ResourceLoader.exists(path), path)
		else:
			assert_false(path.begins_with("user://"), "demo hole leans on a user file: %s" % path)


func test_setup_round_is_a_solo_card_of_one() -> void:
	assert_true(DemoBoot.setup_round())
	assert_true(GameSettings.is_solo())
	assert_true(GameSettings.is_custom())
	assert_eq(GameSettings.difficulty, GameSettings.Kind.EASY)


func test_missing_hole_file_fails_quietly() -> void:
	assert_null(HoleStore.load_bundled("res://resources/demo/nope.json"))


func test_demo_round_drops_the_cpu_partner() -> void:
	DemoBoot.setup_round()
	var root := (load(DemoBoot.ROUND) as PackedScene).instantiate() as Splitscreen
	assert_false(root.companion)
	assert_false(root.capture_mouse)
	assert_true(root.leave_on_end)
	root._enter_tree()
	assert_null(root.get_node_or_null(SEAT + "Player1"))
	assert_not_null(root.get_node_or_null(SEAT + "Player2"))
	root.free()


func test_full_game_keeps_the_cpu_partner() -> void:
	GameSettings.mode = GameSettings.Mode.SOLO
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Splitscreen
	assert_true(root.companion)
	assert_eq(root.title_scene, Splitscreen.TITLE)
	root._enter_tree()
	assert_not_null(root.get_node_or_null(SEAT + "Player1"))
	root.free()


func test_end_copy_reads_the_result() -> void:
	DemoEnd.record(true, 4, 4)
	assert_eq(DemoEnd.headline(), "HOLED IN 4")
	assert_string_contains(DemoEnd.detail(), "Right on the number")
	DemoEnd.record(true, 6, 4)
	assert_string_contains(DemoEnd.detail(), "+2")
	DemoEnd.record(false, -1, 4)
	assert_eq(DemoEnd.headline(), "THE ZOMBIES GOT YOU")
