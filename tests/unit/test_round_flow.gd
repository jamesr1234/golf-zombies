extends GutTest
## Integration pass over a live world: hole loads, ball can be claimed, a swing
## resolves into a counted stroke, out-of-bounds costs a penalty, and a team wipe
## ends the run. Water is a swim, not a penalty.

const WORLD := preload("res://scenes/world.tscn")

var world: Node3D
var flow: MatchFlow
var golf: GolfController
var ball: GolfBall
var cart: GolfCart
var players: Array[Player] = []


func before_each() -> void:
	GameSettings.reset()
	players = []
	world = WORLD.instantiate()
	add_child_autofree(world)
	flow = world.get_node("MatchFlow") as MatchFlow
	golf = world.get_node("GolfController") as GolfController
	ball = world.get_node("GolfBall") as GolfBall
	cart = world.get_node("GolfCart") as GolfCart
	players.append(world.get_node("Players/Player1") as Player)
	players.append(world.get_node("Players/Player2") as Player)
	flow.starting_hole = 1
	flow.start_in_clubhouse = false
	flow.start_on_cart_path = false
	flow.begin()
	# Most tests are about a hole in progress, so warm-up is called on straight
	# away. The tests below that cover warm-up put the hole back into it.
	flow.start_play()
	# Zombies are only wanted in the test that checks for them.
	flow.spawner.stop()
	flow.spawner.clear_zombies()
	await wait_physics_frames(6)


func test_first_hole_is_built_with_navigation() -> void:
	assert_not_null(flow.hole)
	assert_eq(flow.hole.par, 4)
	var hole_node := flow.hole_root.get_child(0)
	var has_region := false
	for child in hole_node.get_children():
		if child is NavigationRegion3D:
			has_region = true
	assert_true(has_region, "zombies need a navigation region")


func test_the_pin_throws_a_beam_into_the_sky() -> void:
	var beam := flow.hole_root.find_child("PinBeam", true, false) as Node3D
	assert_not_null(beam, "the pin needs a sky marker or long holes are guesswork")
	var at := Vector2(beam.global_position.x, beam.global_position.z)
	var cup := Vector2(flow.hole.cup.x, flow.hole.cup.z)
	assert_almost_eq(at.distance_to(cup), 0.0, 0.4)
	assert_gt(HoleBuilder.BEAM_HEIGHT, 80.0, "short of the sky and it hides behind a hill")
	assert_eq(beam.get_child_count(), 2, "a core and a glow so it reads up close and far away")


func test_ball_starts_on_the_tee_surface() -> void:
	var flat := Vector2(ball.global_position.x, ball.global_position.z)
	assert_almost_eq(flat.distance_to(Vector2(flow.hole.tee.x, flow.hole.tee.z)), 0.0, 0.3)
	assert_eq(ball.current_surface(), Surface.Type.TEE)
	assert_false(ball.is_in_play())


func test_players_start_together_on_the_practice_green() -> void:
	for player in players:
		var to_mat := player.global_position.distance_to(flow.hole.practice_tee)
		assert_between(to_mat, 1.0, 8.0)
		assert_gt(
			player.global_position.distance_to(flow.hole.tee), 12.0,
			"warm up first, then walk to the tee"
		)
	assert_lt(players[0].global_position.distance_to(players[1].global_position), 8.0)


func test_scorecard_starts_clean() -> void:
	assert_eq(flow.score.strokes, 0)
	assert_eq(flow.score.hole_index, 0)
	assert_eq(flow.score.max_strokes(), 6)
	assert_eq(flow.score.money, 0)
	assert_almost_eq(flow.hole_time_left, GameSettings.hole_seconds(), 0.5)


func test_the_ball_is_waiting_to_be_played() -> void:
	assert_true(golf.is_available())
	assert_false(golf.can_claim(players[0]), "the players start too far away to swing")


func test_play_can_open_on_hole_nine() -> void:
	var extra := WORLD.instantiate()
	add_child_autofree(extra)
	var other := extra.get_node("MatchFlow") as MatchFlow
	assert_eq(other.starting_hole, 1)
	other.starting_hole = 9
	other.start_in_clubhouse = false
	other.start_on_cart_path = false
	other.begin()
	await wait_physics_frames(6)
	assert_eq(other.score.hole_index, 8)
	assert_eq(other.hole.index, 8)
	assert_eq(other.hole.par, 4)


func test_playtest_can_open_inside_the_clubhouse() -> void:
	var extra := WORLD.instantiate()
	add_child_autofree(extra)
	var other := extra.get_node("MatchFlow") as MatchFlow
	var who := extra.get_node("Players/Player1") as Player
	other.start_in_clubhouse = true
	other.start_on_cart_path = false
	other.begin()
	await wait_physics_frames(6)
	assert_true(other.in_clubhouse())
	assert_not_null(other.clubhouse)
	assert_true(other.clubhouse.inside(who), "you spawn in the hall, not on the tee")
	assert_eq(other.hole.index, 0)
	assert_lt(
		other.clubhouse.exit_point().distance_to(other.hole.practice_tee),
		other.clubhouse.door_point().distance_to(other.hole.practice_tee),
		"the back door still opens onto the practice green"
	)
	assert_eq(other.get_tree().get_nodes_in_group("clubhouse_posters").size(), 2)
	other.leave_clubhouse()
	await wait_physics_frames(6)
	assert_eq(other.phase, MatchFlow.Phase.PREP)
	assert_true(other.clubhouse.exit_open)


func test_playtest_can_open_on_the_cart_path() -> void:
	var extra := WORLD.instantiate()
	add_child_autofree(extra)
	var other := extra.get_node("MatchFlow") as MatchFlow
	var ride := extra.get_node("GolfCart") as GolfCart
	var who := extra.get_node("Players/Player1") as Player
	var buddy := extra.get_node("Players/Player2") as Player
	other.start_on_cart_path = true
	other.begin()
	await wait_physics_frames(6)
	assert_eq(other.phase, MatchFlow.Phase.TRANSIT)
	assert_not_null(other.cart_path)
	assert_not_null(other.clubhouse)
	assert_false(other.in_clubhouse())
	assert_true(extra.get_node("GolfBall").is_stowed())
	assert_eq(other.score.hole_index, 1, "hole one is already in the books")
	assert_true(ride.is_riding(who), "you start in the cart, not walking to it")
	assert_true(ride.is_riding(buddy))
	assert_eq(ride.driver, who)
	assert_lt(
		ride.global_position.distance_to(other.cart_path.centerline[0]), 16.0,
		"the cart starts at the clubhouse gate"
	)
	assert_gt(extra.get_tree().get_nodes_in_group("forest_trees").size(), 8)
	assert_gt(extra.get_tree().get_nodes_in_group("clubhouse_gate").size(), 0)
	assert_true(other.spawner.is_transit())


func test_flying_into_the_trees_puts_the_cart_back_on_the_path() -> void:
	var extra := WORLD.instantiate()
	add_child_autofree(extra)
	var other := extra.get_node("MatchFlow") as MatchFlow
	var ride := extra.get_node("GolfCart") as GolfCart
	other.start_on_cart_path = true
	other.begin()
	await wait_physics_frames(6)
	var path := other.cart_path
	assert_not_null(path)
	var mid: Vector3 = path.centerline[path.centerline.size() / 2]
	var along: Vector3 = path.centerline[path.centerline.size() / 2 + 1] - mid
	along.y = 0.0
	var right := along.normalized().cross(Vector3.UP).normalized()
	var crash_at := mid + right * (CartPath.PATH_WIDTH * 0.5 + 8.0)
	var crash_along := CartPathTrack.along(path.centerline, crash_at)
	ride.recover_at(crash_at, 0.0)
	await wait_physics_frames(3)
	assert_eq(ride.drive_speed, 0.0, "you start again from a stop")
	assert_lt(
		Vector2(ride.velocity.x, ride.velocity.z).length(), 1.5,
		"no leftover drive speed"
	)
	assert_lt(
		_lane_offset(path, ride.global_position), 1.5,
		"the cart lands on the path, not in the trees"
	)
	assert_almost_eq(
		CartPathTrack.along(path.centerline, ride.global_position),
		crash_along - CartPath.CRASH_BACK,
		5.0
	)


func test_snipers_stay_off_the_towers() -> void:
	flow.start_hole(0)
	await wait_physics_frames(6)
	assert_eq(flow.phase, MatchFlow.Phase.PREP)
	assert_eq(flow.hole.sniper_perches().size(), 2)
	assert_eq(flow.spawner.live_count(), 0, "the perches stay empty during warm-up")
	players[0].global_position = flow.hole.tee + Vector3.UP * 0.9
	flow.start_play()
	await wait_physics_frames(4)
	var snipers := 0
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie != null and zombie.stats != null and zombie.stats.display_name == "Sniper":
			snipers += 1
	assert_eq(snipers, 0, "tower snipers are parked for now")


func test_a_hole_opens_on_the_practice_green_with_nothing_running() -> void:
	flow.start_hole(0)
	await wait_physics_frames(6)
	assert_eq(flow.phase, MatchFlow.Phase.PREP)
	assert_almost_eq(
		ball.global_position.distance_to(flow.hole.practice_tee), GolfBall.RADIUS + 0.06, 0.5,
		"the ball waits on the practice mat, not the tee"
	)
	assert_eq(ball.current_surface(), Surface.Type.GREEN)
	var clock := flow.hole_time_left
	await wait_seconds(0.4)
	assert_eq(flow.hole_time_left, clock, "the hole clock is parked until you start")
	await wait_seconds(SpawnDirector.FIRST_SPAWN_DELAY)
	assert_eq(flow.spawner.live_count(), 0, "nothing spawns while you are warming up")


func test_warm_up_putts_are_free_and_do_not_advance_the_hole() -> void:
	flow.start_hole(0)
	await wait_physics_frames(6)
	_swing(players[0], 0.05)
	assert_eq(flow.score.strokes, 0, "practice swings do not count")
	ball.global_position = flow.hole.practice_cup + Vector3.UP * GolfBall.RADIUS
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	for _frame in 90:
		if ball.global_position.distance_to(flow.hole.practice_tee) < 1.0:
			break
		await wait_physics_frames(1)
	assert_eq(flow.score.hole_index, 0, "holing a practice putt does not finish the hole")
	assert_eq(flow.phase, MatchFlow.Phase.PREP)
	assert_almost_eq(
		ball.global_position.distance_to(flow.hole.practice_tee), GolfBall.RADIUS + 0.06, 0.5,
		"the ball goes back to the mat for another go"
	)


func test_stepping_onto_the_tee_starts_the_hole() -> void:
	flow.start_hole(0)
	await wait_physics_frames(6)
	assert_false(
		flow.can_start_play(players[0]),
		"you start behind the tee, so it takes a step forward to call it on"
	)
	players[0].global_position = flow.hole.tee + Vector3.UP * 0.9
	assert_true(flow.can_start_play(players[0]))
	assert_string_contains(players[0].get_prompt(), "start the hole")
	flow.start_play()
	await wait_physics_frames(6)
	assert_eq(flow.phase, MatchFlow.Phase.PLAYING)
	assert_false(flow.can_start_play(players[0]), "the hole is already on")
	assert_eq(ball.current_surface(), Surface.Type.TEE)
	await wait_seconds(SpawnDirector.FIRST_SPAWN_DELAY + 1.5)
	assert_gt(flow.spawner.live_count(), 0, "readying up is what lets them in")


func test_the_hole_clock_counts_down() -> void:
	var start := flow.hole_time_left
	await wait_seconds(0.4)
	assert_lt(flow.hole_time_left, start - 0.25, "the two-minute clock has to actually run")


func test_running_out_of_time_ends_the_run() -> void:
	watch_signals(flow)
	flow.hole_time_left = 0.01
	await wait_seconds(0.1)
	assert_true(flow.finished)
	assert_eq(flow.hole_time_left, 0.0)
	assert_signal_emitted_with_parameters(flow, "run_ended", [false])
	var banner: Array = get_signal_parameters(flow, "message_changed")
	assert_eq(banner[0], "GAME OVER")
	assert_string_contains(banner[1], "Time ran out")
	assert_string_contains(banner[1], "new round")
	assert_true(banner[2], "the time-up banner stays on screen")


func test_nobody_owns_the_ball_until_they_walk_up_to_it() -> void:
	assert_null(golf.golfer)
	assert_false(golf.can_claim(players[0]), "the players start too far away to swing")


func test_first_player_to_the_ball_becomes_the_golfer() -> void:
	_stand_by_ball(players[0])
	golf.try_toggle(players[0])
	assert_eq(golf.golfer, players[0])
	assert_true(players[0].is_golfing())
	assert_false(golf.can_claim(players[1]), "only one golfer at a time")


func test_claiming_the_ball_brings_the_golfer_to_address() -> void:
	_stand_by_ball(players[0])
	golf.try_toggle(players[0])
	await wait_process_frames(2)
	var offset := players[0].global_position - ball.global_position
	offset.y = 0.0
	assert_almost_eq(
		offset.length(), GolfClub.SIDE, 0.2,
		"the claim can be made from a few metres out, but the swing happens at the ball"
	)


func test_the_flight_is_drawn_behind_the_ball() -> void:
	var trail := ball.get_node("Trail") as BallTrail
	assert_eq(trail.mesh.get_surface_count(), 0, "nothing to draw before the shot")
	_swing(players[0], 0.4)
	await wait_physics_frames(12)
	assert_gt(trail.mesh.get_surface_count(), 0, "the shot should leave a line in the air")
	await _wait_for_ball()
	await wait_seconds(BallTrail.FADE_TIME + 0.5)
	assert_eq(
		trail.mesh.get_surface_count(), 0,
		"the line fades, so it cannot be left behind as a yardage marker"
	)


func test_the_golfer_can_step_away_from_the_ball() -> void:
	_stand_by_ball(players[0])
	golf.try_toggle(players[0])
	golf.try_toggle(players[0])
	assert_null(golf.golfer)
	assert_false(players[0].is_golfing())


func test_aim_starts_pointed_at_the_cup() -> void:
	_stand_by_ball(players[1])
	golf.try_toggle(players[1])
	var aim := Shot.aim_direction(golf.aim_yaw, 0.0)
	var to_cup := (flow.hole.cup - ball.global_position)
	to_cup.y = 0.0
	assert_almost_eq(aim.angle_to(to_cup.normalized()), 0.0, 0.01)


func test_a_swing_counts_one_stroke_and_moves_the_ball() -> void:
	var tee := ball.global_position
	_swing(players[0], 0.35)
	assert_eq(flow.score.strokes, 1)
	assert_true(ball.is_in_play())
	await _wait_for_ball()
	assert_false(ball.is_in_play(), "the ball should have settled")
	assert_gt(ball.global_position.distance_to(tee), 15.0)
	assert_null(golf.golfer, "the claim is released so the golfer has to walk to the ball")


func test_taking_a_hit_mid_swing_costs_no_stroke() -> void:
	_stand_by_ball(players[0])
	golf.try_toggle(players[0])
	golf.click()
	assert_eq(golf.meter.state, SwingMeter.State.BACKSWING)
	players[0].health.take_damage(15.0)
	assert_eq(golf.meter.state, SwingMeter.State.READY, "the swing is interrupted")
	assert_eq(flow.score.strokes, 0)
	assert_eq(golf.golfer, players[0], "an interruption does not take the ball away")


func test_going_out_of_bounds_costs_a_penalty_and_replays_the_spot() -> void:
	_swing(players[0], 0.3)
	var safe := ball.last_safe_position
	ball.global_position = Vector3(flow.hole.bounds.position.x - 30.0, 2.0, 0.0)
	await wait_physics_frames(6)
	assert_eq(flow.score.strokes, 2, "one for the swing, one for the penalty")
	assert_almost_eq(ball.global_position.distance_to(safe), GolfBall.RADIUS, 0.3)


func test_water_does_not_cost_a_penalty() -> void:
	_swing(players[0], 0.2)
	var strokes := flow.score.strokes
	ball.freeze = true
	var where := ball.global_position
	ball.entered_hazard.emit("water")
	await wait_physics_frames(2)
	assert_eq(flow.score.strokes, strokes, "a splash is a swim, not a stroke")
	assert_almost_eq(
		ball.global_position.distance_to(where), 0.0, 0.05,
		"the ball stays where it sank instead of replaying the last lie"
	)
	assert_false(flow.finished)


func test_holing_out_makes_you_pick_up_the_ball() -> void:
	await _hole_out()
	assert_eq(flow.score.results[0], 1, "the hole should be recorded as a one")
	assert_eq(flow.score.hole_index, 1)
	assert_eq(flow.phase, MatchFlow.Phase.RETRIEVE)
	assert_false(flow.in_clubhouse(), "the shop waits at the next tee, not the cup")
	assert_true(ball.is_holed())
	assert_lt(
		ball.global_position.y, flow.hole.cup.y,
		"the ball should be down in the cup, not sitting on the green"
	)
	assert_true(players[0].is_celebrating(), "solo play gets a hole-out dance")
	_stand_by_ball(players[0])
	assert_false(golf.can_claim(players[0]), "the hole is finished; you pick the ball up")
	assert_true(flow.can_retrieve_ball(players[0]))
	assert_eq(flow.score.money, GameState.hole_payout(-3, flow.hole_time_left))
	assert_lt(
		cart.global_position.distance_to(flow.hole.cup), 20.0,
		"the cart should be waiting by the green, not left back at the tee"
	)


func test_a_double_bogey_costs_money_and_the_run_goes_on() -> void:
	flow.score.credit(90)
	flow.score.add_stroke(6)
	ball.came_to_rest.emit(ball.global_position)
	await wait_physics_frames(2)
	assert_false(flow.finished, "a double bogey is a fine, not the end")
	assert_eq(flow.score.results[0], 6)
	assert_eq(flow.score.hole_index, 1)
	assert_eq(flow.phase, MatchFlow.Phase.RETRIEVE)
	assert_eq(flow.score.money, 90 + GameState.score_payout(2))
	assert_true(ball.is_closed())
	_stand_by_ball(players[0])
	assert_false(golf.can_claim(players[0]), "the hole is finished; you pick the ball up")
	assert_true(flow.can_retrieve_ball(players[0]))
	assert_false(players[0].is_celebrating())


func test_a_penalty_that_reaches_double_bogey_picks_up_instead_of_ending() -> void:
	flow.score.credit(90)
	flow.score.add_stroke(5)
	ball.entered_hazard.emit("out of bounds")
	await wait_physics_frames(2)
	assert_false(flow.finished)
	assert_eq(flow.score.results[0], 6)
	assert_eq(flow.score.money, 90 + GameState.score_payout(2))
	assert_eq(flow.phase, MatchFlow.Phase.RETRIEVE)


func test_holing_out_on_a_double_bogey_still_takes_the_fine() -> void:
	flow.score.credit(90)
	flow.score.add_stroke(5)
	await _hole_out()
	assert_false(flow.finished)
	assert_eq(flow.score.results[0], 6)
	assert_eq(flow.score.money, 90 + GameState.score_payout(2))
	assert_eq(flow.phase, MatchFlow.Phase.RETRIEVE)


func test_coop_does_not_steal_the_camera_for_a_dance() -> void:
	GameSettings.mode = GameSettings.Mode.COOP
	await _hole_out()
	assert_false(players[0].is_celebrating())
	assert_false(players[1].is_celebrating())


func test_picking_up_the_ball_opens_the_drive_to_the_next_tee() -> void:
	await _hole_out()
	flow.retrieve_ball(players[0])
	await wait_physics_frames(6)
	assert_true(ball.is_stowed())
	assert_eq(flow.phase, MatchFlow.Phase.TRANSIT)
	assert_not_null(flow.cart_path)
	assert_not_null(flow.clubhouse)
	assert_false(flow.in_clubhouse(), "you still have to drive there and interact")
	var to_tee := flow.cart_path.tee - flow.hole.cup
	to_tee.y = 0.0
	assert_gt(to_tee.length(), 40.0, "the next tee should be a drive, not a step")
	assert_lt(
		flow.clubhouse.global_position.distance_to(flow.cart_path.tee), 30.0,
		"the clubhouse belongs at the next tee"
	)
	assert_gt(
		flow.clubhouse.global_position.distance_to(flow.hole.cup), 40.0,
		"it should not spawn beside the cup you just finished"
	)
	assert_gt(
		get_tree().get_nodes_in_group("transit_arrows").size(), 4,
		"arrows should point the cart down the path"
	)
	flow.spawner.stop()
	flow.arrive_at_clubhouse()
	assert_true(flow.in_clubhouse())
	assert_eq(flow.hole.par, 3, "opening the front door loads the next hole behind the exit")
	assert_eq(flow.hole.index, flow.score.hole_index)
	assert_lt(
		flow.clubhouse.exit_point().distance_to(flow.hole.practice_tee),
		flow.clubhouse.door_point().distance_to(flow.hole.practice_tee),
		"the back door opens onto the practice green"
	)
	assert_true(
		flow.clubhouse.inside(players[0]),
		"opening the doors puts you in the hall while the course swaps"
	)
	flow.leave_clubhouse()
	await wait_physics_frames(6)
	assert_false(flow.in_clubhouse())
	assert_true(flow.clubhouse.exit_open)
	assert_eq(flow.hole.par, 3, "hole two of the template is the par three")
	assert_eq(flow.score.strokes, 0)
	assert_eq(flow.phase, MatchFlow.Phase.PREP, "the next hole opens on the practice green")
	assert_eq(ball.current_surface(), Surface.Type.GREEN, "warm up before the hole starts")
	flow.start_play()
	await wait_physics_frames(6)
	assert_eq(
		ball.current_surface(), Surface.Type.TEE,
		"the ball is teed up on the new hole, not reading the old one"
	)
	assert_false(ball.is_stowed())


func test_clubhouse_elevator_fades_out_then_cuts_on_the_tee() -> void:
	await _hole_out()
	flow.retrieve_ball(players[0])
	await wait_physics_frames(6)
	assert_eq(Music.current, Music.Track.LEVEL)
	flow.arrive_at_clubhouse()
	assert_eq(Music.current, Music.Track.CLUBHOUSE)
	assert_eq(Music.player().stream.resource_path, Music.CLUBHOUSE_PATH)
	assert_not_null(Music.fader(), "the hole bed keeps playing while it fades out")
	assert_eq(Music.fader().stream.resource_path, Music.LEVEL_PATH)
	flow.leave_clubhouse()
	assert_true(Music.following_clubhouse)
	assert_eq(Music.current, Music.Track.CLUBHOUSE)
	var inside_vol := Music.player().volume_db
	for who in players:
		who.global_position = flow.hole.tee + Vector3.UP * 1.2
	await wait_process_frames(2)
	assert_lt(Music.player().volume_db, inside_vol - 20.0, "almost gone by the tee box")
	assert_almost_eq(Music.player().volume_db, Music.SILENCE_DB, 6.0)
	flow.start_play()
	assert_eq(Music.current, Music.Track.LEVEL)
	assert_false(Music.following_clubhouse)
	assert_null(Music.fader())
	assert_eq(Music.player().stream.resource_path, Music.LEVEL_PATH)


func test_the_cart_path_swarm_clears_when_you_reach_the_clubhouse() -> void:
	await _hole_out()
	flow.retrieve_ball(players[0])
	await wait_physics_frames(8)
	assert_gt(flow.spawner.live_count(), 5, "the road to the next tee should be packed")
	assert_true(flow.spawner.is_transit())
	players[0].global_position = flow.clubhouse.door_point() + Vector3(0.0, 0.9, 0.0)
	players[0].open_shop()
	await wait_physics_frames(6)
	assert_true(flow.in_clubhouse())
	assert_eq(flow.spawner.live_count(), 0, "interacting with the clubhouse clears the swarm")
	assert_true(flow.clubhouse.doors_open)
	assert_eq(flow.clubhouse.stations.size(), 5)
	assert_eq(flow.clubhouse.npcs.size(), 6)
	assert_eq(flow.clubhouse.comedy_count(), 2)


func test_shopping_does_not_score_or_advance() -> void:
	await _hole_out()
	flow.retrieve_ball(players[0])
	await wait_physics_frames(6)
	flow.arrive_at_clubhouse()
	var hole_index := flow.score.hole_index
	_swing(players[0], 0.05)
	assert_eq(flow.score.strokes, 0, "practice swings are free")
	assert_eq(flow.score.hole_index, hole_index)
	assert_true(flow.in_clubhouse(), "the shop does not start the next hole")
	assert_eq(flow.score.results[1], -1)


func test_the_walk_from_the_tee_to_the_clubhouse_stays_on_the_ground() -> void:
	await _hole_out()
	flow.retrieve_ball(players[0])
	await wait_physics_frames(6)
	var house := flow.clubhouse
	assert_not_null(house)
	assert_not_null(house.plaza)
	assert_eq(house.plaza.collision_layer, Layers.WORLD)
	assert_true(
		house.covers_local(house.to_local(flow.cart_path.tee)),
		"the plaza has to reach the staging tee"
	)
	assert_true(house.covers_local(house.to_local(house.door_point())))
	var space := world.get_world_3d().direct_space_state
	var from := flow.cart_path.tee + Vector3.UP * 1.2
	var door := house.door_point() + Vector3.UP * 1.2
	for i in 9:
		var at := from.lerp(door, float(i) / 8.0)
		var query := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 6.0)
		query.collision_mask = Layers.WORLD | Layers.PROP
		var hit := space.intersect_ray(query)
		assert_false(hit.is_empty(), "ground between the tee and the doors")


func test_the_exit_walks_onto_the_practice_green_then_the_tee() -> void:
	await _hole_out()
	flow.retrieve_ball(players[0])
	await wait_physics_frames(6)
	flow.arrive_at_clubhouse()
	await wait_physics_frames(6)
	var house := flow.clubhouse
	assert_not_null(house)
	assert_true(house.covers_local(house.to_local(house.exit_point())))
	assert_true(
		house.covers_local(house.to_local(flow.hole.practice_tee)),
		"the back plaza has to reach the practice tee"
	)
	flow.leave_clubhouse()
	var space := world.get_world_3d().direct_space_state
	var exit := house.exit_point() + Vector3.UP * 1.2
	var practice := flow.hole.practice_tee + Vector3.UP * 1.2
	var tee := flow.hole.tee + Vector3.UP * 1.2
	for pair in [[exit, practice], [practice, tee]]:
		var from: Vector3 = pair[0]
		var to: Vector3 = pair[1]
		for i in 9:
			var at := from.lerp(to, float(i) / 8.0)
			var query := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 6.0)
			query.collision_mask = Layers.WORLD | Layers.PROP
			var hit := space.intersect_ray(query)
			assert_false(hit.is_empty(), "ground from the exit onto the hole")


func test_bonus_seconds_land_on_the_next_hole() -> void:
	await _hole_out()
	flow.retrieve_ball(players[0])
	await wait_physics_frames(4)
	flow.score.add_bonus_seconds(30)
	flow.score.add_freeze_seconds(15.0)
	flow.leave_clubhouse()
	await wait_physics_frames(6)
	assert_almost_eq(flow.hole_time_left, GameSettings.hole_seconds() + 30.0, 0.6)
	assert_almost_eq(flow.freeze_left, 15.0, 0.6)
	assert_eq(flow.score.bonus_seconds, 0)
	assert_eq(flow.score.freeze_seconds, 0.0)


func test_both_players_down_ends_the_run() -> void:
	watch_signals(flow)
	players[0].health.take_damage(500.0)
	assert_false(flow.finished, "one player down is survivable")
	players[1].health.take_damage(500.0)
	assert_true(flow.finished)
	assert_signal_emitted_with_parameters(flow, "run_ended", [false])


func test_zombies_arrive_while_the_hole_is_being_played() -> void:
	flow.spawner.begin_hole(0, flow.hole.spawn_points)
	assert_gt(flow.spawner.cap(), 0)
	await wait_seconds(SpawnDirector.FIRST_SPAWN_DELAY + 1.5)
	assert_gt(flow.spawner.live_count(), 0, "the hole should be under attack")


func test_a_shot_zombie_blinks_white_and_gets_knocked_back() -> void:
	flow.spawner.begin_hole(0, flow.hole.spawn_points)
	await wait_seconds(SpawnDirector.FIRST_SPAWN_DELAY + 1.5)
	var zombie := get_tree().get_first_node_in_group("zombies") as Zombie
	assert_not_null(zombie, "need something to shoot at")
	# Stand it on the tee shelf so a pond bank cannot swallow the knockback, and
	# put a player ahead of it so its walk does not eat the shove.
	var forward := flow.hole.cup - flow.hole.tee
	forward.y = 0.0
	forward = forward.normalized()
	var on_tee := flow.hole.lift(flow.hole.tee) + Vector3.UP * 1.2
	zombie.global_position = on_tee + forward * 3.0
	players[0].global_position = on_tee + forward * 8.0
	await wait_physics_frames(4)
	var before := zombie.global_position
	assert_false(zombie.is_flashing())
	zombie.take_damage(20.0, forward)
	assert_true(zombie.is_flashing(), "a hit should light it up")
	await wait_physics_frames(8)
	assert_gt(
		(zombie.global_position - before).dot(forward), 0.0,
		"the hit should carry it back, not just slow its walk"
	)
	await wait_seconds(Zombie.FLASH_TIME + 0.2)
	assert_false(zombie.is_flashing(), "the flash is a blink, not a paint job")


func test_both_players_carry_a_raygun_until_they_pick_up_the_club() -> void:
	for player in players:
		assert_true(player.raygun.visible)
		assert_gt(player.raygun.get_child_count(), 0, "the gun should have a model")
	_stand_by_ball(players[0])
	golf.try_toggle(players[0])
	await wait_physics_frames(2)
	assert_false(players[0].raygun.visible, "the golfer swings a club, not a raygun")
	assert_true(players[1].raygun.visible, "the other player is still on guard")


func test_the_robot_stands_still_until_it_is_moving() -> void:
	var body := players[0].body
	assert_eq(body.legs.size(), 2)
	assert_almost_eq(body.legs[0].rotation.x, 0.0, 0.0001)
	assert_almost_eq(body.hips.position.y, PlayerBody.HIP_HEIGHT, 0.0001)


func test_the_cart_is_waiting_off_to_the_side_of_the_tee() -> void:
	var distance := cart.global_position.distance_to(flow.hole.tee)
	assert_between(distance, 4.0, 16.0, "close enough to walk to, clear of the first shot")
	assert_gt(cart.global_position.distance_to(ball.global_position), 4.0)


func test_first_player_to_the_cart_drives_and_the_other_rides_along() -> void:
	_stand_by_cart(players[0])
	_stand_by_cart(players[1])
	cart.board(players[0])
	cart.board(players[1])
	assert_eq(cart.driver, players[0])
	assert_eq(cart.passenger, players[1])
	await wait_physics_frames(2)
	for player in players:
		assert_true(player.is_riding())
		assert_lt(
			player.global_position.distance_to(cart.global_position), 2.0,
			"riders are carried by the cart, not left standing where they were"
		)


func test_the_driver_looks_forward_and_cannot_look_around() -> void:
	_stand_by_cart(players[0])
	cart.board(players[0])
	await wait_physics_frames(2)
	assert_true(players[0].is_driving())
	assert_false(players[0].raygun.visible, "hands are on the wheel, not the gun")
	assert_true(players[0].body.visible, "the driver is sitting in the cart, not vanished")
	assert_lt(
		players[0].body.hips.position.y, PlayerBody.HIP_HEIGHT,
		"folded into the seat rather than standing through the roof"
	)
	var before := players[0].get_view_transform()
	players[0].add_mouse_look(Vector2(400.0, 250.0))
	await wait_physics_frames(2)
	var after := players[0].get_view_transform()
	assert_almost_eq(
		before.basis.z.dot(after.basis.z), 1.0, 0.001,
		"looking around does nothing from the driver's seat"
	)
	var view_flat := Vector2(-after.basis.z.x, -after.basis.z.z).normalized()
	var cart_flat := Vector2(-cart.global_transform.basis.z.x, -cart.global_transform.basis.z.z).normalized()
	assert_almost_eq(view_flat.dot(cart_flat), 1.0, 0.02, "the driver faces the way the cart is pointing")
	var wheel := _steering_wheel()
	assert_not_null(wheel, "there should be a wheel in front of the driver")
	assert_true(wheel.has_hands_on(), "and a pair of hands holding it")
	assert_gt(
		after.origin.distance_to(wheel.global_position), 0.65,
		"the wheel should sit in the cabin, not fill the lens"
	)
	assert_lt(
		players[0].body.arms[0].global_position.distance_to(wheel.grip_positions()[0]),
		0.85,
		"the driver's arm should reach the rim rather than float at the edge of the view"
	)
	assert_gt(players[0].get_view_fov(), Player.BASE_FOV, "driving pulls the view back")
	assert_eq(
		players[0].body.cabin[0].layers, players[0].cabin_layer(),
		"the driver's chest is not drawn in their own camera"
	)
	assert_eq(
		players[0].body.arms[0].get_child(0).layers, PlayerBody.WORLD_LAYER,
		"but the arms on the wheel still are"
	)
	assert_eq(players[0].view_cull_mask() & players[0].cabin_layer(), 0)
	assert_ne(
		players[1].view_cull_mask() & players[0].cabin_layer(), 0,
		"the other player still sees the whole robot in the seat"
	)


func test_the_driver_can_pull_the_camera_out_behind_the_cart() -> void:
	_stand_by_cart(players[0])
	cart.board(players[0])
	await wait_physics_frames(2)
	players[0].set_physics_process(false)
	players[0].input = CpuInput.new(players[0].input_prefix, false)
	var cabin := players[0].get_view_transform()
	var pad := players[0].input as CpuInput
	pad.tap("melee")
	players[0]._apply_look(0.016)
	players[0]._animate(0.016)
	var chase := players[0].get_view_transform()
	assert_gt(
		cabin.origin.distance_to(chase.origin), 6.0,
		"L1 pulls the lens out of the cabin"
	)
	assert_gt(chase.origin.distance_to(cart.global_position), 7.0)
	assert_gt(chase.origin.y, cart.global_position.y + 3.0, "high enough to see the cart")
	assert_ne(
		players[0].view_cull_mask() & players[0].cabin_layer(), 0,
		"the driver has to stay in frame"
	)
	assert_eq(
		players[0].body.cabin[0].layers, PlayerBody.WORLD_LAYER,
		"the whole robot is drawn in chase view"
	)
	assert_eq(players[0].get_view_fov(), GolfCart.CHASE_FOV)
	pad.begin_frame()
	pad.tap("melee")
	players[0]._apply_look(0.016)
	players[0]._animate(0.016)
	var back := players[0].get_view_transform()
	assert_lt(
		back.origin.distance_to(cabin.origin), 0.05,
		"L1 again returns to the cabin"
	)
	assert_eq(players[0].view_cull_mask() & players[0].cabin_layer(), 0)
	cart.eject(players[0])
	_stand_by_cart(players[0])
	cart.board(players[0])
	assert_eq(
		players[0].get_view_fov(), Player.DRIVER_FOV,
		"hopping back in starts in the cabin, not the last chase cam"
	)


func test_the_passenger_can_still_look_around() -> void:
	_stand_by_cart(players[0])
	_stand_by_cart(players[1])
	cart.board(players[1])
	cart.board(players[0])
	await wait_physics_frames(2)
	assert_true(players[1].is_driving())
	assert_false(players[0].is_driving())
	assert_true(players[0].raygun.visible, "shotgun still has the gun")
	var before := players[0].get_view_transform()
	players[0].add_mouse_look(Vector2(180.0, 0.0))
	await wait_physics_frames(2)
	var after := players[0].get_view_transform()
	assert_lt(
		before.basis.z.dot(after.basis.z), 0.98,
		"the passenger can still look around"
	)


func test_hopping_out_leaves_you_standing_beside_the_cart() -> void:
	_stand_by_cart(players[0])
	cart.board(players[0])
	cart.eject(players[0])
	assert_null(cart.driver)
	assert_false(players[0].is_riding())
	var offset := players[0].global_position - cart.global_position
	offset.y = 0.0
	assert_between(offset.length(), 1.0, 3.2, "dropped off clear of the wheels")
	var ground := flow.hole.lift(players[0].global_position)
	assert_gt(
		players[0].global_position.y, ground.y - 0.05,
		"hopping out cannot plant you inside the turf"
	)
	assert_eq(players[0].collision_layer, Layers.PLAYER, "hopping out puts the capsule back")
	assert_eq(
		players[0].body.cabin[0].layers, PlayerBody.WORLD_LAYER,
		"hopping out puts the whole robot back in their own view"
	)


func test_a_cart_girl_is_waiting_on_the_first_hole() -> void:
	var girl := flow.hole_root.find_child("CartGirl", true, false) as CartGirl
	assert_not_null(girl, "the beer cart rolls up on every hole")
	assert_eq(girl.visit, CartGirl.Visit.WAITING)
	assert_false(girl.visible, "she stays out of sight until the first counted shot")
	assert_gt(
		girl.global_position.distance_to(players[0].global_position), 30.0,
		"she drives in from down the hole rather than spawning on the players"
	)


func test_the_beer_cart_rolls_in_after_the_first_shot() -> void:
	assert_eq(flow.cart_girl.visit, CartGirl.Visit.WAITING)
	assert_false(flow.cart_girl.visible)
	golf.stroke_taken.emit()
	assert_eq(flow.score.strokes, 1)
	assert_eq(flow.cart_girl.visit, CartGirl.Visit.APPROACHING)
	assert_true(flow.cart_girl.visible, "the first stroke is when she appears down the hole")
	golf.stroke_taken.emit()
	assert_eq(flow.cart_girl.visit, CartGirl.Visit.APPROACHING, "later shots do not restart her")


func test_later_holes_still_bring_the_beer_cart() -> void:
	flow.start_hole(1)
	assert_not_null(flow.hole_root.find_child("CartGirl", true, false))
	assert_not_null(flow.cart_girl)
	assert_eq(flow.cart_girl.visit, CartGirl.Visit.WAITING)
	flow.start_hole(3)
	assert_not_null(flow.cart_girl)
	assert_eq(flow.cart_girl.visit, CartGirl.Visit.WAITING)


func test_the_beer_cart_comes_back_on_the_next_hole() -> void:
	await _hole_out()
	flow.retrieve_ball(players[0])
	await wait_physics_frames(4)
	flow.arrive_at_clubhouse()
	flow.leave_clubhouse()
	await wait_physics_frames(6)
	assert_not_null(flow.cart_girl, "the next hole has a fresh beer cart")
	assert_eq(flow.cart_girl.visit, CartGirl.Visit.WAITING)
	flow.start_play()
	golf.stroke_taken.emit()
	assert_eq(flow.cart_girl.visit, CartGirl.Visit.APPROACHING)


func test_a_cpu_partner_walks_out_onto_hole_two() -> void:
	players[0].possess_cpu()
	await _hole_out()
	flow.retrieve_ball(players[1])
	flow.spawner.stop()
	flow.spawner.clear_zombies()
	players[0].health.take_damage(players[0].health.max_hp + 1.0)
	assert_true(players[0].health.is_downed())
	flow.arrive_at_clubhouse()
	assert_true(players[0].health.is_alive(), "the clubhouse stands a downed buddy back up")
	assert_true(flow.clubhouse.inside(players[0]))
	players[0].global_position = flow.clubhouse.to_global(Vector3(12.0, 1.2, 10.0))
	players[1].global_position = flow.clubhouse.exit_point() + Vector3.UP * 1.2
	flow.leave_clubhouse()
	assert_lt(
		players[0].global_position.distance_to(players[1].global_position), 4.0,
		"the buddy has to leave with you instead of staying in the hall"
	)
	assert_true(players[0].health.is_alive())


func test_a_new_hole_turns_the_riders_out() -> void:
	_stand_by_cart(players[0])
	cart.board(players[0])
	flow.start_hole(1)
	assert_null(cart.driver)
	assert_false(players[0].is_riding(), "the cart moves to the new tee without its riders")


func test_driving_into_a_zombie_runs_it_over() -> void:
	flow.spawner.begin_hole(0, flow.hole.spawn_points)
	await wait_seconds(SpawnDirector.FIRST_SPAWN_DELAY + 1.5)
	var zombie := get_tree().get_first_node_in_group("zombies") as Zombie
	assert_not_null(zombie, "need something to run over")
	var hp_before := zombie.hp
	# Line the cart up a few metres short of it, rolling in.
	cart.place_at(zombie.global_position + Vector3(0.0, 0.4, 3.5), 0.0)
	cart.drive_speed = 12.0
	await wait_physics_frames(20)
	assert_true(
		not is_instance_valid(zombie) or zombie.hp < hp_before,
		"the cart should have flattened it on the way past"
	)


func test_the_live_hole_has_hills() -> void:
	var relief := flow.hole.height.max_height - flow.hole.height.min_height
	assert_gt(relief, 0.6, "the hole you are standing on should not be a slab")
	assert_lt(relief, 20.0, "and it should not be a mountainside")
	assert_almost_eq(
		ball.global_position.y, flow.hole.tee.y + GolfBall.RADIUS, 0.4,
		"the ball sits on the tee, not at sea level"
	)


func test_killing_a_zombie_pays_its_bounty() -> void:
	flow.spawner.begin_hole(0, flow.hole.spawn_points)
	await wait_seconds(SpawnDirector.FIRST_SPAWN_DELAY + 1.5)
	var zombie := get_tree().get_first_node_in_group("zombies") as Zombie
	assert_not_null(zombie)
	var bounty := zombie.stats.bounty
	var before := flow.score.money
	zombie.take_damage(500.0, Vector3.FORWARD)
	await wait_process_frames(2)
	assert_eq(flow.score.money, before + bounty)


func test_shooting_a_zombie_dead_explodes() -> void:
	flow.spawner.begin_hole(0, flow.hole.spawn_points)
	await wait_seconds(SpawnDirector.FIRST_SPAWN_DELAY + 1.5)
	var zombie := get_tree().get_first_node_in_group("zombies") as Zombie
	assert_not_null(zombie)
	zombie.take_damage(500.0, Vector3.FORWARD)
	assert_true(zombie.is_dying())
	assert_false(zombie.visual.is_limp(), "a killing shot should skip the ragdoll")
	assert_gt(get_tree().get_nodes_in_group("fireworks").size(), 0, "the burst should be in the world")
	await wait_process_frames(3)
	assert_false(is_instance_valid(zombie), "the fireworks take them on the killing shot")


func test_a_melee_kill_throws_them_then_explodes_in_the_sky() -> void:
	flow.spawner.begin_hole(0, flow.hole.spawn_points)
	await wait_seconds(SpawnDirector.FIRST_SPAWN_DELAY + 1.5)
	var zombie := get_tree().get_first_node_in_group("zombies") as Zombie
	assert_not_null(zombie)
	var before := zombie.global_position
	var from := zombie.global_position + Vector3(0.0, 1.5, 1.6)
	zombie.melee_hit(from)
	assert_true(zombie.is_dying(), "a shove should pop them even at full health")
	assert_true(zombie.is_launched())
	assert_true(zombie.visual.is_limp(), "the thrown body has to go limp")
	assert_almost_eq(zombie.explode_in(), Zombie.MELEE_EXPLODE_DELAY, 0.05)
	assert_gt(zombie.velocity.y, Zombie.MELEE_SKY_LIFT - 0.01)
	await wait_seconds(Zombie.MELEE_EXPLODE_DELAY * 0.6)
	assert_true(is_instance_valid(zombie), "they fly for a beat before the burst")
	assert_gt(
		zombie.global_position.distance_to(before), 1.5,
		"a melee kill should throw them, not drop them in place"
	)
	assert_gt(
		zombie.global_position.y, before.y + 1.5,
		"they should be up in the air when they burst"
	)
	await wait_seconds(Zombie.MELEE_EXPLODE_DELAY * 0.7)
	await wait_process_frames(3)
	assert_false(is_instance_valid(zombie), "then they explode")
	assert_gt(get_tree().get_nodes_in_group("fireworks").size(), 0)


func _stand_by_cart(player: Player) -> void:
	player.global_position = cart.global_position + Vector3(0.0, 0.9, 2.0)


func _steering_wheel() -> SteeringWheel:
	for child in cart.get_children():
		if child is SteeringWheel:
			return child
	return null


func _stand_by_ball(player: Player) -> void:
	player.global_position = ball.global_position + Vector3(1.5, 0.9, 0.0)


func _hole_out() -> void:
	_swing(players[0], 0.05)
	ball.global_position = flow.hole.cup + Vector3.UP * GolfBall.RADIUS
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	await _await_holed()


func _await_holed() -> void:
	for _frame in 90:
		if ball.is_holed():
			return
		await wait_physics_frames(1)
	assert_true(ball.is_holed(), "the ball should have dropped in")


func _lane_offset(path: CartPath, point: Vector3) -> float:
	return CartPathTrack.distance_to(path.centerline, point)


## Drives the three-click meter to a chosen power with clean contact.
func _swing(player: Player, power: float) -> void:
	_stand_by_ball(player)
	golf.try_toggle(player)
	golf.click()
	golf.meter.value = power
	golf.click()
	golf.meter.value = 0.0
	golf.click()


func _wait_for_ball(timeout := 12.0) -> void:
	var waited := 0.0
	while ball.is_in_play() and waited < timeout:
		await wait_seconds(0.2)
		waited += 0.2
