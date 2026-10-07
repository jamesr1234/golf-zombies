extends GutTest
## Water is a swim: ponds are big enough to dive in, the ball sinks without a
## penalty, and R2 / L1 / R1 / Circle retrieve it instead of shooting. Circle
## also hauls you onto the bank when you are treading empty-handed at the edge.

const SEED := 20260816
const PLAYER_SCENE := preload("res://scenes/players/player.tscn")
const STEP := 1.0 / 60.0


class FakeFlow:
	extends RefCounted
	var hole: HoleData

	func can_open_doors(_who: Node3D) -> bool:
		return false

	func station_for(_who: Node3D) -> ShopStation:
		return null

	func npc_for(_who: Node3D) -> ClubhouseNpc:
		return null

	func in_clubhouse() -> bool:
		return false

	func has_shop() -> bool:
		return false


func test_a_pond_is_at_least_six_players_across() -> void:
	assert_almost_eq(HoleGenerator.WATER_MIN_SPAN, 1.8 * 6.0, 0.001)
	var hole := _hole_with_water()
	var size: Vector2 = _water_patch(hole)["size"]
	assert_gte(size.x, HoleGenerator.WATER_MIN_SPAN)
	assert_gte(size.y, HoleGenerator.WATER_MIN_SPAN)


func test_the_middle_of_a_pond_is_deep_enough_to_dive_into() -> void:
	var hole := _hole_with_water()
	var at: Vector3 = _water_patch(hole)["position"]
	var depth := hole.water_depth_at(at)
	assert_almost_eq(depth, HeightField.WATER_DEPTH, 0.35)
	assert_gt(depth, Player.SWIM_FLOAT_DEPTH + Player.SWIM_FLOOR_CLEARANCE + 1.0,
		"treading and the floor must not be the same place")


## The whole point of the surface: one flat level, meeting ground of the same
## height all the way round, so the pond sits in the land instead of on it.
func test_the_water_line_is_flat_and_level_with_the_land() -> void:
	var hole := _hole_with_water()
	var patch := _water_patch(hole)
	var level := SurfacePatch.water_level(patch)
	for spot in _across_pond(patch, 0.9):
		assert_almost_eq(hole.water_surface_y(spot), level, 0.001,
			"the surface cannot slope")
	for spot in _around_pond(patch, 0.5):
		if _on_a_jump(hole, spot):
			continue
		assert_almost_eq(hole.water_floor_y(spot), level, 0.25,
			"the shore at the water's edge has to be at the water line")


## Every other lie is draped over the heightmap. A pond is the one that is not,
## because a sloped water surface is the thing that looks wrong.
func test_the_painted_surface_is_a_flat_plane_on_the_water_line() -> void:
	var hole := _hole_with_water()
	var patch := _water_patch(hole)
	var node := SurfacePatch.create(patch, hole.height)
	add_child_autofree(node)
	var painted := _painted_mesh(node)
	var box := painted.mesh.get_aabb()
	assert_almost_eq(box.size.y, 0.0, 0.001, "a pond surface cannot be a funnel")
	assert_almost_eq(
		painted.global_position.y + box.position.y,
		SurfacePatch.water_level(patch) + Surface.DRAW_HEIGHT[Surface.Type.WATER],
		0.001, "and it sits on the water line"
	)


## The pond is the only see-through thing on the course. Turning it on for every
## lie is what put sorting artefacts all over the hole.
func test_only_the_water_is_transparent() -> void:
	var water := MeshFactory.grid_material(Surface.LOOK[Surface.Type.WATER])
	assert_eq(water.shader, MeshFactory.WATER_SHADER)
	assert_lt(float(water.get_shader_parameter("opacity")), 1.0)
	for type in [Surface.Type.ROUGH, Surface.Type.FAIRWAY, Surface.Type.GREEN,
			Surface.Type.TEE, Surface.Type.FRINGE, Surface.Type.BUNKER]:
		assert_eq(
			MeshFactory.grid_material(Surface.LOOK[type]).shader, MeshFactory.GRID_SHADER,
			"%s has to stay opaque" % Surface.Type.keys()[type]
		)


func test_the_shore_is_dry_ground_you_walk_in_over() -> void:
	var hole := _hole_with_water()
	var patch := _water_patch(hole)
	for spot in _around_pond(patch, -1.0):
		assert_lt(hole.water_depth_at(spot), Player.WADE_DEPTH,
			"the edge of a pond is waded into, not fallen into")


func test_the_ball_does_not_treat_water_as_a_hazard() -> void:
	var ball := GolfBall.new()
	add_child_autofree(ball)
	watch_signals(ball)
	ball._in_play = true
	ball.enter_surface(Surface.Type.WATER)
	assert_signal_not_emitted(ball, "entered_hazard")
	assert_true(ball.is_submerged())
	assert_true(ball.is_in_play(), "it keeps sinking until it comes to rest")


func test_a_submerged_ball_cannot_be_claimed_for_a_swing() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	var ball := GolfBall.new()
	var golf := GolfController.new()
	add_child_autofree(player)
	add_child_autofree(ball)
	add_child_autofree(golf)
	golf.ball = ball
	ball.global_position = player.global_position + Vector3(0.5, 0.0, 0.0)
	ball.enter_surface(Surface.Type.WATER)
	assert_false(golf.can_claim(player), "you have to dive for it, not address it")


func test_walking_into_a_pond_starts_a_swim() -> void:
	var player := _swimmer()
	player._physics_process(STEP)
	assert_true(player.is_swimming())
	assert_false(player.is_underwater(), "you tread until you dive")
	assert_string_contains(player.get_prompt().to_lower(), "dive")


func test_the_shallows_are_walked_through_rather_than_swum() -> void:
	var player := _swimmer()
	var hole: HoleData = player.flow.hole
	var shelf: Vector3 = _around_pond(_water_patch(hole), -1.0)[0]
	player.global_position = Vector3(shelf.x, hole.water_surface_y(shelf), shelf.z)
	player._physics_process(STEP)
	assert_false(player.is_swimming(), "you walk in off the bank on your own feet")


## Deep water holds you at the top with your head out. Nothing pulls you under
## until you ask to go down.
func test_treading_keeps_your_head_above_the_water_line() -> void:
	var player := _swimmer()
	var line := player.global_position.y
	await wait_physics_frames(40)
	assert_true(player.is_swimming())
	assert_false(player.is_underwater())
	assert_gt(player.global_position.y + Player.STAND_HEAD_HEIGHT, line,
		"your head has to stay out of the water")
	assert_lt(player.global_position.y, line, "and your feet have to be in it")
	assert_almost_eq(
		player.global_position.y, line - Player.SWIM_FLOAT_DEPTH, 0.1,
		"treading settles onto the water line, it does not sink"
	)


func test_the_player_cannot_shoot_while_swimming() -> void:
	var player := _swimmer()
	player._physics_process(STEP)
	watch_signals(player.weapon)
	var pad := player.input as CpuInput
	pad.begin_frame()
	pad.hold("shoot")
	pad.tap("shoot")
	# Already swimming, so a held trigger must not fire. A fresh tap dives.
	player._physics_process(STEP)
	assert_signal_not_emitted(player.weapon, "fired")
	assert_true(player.is_underwater(), "R2 from the surface is the dive")


func test_diving_hides_the_body_and_leaves_the_arms() -> void:
	var player := _swimmer()
	player._physics_process(STEP)
	assert_true(player.is_swimming())
	assert_false(player.is_underwater())
	assert_eq(player.body.cabin[0].layers, PlayerBody.WORLD_LAYER, "treading still shows the body")
	assert_ne(player.view_cull_mask() & player.cabin_layer(), 0)
	var pad := player.input as CpuInput
	pad.begin_frame()
	pad.tap("shoot")
	player._physics_process(STEP)
	assert_true(player.is_underwater())
	assert_eq(
		player.body.cabin[0].layers, player.cabin_layer(),
		"the chest is not drawn in their own camera"
	)
	assert_eq(
		player.body.arms[0].get_child(0).layers, PlayerBody.WORLD_LAYER,
		"the swimming arms still are"
	)
	assert_eq(player.view_cull_mask() & player.cabin_layer(), 0)


func test_l1_descends_and_r1_brings_you_back_up() -> void:
	var player := _swimmer()
	var pad := player.input as CpuInput
	pad.begin_frame()
	pad.tap("shoot")
	await wait_physics_frames(3)
	assert_true(player.is_underwater())
	var start_y := player.global_position.y
	pad.begin_frame()
	pad.hold("melee")
	await wait_physics_frames(24)
	assert_lt(player.global_position.y, start_y - 0.3, "L1 has to push you deeper")
	pad.begin_frame()
	pad.hold("ascend")
	for _i in 50:
		await wait_physics_frames(2)
		if not player.is_underwater():
			break
	assert_false(player.is_underwater(), "holding R1 all the way up surfaces you")


func test_circle_climbs_out_onto_the_bank() -> void:
	var player := _bank_swimmer()
	player._physics_process(STEP)
	assert_true(player.is_swimming())
	assert_false(player.is_underwater())
	assert_string_contains(player.get_prompt().to_lower(), "climb")
	var pad := player.input as CpuInput
	pad.begin_frame()
	pad.tap("grab")
	player._physics_process(STEP)
	assert_false(player.is_swimming(), "Circle hauls you onto the bank")
	assert_lt(
		player.flow.hole.water_depth_at(player.global_position), Player.WADE_DEPTH,
		"the landing has to be standable ground"
	)


func test_circle_does_not_climb_out_in_open_water() -> void:
	var player := _swimmer()
	player._physics_process(STEP)
	assert_true(player.is_swimming())
	assert_false(player.get_prompt().to_lower().contains("climb"),
		"open water is a swim, not a climb")
	var pad := player.input as CpuInput
	pad.begin_frame()
	pad.tap("grab")
	player._physics_process(STEP)
	assert_true(player.is_swimming(), "you have to reach the bank first")


func test_circle_does_not_climb_out_with_the_ball_in_hand() -> void:
	var player := _bank_swimmer()
	var ball := _give_ball(player)
	ball.pick_up(player)
	player._physics_process(STEP)
	assert_true(player.is_carrying_ball())
	var pad := player.input as CpuInput
	pad.begin_frame()
	pad.tap("grab")
	player._physics_process(STEP)
	assert_true(player.is_swimming(), "the ball has to leave the hands first")
	assert_true(player.is_carrying_ball())


func test_circle_grabs_a_nearby_sunk_ball() -> void:
	var player := _swimmer()
	var ball := _give_ball(player)
	ball.enter_surface(Surface.Type.WATER)
	ball.global_position = player.global_position + Vector3(0.4, -0.8, 0.0)
	var pad := player.input as CpuInput
	pad.begin_frame()
	pad.tap("shoot")
	player._physics_process(STEP)
	pad.begin_frame()
	pad.tap("interact")
	player._physics_process(STEP)
	assert_false(player.is_carrying_ball(), "E is swim-up, not the grab")
	pad.begin_frame()
	pad.tap("grab")
	player._physics_process(STEP)
	assert_true(player.is_carrying_ball())
	assert_eq(ball.carrier(), player)


## The shot is only over once the ball resolves, and a ball fished out of a pond
## never comes to rest. Leaving the claim on stranded the partner who played it
## at their stance: rooted, unable to shoot, and still worth eating.
func test_grabbing_a_partners_ball_lets_them_off_their_stance() -> void:
	var swimmer := _swimmer()
	var ball := _give_ball(swimmer)
	var golfer: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(golfer)
	golfer.golf = swimmer.golf
	golfer.global_position = ball.global_position + Vector3(0.5, 0.0, 0.0)
	swimmer.golf.try_toggle(golfer)
	assert_eq(swimmer.golf.golfer, golfer, "the partner is addressing the ball")
	assert_true(golfer.is_golfing())
	ball.enter_surface(Surface.Type.WATER)
	ball.global_position = swimmer.global_position + Vector3(0.4, -0.8, 0.0)
	swimmer.swim.try_grab_ball(swimmer)
	assert_true(swimmer.is_carrying_ball())
	assert_null(swimmer.golf.golfer, "the shot is settled, so the claim goes with it")
	assert_false(golfer.is_golfing(), "and they can walk and shoot again")


func test_r2_on_the_surface_throws_a_carried_ball() -> void:
	var player := _swimmer()
	var ball := _give_ball(player)
	ball.pick_up(player)
	assert_true(player.is_carrying_ball())
	var pad := player.input as CpuInput
	pad.begin_frame()
	pad.tap("shoot")
	player._physics_process(STEP)
	assert_false(player.is_carrying_ball())
	assert_true(ball.is_in_play(), "the toss has to leave the hands")
	assert_gt(ball.linear_velocity.length(), 5.0)


func test_a_throw_aims_up_and_out() -> void:
	var velocity := Player.throw_velocity(Vector3.FORWARD)
	assert_gt(velocity.y, 0.0, "it has to clear the bank")
	assert_lt(velocity.z, 0.0)


func test_the_solo_human_lists_keyboard_and_pad_prompts() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.input_prefix = "p2"
	player.listen_to_both_devices()
	assert_true(player.uses_mouse, "the trackpad has to turn the human")
	assert_eq(player.input.prefixes.size(), 2)
	assert_string_contains(player.input.hint("grab"), "Space")
	assert_string_contains(player.input.hint("grab"), "Circle")
	assert_string_contains(player.input.hint("ascend"), "E")
	assert_string_contains(player.input.hint("ascend"), "R1")


## A dug tunnel is the one place the ground is not solid to you, so the swim
## itself has to keep you inside the bore and hand the ground back on the way
## out. Nothing about the run is a collider, which is what makes it cheap.
func test_a_tunnel_is_a_swim_that_holds_you_inside_the_bore() -> void:
	var player := _tunnel_swimmer()
	var axis := Vector3(0.0, -2.0, -32.0)
	player._physics_process(STEP)
	assert_true(player.is_swimming(), "the bore is deep enough to swim")
	assert_true(player.in_tunnel)
	assert_eq(player.collision_mask & Layers.WORLD, 0, "the rock it runs through lets you by")
	player.global_position += Vector3(1.0, 0.0, 0.0)
	player._physics_process(STEP)
	var ride := _ride_point(player)
	assert_lt(absf(ride.x - axis.x), 1.5 - PlayerSwim.TUNNEL_MARGIN + 0.01,
		"pushing at the wall holds you off it")
	assert_almost_eq(ride.z, axis.z, 0.5, "along the run you are free to go")
	var lens := player.global_position + Vector3.UP * player.head.position.y
	assert_lt(absf(lens.y - axis.y), 1.5, "and the lens stays under the roof")


## Reaching a mouth from open water has to take you in. The ground is still
## solid until it does, so a bore you can only enter dead centre is one you
## bump your nose on.
func test_swimming_at_a_mouth_from_the_pond_takes_you_into_the_run() -> void:
	var player := _tunnel_swimmer()
	var hole: HoleData = player.flow.hole
	var mouth: Vector3 = WaterTunnel.nodes_of(hole.custom.placements[2])[0]
	assert_true(hole.tunnel_at(mouth).is_empty() == false)
	# Floating in the pond just short of the opening, off to one side of it.
	player.global_position = (
		mouth + Vector3(0.7, 0.4, 1.2) - Vector3.UP * (Player.STAND_HEAD_HEIGHT * 0.5)
	)
	player._physics_process(STEP)
	assert_true(player.in_tunnel, "the mouth reaches out for you")
	assert_eq(player.collision_mask & Layers.WORLD, 0)


## A tunnel mouth sits in the pond. That cannot steal the surface swim, or
## walking in is an instant dive through the floor.
func test_a_pond_with_a_tunnel_is_still_treading_water() -> void:
	var player := _tunnel_swimmer()
	var hole: HoleData = player.flow.hole
	var pond: Vector3 = hole.custom.placements[0][CustomHole.POSITION]
	player.global_position = Vector3(pond.x, hole.water_surface_y(pond), pond.z)
	player._physics_process(STEP)
	assert_true(player.is_swimming())
	assert_false(player.is_underwater(), "open water is a tread, not a dive")
	assert_false(player.in_tunnel, "the pond is not the bore")
	assert_eq(player.collision_mask & Layers.WORLD, Layers.WORLD, "the floor has to stay")


func test_a_planted_custom_pond_still_starts_a_swim() -> void:
	var player := _tunnel_swimmer()
	var hole: HoleData = player.flow.hole
	var node := Node3D.new()
	add_child_autofree(node)
	hole.face_arrival(node, Vector3.RIGHT, Vector3(40.0, 0.0, 80.0))
	var pond: Vector3 = hole.from_custom(hole.custom.placements[0][CustomHole.POSITION])
	player.global_position = Vector3(pond.x, hole.water_surface_y(pond), pond.z)
	player._physics_process(STEP)
	assert_true(player.is_swimming(), "planting the hole cannot lose the pond")
	assert_false(player.is_underwater())


func test_walking_over_a_tunnel_is_dry_ground() -> void:
	var player := _tunnel_swimmer()
	var hole: HoleData = player.flow.hole
	var over := Vector3(0.0, hole.height.height_at(0.0, -32.0), -32.0)
	assert_almost_eq(hole.water_depth_at(over), 0.0, 0.001)
	player.global_position = over
	player._physics_process(STEP)
	assert_false(player.is_swimming())
	assert_false(player.in_tunnel)
	assert_eq(player.collision_mask & Layers.WORLD, Layers.WORLD, "the ground is solid again")


## Two ponds joined by one dug run, which is the shape a swim race is set on.
func _tunnel_swimmer() -> Player:
	var custom := CustomHole.create("Race")
	for at in [Vector3(0.0, 0.0, -20.0), Vector3(0.0, 0.0, -44.0)]:
		custom.add_placement(CustomHole.WATER, at)
		var tile: Dictionary = custom.placements[custom.placements.size() - 1]
		tile[CustomHole.DEPTH] = 3.0
		tile[CustomHole.POOL] = at
		tile[CustomHole.SURFACE] = 0.0
	custom.add_placement(CustomHole.TUNNEL, Vector3(0.0, -2.0, -20.0))
	var dug: Dictionary = custom.placements[custom.placements.size() - 1]
	dug[CustomHole.NODES] = [Vector3(0.0, -2.0, -20.0), Vector3(0.0, -2.0, -44.0)]
	dug[CustomHole.BORE] = 3.0
	dug[CustomHole.DONE] = true
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var flow := FakeFlow.new()
	flow.hole = CustomLayout.build(custom)
	player.flow = flow
	player.input = CpuInput.new(player.input_prefix, false)
	player.global_position = (
		Vector3(0.0, -2.0, -32.0) - Vector3.UP * (Player.STAND_HEAD_HEIGHT * 0.5)
	)
	return player


## The part of you that rides down the middle of a bore.
func _ride_point(player: Player) -> Vector3:
	return player.global_position + Vector3.UP * (player.head.position.y * PlayerSwim.TUNNEL_RIDE)


func _swimmer() -> Player:
	var hole := _hole_with_water()
	var patch := _water_patch(hole)
	var at: Vector3 = patch["position"]
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var flow := FakeFlow.new()
	flow.hole = hole
	player.flow = flow
	player.input = CpuInput.new(player.input_prefix, false)
	player.global_position = Vector3(at.x, hole.water_surface_y(at), at.z)
	return player


func _bank_swimmer() -> Player:
	var player := _swimmer()
	var hole: HoleData = player.flow.hole
	player.global_position = _swim_at_bank(hole, _water_patch(hole))
	return player


## Deep enough to tread, close enough that Circle can still reach the shelf.
func _swim_at_bank(hole: HoleData, patch: Dictionary) -> Vector3:
	for margin in [-3.8, -4.2, -4.6, -5.0, -5.4, -5.8]:
		for spot in _around_pond(patch, margin):
			if hole.water_depth_at(spot) < Player.WADE_DEPTH:
				continue
			return Vector3(spot.x, hole.water_surface_y(spot), spot.z)
	fail_test("the pond should have a swimming bank")
	return patch["position"]


func _give_ball(player: Player) -> GolfBall:
	var ball := GolfBall.new()
	var golf := GolfController.new()
	add_child_autofree(ball)
	add_child_autofree(golf)
	golf.ball = ball
	player.golf = golf
	return ball


func _hole_with_water() -> HoleData:
	for extra in 24:
		for index in 9:
			var hole := HoleGenerator.generate(index, SEED + extra * 17)
			if hole.is_setpiece():
				continue
			if _water_patch(hole) != {}:
				return hole
	fail_test("a later hole should still roll a swimming pond")
	return HoleGenerator.generate(3, SEED)


func _water_patch(hole: HoleData) -> Dictionary:
	for patch in hole.patches:
		if patch["type"] == Surface.Type.WATER:
			return patch
	return {}


func _on_a_jump(hole: HoleData, spot: Vector3) -> bool:
	for jump in hole.jumps:
		if JumpRamp.contains(jump, spot):
			return true
	return false


## Points spread over the pond's interior, out to the given fraction of its size.
func _across_pond(patch: Dictionary, spread: float) -> Array[Vector3]:
	var size: Vector2 = patch["size"]
	var points: Array[Vector3] = []
	for iz in 3:
		for ix in 3:
			points.append(_on_pond(patch, Vector2(
				lerpf(-1.0, 1.0, float(ix) * 0.5) * size.x * 0.5 * spread,
				lerpf(-1.0, 1.0, float(iz) * 0.5) * size.y * 0.5 * spread
			)))
	return points


## Points around the pond's rim, pushed that many metres outward. A negative
## margin walks the same ring inside the water instead.
func _around_pond(patch: Dictionary, margin: float) -> Array[Vector3]:
	var size: Vector2 = patch["size"]
	var half := Vector2(size.x * 0.5 + margin, size.y * 0.5 + margin)
	var points: Array[Vector3] = []
	for i in 12:
		var angle := TAU * float(i) / 12.0
		var dir := Vector2(cos(angle), sin(angle))
		# Where that heading leaves the rectangle, not a circle inside it.
		var reach := 1.0 / maxf(absf(dir.x) / half.x, absf(dir.y) / half.y)
		points.append(_on_pond(patch, dir * reach))
	return points


func _painted_mesh(node: SurfacePatch) -> MeshInstance3D:
	for child in node.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node != null:
			return mesh_node
	fail_test("a surface patch should paint a mesh")
	return MeshInstance3D.new()


func _on_pond(patch: Dictionary, local: Vector2) -> Vector3:
	var center: Vector3 = patch["position"]
	var offset := Vector3(local.x, 0.0, local.y).rotated(
		Vector3.UP, deg_to_rad(patch["yaw"])
	)
	return Vector3(center.x + offset.x, 0.0, center.z + offset.z)
