extends GutTest
## Hole cards sit in the hands. The board is on the felt and on the HUD.


func test_the_blender_faces_are_in_the_project() -> void:
	assert_true(FileAccess.file_exists("res://assets/cards/AH.png"))
	assert_true(FileAccess.file_exists("res://assets/cards/AS.png"))
	assert_true(FileAccess.file_exists("res://assets/cards/back.png"))


func test_an_ace_wears_a_center_pip_and_a_two_does_not() -> void:
	var ace := PokerCardArt.image(38)
	var two := PokerCardArt.image(26)
	var mid := Vector2i(PokerCardArt.W / 2, PokerCardArt.H / 2)
	var ace_px := ace.get_pixelv(mid)
	var two_px := two.get_pixelv(mid)
	assert_gt(ace_px.r + ace_px.g + ace_px.b, two_px.r + two_px.g + two_px.b + 0.2)
	assert_gt(ace_px.r, 0.35)
	assert_true(two_px.r + two_px.g + two_px.b < 0.7, "two of hearts keeps the middle empty")


func test_spades_glow_cool_and_diamonds_glow_warm() -> void:
	var mid := Vector2i(PokerCardArt.W / 2, PokerCardArt.H / 2)
	var spade := PokerCardArt.image(51).get_pixelv(mid)
	var diamond := PokerCardArt.image(25).get_pixelv(mid)
	assert_gt(spade.b, diamond.b)
	assert_gt(diamond.r, spade.r)


func test_the_back_is_a_patterned_stock_not_a_blank() -> void:
	var back := PokerCardArt.back().get_image()
	var cool := 0
	var warm := 0
	for y in range(40, PokerCardArt.H - 40, 4):
		for x in range(40, PokerCardArt.W - 40, 4):
			var px := back.get_pixel(x, y)
			if px.a < 0.4:
				continue
			if px.b > px.r + 0.08:
				cool += 1
			elif px.r > px.b + 0.08:
				warm += 1
	assert_gt(cool, 20)
	assert_gt(warm, 20)


func test_board_faces_point_up() -> void:
	var host := PokerCards.new()
	add_child_autofree(host)
	var hand := PokerHand.new()
	hand.hole = [[], []]
	hand.board.append(38)
	host.refresh(hand, [], [null, null], PokerTable.Phase.PLAYING)
	assert_eq(host.get_child_count(), 1)
	var card := host.get_child(0) as Node3D
	assert_not_null(card.get_node("Face"))
	assert_not_null(card.get_node("Back"))
	var face_dir := -card.global_transform.basis.z
	assert_gt(face_dir.dot(Vector3.UP), 0.9, "the painted face looks up off the felt")
	assert_almost_eq(card.scale.x, PokerCards.BOARD_SCALE, 0.01)


func test_the_board_hud_shows_the_flop_on_the_right() -> void:
	var hud: Hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child_autofree(hud)
	await wait_physics_frames(1)
	var board: PokerBoardHud = hud.board_hud
	assert_not_null(board)
	assert_eq(board.anchor_left, 1.0)
	assert_eq(board.anchor_right, 1.0)
	assert_lt(board.offset_right, -10.0)
	assert_eq(PokerBoardHud.CARD, Vector2(160, 224))
	assert_lt(board.offset_top, -100.0)
	board.show_ids([38, 26, 0])
	assert_true(board.visible)
	assert_eq(board.card_count(), 3)
	var flop := board.get_child(0) as HBoxContainer
	assert_eq((flop.get_child(0) as Control).custom_minimum_size, PokerBoardHud.CARD)
	board.show_ids([])
	assert_false(board.visible)
	assert_eq(board.get_child_count(), 0)


func test_the_board_hud_shows_their_hand_at_showdown() -> void:
	var hud: Hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child_autofree(hud)
	await wait_physics_frames(1)
	var board: PokerBoardHud = hud.board_hud
	board.show_rows([38, 26, 0], [51, 25])
	assert_true(board.visible)
	assert_eq(board.card_count(), 5)
	assert_eq(board.get_child_count(), 3)
	assert_eq((board.get_child(1) as Label).text, "THEIR HAND")


func test_the_result_dialogue_has_yes_and_no_buttons() -> void:
	var hud: Hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child_autofree(hud)
	await wait_physics_frames(1)
	var result: PokerResultHud = hud.poker_result
	assert_not_null(result)
	var panel := result.get_node("Panel") as Control
	assert_lt(panel.anchor_left, 0.6)
	assert_gt(panel.anchor_right, 0.4)
	assert_not_null(result.yes_btn)
	assert_not_null(result.no_btn)
	assert_eq(result.yes_btn.text, "YES")
	assert_eq(result.no_btn.text, "NO")
	assert_gt(result.z_index, 0, "the prompt has to sit above the board cards")
