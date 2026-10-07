extends GutTest
## Touch stick and button math for the web demo.


func after_each() -> void:
	PlayerInput.touch = false
	PlayerInput.touch_stick_held = false
	PlayerInput.touch_move = Vector2.ZERO
	PlayerInput.touch_sprint = false
	PlayerInput.touch_taps.clear()


func test_idle_stick_is_zero() -> void:
	var stick := TouchStick.new()
	assert_eq(stick.vector(), Vector2.ZERO)
	assert_false(stick.sprinting())


func test_small_wobble_stays_in_the_deadzone() -> void:
	var stick := TouchStick.new()
	stick.grab(0, Vector2(100, 100))
	stick.drag(Vector2(105, 100))
	assert_eq(stick.vector(), Vector2.ZERO)


func test_drag_reports_direction_and_strength() -> void:
	var stick := TouchStick.new()
	stick.grab(0, Vector2(100, 100))
	stick.drag(Vector2(100, 100 - TouchStick.RADIUS * 0.5))
	assert_almost_eq(stick.vector().y, -0.5, 0.001)
	assert_almost_eq(stick.vector().x, 0.0, 0.001)
	assert_false(stick.sprinting())


func test_drag_past_the_rim_clamps_and_sprints() -> void:
	var stick := TouchStick.new()
	stick.grab(0, Vector2(100, 100))
	stick.drag(Vector2(100 + TouchStick.RADIUS * 3.0, 100))
	assert_almost_eq(stick.vector().length(), 1.0, 0.001)
	assert_true(stick.sprinting())


func test_a_phone_finger_with_a_negative_id_still_holds_the_stick() -> void:
	var stick := TouchStick.new()
	stick.grab(-903363112, Vector2(100, 100))
	stick.drag(Vector2(100, 100 - TouchStick.RADIUS))
	assert_true(stick.is_held())
	assert_almost_eq(stick.vector().y, -1.0, 0.001)
	var button := TouchButton.new("JUMP", PackedStringArray(), Vector2.ZERO)
	button.press(-903363110)
	assert_true(button.is_held())
	button.release()
	assert_false(button.is_held())


func test_touch_move_reaches_the_player_while_the_stick_is_held() -> void:
	var input := PlayerInput.new("p2", true, PackedStringArray(["p1"]))
	PlayerInput.touch = true
	PlayerInput.touch_stick_held = true
	PlayerInput.touch_move = Vector2(0, -1)
	PlayerInput.touch_sprint = true
	assert_eq(input.move_vector(), Vector2(0, -1))
	assert_true(input.pressed("sprint"))
	PlayerInput.touch_stick_held = false
	PlayerInput.touch_move = Vector2.ZERO
	PlayerInput.touch_sprint = false
	PlayerInput.touch_taps.clear()
	PlayerInput.touch = false


func test_a_touch_tap_counts_once() -> void:
	var input := PlayerInput.new("p1", true)
	PlayerInput.touch = true
	PlayerInput.note_tap("jump")
	PlayerInput.note_tap("swing")
	assert_true(input.just_pressed("jump"))
	assert_false(input.just_pressed("jump"))
	assert_true(input.just_pressed("swing"))


func test_release_recenters() -> void:
	var stick := TouchStick.new()
	stick.grab(2, Vector2(50, 50))
	stick.drag(Vector2(120, 50))
	stick.release()
	assert_false(stick.is_held())
	assert_eq(stick.vector(), Vector2.ZERO)


func test_button_sits_off_the_bottom_right_corner() -> void:
	var button := TouchButton.new("JUMP", ["p1_jump"], Vector2(0.1, 0.2), 50.0)
	button.place(Vector2(1000, 500))
	assert_eq(button.center, Vector2(950, 400))
	assert_true(button.contains(Vector2(960, 410)))
	assert_false(button.contains(Vector2(500, 250)))
	button.visible = false
	assert_false(button.contains(button.center))


func test_phone_prompts_name_the_on_screen_buttons() -> void:
	var input := PlayerInput.new("p1", true)
	PlayerInput.touch = true
	assert_eq(input.hint("interact"), "USE")
	assert_eq(input.hint("shoot"), "FIRE")
	assert_eq(input.hint("drop"), "PICK UP")
	assert_eq(input.hint("melee"), "L HAND")
	PlayerInput.touch = false
	assert_string_contains(input.hint("interact"), "E")


func test_every_touch_button_label_is_a_touch_hint() -> void:
	var controls := TouchControls.new()
	var hints: Array = PlayerInput.TOUCH_HINTS.values()
	for button in [controls.fire, controls.jump, controls.reload, controls.action,
			controls.pick_up, controls.left_hand, controls.right_hand, controls.grapple]:
		assert_has(hints, button.label)
	controls.free()


func test_button_holds_and_releases_its_actions() -> void:
	InputActions.register_all()
	var button := TouchButton.new("FIRE", ["p1_shoot", "p1_swing"], Vector2.ZERO)
	button.press(0)
	assert_true(Input.is_action_pressed("p1_shoot"))
	assert_true(Input.is_action_pressed("p1_swing"))
	button.release()
	assert_false(Input.is_action_pressed("p1_shoot"))
	assert_false(Input.is_action_pressed("p1_swing"))
