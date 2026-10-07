extends GutTest
## Practice vs ranked in the web demo, and how leaderboard replies read.


func after_each() -> void:
	DemoRun.begin(false)
	DemoRun.code = ""


func test_bottle_codes_match_the_server_alphabet() -> void:
	assert_true(DemoRun.valid_code("ABCDEFGH23"))
	assert_false(DemoRun.valid_code("ABCDEFGH2"), "too short")
	assert_false(DemoRun.valid_code("ABCDEFGH20"), "0 is never handed out")
	assert_false(DemoRun.valid_code("abcdefgh23"), "codes are read upper case")
	assert_false(DemoRun.valid_code(""))


func test_a_ranked_ticket_is_handed_over_once() -> void:
	DemoRun.begin(true, "T1")
	assert_true(DemoRun.ranked)
	assert_eq(DemoRun.take_ticket(), "T1")
	assert_eq(DemoRun.take_ticket(), "", "a score can't be sent twice")


func test_practice_carries_no_ticket() -> void:
	DemoRun.begin(true, "T1")
	DemoRun.begin(false)
	assert_false(DemoRun.ranked)
	assert_eq(DemoRun.take_ticket(), "")


func test_tries_copy() -> void:
	assert_eq(DemoRun.tries_copy({"tries_left": 2, "tries": 3}), "2 of 3 ranked tries left")
	assert_string_contains(DemoRun.tries_copy({"tries_left": 0, "tries": 3}), "Practice is still free")


func test_best_copy_only_when_there_is_a_best() -> void:
	assert_eq(DemoRun.best_copy({"best": null}), "")
	assert_eq(DemoRun.best_copy({"best": {"strokes": 3, "seconds": 41.25}}), "Your best: 3 strokes in 41.2s")


func test_rank_copy() -> void:
	assert_eq(DemoEnd.rank_copy({"rank": 2, "seconds": 50.0}), "Leaderboard rank #2 (50.0s)")
	assert_string_contains(DemoEnd.rank_copy({"rank": null, "seconds": 9.0}), "No score")


func test_board_copy_lists_in_order() -> void:
	var text := DemoEnd.board_copy([
		{"nickname": "Ace", "strokes": 2, "seconds": 30.0},
		{"nickname": "Bo", "strokes": 3, "seconds": 20.0},
	])
	assert_string_contains(text, "1. Ace  2 strokes  30.0s")
	assert_string_contains(text, "2. Bo  3 strokes  20.0s")
	assert_string_contains(DemoEnd.board_copy([]), "Be the first")


func test_holed_needs_a_win_with_strokes() -> void:
	DemoEnd.record(true, 3, 4)
	assert_true(DemoEnd.holed())
	DemoEnd.record(false, 3, 4)
	assert_false(DemoEnd.holed())
	DemoEnd.record(true, -1, 4)
	assert_false(DemoEnd.holed())


func test_reply_reads_success_and_server_errors() -> void:
	var good := LeaderboardApi.reply(HTTPRequest.RESULT_SUCCESS, 200, '{"tries_left": 3}')
	assert_true(good.ok)
	assert_eq(int(good.data.tries_left), 3)
	var bad := LeaderboardApi.reply(HTTPRequest.RESULT_SUCCESS, 400, '{"error": "no tries left"}')
	assert_false(bad.ok)
	assert_eq(bad.error, "no tries left")


func test_reply_survives_no_network_and_junk() -> void:
	var offline := LeaderboardApi.reply(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	assert_false(offline.ok)
	assert_string_contains(offline.error, "Can't reach")
	var junk := LeaderboardApi.reply(HTTPRequest.RESULT_SUCCESS, 502, "<html>bad gateway</html>")
	assert_false(junk.ok)
	assert_eq(junk.data, {})


func test_off_the_web_the_api_uses_the_local_server() -> void:
	if OS.get_environment("LEADERBOARD_URL").is_empty():
		assert_eq(LeaderboardApi.base_url(), LeaderboardApi.DEV_URL)
	else:
		assert_eq(LeaderboardApi.base_url(), OS.get_environment("LEADERBOARD_URL"))
