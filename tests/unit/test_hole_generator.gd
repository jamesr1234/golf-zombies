extends GutTest
## Generated holes have to be repeatable and their par has to match how far the
## single club can actually hit the ball.

const SEED := 20260816


func test_nine_holes_with_a_mixed_par_template() -> void:
	var pars := HoleGenerator.pars()
	assert_eq(pars.size(), 12)
	assert_eq(pars[9], 4, "hole 10 is a double-wide par 4")
	assert_eq(pars[10], 5, "hole 11 is the four-thousand-yard circuit")
	assert_eq(pars[11], 5, "hole 12 is the soccer-goal par 5")
	assert_true(pars.has(3) and pars.has(4) and pars.has(5), "the course needs a mix of pars")


func test_hole_twelve_skips_the_usual_length_band() -> void:
	var hole := HoleGenerator.generate(SoccerHole.INDEX, SEED)
	assert_true(hole.has_soccer_goal())
	assert_almost_eq(hole.length(), SoccerHole.LENGTH, 0.01)
	var band := HoleGenerator.length_range(hole.par)
	assert_gt(hole.length(), band.y, "500 yards is past a normal par 5")


func test_hole_ten_paints_a_double_wide_fairway() -> void:
	var hole := HoleGenerator.generate(9, SEED)
	var wide := HoleGenerator.fairway_width(hole.par, hole.index)
	assert_almost_eq(wide, HoleGenerator.fairway_width(4) * 2.0, 0.01)
	var strips := 0
	for patch in hole.patches:
		if patch["type"] != Surface.Type.FAIRWAY:
			continue
		assert_almost_eq(patch["size"].x, wide, 0.01)
		strips += 1
	assert_gt(strips, 0)


func test_generation_is_deterministic() -> void:
	var first := HoleGenerator.generate(3, SEED)
	var second := HoleGenerator.generate(3, SEED)
	assert_eq(first.par, second.par)
	assert_eq(first.cup, second.cup)
	assert_eq(first.patches.size(), second.patches.size())
	assert_eq(first.props.size(), second.props.size())
	assert_almost_eq(first.green_radius, second.green_radius, 0.0001)


func test_different_seeds_give_different_holes() -> void:
	var first := HoleGenerator.generate(0, SEED)
	var second := HoleGenerator.generate(0, SEED + 1)
	assert_ne(first.cup, second.cup)


func test_par_matches_the_length_of_every_hole() -> void:
	for index in HoleGenerator.pars().size():
		var hole := HoleGenerator.generate(index, SEED)
		if SoccerHole.applies(hole):
			assert_almost_eq(hole.length(), SoccerHole.LENGTH, 0.01)
			assert_eq(hole.par, SoccerHole.PAR)
			continue
		if RaceHole.applies(hole):
			assert_almost_eq(hole.length(), RaceHole.LENGTH, 0.2)
			assert_eq(hole.par, RaceHole.PAR)
			continue
		if ArenaHole.applies(hole):
			assert_almost_eq(hole.length(), ArenaHole.floor_radius(), 0.05)
			assert_eq(hole.par, ArenaHole.PAR)
			continue
		assert_eq(
			HoleGenerator.par_for_length(hole.length()), hole.par,
			"hole %d length does not match its par" % (index + 1)
		)
		var band := HoleGenerator.length_range(hole.par)
		assert_between(hole.length(), band.x, band.y)


func test_par_thresholds_follow_the_club() -> void:
	var carry := Shot.max_carry()
	assert_eq(HoleGenerator.par_for_length(carry * 0.5), 3, "one swing distance is a par three")
	assert_eq(HoleGenerator.par_for_length(carry * 1.5), 4)
	assert_eq(HoleGenerator.par_for_length(carry * 2.4), 5)


func test_the_tee_sign_names_the_hole_and_the_distance() -> void:
	var data := HoleGenerator.generate(0, SEED)
	assert_eq(data.sign_text(), "HOLE 1\n%d m" % data.yardage())
	assert_eq(data.yardage(), roundi(data.length()))
	var hole := HoleBuilder.build(data)
	add_child_autofree(hole)
	var signs := get_tree().get_nodes_in_group("hole_signs")
	assert_eq(signs.size(), 1)
	var sign: Node3D = signs[0]
	var to_tee := sign.position - data.tee
	to_tee.y = 0.0
	assert_between(to_tee.length(), 4.0, 9.0, "beside the tee, not on the hitting area")
	var hole_copy := sign.get_node("HoleCopy") as Label3D
	var yard_copy := sign.get_node("YardCopy") as Label3D
	assert_not_null(hole_copy)
	assert_not_null(yard_copy)
	assert_eq(hole_copy.text, "HOLE 1")
	assert_eq(yard_copy.text, "%d m" % data.yardage())
	assert_false(hole_copy.double_sided, "the back of a Label3D is mirrored")


func test_the_tee_sign_faces_the_tee() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var hole := HoleBuilder.build(data)
	add_child_autofree(hole)
	var sign: Node3D = get_tree().get_nodes_in_group("hole_signs")[0]
	var to_tee := data.tee - sign.global_position
	to_tee.y = 0.0
	var facing := sign.global_transform.basis.z
	facing.y = 0.0
	assert_gt(
		facing.normalized().dot(to_tee.normalized()), 0.85,
		"the board has to face the tee, not the rough"
	)


func test_later_holes_number_their_own_tee_sign() -> void:
	var data := HoleGenerator.generate(2, SEED)
	assert_eq(data.sign_text(), "HOLE 3\n%d m" % data.yardage())
	var hole := HoleBuilder.build(data)
	add_child_autofree(hole)
	var sign: Node3D = get_tree().get_nodes_in_group("hole_signs")[0]
	assert_eq(sign.get_node("HoleCopy").text, "HOLE 3")
	assert_eq(sign.get_node("YardCopy").text, "%d m" % data.yardage())


func test_the_tee_sign_keeps_copy_inside_the_frame() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var hole := HoleBuilder.build(data)
	add_child_autofree(hole)
	await wait_process_frames(2)
	var sign: Node3D = get_tree().get_nodes_in_group("hole_signs")[0]
	for name in ["HoleCopy", "YardCopy"]:
		var copy := sign.get_node(name) as Label3D
		assert_not_null(copy)
		for corner in _aabb_corners(copy):
			assert_true(
				_inside_sign_frame(sign, sign.to_local(corner)),
				"%s spills outside the neon border" % name
			)


func test_the_tee_sign_keeps_hole_and_yardage_apart() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var hole := HoleBuilder.build(data)
	add_child_autofree(hole)
	await wait_process_frames(2)
	var sign: Node3D = get_tree().get_nodes_in_group("hole_signs")[0]
	var hole_copy := sign.get_node("HoleCopy") as Label3D
	var yard_copy := sign.get_node("YardCopy") as Label3D
	var hole_box := _label_aabb_in_sign(sign, hole_copy)
	var yard_box := _label_aabb_in_sign(sign, yard_copy)
	assert_false(hole_box.intersects(yard_box), "hole number and yardage overlap")
	assert_gt(
		yard_box.position.x - hole_box.end.x, TeeSign.COPY_GAP * 0.5,
		"there has to be readable air between the hole number and the yards"
	)


func test_the_tee_sign_shows_a_top_down_of_the_hole() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var hole := HoleBuilder.build(data)
	add_child_autofree(hole)
	var sign: Node3D = get_tree().get_nodes_in_group("hole_signs")[0]
	var plan := sign.get_node("HolePlan") as Node3D
	assert_not_null(plan)
	var tee := plan.get_node("Tee") as Node3D
	var cup := plan.get_node("Cup") as Node3D
	assert_not_null(tee)
	assert_not_null(cup)
	assert_gt(cup.position.y, tee.position.y, "cup sits up-hole, the way you play it")
	assert_true(_inside_sign_frame(sign, tee.position))
	assert_true(_inside_sign_frame(sign, cup.position))
	assert_gt(plan.get_child_count(), 4, "fairway, hazards and the pin all have to show")


func test_tee_and_cup_sit_inside_the_bounds() -> void:
	for index in 9:
		var hole := HoleGenerator.generate(index, SEED)
		assert_true(hole.bounds.has_point(Vector2(hole.tee.x, hole.tee.z)))
		assert_true(hole.bounds.has_point(Vector2(hole.cup.x, hole.cup.z)))


func test_every_hole_has_a_green_and_some_sand() -> void:
	for index in 9:
		var hole := HoleGenerator.generate(index, SEED)
		var greens := 0
		var fringes := 0
		var bunkers := 0
		for patch in hole.patches:
			if patch["type"] == Surface.Type.GREEN:
				greens += 1
			elif patch["type"] == Surface.Type.FRINGE:
				fringes += 1
			elif patch["type"] == Surface.Type.BUNKER:
				bunkers += 1
		assert_eq(greens, 2, "hole %d should have a green and a practice green" % (index + 1))
		assert_eq(fringes, 2, "hole %d should have a collar around each" % (index + 1))
		if hole.is_setpiece() or ArenaHole.applies(hole):
			assert_eq(bunkers, 0, "a set-piece strip has no side sand")
		else:
			assert_gt(bunkers, 0, "hole %d should have sand" % (index + 1))


func test_green_is_centred_on_the_cup() -> void:
	var hole := HoleGenerator.generate(2, SEED)
	var on_the_cup := 0
	for patch in hole.patches:
		if patch["type"] != Surface.Type.GREEN:
			continue
		if (patch["position"] as Vector3).distance_to(hole.cup) < 0.001:
			on_the_cup += 1
	assert_eq(on_the_cup, 1, "the hole green sits on the cup; the practice one does not")
	assert_almost_eq(hole.green_span(), hole.green_radius * 2.0, 0.001)
	assert_between(
		hole.green_radius, HoleGenerator.GREEN_RADIUS_MIN, HoleGenerator.GREEN_RADIUS_MAX
	)


func test_the_fringe_is_a_collar_around_the_green() -> void:
	var hole := HoleGenerator.generate(2, SEED)
	var green_size := Vector2.ZERO
	var fringe_size := Vector2.ZERO
	for patch in hole.patches:
		var at: Vector3 = patch["position"]
		if at.distance_to(hole.cup) > 0.001:
			continue
		if patch["type"] == Surface.Type.GREEN:
			green_size = patch["size"]
		elif patch["type"] == Surface.Type.FRINGE:
			fringe_size = patch["size"]
	assert_gt(fringe_size.x, green_size.x, "the fringe has to sit outside the green")
	assert_almost_eq(
		fringe_size.x * 0.5, hole.green_radius + HoleGenerator.FRINGE_WIDTH, 0.001
	)


func test_every_hole_opens_with_a_practice_green() -> void:
	for index in 9:
		var hole := HoleGenerator.generate(index, SEED)
		var walk := hole.practice_tee.distance_to(hole.tee)
		assert_between(walk, 8.0, 30.0, "hole %d: a walk from the tee, not a hike" % (index + 1))
		assert_almost_eq(
			hole.practice_tee.distance_to(hole.practice_cup), PracticeGreen.PUTT, 0.3,
			"hole %d: the warm-up putt is a fixed length" % (index + 1)
		)
		for point in [hole.practice_tee, hole.practice_cup]:
			assert_true(
				hole.bounds.has_point(Vector2(point.x, point.z)),
				"hole %d: the practice green is out of bounds" % (index + 1)
			)
		assert_lt(
			hole.practice_cup.distance_to(hole.tee), hole.practice_tee.distance_to(hole.tee),
			"hole %d: the practice cup sits toward the real tee" % (index + 1)
		)
		var to_cup := hole.cup - hole.tee
		to_cup.y = 0.0
		var to_practice := hole.practice_center() - hole.tee
		to_practice.y = 0.0
		assert_lt(
			to_practice.dot(to_cup.normalized()), -6.0,
			"hole %d: the practice green sits behind the tee, not beside it" % (index + 1)
		)
		assert_gt(
			HoleGenerator.distance_to_centerline(hole, hole.practice_center()),
			HoleGenerator.fairway_width(hole.par) * 0.5,
			"hole %d: the practice green is standing on the fairway" % (index + 1)
		)
		var on_green := false
		for patch in hole.patches:
			if patch["type"] == Surface.Type.GREEN:
				on_green = on_green or HoleGenerator.patch_covers(patch, hole.practice_cup)
		assert_true(on_green, "hole %d: the practice cup needs green under it" % (index + 1))


func test_the_practice_green_is_flat_and_level_with_the_tee() -> void:
	for index in 9:
		var hole := HoleGenerator.generate(index, SEED)
		var at := hole.practice_center()
		assert_almost_eq(
			hole.height.height_at(at.x + 2.0, at.z), hole.height.height_at(at.x - 2.0, at.z), 0.25,
			"hole %d: a practice putt should roll true" % (index + 1)
		)
		assert_almost_eq(
			hole.height.height_at(at.x, at.z), hole.tee.y, 0.3,
			"hole %d: the warm-up green shares the tee shelf" % (index + 1)
		)


func test_trees_ring_the_hole() -> void:
	var hole := HoleGenerator.generate(0, SEED)
	var trees: Array[Dictionary] = []
	for prop in hole.props:
		if String(prop["kind"]) == "tree":
			trees.append(prop)
	assert_gt(trees.size(), 40, "the hole should sit in woods")
	var left := 0
	var right := 0
	var along := hole.cup - hole.tee
	along.y = 0.0
	along = along.normalized()
	var lateral := along.cross(Vector3.UP).normalized()
	var edge := 0
	for tree in trees:
		var at: Vector3 = tree["position"]
		var side := (at - hole.tee).dot(lateral)
		if side < 0.0:
			left += 1
		else:
			right += 1
		if _near_bounds_edge(hole.bounds, at, 22.0):
			edge += 1
	assert_gt(left, 8, "trees belong on both sides of the hole")
	assert_gt(right, 8)
	assert_gt(edge, 12, "a belt around the bounds so the map does not end in empty grass")


func test_props_keep_the_fairway_clear() -> void:
	var hole := HoleGenerator.generate(5, SEED)
	var clearance := HoleGenerator.fairway_width(hole.par) * 0.5
	for prop in hole.props:
		assert_gt(
			_distance_to_centerline(hole, prop["position"]), clearance,
			"a prop was placed on the fairway"
		)


func test_spawn_points_stay_on_the_map() -> void:
	for index in 12:
		var hole := HoleGenerator.generate(index, SEED)
		assert_gt(hole.spawn_points.size(), 5, "hole %d needs somewhere to spawn" % (index + 1))
		for point in hole.spawn_points:
			assert_true(hole.bounds.has_point(Vector2(point.x, point.z)))


func test_most_spawn_points_sit_on_the_fairway_away_from_the_tee() -> void:
	for index in 12:
		if ArenaHole.applies_index(index):
			continue
		var hole := HoleGenerator.generate(index, SEED)
		var half := hole.fairway_width() * 0.5
		var on_fairway := 0
		for point in hole.spawn_points:
			if HoleGenerator.distance_to_centerline(hole, point) <= half:
				on_fairway += 1
			# The race track folds back, so crow-flies can sit near the tee.
			if not RaceHole.applies_index(index):
				assert_gt(
					point.distance_to(hole.tee), hole.length() * 0.2,
					"hole %d spawned too close to the tee" % (index + 1)
				)
			assert_gt(
				point.distance_to(hole.cup), hole.green_radius,
				"hole %d spawned on the green" % (index + 1)
			)
		assert_gt(
			on_fairway * 2, hole.spawn_points.size(),
			"hole %d should put most zombies on the fairway" % (index + 1)
		)


func test_every_hole_has_gentle_ground() -> void:
	for index in 9:
		var hole := HoleGenerator.generate(index, SEED)
		var relief := hole.height.max_height - hole.height.min_height
		assert_gt(relief, 0.6, "hole %d should not be a slab" % (index + 1))
		if hole.is_setpiece():
			assert_gt(relief, 20.0, "hole %d falls away beside the fairway" % (index + 1))
			continue
		assert_lt(relief, 20.0, "hole %d should still be a golf course" % (index + 1))


func test_the_rough_is_hillier_than_the_fairway() -> void:
	var hole := HoleGenerator.generate(0, SEED)
	var fairway := HoleGenerator.fairway_width(hole.par) * 0.5
	var along := hole.cup - hole.tee
	along.y = 0.0
	along = along.normalized()
	var side := along.cross(Vector3.UP).normalized()
	var fair_min := INF
	var fair_max := -INF
	var rough_min := INF
	var rough_max := -INF
	for i in 16:
		var p: Vector3 = hole.tee.lerp(hole.cup, float(i) / 15.0)
		if _near_water(hole, p):
			continue
		var fair_h := hole.height.height_at(p.x, p.z)
		fair_min = minf(fair_min, fair_h)
		fair_max = maxf(fair_max, fair_h)
		for sign: float in [-1.0, 1.0]:
			var r := p + side * sign * (fairway + 18.0)
			if _near_water(hole, r):
				continue
			var rough_h := hole.height.height_at(r.x, r.z)
			rough_min = minf(rough_min, rough_h)
			rough_max = maxf(rough_max, rough_h)
	assert_gt(
		rough_max - rough_min, (fair_max - fair_min) + 1.2,
		"the mounds should live in the rough, not on the landing strip"
	)


func test_the_fairway_stays_on_the_deck() -> void:
	for index in 9:
		var hole := HoleGenerator.generate(index, SEED)
		if hole.is_setpiece():
			continue
		for i in range(1, hole.centerline.size()):
			var a: Vector3 = hole.centerline[i - 1]
			var b: Vector3 = hole.centerline[i]
			for step in 8:
				var p: Vector3 = a.lerp(b, float(step) / 7.0)
				if _near_water(hole, p) or _near_jump(hole, p):
					continue
				assert_almost_eq(
					hole.height.height_at(p.x, p.z),
					HeightField.DECK,
					0.05,
					"hole %d: the fairway has to stay on the snap deck" % (index + 1)
				)


func test_the_fairway_lip_is_a_slope_not_a_shelf() -> void:
	var hole := HoleGenerator.generate(0, SEED)
	var half := HoleGenerator.fairway_width(hole.par) * 0.5
	var along := hole.cup - hole.tee
	along.y = 0.0
	along = along.normalized()
	var side := along.cross(Vector3.UP).normalized()
	var mid: Vector3 = hole.tee.lerp(hole.cup, 0.5)
	var inside := mid + side * (half - 0.5)
	var outside := mid + side * (half + HeightField.CELL)
	var step := absf(
		hole.height.height_at(outside.x, outside.z)
		- hole.height.height_at(inside.x, inside.z)
	)
	assert_lt(step, 2.0, "the rough has to rise off the deck, not drop off a cliff")


func test_the_tee_and_green_stay_locally_flat() -> void:
	var hole := HoleGenerator.generate(0, SEED)
	var tee_a := hole.height.height_at(hole.tee.x + 2.0, hole.tee.z)
	var tee_b := hole.height.height_at(hole.tee.x - 2.0, hole.tee.z)
	assert_almost_eq(tee_a, HeightField.DECK, 0.05, "you should be able to stand on the tee")
	assert_almost_eq(tee_b, HeightField.DECK, 0.05, "you should be able to stand on the tee")
	var green_a := hole.height.height_at(hole.cup.x + 2.0, hole.cup.z)
	var green_b := hole.height.height_at(hole.cup.x - 2.0, hole.cup.z)
	assert_almost_eq(green_a, HeightField.DECK, 0.05, "the green should not be a ski jump")
	assert_almost_eq(green_b, HeightField.DECK, 0.05, "the green should not be a ski jump")
	var collar := hole.green_radius + HoleGenerator.FRINGE_WIDTH * 0.5
	var fringe_a := hole.height.height_at(hole.cup.x + collar, hole.cup.z)
	var fringe_b := hole.height.height_at(hole.cup.x - collar, hole.cup.z)
	assert_almost_eq(fringe_a, HeightField.DECK, 0.05, "a collar putt should not sit on a slope")
	assert_almost_eq(fringe_b, HeightField.DECK, 0.05, "a collar putt should not sit on a slope")


func test_the_clubhouse_pad_is_flat_and_level_with_the_tee() -> void:
	for index in 9:
		var hole := HoleGenerator.generate(index, SEED)
		var house := ClubhouseBuild.at_exit(hole.practice_tee, hole.cup - hole.tee)
		var yaw := deg_to_rad(ClubhouseBuild.yaw_at_exit(hole.cup - hole.tee))
		var lo := INF
		var hi := -INF
		for local in [
			Vector3.ZERO,
			Vector3(14.0, 0.0, 12.0),
			Vector3(-14.0, 0.0, 12.0),
			Vector3(14.0, 0.0, -12.0),
			Vector3(-14.0, 0.0, -12.0),
			Vector3(0.0, 0.0, ClubhouseBuild.DEPTH * 0.5 - 1.0),
			Vector3(0.0, 0.0, -ClubhouseBuild.DEPTH * 0.5 + 1.0),
		]:
			var offset := local as Vector3
			var at := house + offset.rotated(Vector3.UP, yaw)
			var h := hole.height.height_at(at.x, at.z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			assert_almost_eq(
				h, hole.tee.y, 0.25,
				"hole %d: the hall has to sit on the tee shelf, not a hill" % (index + 1)
			)
		assert_lt(hi - lo, 0.3, "hole %d: no mound inside the clubhouse" % (index + 1))


func test_props_stay_out_of_the_clubhouse() -> void:
	for index in 9:
		var hole := HoleGenerator.generate(index, SEED)
		for prop in hole.props:
			assert_false(
				ClubhouseBuild.covers_exit_ground(
					hole.practice_tee, hole.cup - hole.tee, prop["position"], 2.0
				),
				"hole %d: a %s was planted in the clubhouse" % [index + 1, prop["kind"]]
			)


func test_sampling_the_heightmap_agrees_with_lifted_points() -> void:
	var hole := HoleGenerator.generate(2, SEED)
	assert_almost_eq(hole.height.height_at(hole.tee.x, hole.tee.z), hole.tee.y, 0.2)
	assert_almost_eq(hole.height.height_at(hole.cup.x, hole.cup.z), hole.cup.y, 0.2)


func test_ground_collision_is_a_heightmap_not_a_triangle_soup() -> void:
	var hole := HoleGenerator.generate(0, SEED)
	var body := hole.height.make_body()
	add_child_autofree(body)
	var shape_node := body.get_child(0) as CollisionShape3D
	assert_not_null(shape_node)
	var heightmap := shape_node.shape as HeightMapShape3D
	assert_not_null(heightmap, "capsules hitch on trimesh edges")
	assert_eq(heightmap.map_width, hole.height.width)
	assert_eq(heightmap.map_depth, hole.height.depth)
	assert_almost_eq(shape_node.scale.x, HeightField.CELL, 0.001)
	assert_almost_eq(shape_node.scale.y, HeightField.CELL, 0.001)
	var mid := hole.height.width / 2 + (hole.height.depth / 2) * hole.height.width
	assert_almost_eq(
		heightmap.map_data[mid] * HeightField.CELL,
		hole.height.samples[mid],
		0.001
	)


func test_a_downhill_profile_drops_from_tee_to_cup() -> void:
	assert_gt(
		HeightField.profile_at(0.0, HeightField.Profile.DOWNHILL, 6.0),
		HeightField.profile_at(1.0, HeightField.Profile.DOWNHILL, 6.0)
	)
	assert_lt(
		HeightField.profile_at(0.0, HeightField.Profile.UPHILL, 6.0),
		HeightField.profile_at(1.0, HeightField.Profile.UPHILL, 6.0)
	)
	assert_gt(
		HeightField.profile_at(0.5, HeightField.Profile.RIDGE, 6.0),
		HeightField.profile_at(0.0, HeightField.Profile.RIDGE, 6.0)
	)


func test_par_three_holes_are_straight() -> void:
	var hole := HoleGenerator.generate(5, SEED)
	assert_eq(hole.par, 3)
	assert_eq(hole.centerline.size(), 2, "a par three should not dogleg")


func test_water_hazards_fit_a_swimming_player() -> void:
	var found := 0
	for index in 9:
		var hole := HoleGenerator.generate(index, SEED)
		for patch in hole.patches:
			if patch["type"] != Surface.Type.WATER:
				continue
			found += 1
			var size: Vector2 = patch["size"]
			assert_gte(
				minf(size.x, size.y), HoleGenerator.WATER_MIN_SPAN,
				"a pond has to be at least six players across"
			)
			assert_almost_eq(
				hole.water_depth_at(patch["position"]),
				HeightField.WATER_DEPTH, 0.35,
				"and deep in the middle so you can actually dive"
			)
	assert_gt(found, 0, "the nine-hole template should include a water hazard")


func test_hole_three_is_a_mountain_you_climb_then_jump() -> void:
	var hole := HoleGenerator.generate(2, SEED)
	assert_eq(hole.par, 4)
	assert_true(hole.has_mountain(), "the fairway climbs a mesa")
	assert_true(hole.has_cart_pad(), "carts wait on the summit")
	var peak := hole.height.height_at(hole.mountain.x, hole.mountain.z)
	assert_gt(peak, hole.tee.y + 3.5, "you have to climb, not walk up a mound")
	assert_gt(peak, hole.cup.y + 1.5, "the green sits below the jump")
	assert_gt(
		hole.height.height_at(hole.cart_pad.x, hole.cart_pad.z), hole.tee.y + 3.5,
		"the carts are on top of the mountain"
	)
	var wall := {}
	for prop in hole.props:
		if String(prop.get("kind", "")) == "climb_wall":
			wall = prop
	assert_false(wall.is_empty())
	assert_eq(hole.props.size(), 1, "the strip is the whole map")
	var wall_size: Vector3 = wall["size"]
	assert_almost_eq(wall_size.x, HoleGenerator.fairway_width(hole.par), 0.01)
	assert_almost_eq(wall_size.y, MountainHole.RISE, 0.01)
	assert_almost_eq(
		(wall["position"] as Vector3).y, hole.tee.y, 0.45,
		"the climb wall stands on the tee shelf, not on the summit"
	)
	assert_lt(
		(wall["position"] as Vector3).distance_to(hole.tee), 18.0,
		"the climb starts just past the tee"
	)
	var launch := Shot.velocity(0.0, 0.0, 1.0, Surface.Type.TEE, false)
	var wall_d := Vector2(
		wall["position"].x - hole.tee.x, wall["position"].z - hole.tee.z
	).length()
	var fly_t := wall_d / maxf(Vector2(launch.x, launch.z).length(), 0.01)
	var fly_h := launch.y * fly_t - 0.5 * Shot.GRAVITY * fly_t * fly_t
	assert_lt(fly_h, peak - hole.tee.y, "a drive cannot clear the face")
	assert_eq(hole.jumps.size(), 1)
	assert_lt(
		(hole.jumps[0]["position"] as Vector3).distance_to(hole.mountain),
		(hole.jumps[0]["position"] as Vector3).distance_to(hole.tee),
		"the takeoff is on the mesa, not the tee"
	)
	var water := {}
	for patch in hole.patches:
		if patch["type"] == Surface.Type.WATER:
			water = patch
			break
	assert_false(water.is_empty(), "the jump needs a gap")
	assert_gt(
		(water["position"] as Vector3).distance_to(hole.tee),
		hole.mountain.distance_to(hole.tee) - 8.0,
		"the pond sits past the mountain, in front of the green"
	)
	var jump: Dictionary = hole.jumps[0]
	assert_eq(jump["length"], MountainHole.RAMP_LENGTH)
	var water_along: float = (water["size"] as Vector2).y
	var range := JumpRamp.flight_distance(
		GolfCart.MAX_SPEED,
		jump["angle_deg"],
		JumpRamp.lip_height(jump["length"], jump["angle_deg"]) + MountainHole.RISE
	)
	assert_gt(range, water_along, "a full-speed launch has to clear the water")
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
	assert_false(HoleGenerator.generate(0, SEED).has_mountain())
	assert_false(HoleGenerator.generate(1, SEED).has_mountain())


func test_hole_one_has_no_water_trap() -> void:
	for extra in 6:
		var hole := HoleGenerator.generate(0, SEED + extra * 17)
		assert_eq(hole.index, 0)
		for patch in hole.patches:
			assert_ne(patch["type"], Surface.Type.WATER, "hole 1 stays a dry opener")
		assert_eq(hole.jumps.size(), 0, "no pond means no takeoff ramp")


func _near_bounds_edge(bounds: Rect2, point: Vector3, margin: float) -> bool:
	var p := Vector2(point.x, point.z)
	if not bounds.has_point(p):
		return false
	return (
		p.x - bounds.position.x < margin
		or bounds.end.x - p.x < margin
		or p.y - bounds.position.y < margin
		or bounds.end.y - p.y < margin
	)


func _distance_to_centerline(hole: HoleData, point: Vector3) -> float:
	var closest := INF
	for i in range(1, hole.centerline.size()):
		var on_segment := Geometry3D.get_closest_point_to_segment(
			point, hole.centerline[i - 1], hole.centerline[i]
		)
		closest = minf(closest, point.distance_to(on_segment))
	return closest


func _near_jump(hole: HoleData, point: Vector3) -> bool:
	for jump in hole.jumps:
		if JumpRamp.contains(jump, point):
			return true
	return false


## A pond levels its own bank and drops its own floor, so samples in or beside one
## are not the fairway's real grade.
func _near_water(hole: HoleData, point: Vector3) -> bool:
	for patch in hole.patches:
		if patch["type"] != Surface.Type.WATER:
			continue
		var inflated := patch.duplicate()
		var size: Vector2 = inflated["size"]
		var margin := HeightField.WATER_BANK + HeightField.CELL
		inflated["size"] = size + Vector2(margin, margin) * 2.0
		if HoleGenerator.patch_covers(inflated, point):
			return true
	return false


func _inside_sign_frame(sign: Node3D, local: Vector3) -> bool:
	var half := TeeSign.BOARD * 0.5 - Vector2(TeeSign.INSET, TeeSign.INSET)
	return absf(local.x) <= half.x + 0.01 and absf(local.y - TeeSign.BOARD_Y) <= half.y + 0.01


func _label_aabb_in_sign(sign: Node3D, copy: Label3D) -> AABB:
	return (sign.global_transform.affine_inverse() * copy.global_transform) * copy.get_aabb()


func _aabb_corners(node: Node3D) -> Array[Vector3]:
	var aabb: AABB = node.get_aabb()
	var corners: Array[Vector3] = []
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				corners.append(node.to_global(aabb.position + aabb.size * Vector3(x, y, z)))
	return corners


