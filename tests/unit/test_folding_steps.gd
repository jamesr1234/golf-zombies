extends GutTest
## Stairs with a lever on the landing. Throw it and the steps swing into one
## even slope, too steep to stand on, so everyone below slides back down.

const STEP := 0.05
const _Steps := preload("res://scripts/course/folding_steps.gd")


func before_each() -> void:
	Sfx.clear_log()


func test_it_builds_treads_a_landing_and_a_lever() -> void:
	var stairs := _spawn()
	assert_true(stairs.is_in_group("folding_steps"))
	assert_eq(stairs.collision_layer, Layers.WORLD)
	assert_gt(stairs.step_count(), 8, "the treads are shallow enough to run")
	assert_not_null(stairs.get_node_or_null("Slope"))
	assert_not_null(stairs.get_node_or_null("Landing"))
	assert_not_null(stairs.get_node_or_null("Lever"))
	assert_not_null(stairs.get_node_or_null("Support/Pier"))
	assert_eq(stairs.get_node("Steps").get_child_count(), stairs.step_count())


func test_the_stairs_start_as_stairs_you_can_run_up() -> void:
	var stairs := _spawn()
	assert_false(stairs.is_folded())
	assert_almost_eq(stairs.fold_amount(), 0.0, 0.001)
	assert_lt(
		rad_to_deg(stairs.slope_angle()),
		PlayerMotion.FLOOR_MAX_DEG,
		"the race to the lever has to be winnable on foot"
	)
	assert_almost_eq(stairs.slope_toe().x, 0.0, 0.01, "the stairs start at the toe")


func test_the_lever_folds_them_past_the_walking_limit() -> void:
	var stairs := _spawn()
	var hand := _hand_at(stairs.lever_at())
	assert_true(stairs.can_use(hand))
	stairs.try_toggle(hand)
	assert_true(stairs.is_folded())
	assert_eq(Sfx.last_cue, "steps_fold")
	_settle(stairs)
	assert_almost_eq(stairs.fold_amount(), 1.0, 0.001)
	assert_gt(
		rad_to_deg(stairs.slope_angle()),
		PlayerMotion.FLOOR_MAX_DEG,
		"nobody walks up the folded slope"
	)


func test_the_fold_takes_a_moment_rather_than_a_frame() -> void:
	var stairs := _spawn()
	stairs.try_toggle(_hand_at(stairs.lever_at()))
	stairs._physics_process(STEP)
	assert_gt(stairs.fold_amount(), 0.0)
	assert_lt(stairs.fold_amount(), 1.0)
	assert_gt(rad_to_deg(stairs.slope_angle()), rad_to_deg(stairs.stair_angle()))


func test_folding_pivots_about_the_landing_and_keeps_the_ground() -> void:
	var stairs := _spawn()
	var top := stairs.slope_top()
	stairs.try_toggle(_hand_at(stairs.lever_at()))
	_settle(stairs)
	assert_eq(stairs.slope_top(), top, "the lip of the landing is the hinge")
	var toe := stairs.slope_toe()
	assert_almost_eq(toe.y, 0.0, 0.001, "the slope still lands on the ground")
	assert_gt(toe.x, 0.0, "a steeper slope needs less run")
	assert_lt(toe.x, stairs.run_len())


func test_a_solid_block_sits_under_the_steps() -> void:
	var stairs := _spawn()
	var pier := stairs.get_node("Support/Pier") as CollisionShape3D
	var pier_box := pier.shape as BoxShape3D
	assert_almost_eq(
		pier.position.y + pier_box.size.y * 0.5,
		stairs.rise_len() - _Steps.DECK,
		0.02,
		"the pier meets the landing"
	)
	var at := pier.position
	var pitch := tan(stairs.fold_angle())
	for child in stairs.get_node("Support").get_children():
		var shape := child as CollisionShape3D
		if shape == null:
			continue
		var box := shape.shape as BoxShape3D
		var left := shape.position.x - box.size.x * 0.5
		var top := shape.position.y + box.size.y * 0.5
		var slope_x := stairs.run_len() - (stairs.rise_len() - top) / pitch
		assert_gt(
			left + 0.02,
			slope_x,
			"support stays under the folded slope so the treads can swing"
		)
	stairs.try_toggle(_hand_at(stairs.lever_at()))
	_settle(stairs)
	assert_eq(pier.position, at, "the support does not fold with the treads")


func test_the_landing_holds_still_through_the_fold() -> void:
	var stairs := _spawn()
	var deck := stairs.get_node("Landing") as CollisionShape3D
	var at := deck.position
	stairs.try_toggle(_hand_at(stairs.lever_at()))
	_settle(stairs)
	assert_eq(deck.position, at, "whoever threw the lever keeps their footing")
	assert_almost_eq(
		at.y + _Steps.DECK * 0.5, stairs.rise_len(), 0.001, "the deck is flush with the top step"
	)


func test_the_walking_slab_follows_the_fold() -> void:
	var stairs := _spawn()
	var slope := stairs.get_node("Slope") as CollisionShape3D
	assert_almost_eq(slope.rotation.z, stairs.stair_angle(), 0.001)
	_assert_slab_spans_the_slope(stairs)
	stairs.try_toggle(_hand_at(stairs.lever_at()))
	_settle(stairs)
	assert_almost_eq(slope.rotation.z, stairs.fold_angle(), 0.001)
	_assert_slab_spans_the_slope(stairs)


func test_the_steps_glow_green_to_climb_and_red_once_folded() -> void:
	var stairs := _spawn()
	var lip := stairs.get_node("Steps/Step0/Lip") as MeshInstance3D
	var green := (lip.material_override as StandardMaterial3D).albedo_color
	assert_gt(green.g, green.r, "green says the stairs are yours to run")
	stairs.try_toggle(_hand_at(stairs.lever_at()))
	_settle(stairs)
	var red := (lip.material_override as StandardMaterial3D).albedo_color
	assert_gt(red.r, red.g, "red says the slope is live")
	assert_eq(
		lip.material_override,
		(stairs.get_node("LandingDeck/Lip") as MeshInstance3D).material_override,
		"every lip shares the one material so the whole piece turns together"
	)


func test_the_lever_only_answers_from_the_landing() -> void:
	var stairs := _spawn()
	var hand := _hand_at(stairs.to_global(Vector3(0.0, 0.2, 0.0)))
	assert_false(stairs.can_use(hand), "the lever is at the top, not the toe")
	stairs.try_toggle(hand)
	assert_false(stairs.is_folded())
	assert_eq(Sfx.last_cue, "")


func test_throwing_the_lever_again_puts_the_steps_back() -> void:
	var stairs := _spawn()
	var hand := _hand_at(stairs.lever_at())
	stairs.try_toggle(hand)
	_settle(stairs)
	stairs.try_toggle(hand)
	assert_false(stairs.is_folded())
	assert_eq(Sfx.last_cue, "steps_unfold")
	_settle(stairs)
	assert_almost_eq(stairs.fold_amount(), 0.0, 0.001)
	assert_lt(rad_to_deg(stairs.slope_angle()), PlayerMotion.FLOOR_MAX_DEG)


func test_a_shallow_fold_angle_is_pulled_clear_of_the_floor_limit() -> void:
	var stairs := _spawn()
	stairs.fold_deg = 30.0
	assert_gt(rad_to_deg(stairs.fold_angle()), PlayerMotion.FLOOR_MAX_DEG)


func test_nearest_picks_the_lever_you_are_standing_at() -> void:
	var stairs := _spawn()
	var far := _spawn()
	far.position = Vector3(60.0, 0.0, 0.0)
	var hand := _hand_at(stairs.lever_at())
	assert_eq(_Steps.nearest(hand), stairs)
	assert_null(_Steps.nearest(_hand_at(Vector3(0.0, 40.0, 0.0))))


func test_a_walker_runs_up_the_stairs() -> void:
	var stairs := _spawn()
	var walker := _walker_on(stairs, Vector3(0.5, 1.2, 0.0))
	await _hold_uphill(walker, 90)
	assert_gt(
		walker.global_position.y,
		stairs.rise_len() * 0.6,
		"the stairs have to be climbable or nobody reaches the lever"
	)


func test_a_walker_cannot_hold_the_folded_slope() -> void:
	var stairs := _spawn()
	stairs.sync_folded = true
	_settle(stairs)
	var down := (stairs.slope_toe() - stairs.slope_top()).normalized()
	var walker := _walker_on(stairs, stairs.slope_top() + down * 1.2 + Vector3(0.0, 0.9, 0.0))
	var from := walker.global_position.y
	await _hold_uphill(walker, 60)
	assert_lt(walker.global_position.y, from - 1.0, "the slope sheds anyone who tries to run it")
	assert_false(walker.is_on_floor(), "a slope this steep is never floor")


func test_the_prop_scene_is_placeable_on_an_overlay() -> void:
	var path := "res://scenes/course/props/folding_steps.tscn"
	assert_true(ResourceLoader.exists(path))
	var node: Node = (load(path) as PackedScene).instantiate()
	add_child_autofree(node)
	assert_true(node is FoldingSteps)
	assert_true(node.is_in_group("folding_steps"))


func _spawn() -> FoldingSteps:
	var stairs: FoldingSteps = _Steps.new()
	add_child_autofree(stairs)
	return stairs


## A capsule set up the way PlayerMotion sets the player up, so what it can and
## cannot walk here is what a player can and cannot walk.
func _walker_on(stairs: FoldingSteps, at: Vector3) -> CharacterBody3D:
	var walker := CharacterBody3D.new()
	walker.floor_max_angle = deg_to_rad(PlayerMotion.FLOOR_MAX_DEG)
	walker.floor_snap_length = PlayerMotion.FLOOR_SNAP
	walker.floor_constant_speed = true
	walker.safe_margin = PlayerMotion.SAFE_MARGIN
	walker.collision_layer = Layers.PLAYER
	walker.collision_mask = Layers.WORLD
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	walker.add_child(shape)
	add_child_autofree(walker)
	walker.global_position = stairs.to_global(at)
	return walker


func _hold_uphill(walker: CharacterBody3D, frames: int) -> void:
	for i in frames:
		var delta := walker.get_physics_process_delta_time()
		if not walker.is_on_floor():
			walker.velocity += walker.get_gravity() * delta
		walker.velocity.x = PlayerMotion.SPRINT_SPEED
		walker.move_and_slide()
		await wait_physics_frames(1)


func _hand_at(at: Vector3) -> Node3D:
	var hand := Node3D.new()
	add_child_autofree(hand)
	hand.global_position = at
	return hand


## The slab runs from the toe to the lip and no further, so nothing of it is
## left buried in the ground once the slope steepens.
func _assert_slab_spans_the_slope(stairs: FoldingSteps) -> void:
	var slope := stairs.get_node("Slope") as CollisionShape3D
	var box := slope.shape as BoxShape3D
	var along := Vector3(cos(slope.rotation.z), sin(slope.rotation.z), 0.0)
	var head := slope.position + along * (box.size.x * 0.5)
	var toe := slope.position - along * (box.size.x * 0.5)
	assert_almost_eq(head.distance_to(stairs.slope_top()), box.size.y * 0.5, 0.01)
	assert_almost_eq(toe.distance_to(stairs.slope_toe()), box.size.y * 0.5, 0.01)


func _settle(stairs: FoldingSteps) -> void:
	for i in 40:
		stairs._physics_process(STEP)
