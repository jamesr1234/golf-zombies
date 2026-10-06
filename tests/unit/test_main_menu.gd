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


func test_analog_events_do_not_skip_modes() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	# A flick used to fire move() once per JoypadMotion on that frame.
	for _i in 6:
		menu._unhandled_input(_stick_event(1.0))
	assert_eq(menu.mode_index, 0)


func test_one_key_press_moves_one_row() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	menu._unhandled_input(_key_event(KEY_DOWN))
	assert_eq(menu.mode_index, 1)
	menu._unhandled_input(_key_event(KEY_DOWN, true))
	assert_eq(menu.mode_index, 1, "held-key echo must not skip")
	menu._unhandled_input(_key_event(KEY_UP))
	assert_eq(menu.mode_index, 0)


func test_a_held_stick_steps_once_then_waits() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	menu._apply_pad({}, Vector2i(0, 1))
	assert_eq(menu.mode_index, 1)
	menu._apply_pad({}, Vector2i.ZERO)
	assert_eq(menu.mode_index, 1)
	menu._apply_pad({"swap_weapon": true}, Vector2i.ZERO)
	assert_eq(menu.mode_index, 2)


func test_pad_confirm_does_not_skip_difficulty() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_B
	button.pressed = true
	menu._unhandled_input(button)
	menu._unhandled_input(button)
	assert_eq(menu.step, MainMenu.Step.MODE, "Circle events must not confirm from _unhandled_input")
	menu._apply_pad({"interact": true}, Vector2i.ZERO)
	assert_eq(menu.step, MainMenu.Step.DIFFICULTY)
	menu._apply_pad({}, Vector2i.ZERO)
	assert_eq(menu.step, MainMenu.Step.DIFFICULTY)
	assert_false(menu.started, "one Circle must not also start the round")


func _key_event(keycode: Key, echo := false) -> InputEventKey:
	var key := InputEventKey.new()
	key.pressed = true
	key.echo = echo
	key.physical_keycode = keycode
	return key


func _stick_event(value: float) -> InputEventJoypadMotion:
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_Y
	motion.axis_value = value
	return motion


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
	assert_eq(menu._blurb.get_parent().custom_minimum_size.y, MainMenu.BLURB_HEIGHT)
	assert_eq(menu._options.custom_minimum_size.y, menu._options_height(MainMenu.MODE_COPY.size()))


func test_the_panel_keeps_its_size_while_the_blurb_changes() -> void:
	var menu: MainMenu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(2)
	var size := menu._panel.size
	assert_gt(menu._blurb.get_parent().size.y, 32.0, "two lines of copy have a reserved slot")
	for _i in MainMenu.MODE_COPY.size():
		menu.move(1)
		await wait_frames(1)
		assert_eq(menu._panel.size, size, "hovering a mode must not resize the box")
	menu.confirm()
	await wait_frames(1)
	assert_eq(menu._panel.size, size, "the difficulty step uses the same box")
	for _i in GameSettings.LABELS.size():
		menu.move(1)
		await wait_frames(1)
		assert_eq(menu._panel.size, size, "hovering a difficulty must not resize the box")


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
