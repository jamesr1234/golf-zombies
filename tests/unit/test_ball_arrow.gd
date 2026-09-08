extends GutTest
## The HUD chevron shows for your ball when it is off camera or behind scenery.

const PLAYER_SCENE := preload("res://scenes/players/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")


func test_an_on_screen_lie_hides_the_arrow() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(800, 600))
	assert_true(BallArrow.on_screen(rect, Vector2(400, 300), false))
	assert_false(BallArrow.on_screen(rect, Vector2(400, 300), true), "behind the camera")
	assert_false(BallArrow.on_screen(rect, Vector2(-40, 300), false))


func test_the_edge_point_stays_in_the_margin() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(800, 600))
	var right := BallArrow.edge_point(rect, Vector2.RIGHT, BallArrow.MARGIN)
	var up := BallArrow.edge_point(rect, Vector2.UP, BallArrow.MARGIN)
	assert_almost_eq(right.x, rect.size.x - BallArrow.MARGIN, 0.01)
	assert_almost_eq(right.y, rect.size.y * 0.5, 0.01)
	assert_almost_eq(up.x, rect.size.x * 0.5, 0.01)
	assert_almost_eq(up.y, BallArrow.MARGIN, 0.01)
	assert_gt(right.x, BallArrow.MARGIN)
	assert_lt(right.x, rect.size.x)
	assert_gt(up.y, 0.0)
	assert_lt(up.y, rect.size.y - BallArrow.MARGIN)


func test_a_ball_to_the_right_aims_the_chevron_right() -> void:
	var dir := BallArrow.screen_dir(Vector3(4.0, 0.0, -8.0))
	assert_almost_eq(dir.x, 1.0, 0.001)
	assert_almost_eq(dir.y, 0.0, 0.001)


func test_a_ball_behind_the_camera_still_has_a_screen_dir() -> void:
	var dir := BallArrow.screen_dir(Vector3(-3.0, 0.0, 6.0))
	assert_almost_eq(dir.x, -1.0, 0.001)


func test_golfing_or_the_map_hides_the_arrow() -> void:
	var player := _player()
	var ball := GolfBall.new()
	add_child_autofree(ball)
	assert_true(BallArrow.allowed(player, ball))
	player.state = Player.State.GOLFING
	assert_false(BallArrow.allowed(player, ball), "hide while addressing")
	player.state = Player.State.NORMAL
	var pad := CpuInput.new("p2", false)
	player.input = pad
	pad.hold("map")
	assert_false(BallArrow.allowed(player, ball), "hide while the map is up")


func test_shopping_talking_or_carrying_hides_the_arrow() -> void:
	var player := _player()
	var ball := GolfBall.new()
	add_child_autofree(ball)
	player.shopping = true
	assert_false(BallArrow.allowed(player, ball))
	player.shopping = false
	player.talking = true
	assert_false(BallArrow.allowed(player, ball))
	player.talking = false
	ball.pick_up(player)
	assert_false(BallArrow.allowed(player, ball))


func test_the_hud_paints_the_arrow_in_the_player_colour() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	var player := _player()
	var ball := GolfBall.new()
	var cam := Camera3D.new()
	add_child_autofree(hud)
	add_child_autofree(ball)
	add_child_autofree(cam)
	cam.current = true
	cam.position = Vector3(0.0, 2.0, 8.0)
	cam.look_at(Vector3.ZERO)
	ball.global_position = Vector3.ZERO
	player.body_color = Palette.MAGENTA
	player.golf = GolfController.new()
	add_child_autofree(player.golf)
	player.golf.ball = ball
	hud.player = player
	hud.flow = autofree(MatchFlow.new())
	hud.flow.ball = ball
	hud._update_arrow()
	assert_eq(hud.ball_arrow.color, Palette.MAGENTA)
	assert_false(hud.ball_arrow.visible, "the lie is in frame")


func test_the_hud_shows_the_arrow_when_the_ball_is_off_camera() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	var player := _player()
	var ball := GolfBall.new()
	var cam := Camera3D.new()
	add_child_autofree(hud)
	add_child_autofree(ball)
	add_child_autofree(cam)
	cam.current = true
	cam.position = Vector3(0.0, 2.0, 8.0)
	cam.look_at(Vector3.ZERO)
	ball.global_position = Vector3(200.0, 0.0, 0.0)
	player.golf = GolfController.new()
	add_child_autofree(player.golf)
	player.golf.ball = ball
	hud.player = player
	hud.flow = autofree(MatchFlow.new())
	hud.flow.ball = ball
	hud._update_arrow()
	assert_true(hud.ball_arrow.visible)
	assert_true(hud.ball_arrow.tracking)


func test_a_wall_between_the_camera_and_the_ball_counts_as_blocked() -> void:
	var cam := Camera3D.new()
	var ball := GolfBall.new()
	add_child_autofree(cam)
	add_child_autofree(ball)
	cam.position = Vector3(0.0, 2.0, 8.0)
	cam.look_at(Vector3.ZERO)
	ball.global_position = Vector3.ZERO
	_wall(Vector3(0.0, 2.0, 4.0))
	await wait_physics_frames(2)
	assert_true(BallArrow.occluded(
		cam.get_world_3d(), cam.global_position, ball.global_position, [ball.get_rid()]
	))
	assert_false(BallArrow.occluded(
		cam.get_world_3d(), cam.global_position, Vector3(0.0, 2.0, 6.0), [ball.get_rid()]
	), "a clear look stays clear")


func test_the_hud_keeps_the_arrow_when_a_wall_hides_the_ball() -> void:
	var player := _player()
	var ball := GolfBall.new()
	var cam := Camera3D.new()
	add_child_autofree(ball)
	add_child_autofree(cam)
	cam.current = true
	cam.position = Vector3(0.0, 2.0, 8.0)
	cam.look_at(Vector3.ZERO)
	ball.global_position = Vector3.ZERO
	_wall(Vector3(0.0, 2.0, 4.0))
	player.golf = GolfController.new()
	add_child_autofree(player.golf)
	player.golf.ball = ball
	await wait_physics_frames(2)
	var hud: Hud = HUD_SCENE.instantiate()
	add_child_autofree(hud)
	hud.set_process(false)
	hud.player = player
	hud.flow = autofree(MatchFlow.new())
	hud.flow.ball = ball
	hud._update_arrow()
	assert_true(hud.ball_arrow.visible, "a tree in the way still keeps the waypoint")


func test_the_hud_hides_the_arrow_while_golfing() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	var player := _player()
	var ball := GolfBall.new()
	add_child_autofree(hud)
	add_child_autofree(ball)
	player.state = Player.State.GOLFING
	player.golf = GolfController.new()
	add_child_autofree(player.golf)
	player.golf.ball = ball
	hud.player = player
	hud.flow = autofree(MatchFlow.new())
	hud.flow.ball = ball
	hud._update_arrow()
	assert_false(hud.ball_arrow.visible)


func _wall(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.PROP
	body.collision_mask = 0
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, 1.0)
	node.shape = box
	body.add_child(node)
	add_child_autofree(body)
	body.global_position = at
	return body


func _player() -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var pad := CpuInput.new("p2", false)
	player.input = pad
	return player
