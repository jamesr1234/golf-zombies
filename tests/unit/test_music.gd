extends GutTest
## Lounge on the title screen, Gravity on the hole, elevator in the clubhouse.

const Music := preload("res://scripts/fx/music.gd")


func after_each() -> void:
	Music.stop()


func test_all_three_beds_are_in_the_project() -> void:
	assert_true(ResourceLoader.exists(Music.LEVEL_PATH))
	assert_true(ResourceLoader.exists(Music.LOUNGE_PATH))
	assert_true(ResourceLoader.exists(Music.CLUBHOUSE_PATH))
	assert_true(load(Music.LEVEL_PATH) is AudioStreamOggVorbis)
	assert_true(load(Music.LOUNGE_PATH) is AudioStreamWAV)
	assert_true(load(Music.CLUBHOUSE_PATH) is AudioStreamMP3)


func test_the_title_screen_starts_the_lounge() -> void:
	var menu: MainMenu = preload("res://scenes/ui/main_menu.tscn").instantiate()
	add_child_autofree(menu)
	await wait_physics_frames(1)
	assert_eq(Music.current, Music.Track.LOUNGE)
	assert_eq(Music.player().stream.resource_path, Music.LOUNGE_PATH)


func test_teeing_off_switches_to_the_level_bed() -> void:
	var node := Music.play_lounge()
	assert_eq(Music.current, Music.Track.LOUNGE)
	var same := Music.play_level()
	assert_eq(same, node, "one player swaps beds instead of stacking")
	assert_eq(Music.current, Music.Track.LEVEL)
	assert_eq(same.stream.resource_path, Music.LEVEL_PATH)


func test_entering_the_clubhouse_crossfades_off_the_hole_bed() -> void:
	Music.play_level()
	var hole := Music.player()
	var club := Music.enter_clubhouse()
	assert_eq(club, hole, "the incoming bed keeps the same player")
	assert_eq(Music.current, Music.Track.CLUBHOUSE)
	assert_eq(club.stream.resource_path, Music.CLUBHOUSE_PATH)
	var mp3 := club.stream as AudioStreamMP3
	assert_true(mp3.loop)
	var outgoing := Music.fader()
	assert_not_null(outgoing, "the hole bed keeps playing while it drains")
	assert_eq(outgoing.stream.resource_path, Music.LEVEL_PATH)
	assert_true(outgoing.playing)
	assert_true(club.playing)
	assert_lt(club.volume_linear, outgoing.volume_linear, "elevator starts under the hole music")


func test_teeing_off_cuts_the_clubhouse_bed() -> void:
	Music.play_level()
	Music.enter_clubhouse()
	Music.follow_clubhouse()
	var bed := Music.play_level()
	assert_eq(Music.current, Music.Track.LEVEL)
	assert_false(Music.following_clubhouse)
	assert_null(Music.fader(), "the elevator does not linger")
	assert_eq(bed.stream.resource_path, Music.LEVEL_PATH)
	assert_almost_eq(bed.volume_db, float(Music.VOLUME_DB[Music.Track.LEVEL]), 0.05)


func test_walking_away_turns_the_elevator_down() -> void:
	Music.play_clubhouse()
	Music.follow_clubhouse()
	Music.set_listener_distance(0.0)
	var full := Music.player().volume_db
	assert_almost_eq(full, float(Music.VOLUME_DB[Music.Track.CLUBHOUSE]), 0.05)
	var mid := (Music.CLUBHOUSE_NEAR + Music.CLUBHOUSE_FAR) * 0.5
	Music.set_listener_distance(mid)
	assert_lt(Music.player().volume_db, full - 4.0)
	Music.set_listener_distance(Music.CLUBHOUSE_FAR)
	assert_almost_eq(Music.player().volume_db, Music.SILENCE_DB, 0.05)


func test_the_quiet_end_is_the_tee_you_pass_in() -> void:
	Music.play_clubhouse()
	Music.follow_clubhouse(40.0)
	Music.set_listener_distance(Music.CLUBHOUSE_NEAR)
	assert_almost_eq(Music.player().volume_db, float(Music.VOLUME_DB[Music.Track.CLUBHOUSE]), 0.05)
	Music.set_listener_distance(40.0)
	assert_almost_eq(Music.player().volume_db, Music.SILENCE_DB, 0.05)
