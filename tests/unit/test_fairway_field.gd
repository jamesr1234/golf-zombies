extends GutTest
## The fairway lip is an invisible wall. Play stays on the landing strip.

const SEED := 20260816
const FLASH_WAIT := 0.35
const _Field := preload("res://scripts/course/fairway_field.gd")
const _Boost := preload("res://scripts/course/cart_path_boost.gd")


func test_a_built_hole_has_the_field() -> void:
	var root := _hole(0)
	var field := root.find_child("FairwayField", true, false) as StaticBody3D
	assert_not_null(field)
	assert_eq(field.collision_layer, Layers.FORCEFIELD)
	assert_true(field.is_in_group(_Field.GROUP))


func test_the_masks_keep_shots_clear() -> void:
	assert_eq(Layers.BALL_MASK & Layers.FORCEFIELD, Layers.FORCEFIELD)
	assert_eq(Layers.PLAYER_MASK & Layers.FORCEFIELD, Layers.FORCEFIELD)
	assert_eq(Layers.ZOMBIE_MASK & Layers.FORCEFIELD, Layers.FORCEFIELD)
	assert_eq(Layers.VEHICLE_MASK & Layers.FORCEFIELD, Layers.FORCEFIELD)
	assert_eq(Layers.BULLET_MASK & Layers.FORCEFIELD, 0, "you still shoot through the lip")


func test_a_side_ray_hits_and_the_fairway_stays_open() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	await wait_physics_frames(2)
	var mid := HoleGenerator.point_along(data, 0.5) + Vector3.UP * 2.0
	var right := _right(data, 0.5)
	var half := HoleGenerator.fairway_width(data.par) * 0.5
	var space := root.get_world_3d().direct_space_state
	var side := PhysicsRayQueryParameters3D.create(mid, mid + right * (half + 4.0))
	side.collision_mask = Layers.FORCEFIELD
	assert_false(space.intersect_ray(side).is_empty(), "the lip has to catch a run into the rough")
	var along := PhysicsRayQueryParameters3D.create(
		HoleGenerator.point_along(data, 0.35) + Vector3.UP * 2.0,
		HoleGenerator.point_along(data, 0.65) + Vector3.UP * 2.0
	)
	along.collision_mask = Layers.FORCEFIELD
	assert_true(space.intersect_ray(along).is_empty(), "the landing strip stays open")


func test_a_high_shot_still_hits_the_lip() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	await wait_physics_frames(2)
	var apex := Shot.apex_height(1.0, Shot.LOFT_BIAS_MAX) + 4.0
	var high := HoleGenerator.point_along(data, 0.5) + Vector3.UP * apex
	var right := _right(data, 0.5)
	var half := HoleGenerator.fairway_width(data.par) * 0.5
	var side := PhysicsRayQueryParameters3D.create(high, high + right * (half + 4.0))
	side.collision_mask = Layers.FORCEFIELD
	assert_false(
		root.get_world_3d().direct_space_state.intersect_ray(side).is_empty(),
		"a flop cannot clear the lip into the rough"
	)


func test_pulse_raises_then_fades_the_hit() -> void:
	var field := _Field.create(HoleGenerator.generate(0, SEED))
	add_child_autofree(field)
	assert_eq(field.hit_energy(), 0.0, "the pane stays dark until a strike")
	field.pulse(Vector3.ZERO)
	assert_gt(field.hit_energy(), 3.0)
	await wait_seconds(FLASH_WAIT)
	assert_lt(field.hit_energy(), 0.2)


func test_both_lips_have_a_rail() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	await wait_physics_frames(2)
	var mid := HoleGenerator.point_along(data, 0.5) + Vector3.UP * 1.2
	var right := _right(data, 0.5)
	var half := HoleGenerator.fairway_width(data.par, data.index) * 0.5
	var space := root.get_world_3d().direct_space_state
	for side in [-1.0, 1.0]:
		var ray := PhysicsRayQueryParameters3D.create(mid, mid + right * side * (half + 4.0))
		ray.collision_mask = Layers.FORCEFIELD
		assert_false(
			space.intersect_ray(ray).is_empty(),
			"each lip needs a wall, not only the one you ran into last time"
		)


func test_the_lip_is_too_deep_to_cross_in_one_frame() -> void:
	var step := _Boost.SPEED / float(Engine.physics_ticks_per_second)
	assert_gt(
		_Field.HIT_THICK, step * 2.0, "a boosted cart has to be caught, not pass straight through"
	)


func test_the_deeper_lip_grows_into_the_rough_not_the_strip() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	await wait_physics_frames(2)
	var mid := HoleGenerator.point_along(data, 0.5) + Vector3.UP * 2.0
	var right := _right(data, 0.5)
	var half := HoleGenerator.fairway_width(data.par, data.index) * 0.5
	var side := PhysicsRayQueryParameters3D.create(mid, mid + right * (half + 6.0))
	side.collision_mask = Layers.FORCEFIELD
	var hit := root.get_world_3d().direct_space_state.intersect_ray(side)
	assert_false(hit.is_empty(), "the lip still catches a run into the rough")
	var lateral: float = (hit.position - mid).dot(right)
	assert_gt(lateral, half - _Field.THICK, "the extra depth cannot eat into the landing strip")


func test_the_wall_is_taller_than_a_flop() -> void:
	assert_gt(_Field.HEIGHT, Shot.apex_height(1.0, Shot.LOFT_BIAS_MAX) + MountainHole.TOP)


func test_hole_ten_holds_the_wide_lip() -> void:
	var data := HoleGenerator.generate(9, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	await wait_physics_frames(2)
	var mid := HoleGenerator.point_along(data, 0.5) + Vector3.UP * 2.0
	var right := _right(data, 0.5)
	var half := HoleGenerator.fairway_width(data.par, data.index) * 0.5
	var space := root.get_world_3d().direct_space_state
	var side := PhysicsRayQueryParameters3D.create(mid, mid + right * (half + 4.0))
	side.collision_mask = Layers.FORCEFIELD
	assert_false(space.intersect_ray(side).is_empty(), "the wide lip has to catch a run into the rough")
	var inside := PhysicsRayQueryParameters3D.create(mid, mid + right * (half * 0.5))
	inside.collision_mask = Layers.FORCEFIELD
	assert_true(space.intersect_ray(inside).is_empty(), "the double-wide strip stays open")


func test_the_practice_green_and_cart_exit_stay_open() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	await wait_physics_frames(2)
	var space := root.get_world_3d().direct_space_state
	var from_practice := data.practice_center() + Vector3.UP * 2.0
	var to_tee := PhysicsRayQueryParameters3D.create(
		from_practice, data.tee + Vector3.UP * 2.0
	)
	to_tee.collision_mask = Layers.FORCEFIELD
	assert_true(space.intersect_ray(to_tee).is_empty(), "warmup still reaches the tee")
	var along := _along(data)
	var exit_at := data.cup + along * (data.green_radius + 2.0) + Vector3.UP * 2.0
	var exit_ray := PhysicsRayQueryParameters3D.create(exit_at, exit_at + along * 12.0)
	exit_ray.collision_mask = Layers.FORCEFIELD
	assert_true(space.intersect_ray(exit_ray).is_empty(), "the cart still leaves past the cup")


func test_the_practice_green_has_side_walls() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	await wait_physics_frames(2)
	var from_practice := data.practice_center() + Vector3.UP * 2.0
	var half := HoleGenerator.fairway_width(data.par, data.index) * 0.5
	var side := PhysicsRayQueryParameters3D.create(
		from_practice, from_practice + _right(data, 0.0) * (half + 4.0)
	)
	side.collision_mask = Layers.FORCEFIELD
	assert_false(
		root.get_world_3d().direct_space_state.intersect_ray(side).is_empty(),
		"warmup cannot walk off into the woods"
	)


func test_a_fast_cart_cannot_hop_the_lip_into_the_rough() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	await wait_physics_frames(2)
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	root.add_child(cart)
	var mid := HoleGenerator.point_along(data, 0.5) + Vector3.UP * 0.4
	var right := _right(data, 0.5)
	cart.place_at(mid, rad_to_deg(atan2(-right.x, -right.z)))
	cart.drive_speed = GolfCart.MAX_SPEED
	cart.velocity = right * GolfCart.MAX_SPEED
	for _i in 90:
		cart._drive(1.0 / 60.0)
	var half := HoleGenerator.fairway_width(data.par, data.index) * 0.5
	var lateral := absf((cart.global_position - mid).dot(right))
	assert_lt(lateral, half + 1.2, "the cart cannot hop the lip into the rough")
	assert_lt(cart.global_position.y, 1.2, "hitting the lip must not leave the cart jammed in the air")
	var exit_at := cart.exit_point(1.0)
	var exit_side := (exit_at - mid).dot(right)
	assert_lt(exit_side, half + 0.8, "hopping out has to land on the strip, not the rough")


func test_hole_ten_cannot_sprint_off_the_strip() -> void:
	var data := HoleGenerator.generate(9, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	await wait_physics_frames(2)
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	body.add_child(shape)
	body.collision_layer = Layers.PLAYER
	body.collision_mask = Layers.PLAYER_MASK
	root.add_child(body)
	body.global_position = data.practice_tee + Vector3.UP * 1.2
	var right := _right(data, 0.0)
	var half := HoleGenerator.fairway_width(data.par, data.index) * 0.5
	for _i in 90:
		body.velocity = right * 8.2
		body.move_and_slide()
	var lateral := absf((body.global_position - data.tee).dot(right))
	assert_lt(lateral, half + 0.8, "a sprint cannot leave the wide lip")


func _hole(index: int) -> Node3D:
	var root := HoleBuilder.build(HoleGenerator.generate(index, SEED))
	add_child_autofree(root)
	return root


func _along(data: HoleData) -> Vector3:
	var step := data.cup - data.tee
	step.y = 0.0
	if step.length_squared() < 0.0001:
		return Vector3.FORWARD
	return step.normalized()


func _right(data: HoleData, t: float) -> Vector3:
	var here := HoleGenerator.point_along(data, t)
	var ahead := HoleGenerator.point_along(data, minf(1.0, t + 0.04))
	var dir := ahead - here
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = _along(data)
	return dir.normalized().cross(Vector3.UP).normalized()
