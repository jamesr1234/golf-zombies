extends GutTest
## The Computer 2 CPU has to press the same actions a human would.

var _ghost: InputGhost
var _pad: PlayerInput


func before_each() -> void:
	GameSettings.mode = GameSettings.Mode.ONLINE_VS
	InputActions.register_for_mode(GameSettings.Mode.ONLINE_VS)
	_ghost = InputGhost.new()
	_pad = PlayerInput.new("p1", true)


func after_each() -> void:
	if _ghost != null:
		_ghost.release_all()
	GameSettings.mode = GameSettings.Mode.SOLO


func test_a_tap_reads_as_just_pressed() -> void:
	_ghost.tap("interact")
	_ghost.apply()
	assert_true(_pad.just_pressed("interact"))
	assert_true(_pad.pressed("interact"))


func test_move_strength_feeds_the_stick() -> void:
	_ghost.move = Vector2(0.0, -0.8)
	_ghost.apply()
	var stick := _pad.move_vector()
	assert_lt(stick.y, -0.5, "forward is negative stick Y")
	assert_almost_eq(stick.x, 0.0, 0.15)


func test_release_all_clears_holds() -> void:
	_ghost.hold("shoot")
	_ghost.apply()
	assert_true(_pad.pressed("shoot"))
	_ghost.release_all()
	assert_false(_pad.pressed("shoot"))
	assert_false(_pad.pressed("interact"))


func test_pause_and_map_stay_untouched() -> void:
	_ghost.tap("pause")
	_ghost.hold("map")
	_ghost.apply()
	assert_false(_ghost.wants("pause"))
	assert_false(_ghost.wants("map"))
	assert_false(_pad.pressed("pause"))
	assert_false(_pad.pressed("map"))
