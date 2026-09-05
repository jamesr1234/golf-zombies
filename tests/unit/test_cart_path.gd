extends GutTest
## The cart path after a hole-out is a drift circuit, not a 3-second straight.

const SEED := 20260816
const _Gate := preload("res://scripts/course/cart_path_gate.gd")
const _Forest := preload("res://scripts/course/cart_path_forest.gd")
const _Boost := preload("res://scripts/course/cart_path_boost.gd")
const _Windmill := preload("res://scripts/course/cart_path_windmill.gd")


func test_the_circuit_runs_through_a_wide_forest() -> void:
	var path := _path()
	assert_eq(CartPath.PATH_WIDTH, 25.0)
	assert_eq(_Forest.ROAD_WIDTH, CartPath.PATH_WIDTH)
	assert_gt(_Forest.LANE_CLEAR, CartPath.PATH_WIDTH * 0.5)
	assert_not_null(path.find_child("ForestGround", true, false), "the woods need ground")
	assert_gt(_Forest.HALF_WIDTH, 40.0, "room for trees on both sides")
	var trees := get_tree().get_nodes_in_group("forest_trees")
	assert_gt(trees.size(), 40, "the drive should read as woods")
	for tree in trees:
		assert_gt(
			_lane_offset(path, tree.global_position), CartPath.PATH_WIDTH * 0.5,
			"trees stay off the racing line"
		)


func test_the_woods_do_not_rewrite_the_green() -> void:
	var path := _path()
	var data := path.get_meta("hole_data") as HoleData
	assert_true(path.keep_out.has_point(Vector2(data.cup.x, data.cup.z)))
	assert_almost_eq(
		data.height.height_at(data.cup.x, data.cup.z), data.cup.y, 0.25,
		"holing out must not move the green under you"
	)
	assert_lt(
		path.forest_height.height_at(data.cup.x, data.cup.z), data.cup.y - 4.0,
		"forest collision has to sit under the hole, not on top of it"
	)
	for tree in get_tree().get_nodes_in_group("forest_trees"):
		assert_gt(
			Vector2(tree.global_position.x - data.cup.x, tree.global_position.z - data.cup.z).length(),
			18.0,
			"no new trees on the green"
		)


func test_the_path_stays_level() -> void:
	var path := _path()
	var lo := INF
	var hi := -INF
	for point in path.centerline:
		lo = minf(lo, point.y)
		hi = maxf(hi, point.y)
	assert_lt(hi - lo, 0.2, "the clubhouse drive is a flat road, not a hill run")
	var data := path.get_meta("hole_data") as HoleData
	assert_almost_eq(
		path.centerline[0].y, data.height.height_at(path.centerline[0].x, path.centerline[0].z),
		0.4, "the path still meets the hole at the gate"
	)


func test_the_forest_floor_matches_the_road() -> void:
	var path := _path()
	assert_not_null(path.forest_height)
	var mid: Vector3 = path.centerline[path.centerline.size() / 2]
	assert_almost_eq(
		path.forest_height.height_at(mid.x, mid.z), mid.y, 0.8,
		"the woods sit at road height"
	)
	var along: Vector3 = path.centerline[path.centerline.size() / 2 + 1] - mid
	along.y = 0.0
	var right := along.normalized().cross(Vector3.UP).normalized()
	var off := mid + right * 18.0
	assert_almost_eq(
		path.forest_height.height_at(off.x, off.z), mid.y, 0.8,
		"off the tarmac is still flat, not a hillside"
	)


func test_the_clubhouse_plaza_is_a_level_shelf() -> void:
	var path := _path()
	var plaza := ClubhouseBuild.at_tee(path.tee, path.heading)
	var yaw := ClubhouseBuild.yaw_at_tee(path.tee, plaza)
	var lo := INF
	var hi := -INF
	for local in [
		Vector3.ZERO,
		Vector3(14.0, 0.0, 12.0),
		Vector3(-14.0, 0.0, -12.0),
		Vector3(0.0, 0.0, ClubhouseBuild.DEPTH * 0.5 - 1.0),
	]:
		var offset := local as Vector3
		var at := plaza + offset.rotated(Vector3.UP, deg_to_rad(yaw))
		var h := path.forest_height.height_at(at.x, at.z)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		assert_almost_eq(h, path.tee.y, 0.25, "hills cannot sit inside the hall")
	assert_lt(hi - lo, 0.3, "the rooms share one floor height")
	for tree in get_tree().get_nodes_in_group("forest_trees"):
		assert_false(
			ClubhouseBuild.covers_ground(plaza, yaw, tree.global_position, 2.0),
			"a tree was planted in the clubhouse"
		)


func test_trees_are_the_path_boundary() -> void:
	var path := _path()
	await wait_physics_frames(2)
	var lined := 0
	for tree in get_tree().get_nodes_in_group("forest_trees"):
		var offset := _lane_offset(path, tree.global_position)
		if offset > CartPath.PATH_WIDTH * 0.5 and offset < CartPath.PATH_WIDTH * 0.5 + 6.0:
			lined += 1
	assert_gt(lined, 10, "trees close on both sides, not a far fence")
	var mid: Vector3 = path.centerline[path.centerline.size() / 2]
	var along: Vector3 = path.centerline[path.centerline.size() / 2 + 1] - mid
	along.y = 0.0
	var right := along.normalized().cross(Vector3.UP).normalized()
	var space := path.get_world_3d().direct_space_state
	var from := mid + Vector3.UP * 1.2
	var inner := PhysicsRayQueryParameters3D.create(
		from, from + right * (CartPath.PATH_WIDTH * 0.5 + 2.0)
	)
	inner.collision_mask = Layers.FORCEFIELD
	var field := space.intersect_ray(inner)
	assert_false(field.is_empty(), "a forcefield has to catch a run off the tarmac")
	var hit_at: Vector3 = field.position
	assert_lt(
		_lane_offset(path, hit_at), CartPath.PATH_WIDTH * 0.5 + 1.0,
		"the field sits on the lip, not out in the trees"
	)


func test_a_cart_cannot_drive_off_the_tarmac() -> void:
	var path := _path()
	await wait_physics_frames(2)
	var mid: Vector3 = path.centerline[path.centerline.size() / 2]
	var along: Vector3 = path.centerline[path.centerline.size() / 2 + 1] - mid
	along.y = 0.0
	var right := along.normalized().cross(Vector3.UP).normalized()
	var cart: GolfCart = preload("res://scenes/vehicles/golf_cart.tscn").instantiate()
	path.add_child(cart)
	cart.set_physics_process(false)
	cart.place_at(mid + Vector3.UP * 0.4, rad_to_deg(atan2(-right.x, -right.z)))
	cart.drive_speed = _Boost.SPEED
	cart.velocity = right * _Boost.SPEED
	for _i in 90:
		cart._drive(1.0 / 60.0)
	assert_lt(
		_lane_offset(path, cart.global_position), CartPath.PATH_WIDTH * 0.5 + 1.2,
		"the forcefield has to hold a boosted cart on the tarmac"
	)
	assert_lt(cart.global_position.y, mid.y + 2.0, "hitting the field must not launch you into the trees")


func test_a_bend_has_no_hole_in_the_outer_rail() -> void:
	var path := _path()
	await wait_physics_frames(2)
	var space := path.get_world_3d().direct_space_state
	var misses := 0
	var samples := 0
	for i in range(2, path.centerline.size() - 2):
		var prev: Vector3 = path.centerline[i - 1]
		var here: Vector3 = path.centerline[i]
		var nxt: Vector3 = path.centerline[i + 1]
		var incoming := Vector3(here.x - prev.x, 0.0, here.z - prev.z)
		var outgoing := Vector3(nxt.x - here.x, 0.0, nxt.z - here.z)
		if incoming.length_squared() < 0.01 or outgoing.length_squared() < 0.01:
			continue
		incoming = incoming.normalized()
		outgoing = outgoing.normalized()
		if incoming.dot(outgoing) > 0.995:
			continue
		var right := (incoming + outgoing).cross(Vector3.UP)
		if right.length_squared() < 0.0001:
			continue
		right = right.normalized()
		var from := here + Vector3.UP * 1.2
		var ray := PhysicsRayQueryParameters3D.create(
			from, from + right * (CartPath.PATH_WIDTH * 0.5 + 3.0)
		)
		ray.collision_mask = Layers.FORCEFIELD
		samples += 1
		if space.intersect_ray(ray).is_empty():
			misses += 1
	assert_gt(samples, 8, "the circuit has to actually bend")
	assert_eq(misses, 0, "the long side of a bend cannot leave a hole")


func test_a_bend_does_not_grow_teeth() -> void:
	var path := _path()
	await wait_physics_frames(2)
	var space := path.get_world_3d().direct_space_state
	var worst := 0.0
	for i in range(2, path.centerline.size() - 2):
		var prev: Vector3 = path.centerline[i - 1]
		var here: Vector3 = path.centerline[i]
		var nxt: Vector3 = path.centerline[i + 1]
		var incoming := Vector3(here.x - prev.x, 0.0, here.z - prev.z)
		var outgoing := Vector3(nxt.x - here.x, 0.0, nxt.z - here.z)
		if incoming.length_squared() < 0.01 or outgoing.length_squared() < 0.01:
			continue
		incoming = incoming.normalized()
		outgoing = outgoing.normalized()
		if incoming.dot(outgoing) > 0.995:
			continue
		var right := (incoming + outgoing).cross(Vector3.UP)
		if right.length_squared() < 0.0001:
			continue
		right = right.normalized()
		var from := here + Vector3.UP * 1.2
		for side in [-1.0, 1.0]:
			var ray := PhysicsRayQueryParameters3D.create(
				from, from + right * side * (CartPath.PATH_WIDTH * 0.5 + 6.0)
			)
			ray.collision_mask = Layers.FORCEFIELD
			var hit := space.intersect_ray(ray)
			if hit.is_empty():
				continue
			var lip := CartPath.PATH_WIDTH * 0.5
			worst = maxf(worst, absf(_lane_offset(path, hit.position) - lip))
	assert_gt(worst, 0.0, "the circuit has to actually bend")
	assert_lt(worst, 1.1, "a turn field has to follow the lip, not poke into the lane")


func test_strokes_end_where_the_centerline_does() -> void:
	var origin := Vector3(4.0, 0.0, -2.0)
	var heading := Vector3(0.0, 0.0, -1.0)
	var line := CartPathTrack.centerline(origin, heading, 1.5)
	var runs := CartPathTrack.strokes(origin, heading, 1.5)
	assert_gt(runs.size(), 10)
	var last: Dictionary = runs[runs.size() - 1]
	var end: Vector3 = last["b"] if last["kind"] == "line" else last["to"]
	assert_almost_eq(end.x, line[line.size() - 1].x, 0.05)
	assert_almost_eq(end.z, line[line.size() - 1].z, 0.05)
	assert_eq(int(last["kind"] == "arc"), 0, "the last stretch is the straight onto the tee")


func test_a_turn_wall_sits_on_the_circle() -> void:
	var path := _path()
	await wait_physics_frames(2)
	var start: Vector3 = path.centerline[0]
	var heading := path.centerline[1] - start
	heading.y = 0.0
	heading = heading.normalized()
	var origin := start + heading * float(CartPathTrack.LEGS[0][0])
	var radius := float(CartPathTrack.LEGS[0][2])
	var inward := -heading.cross(Vector3.UP).normalized()
	var center := origin + inward * radius
	var on := center + (origin - center).rotated(Vector3.UP, deg_to_rad(36.0))
	var out := Vector3(on.x - center.x, 0.0, on.z - center.z).normalized()
	var from := on + Vector3.UP * 1.2
	var ray := PhysicsRayQueryParameters3D.create(from, from + out * 20.0)
	ray.collision_mask = Layers.FORCEFIELD
	var hit := path.get_world_3d().direct_space_state.intersect_ray(ray)
	assert_false(hit.is_empty(), "the first bend has to have an outer field")
	var reach := Vector2(hit.position.x - center.x, hit.position.z - center.z).length()
	assert_almost_eq(
		reach, radius + CartPath.PATH_WIDTH * 0.5, 0.35,
		"the field has to sit on the circular lip, not a chord"
	)


func test_the_green_is_not_a_crash() -> void:
	var path := _path()
	var data := path.get_meta("hole_data") as HoleData
	assert_false(path.off_path(data.cup + Vector3.UP), "standing on the green is not off-path")
	assert_false(path.off_path(path.tee + Vector3.UP), "the clubhouse plaza is not a crash")
	var mid: Vector3 = path.centerline[path.centerline.size() / 2]
	assert_false(path.off_path(mid + Vector3.UP * 0.4))
	var along: Vector3 = path.centerline[path.centerline.size() / 2 + 1] - mid
	along.y = 0.0
	var right := along.normalized().cross(Vector3.UP).normalized()
	assert_true(path.off_path(mid + right * (CartPath.LANE_LIMIT + 2.0)), "into the trees is a crash")


func test_a_crash_puts_you_back_beside_where_you_left() -> void:
	var path := _path()
	var mid: Vector3 = path.centerline[path.centerline.size() / 2]
	var along: Vector3 = path.centerline[path.centerline.size() / 2 + 1] - mid
	along.y = 0.0
	var right := along.normalized().cross(Vector3.UP).normalized()
	var crash := mid + right * (CartPath.PATH_WIDTH * 0.5 + 8.0)
	var crash_along := CartPathTrack.along(path.centerline, crash)
	var pose := path.reset_from(crash)
	var at: Vector3 = pose["position"]
	assert_lt(_lane_offset(path, at), 1.0, "back on the path, not in the trees")
	assert_almost_eq(
		CartPathTrack.along(path.centerline, at), crash_along, 2.0,
		"on the line next to the crash, not ten metres back"
	)


func test_a_walker_in_the_trees_is_put_back_on_the_line() -> void:
	var path := _path()
	var mid: Vector3 = path.centerline[path.centerline.size() / 2]
	var along: Vector3 = path.centerline[path.centerline.size() / 2 + 1] - mid
	along.y = 0.0
	var right := along.normalized().cross(Vector3.UP).normalized()
	var player: Player = preload("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(player)
	player.global_position = mid + right * (CartPath.PATH_WIDTH * 0.5 + 8.0) + Vector3.UP * 0.9
	var crash_along := CartPathTrack.along(path.centerline, player.global_position)
	assert_true(path.off_path(player.global_position), "standing in the trees is off the path")
	path.tick_crash(player, 0.05)
	assert_lt(_lane_offset(path, player.global_position), 1.5, "you cannot stay in the rough")
	assert_almost_eq(
		CartPathTrack.along(path.centerline, player.global_position),
		crash_along,
		3.0
	)


func test_the_path_has_blue_turbo_lines() -> void:
	var path := _path()
	var pads := get_tree().get_nodes_in_group("transit_boost")
	assert_gt(pads.size(), 8, "the clubhouse drive needs turbo stripes on the tarmac")
	var mid: Vector3 = path.centerline[path.centerline.size() / 2]
	var nearest := INF
	for pad in pads:
		nearest = minf(nearest, pad.global_position.distance_to(mid))
		assert_true(pad.is_in_group("transit_boost"))
	assert_lt(nearest, CartPath.PATH_WIDTH * 0.4, "stripes sit in the lane, not in the trees")
	assert_gt(_Boost.SPEED, 40.0)


func test_the_next_tee_is_a_drive_past_the_cup() -> void:
	var path := _path()
	var data := path.get_meta("hole_data") as HoleData
	var along := data.cup - data.tee
	along.y = 0.0
	along = along.normalized()
	var to_tee := path.tee - data.cup
	to_tee.y = 0.0
	assert_gt(to_tee.length(), 80.0, "the staging tee belongs well beyond the green")
	assert_gt(path.spawn_points.size(), 16, "the road needs a swarm to run over")
	assert_gt(
		get_tree().get_nodes_in_group("transit_arrows").size(), 8,
		"arrows should mark the route"
	)
	assert_not_null(path.find_child("NextTeeBeam", true, false), "the next tee needs a sky marker")


func test_the_clubhouse_arrows_hang_in_the_sky() -> void:
	var path := _path()
	var arrows := get_tree().get_nodes_in_group("transit_arrows")
	assert_gt(arrows.size(), 8)
	for arrow in arrows:
		var ground := CartPathTrack.closest(path.centerline, arrow.position)
		assert_gt(
			arrow.position.y - ground.y, 8.0,
			"above the trees so you can read them from the cart"
		)
		assert_null(_arrow_copy(arrow), "the gate is the label now, not every arrow")


func test_aim_at_looks_ahead_into_a_corner() -> void:
	var points: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 0.0, -20.0),
		Vector3(24.0, 0.0, -20.0),
	]
	var aim := CartPathTrack.aim_at(points, Vector3(0.0, 0.0, -18.0), 16.0)
	assert_gt(aim.x, 6.0, "the racing line has to point into the right-hander")
	assert_lt(aim.z, -18.0)


func test_aim_at_pulls_a_wide_cart_back_onto_the_path() -> void:
	var points: Array[Vector3] = [Vector3.ZERO, Vector3(0.0, 0.0, -40.0)]
	var aim := CartPathTrack.aim_at(points, Vector3(8.0, 0.0, -10.0), 12.0)
	assert_lt(aim.x, 8.0, "slide wide and the stick tugs you back to center")


func test_the_circuit_is_a_long_drift_track() -> void:
	var path := _path()
	assert_gte(CartPathTrack.turn_count(), 6, "corners are what make drifting the fast line")
	assert_gte(
		path.track_length, 12.5 * GolfCart.MAX_SPEED * 0.72,
		"even a hot lap should take about 12 seconds"
	)
	assert_gte(path.centerline.size(), 20)
	var yaw := 0.0
	for i in range(2, path.centerline.size()):
		var a: Vector3 = path.centerline[i - 1] - path.centerline[i - 2]
		var b: Vector3 = path.centerline[i] - path.centerline[i - 1]
		a.y = 0.0
		b.y = 0.0
		if a.length() < 0.4 or b.length() < 0.4:
			continue
		yaw += a.angle_to(b)
	assert_gte(yaw, deg_to_rad(360.0), "the circuit has to bend, not run in a line")


func test_the_cart_can_drive_from_the_green_onto_the_path() -> void:
	var path := _path()
	await wait_physics_frames(2)
	var data := path.get_meta("hole_data") as HoleData
	assert_gt(
		path.centerline[0].distance_to(data.cup), data.green_radius,
		"the tarmac starts after the putting surface"
	)
	assert_lt(
		path.centerline[0].distance_to(data.cup), data.green_radius + 20.0,
		"the path has to pick you up at the green, not at the fence"
	)
	var along: Vector3 = path.centerline[1] - path.centerline[0]
	along.y = 0.0
	along = along.normalized()
	var space := path.get_world_3d().direct_space_state
	var start := data.cup + along * (data.green_radius + 2.0)
	var past: Vector3 = path.centerline[0]
	for point in path.centerline:
		past = point
		if not data.bounds.has_point(Vector2(point.x, point.z)):
			past = point + along * 6.0
			break
	var span := Vector2(past.x - start.x, past.z - start.z).length()
	var steps := maxi(4, int(span / 3.0))
	for i in steps:
		var a := start.lerp(past, float(i) / float(steps))
		var b := start.lerp(past, float(i + 1) / float(steps))
		a.y = data.height.height_at(a.x, a.z) + 1.3
		b.y = data.height.height_at(b.x, b.z) + 1.3
		if not data.bounds.has_point(Vector2(b.x, b.z)):
			b.y = path.forest_height.height_at(b.x, b.z) + 1.3
		var query := PhysicsRayQueryParameters3D.create(a, b)
		query.collision_mask = Layers.PROP | Layers.BARRIER
		var hit := space.intersect_ray(query)
		assert_true(hit.is_empty(), "the cart needs a clear lane from the green to the path")
	var edge: Vector3 = past
	var down := PhysicsRayQueryParameters3D.create(
		edge + Vector3.UP * 8.0, edge + Vector3.DOWN * 16.0
	)
	down.collision_mask = Layers.WORLD
	var floor := space.intersect_ray(down)
	assert_false(floor.is_empty(), "there has to be ground on the path side of the fence")
	assert_gt(
		floor["position"].y, path.centerline[0].y - 2.0,
		"the woods cannot be a pit at the gate"
	)
	var steepest := 0.0
	var prev_h := data.cup.y
	var prev_xz := Vector2(data.cup.x, data.cup.z)
	for i in 24:
		var t := float(i + 1) / 24.0
		var at := data.cup.lerp(path.centerline[0], t)
		var h := data.height.height_at(at.x, at.z)
		var run := prev_xz.distance_to(Vector2(at.x, at.z))
		if run > 0.2:
			steepest = maxf(steepest, absf(atan((h - prev_h) / run)))
		prev_h = h
		prev_xz = Vector2(at.x, at.z)
	assert_lt(
		steepest, deg_to_rad(GolfCart.FLOOR_MAX_DEG),
		"the cart has to climb the exit, not a wall of rough"
	)


func test_the_far_fence_opens_a_gate() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var hole := HoleBuilder.build(data)
	add_child_autofree(hole)
	assert_eq(_barrier_count(hole), 4)
	var along := data.cup - data.tee
	along.y = 0.0
	var path := CartPath.build(
		data.cup, along.normalized(), data.bounds, data.height, hole, data.green_radius
	)
	hole.add_child(path)
	assert_gte(_barrier_count(hole), 5)


func test_the_clubhouse_side_of_the_tee_is_open() -> void:
	var path := _path()
	await wait_physics_frames(2)
	var right := path.heading.cross(Vector3.UP).normalized()
	var space := path.get_world_3d().direct_space_state
	var from := path.tee + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, from + right * 10.0)
	query.collision_mask = Layers.BARRIER
	var hit := space.intersect_ray(query)
	assert_true(hit.is_empty(), "you should be able to walk right off the tee toward the clubhouse")
	var back := PhysicsRayQueryParameters3D.create(from, from + path.heading * 6.0)
	back.collision_mask = Layers.BARRIER
	var cap := space.intersect_ray(back)
	assert_false(cap.is_empty(), "the far end still has a wall so you do not drive off the map")


func test_the_swarm_walks_the_middle_of_the_tarmac() -> void:
	var path := _path()
	assert_gt(path.spawn_points.size(), 16)
	for point in path.spawn_points:
		assert_lt(
			_lane_offset(path, point), 1.2,
			"walkers belong on the racing line, not glued to the wall"
		)


func test_large_windmills_stand_in_the_middle_of_the_circuit() -> void:
	var path := _path()
	var mills := _path_mills(path)
	assert_gte(mills.size(), 2, "the clubhouse drive needs more than one mill")
	assert_eq(_Windmill.PILLAR_COUNT, 4)
	assert_gt(_Windmill.PILLAR_LEN, CartPath.PATH_WIDTH * 0.45, "sails have to sweep the lane")
	assert_gt(_Windmill.TOWER_H, 7.0, "they should read as towers, not posts")
	for mill in mills:
		var along := CartPathTrack.along(path.centerline, mill.position)
		assert_gt(along, 80.0, "not in the gate")
		assert_lt(along, path.track_length - 80.0, "not on the clubhouse plaza")
		assert_lt(
			_lane_offset(path, mill.position), 1.2,
			"the mast sits on the racing line"
		)


func test_every_windmill_mesh_sits_on_a_physics_body() -> void:
	var mill := _Windmill.create(Vector3.ZERO, Vector3.FORWARD)
	add_child_autofree(mill)
	var meshes := mill.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 6, "mast, nacelle, cap, hub, and four sails")
	for mesh in meshes:
		var body := _physics_owner(mesh)
		assert_not_null(body, "%s has to be a collision object" % mill.get_path_to(mesh))
		assert_gt(body.collision_layer & Layers.PROP, 0, "balls and carts have to hit it")
	var rotor := mill.get_node("Rotor") as AnimatableBody3D
	assert_not_null(rotor, "spinning sails need a moving body")


func test_a_windmill_pillar_throws_you_off_then_explodes_a_second_later() -> void:
	var path := _path()
	var mill: Node3D = _path_mills(path)[0]
	var cart := GolfCart.new()
	cart.position = mill.position + Vector3(3.0, 0.4, 0.0)
	cart.drive_speed = 16.0
	assert_true(path.fling_off(cart, mill.position))
	assert_true(path.is_flung(cart))
	assert_true(cart.is_flung())
	assert_eq(cart.drive_speed, 0.0)
	assert_gt(Vector2(cart.velocity.x, cart.velocity.z).length(), 28.0)
	var shove := cart.velocity
	shove.y = 0.0
	var away := cart.position + shove.normalized() * (CartPath.LANE_LIMIT + 4.0)
	assert_true(path.off_path(away), "the shove has to leave the tarmac")
	path.tick_crash(cart, 0.5)
	assert_true(path.is_flung(cart), "still in the air")
	assert_gt(cart.position.distance_to(mill.position), 2.0)
	path.tick_crash(cart, 0.6)
	assert_false(path.is_flung(cart))
	assert_false(cart.is_flung())
	assert_lt(_lane_offset(path, cart.position), 1.5, "back on the path after the blast")
	cart.free()


func test_a_fling_does_not_explode_the_instant_you_leave_the_path() -> void:
	var path := _path()
	var mid: Vector3 = path.centerline[path.centerline.size() / 2]
	var along: Vector3 = path.centerline[path.centerline.size() / 2 + 1] - mid
	along.y = 0.0
	var right := along.normalized().cross(Vector3.UP).normalized()
	var cart := GolfCart.new()
	cart.position = mid + right * (CartPath.LANE_LIMIT + 4.0) + Vector3.UP * 0.4
	assert_true(path.off_path(cart.position))
	path.fling_off(cart, mid)
	path.tick_crash(cart, 0.25)
	assert_true(path.is_flung(cart), "the delayed blast has to wait")
	assert_true(path.off_path(cart.position), "still in the trees for a beat")
	cart.free()


func test_the_track_opens_with_a_clubhouse_gate() -> void:
	var path := _path()
	var gate := path.find_child("ClubhouseGate", true, false) as Node3D
	assert_not_null(gate)
	assert_lt(
		Vector2(gate.position.x - path.centerline[0].x, gate.position.z - path.centerline[0].z).length(),
		1.0,
		"the gantry sits at the mouth of the circuit"
	)
	var copy := gate.get_node_or_null("GateCopy") as Label3D
	assert_not_null(copy)
	assert_eq(copy.text, _Gate.COPY)
	assert_gt(_Gate.PILLAR_H, 8.0, "tall enough to read as an entrance")


func test_the_tarmac_holds_you_the_whole_way() -> void:
	var path := _path()
	await wait_physics_frames(2)
	_assert_solid_lane(path)


func test_a_cheap_online_path_still_holds_you() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var hole := HoleBuilder.build(data)
	add_child_autofree(hole)
	var along := data.cup - data.tee
	along.y = 0.0
	var path := CartPath.build(
		data.cup, along.normalized(), data.bounds, data.height, hole, data.green_radius,
		true, true
	)
	hole.add_child(path)
	await wait_physics_frames(2)
	assert_null(path.find_child("ForestGround", true, false), "cheap woods still skip the heightmap")
	assert_gt(get_tree().get_nodes_in_group("cart_path_deck").size(), 8)
	_assert_solid_lane(path)


func test_a_joining_client_does_not_plant_the_woods_in_one_shot() -> void:
	var data := HoleGenerator.generate(0, SEED)
	var hole := HoleBuilder.build(data)
	add_child_autofree(hole)
	var along := data.cup - data.tee
	along.y = 0.0
	var path := CartPath.build(
		data.cup, along.normalized(), data.bounds, data.height, hole, data.green_radius,
		true, true
	)
	hole.add_child(path)
	assert_null(path.find_child("ForestGround", true, false), "no heightmap on Computer 2")
	assert_eq(get_tree().get_nodes_in_group("forest_trees").size(), 0)
	assert_true(_Forest.busy(path), "the trees are waiting")
	_Forest.step(path)
	var after_one := get_tree().get_nodes_in_group("forest_trees").size()
	assert_gt(after_one, 0)
	assert_lte(after_one, _Forest.CHEAP_BATCH)
	_Forest.flush(path)
	var trees := get_tree().get_nodes_in_group("forest_trees")
	assert_gt(trees.size(), 20, "the drive still reads as woods")
	assert_null(path.find_child("ForestGround", true, false))
	for tree in trees:
		assert_false(tree is StaticBody3D, "cheap trees are looks")
		assert_gt(
			_lane_offset(path, tree.global_position), CartPath.PATH_WIDTH * 0.5,
			"trees stay off the racing line"
		)


func _assert_solid_lane(path: CartPath) -> void:
	var space := path.get_world_3d().direct_space_state
	var step := maxi(1, path.centerline.size() / 16)
	for i in range(0, path.centerline.size(), step):
		var at: Vector3 = path.centerline[i]
		var query := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * 4.0, at + Vector3.DOWN * 8.0
		)
		query.collision_mask = Layers.WORLD
		var hit := space.intersect_ray(query)
		assert_false(hit.is_empty(), "the race path has to hold you at metre %d" % i)
		assert_gt(
			(hit["position"] as Vector3).y, at.y - 1.0,
			"the deck cannot sit in a pit under the tarmac"
		)
	var mid: Vector3 = path.centerline[path.centerline.size() / 2]
	var along: Vector3 = path.centerline[path.centerline.size() / 2 + 1] - mid
	along.y = 0.0
	var right := along.normalized().cross(Vector3.UP).normalized()
	var shoulder := mid + right * (CartPath.PATH_WIDTH * 0.35)
	var side := PhysicsRayQueryParameters3D.create(
		shoulder + Vector3.UP * 4.0, shoulder + Vector3.DOWN * 8.0
	)
	side.collision_mask = Layers.WORLD
	assert_false(
		space.intersect_ray(side).is_empty(),
		"the lane has to be wide enough to stand beside a cart"
	)


func _path() -> CartPath:
	var data := HoleGenerator.generate(0, SEED)
	var hole := HoleBuilder.build(data)
	add_child_autofree(hole)
	var along := data.cup - data.tee
	along.y = 0.0
	var path := CartPath.build(
		data.cup, along.normalized(), data.bounds, data.height, hole, data.green_radius
	)
	path.set_meta("hole_data", data)
	hole.add_child(path)
	return path


func _physics_owner(node: Node) -> PhysicsBody3D:
	var walk := node.get_parent()
	while walk != null:
		if walk is PhysicsBody3D:
			return walk
		walk = walk.get_parent()
	return null


## Hole one also authors a mill on the overlay, so the group is wider than the circuit.
func _path_mills(path: CartPath) -> Array:
	var mills: Array = []
	for child in path.get_children():
		if child.is_in_group("cart_path_windmills"):
			mills.append(child)
	return mills


func _arrow_copy(arrow: Node) -> Label3D:
	for child in arrow.get_children():
		if child is Label3D:
			return child
	return null


func _lane_offset(path: CartPath, point: Vector3) -> float:
	var best := INF
	for i in range(1, path.centerline.size()):
		best = minf(best, _point_to_segment(point, path.centerline[i - 1], path.centerline[i]))
	return best


func _point_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var span := along.length_squared()
	var from := Vector3(point.x - a.x, 0.0, point.z - a.z)
	if span < 0.0001:
		return from.length()
	var t := clampf(from.dot(along) / span, 0.0, 1.0)
	var closest := Vector3(a.x, 0.0, a.z) + along * t
	return Vector2(point.x - closest.x, point.z - closest.z).length()


func _barrier_count(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		var body := child as StaticBody3D
		if body != null and (body.collision_layer & Layers.BARRIER) != 0:
			count += 1
		count += _barrier_count(child)
	return count
