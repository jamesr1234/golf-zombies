extends GutTest
## The hole overlay is a top-down of the course, you, and the ball. Zombies stay off.

const SEED := 20260816
const PLAYER_SCENE := preload("res://scenes/players/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")


func test_the_cup_sits_above_the_tee() -> void:
	var map := _map_for(HoleGenerator.generate(0, SEED))
	var tee := map.project(map.hole.tee)
	var cup := map.project(map.hole.cup)
	assert_lt(cup.y, tee.y, "the green should read as up-hole from the tee")


func test_sand_and_water_land_on_the_map() -> void:
	var hole := _hole_with_water()
	var map := _map_for(hole)
	var kinds := HoleMap.drawn_kinds(hole)
	assert_true(kinds.has("bunker"), "sand has to show")
	assert_true(kinds.has("water"), "water has to show when the hole has a pond")
	assert_true(kinds.has("fringe"), "the collar around the green has to show")
	for patch in hole.patches:
		if patch["type"] != Surface.Type.BUNKER and patch["type"] != Surface.Type.WATER:
			continue
		var at := map.project(patch["position"])
		assert_true(Rect2(Vector2.ZERO, map.size).grow(-8.0).has_point(at))


func test_trees_and_rocks_count_as_course_features() -> void:
	var hole := HoleGenerator.generate(4, SEED)
	var kinds := HoleMap.drawn_kinds(hole)
	assert_true(kinds.has("tree") or kinds.has("rock") or kinds.has("wall"))


func test_enemy_spawns_never_make_the_map() -> void:
	var hole := HoleGenerator.generate(2, SEED)
	assert_gt(hole.spawn_points.size(), 0)
	var kinds := HoleMap.drawn_kinds(hole)
	assert_false(kinds.has("spawn"))
	assert_false(kinds.has("zombie"))


func test_holding_triangle_asks_for_the_overlay() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var pad := CpuInput.new("p2", false)
	player.input = pad
	pad.hold("map")
	assert_true(player.wants_map())
	pad.begin_frame()
	assert_false(player.wants_map(), "the map is hold-to-show")


func test_a_cpu_partner_does_not_open_the_map() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.possess_cpu()
	(player.input as CpuInput).hold("map")
	assert_false(player.wants_map())


func test_triangle_still_revives_instead_of_opening_the_map() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	var partner: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	add_child_autofree(partner)
	player.partner = partner
	partner.health.take_damage(partner.health.max_hp + 1.0)
	player.global_position = partner.global_position
	var pad := CpuInput.new("p2", false)
	player.input = pad
	pad.hold("map")
	assert_false(player.wants_map(), "triangle is still revive when a partner is down")


func test_the_ball_is_plotted_where_it_lies() -> void:
	var hole := HoleGenerator.generate(0, SEED)
	var map := _map_for(hole)
	var lie := hole.tee + Vector3(6.0, 0.0, 18.0)
	map.ball = lie
	map.has_ball = true
	var at := map.project(lie)
	assert_true(Rect2(Vector2.ZERO, map.size).grow(-8.0).has_point(at))
	assert_ne(at, map.project(hole.tee), "the ball is not glued to the tee")
	assert_ne(at, map.project(hole.cup), "or the pin")
	assert_eq(HoleMap.BALL_COLOR, Color.WHITE)


func test_the_hud_paints_the_overlay_while_the_button_is_held() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(hud)
	add_child_autofree(player)
	var pad := CpuInput.new("p2", false)
	player.input = pad
	hud.player = player
	var flow: MatchFlow = autofree(MatchFlow.new())
	flow.hole = HoleGenerator.generate(0, SEED)
	hud.flow = flow
	hud._update_map()
	assert_false(hud.hole_map.visible)
	pad.hold("map")
	hud._update_map()
	assert_true(hud.hole_map.visible)
	assert_eq(hud.hole_map.hole, flow.hole)


func test_the_hud_marks_the_ball_on_the_overlay() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	var player: Player = PLAYER_SCENE.instantiate()
	var ball := GolfBall.new()
	add_child_autofree(hud)
	add_child_autofree(player)
	add_child_autofree(ball)
	var pad := CpuInput.new("p2", false)
	player.input = pad
	hud.player = player
	var flow: MatchFlow = autofree(MatchFlow.new())
	flow.hole = HoleGenerator.generate(0, SEED)
	flow.ball = ball
	ball.global_position = flow.hole.tee + Vector3(10.0, 0.0, 20.0)
	hud.flow = flow
	pad.hold("map")
	hud._update_map()
	assert_true(hud.hole_map.has_ball)
	assert_eq(hud.hole_map.ball, ball.global_position)


func _map_for(hole: HoleData) -> HoleMap:
	var map := HoleMap.new()
	add_child_autofree(map)
	map.size = Vector2(420, 320)
	map.hole = hole
	map.you = hole.tee
	return map


func _hole_with_water() -> HoleData:
	for index in 9:
		var hole := HoleGenerator.generate(index, SEED)
		for patch in hole.patches:
			if patch["type"] == Surface.Type.WATER:
				return hole
	fail_test("the nine-hole template should include a water hazard")
	return HoleGenerator.generate(0, SEED)
