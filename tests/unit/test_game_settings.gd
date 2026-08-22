extends GutTest
## Session picks survive a scene reload because they live on static vars.


func after_each() -> void:
	GameSettings.reset()
	InputActions.register_for_mode(GameSettings.Mode.SOLO)


func test_defaults_to_solo_medium() -> void:
	GameSettings.reset()
	assert_true(GameSettings.is_solo())
	assert_eq(GameSettings.difficulty, GameSettings.Kind.MEDIUM)
	assert_eq(GameSettings.hole_seconds(), GameState.HOLE_SECONDS)
	assert_eq(GameSettings.difficulty_label(), "Medium")


func test_online_vs_is_not_solo() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	assert_true(GameSettings.is_online())
	assert_false(GameSettings.is_solo())
	GameSettings.mode = GameSettings.Mode.COOP
	GameSettings.difficulty = GameSettings.Kind.HARD
	assert_false(GameSettings.is_solo())
	assert_eq(GameSettings.hole_seconds(), 90.0)
	assert_eq(GameSettings.difficulty_label(), "Hard")


func test_solo_maps_the_pad_onto_any_device() -> void:
	InputActions.register_for_mode(GameSettings.Mode.SOLO)
	assert_eq(_joy_devices("p2_jump"), PackedInt32Array([-1]))
	assert_eq(_joy_devices("p1_jump").size(), 0, "the keyboard seat has no pad in solo")


func test_coop_uses_the_pad_and_the_keyboard() -> void:
	GameSettings.mode = GameSettings.Mode.COOP
	InputActions.register_for_mode(GameSettings.Mode.COOP)
	assert_eq(_joy_devices("p1_jump"), PackedInt32Array([-1]))
	assert_eq(_joy_devices("p2_jump").size(), 0, "the keyboard seat has no pad")
	assert_true(_has_key("p2_interact", KEY_E), "player two is on the keyboard")
	assert_false(_has_key("p1_interact", KEY_E), "player one is the controller")
	var pad := PlayerInput.new("p1", false)
	var keys := PlayerInput.new("p2", true)
	assert_eq(pad.hint("interact"), "Circle")
	assert_eq(keys.hint("interact"), "E")


func test_coop_clears_the_solo_pad_off_move_and_look() -> void:
	InputActions.register_for_mode(GameSettings.Mode.SOLO)
	assert_gt(_joy_devices("p2_move_left").size(), 0)
	assert_gt(_joy_devices("p2_look_left").size(), 0)
	GameSettings.mode = GameSettings.Mode.COOP
	InputActions.register_for_mode(GameSettings.Mode.COOP)
	assert_eq(_joy_devices("p2_move_left").size(), 0, "WASD must not share the stick")
	assert_eq(_joy_devices("p2_look_left").size(), 0, "the trackpad seat has no right stick")
	assert_eq(_joy_devices("p2_look_right").size(), 0)
	assert_gt(_joy_devices("p1_move_left").size(), 0)
	assert_gt(_joy_devices("p1_look_left").size(), 0)
	assert_false(_has_key("p1_move_left", KEY_A), "player one does not walk with WASD")
	assert_true(_has_key("p2_move_left", KEY_A))


func test_coop_look_stays_on_its_own_device() -> void:
	GameSettings.mode = GameSettings.Mode.COOP
	InputActions.register_for_mode(GameSettings.Mode.COOP)
	var pad := _coop_body("p1")
	var keys := _coop_body("p2")
	var pad_in := CpuInput.new("p1", false)
	var key_in := CpuInput.new("p2", true)
	pad.input = pad_in
	keys.input = key_in
	pad_in.look = Vector2.RIGHT
	key_in.look = Vector2.RIGHT
	var pad_yaw := pad._yaw
	var key_yaw := keys._yaw
	pad._physics_process(0.2)
	keys._physics_process(0.2)
	assert_gt(absf(pad._yaw - pad_yaw), 1.0, "the controller turns player one")
	assert_almost_eq(keys._yaw, key_yaw, 0.01, "the stick must not turn player two")
	pad_in.look = Vector2.ZERO
	key_in.look = Vector2.ZERO
	pad_yaw = pad._yaw
	key_yaw = keys._yaw
	pad.add_mouse_look(Vector2(400.0, 0.0))
	keys.add_mouse_look(Vector2(400.0, 0.0))
	pad._physics_process(0.016)
	keys._physics_process(0.016)
	assert_almost_eq(pad._yaw, pad_yaw, 0.01, "the trackpad must not turn player one")
	assert_gt(absf(keys._yaw - key_yaw), 1.0, "the trackpad turns player two")


func _coop_body(prefix: String) -> Player:
	var player: Player = load("res://scenes/players/player.tscn").instantiate()
	player.input_prefix = prefix
	add_child_autofree(player)
	return player


func _joy_devices(action: String) -> PackedInt32Array:
	var devices := PackedInt32Array()
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			devices.append(event.device)
	return devices


func _has_key(action: String, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
			return true
	return false
