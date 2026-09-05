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
	assert_eq(menu.mode_index, 3)
	menu.move(1)
	assert_eq(menu.mode_index, 4)
	menu.move(1)
	assert_eq(menu.mode_index, 0)


func test_online_opens_from_the_title() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	menu.mode_index = 2
	menu.apply_settings()
	assert_true(GameSettings.is_online())
	assert_false(GameSettings.is_coop_vs())


func test_coop_multiplayer_vs_opens_from_the_title() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	menu.mode_index = 3
	menu.apply_settings()
	assert_true(GameSettings.is_online())
	assert_true(GameSettings.is_coop_vs())
	assert_eq(GameSettings.online_max_players(), 16)


func test_title_shows_every_mode() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(2)
	assert_eq(menu._buttons.size(), 5)
	assert_eq(menu._buttons[0].text, "1 PLAYER")
	assert_eq(menu._buttons[1].text, "2 PLAYER")
	assert_eq(menu._buttons[2].text, "ONLINE VS")
	assert_eq(menu._buttons[3].text, "COOP VS")
	assert_eq(menu._buttons[4].text, "COURSE CREATOR")
	assert_eq(menu._heading.text, "SELECT MODE")
	var last := menu._buttons[menu._buttons.size() - 1]
	assert_true(last.visible)
	assert_gt(last.size.y, 16.0)
	var last_bottom := last.global_position.y + last.size.y
	var panel_bottom := menu._panel.global_position.y + menu._panel.size.y
	assert_lte(last_bottom, panel_bottom + 1.0, "the last mode must sit inside the panel")


## Building a hole is not a difficulty pick, so it skips that step the same way
## the online modes skip it to reach the lobby.
func test_my_holes_skips_the_difficulty_step() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	menu.mode_index = MainMenu.FIRST_CREATOR
	menu.started = true
	menu.confirm()
	assert_eq(menu.step, MainMenu.Step.MODE)
