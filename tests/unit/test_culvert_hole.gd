extends GutTest
## Hole 2 is a ridge you cannot carry. The cart drives down through a culvert
## and comes back up on the far fairway.

const SEED := 20260816


func test_only_hole_two_has_a_culvert() -> void:
	var hole := HoleGenerator.generate(1, SEED)
	assert_eq(hole.par, 4)
	assert_eq(hole.index, 1)
	assert_true(hole.has_culvert(), "the pipe sits under the ridge")
	assert_true(hole.is_setpiece())
	assert_false(hole.has_mountain())
	assert_false(hole.has_cart_pad(), "carts start at the tee, not a summit pad")
	assert_false(HoleGenerator.generate(0, SEED).has_culvert())
	assert_false(HoleGenerator.generate(2, SEED).has_culvert())


func test_the_ridge_blocks_a_full_drive() -> void:
	var hole := HoleGenerator.generate(1, SEED)
	var peak_at := CulvertHole.ridge_peak_at(hole)
	var peak := hole.height.height_at(peak_at.x, peak_at.z)
	assert_gt(peak, hole.tee.y + 8.0, "the hill is a wall, not a mound")
	var face := HoleGenerator.point_along(
		hole, (CulvertHole.APPROACH + CulvertHole.FACE) / maxf(hole.length(), 80.0)
	)
	var launch := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.TEE, false)
	var face_d := Vector2(face.x - hole.tee.x, face.z - hole.tee.z).length()
	var fly_t := face_d / maxf(Vector2(launch.x, launch.z).length(), 0.01)
	var fly_h := launch.y * fly_t - 0.5 * Shot.GRAVITY * fly_t * fly_t
	assert_lt(fly_h, peak - hole.tee.y, "a drive cannot clear the face")


func test_the_trench_runs_under_the_ridge() -> void:
	var hole := HoleGenerator.generate(1, SEED)
	var floor_h := hole.height.height_at(hole.culvert.x, hole.culvert.z)
	var peak := hole.height.height_at(
		CulvertHole.ridge_peak_at(hole).x, CulvertHole.ridge_peak_at(hole).z
	)
	assert_lt(floor_h, hole.tee.y - 4.0, "the pipe sits underground")
	assert_lt(floor_h, peak - 8.0, "the hill stays over the road")
	assert_almost_eq(hole.culvert.y, floor_h, 0.25, "the culvert stands on the trench floor")


func test_the_mouths_are_a_cart_grade() -> void:
	var hole := HoleGenerator.generate(1, SEED)
	var span := maxf(hole.length(), 80.0)
	_assert_ramp(
		hole,
		HoleGenerator.point_along(hole, CulvertHole.APPROACH / span),
		HoleGenerator.point_along(hole, (CulvertHole.APPROACH + CulvertHole.RAMP) / span)
	)
	_assert_ramp(
		hole,
		HoleGenerator.point_along(
			hole, (CulvertHole.APPROACH + CulvertHole.RAMP + CulvertHole.PIPE) / span
		),
		HoleGenerator.point_along(
			hole,
			(CulvertHole.APPROACH + CulvertHole.RAMP + CulvertHole.PIPE + CulvertHole.RAMP) / span
		)
	)


func test_the_green_comes_back_up_to_the_surface() -> void:
	var hole := HoleGenerator.generate(1, SEED)
	assert_almost_eq(hole.cup.y, hole.tee.y, 1.0, "you come back up onto the green")
	assert_gt(
		hole.cup.y, hole.height.height_at(hole.culvert.x, hole.culvert.z) + 4.0,
		"the pin is not still in the trench"
	)


func test_there_is_no_walk_around() -> void:
	var hole := HoleGenerator.generate(1, SEED)
	var along := hole.cup - hole.tee
	along.y = 0.0
	along = along.normalized()
	var side := along.cross(Vector3.UP).normalized()
	var mid := hole.tee.lerp(hole.cup, 0.45)
	var off := mid + side * (HoleGenerator.fairway_width(hole.par) * 0.5 + 8.0)
	assert_lt(
		hole.height.height_at(off.x, off.z), hole.tee.y - 16.0,
		"the map ends at the fairway"
	)


func test_the_strip_is_just_the_culvert() -> void:
	var hole := HoleGenerator.generate(1, SEED)
	assert_eq(hole.props.size(), 1)
	assert_eq(String(hole.props[0]["kind"]), "culvert")
	assert_eq(hole.jumps.size(), 0)
	var size: Vector3 = hole.props[0]["size"]
	assert_almost_eq(size.x, CulvertHole.WIDTH, 0.01)
	assert_almost_eq(size.y, CulvertHole.HEIGHT, 0.01)
	assert_almost_eq(size.z, CulvertHole.PIPE, 0.01)


func test_the_builder_opens_the_pipe_and_blocks_the_walls() -> void:
	var hole := HoleGenerator.generate(1, SEED)
	var root := HoleBuilder.build(hole)
	add_child_autofree(root)
	var pipes := root.find_children("*", "Culvert", true, false)
	assert_eq(pipes.size(), 1)
	var pipe := pipes[0] as Culvert
	assert_eq(pipe.collision_layer, Layers.WORLD)
	assert_eq(pipe.collision_mask, 0)
	assert_true(pipe.is_in_group("culverts"))
	await wait_physics_frames(2)
	var space := pipe.get_world_3d().direct_space_state
	var origin := pipe.global_position + Vector3.UP * 2.0
	var forward := -pipe.global_transform.basis.z
	var through := PhysicsRayQueryParameters3D.create(
		origin - forward * 12.0, origin + forward * 12.0
	)
	through.collision_mask = Layers.WORLD
	assert_true(space.intersect_ray(through).is_empty(), "the ends stay open")
	var into := PhysicsRayQueryParameters3D.create(
		origin, origin + pipe.global_transform.basis.x * 6.0
	)
	into.collision_mask = Layers.WORLD
	assert_false(space.intersect_ray(into).is_empty(), "the walls are solid")


func test_hole_two_tells_you_to_take_the_pipe() -> void:
	var flow: MatchFlow = autofree(MatchFlow.new())
	assert_true(flow._warmup_copy(1).contains("culvert"))


func _assert_ramp(hole: HoleData, a: Vector3, b: Vector3) -> void:
	var run := Vector2(b.x - a.x, b.z - a.z).length()
	var rise := absf(hole.height.height_at(a.x, a.z) - hole.height.height_at(b.x, b.z))
	var deg := rad_to_deg(atan(rise / maxf(run, 0.01)))
	assert_lt(deg, GolfCart.FLOOR_MAX_DEG, "the cart has to stay stuck to the ground")
	assert_gt(rise, 4.0, "the ramp actually changes height")
