extends GutTest
## Title screen writes the session picks. It does not load the course here.

const MENU := preload("res://scenes/ui/main_menu.tscn")
const Music := preload("res://scripts/fx/music.gd")


func after_each() -> void:
	GameSettings.reset()
	Music.stop()


func test_confirming_one_player_hard_writes_settings() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	assert_eq(menu.step, MainMenu.Step.MODE)
	menu.mode_index = 0
	menu.confirm()
	assert_eq(menu.step, MainMenu.Step.DIFFICULTY)
	menu.difficulty_index = GameSettings.Kind.HARD
	menu.apply_settings()
	assert_true(GameSettings.is_solo())
	assert_eq(GameSettings.difficulty, GameSettings.Kind.HARD)
	assert_eq(GameSettings.hole_seconds(), 90.0)


func test_two_player_impossible_is_a_coop_run() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	menu.mode_index = 1
	menu.confirm()
	menu.difficulty_index = GameSettings.Kind.IMPOSSIBLE
	menu.apply_settings()
	assert_false(GameSettings.is_solo())
	assert_eq(GameSettings.difficulty, GameSettings.Kind.IMPOSSIBLE)


func test_back_returns_to_the_player_count() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	menu.confirm()
	assert_eq(menu.step, MainMenu.Step.DIFFICULTY)
	menu.back()
	assert_eq(menu.step, MainMenu.Step.MODE)


func test_stick_or_wasd_cycles_the_highlighted_mode() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	assert_eq(menu.mode_index, 0)
	menu.move(1)
	assert_eq(menu.mode_index, 1)
	menu.move(1)
	assert_eq(menu.mode_index, 2)
	menu.move(1)
	assert_eq(menu.mode_index, 0)


func test_online_opens_from_the_title() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	menu.mode_index = 2
	menu.apply_settings()
	assert_true(GameSettings.is_online())
