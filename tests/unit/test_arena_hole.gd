extends GutTest
## Hole 5 is a sealed survival pit. Last team standing scores; there is no cup.

const SEED := 20260816


func test_hole_five_is_the_arena() -> void:
	var hole := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	assert_true(ArenaHole.applies(hole))
	assert_eq(hole.par, ArenaHole.PAR)
	assert_almost_eq(hole.length(), ArenaHole.floor_radius(), 0.05)
	assert_eq(hole.label(), "Hole 5  Arena")
	assert_eq(hole.banner_title(), "Hole 5   Arena")
	assert_eq(hole.sign_text(), "HOLE 5\nArena")
	assert_eq(hole.yardage_label(), "Arena")
	assert_eq(ArenaHole.WARMUP, "Pick two guns.\nThe round starts when everyone has chosen.")


func test_last_standing_pays_under_par() -> void:
	assert_eq(ArenaHole.strokes_for_place(4, 0), 1)
	assert_eq(ArenaHole.strokes_for_place(4, 1), 2)
	assert_eq(ArenaHole.strokes_for_place(4, 2), 3)
	assert_eq(ArenaHole.strokes_for_place(4, 3), 4)
	assert_eq(ArenaHole.strokes_for_place(4, 7), 4)


func test_the_pit_is_a_round_fairway() -> void:
	var hole := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	var disks := 0
	for patch in hole.patches:
		if patch["type"] != Surface.Type.FAIRWAY:
			continue
		assert_true(patch["round"], "the pit has to be a disk, not a strip")
		assert_almost_eq(patch["size"].x, ArenaHole.floor_radius() * 2.0, 0.05)
		assert_almost_eq(
			(patch["position"] as Vector3).distance_to(hole.cup), 0.0, 0.1
		)
		disks += 1
	assert_eq(disks, 1)
	assert_eq(hole.green_radius, ArenaHole.GREEN_RADIUS)
	assert_eq(hole.spawn_points.size(), ArenaHole.SIDES, "zombies climb the inner rim")
	for point in hole.spawn_points:
		assert_almost_eq(
			Vector2(point.x, point.z).distance_to(Vector2(hole.cup.x, hole.cup.z)),
			ArenaHole.floor_radius() * ArenaHole.SPAWN_RING,
			0.2
		)


func test_the_arena_skips_woods_and_side_props() -> void:
	var hole := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	assert_eq(hole.props.size(), 0, "the pit is empty except for the stands")


func test_the_pit_and_stands_sit_on_the_deck() -> void:
	var hole := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	assert_almost_eq(hole.tee.y, HeightField.DECK, 0.05)
	assert_almost_eq(hole.cup.y, HeightField.DECK, 0.05)
	var reach := ArenaHole.floor_radius() + ArenaHole.STAND_DEPTH * 0.5
	var along := (hole.cup - hole.tee).normalized()
	var side := along.cross(Vector3.UP).normalized()
	var rim: Vector3 = hole.cup + side * reach
	assert_almost_eq(
		hole.height.height_at(rim.x, rim.z), HeightField.DECK, 0.05,
		"the stands have to snap flush with the pit"
	)


func test_the_built_hole_is_a_sealed_bowl() -> void:
	var data := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	assert_null(root.find_child("FairwayField", true, false), "a linear lip would cut the pit")
	assert_eq(root.find_children("*", "Cup", true, false).size(), 0, "there is no hole")
	assert_null(root.find_child("PracticeGreen", true, false))
	var arena := root.find_child(ArenaBuild.ROOT_NAME, true, false)
	assert_not_null(arena)
	assert_null(arena.find_child("Gate", true, false), "the bowl stays sealed until the round ends")
	var steps := 0
	var walls := 0
	for node in arena.get_children():
		var path := String(node.get("scene_file_path"))
		if path.contains("steps_"):
			steps += 1
		elif path.contains("wall_"):
			walls += 1
	assert_eq(
		steps, (ArenaHole.SIDES - ArenaHole.GATE_BAYS) * 3,
		"the leave bays stay on the deck so the cart is not climbing stairs"
	)
	assert_eq(walls, ArenaHole.SIDES)
	assert_not_null(arena.find_child("Scoreboard", true, false))
	var crowd := get_tree().get_nodes_in_group(ArenaBuild.CROWD_GROUP)
	assert_between(crowd.size(), 50, 80)
	for npc in crowd:
		var sit := npc as Node3D
		assert_not_null(sit)
		assert_eq(sit.process_mode, Node.PROCESS_MODE_DISABLED)
		var to_cup := data.cup - sit.global_position
		to_cup.y = 0.0
		var facing := -sit.global_transform.basis.z
		facing.y = 0.0
		assert_gt(
			facing.normalized().dot(to_cup.normalized()), 0.7,
			"the crowd has to face the pit"
		)
		var body := sit.get_child(0) as PlayerBody
		assert_not_null(body)
		assert_almost_eq(body.hips.position.y, PlayerBody.SIT_HIP_HEIGHT, 0.01)


func test_every_weapon_is_on_the_floor() -> void:
	var data := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	var guns := root.find_children("*", "GunPickup", true, false)
	assert_eq(guns.size(), ArenaHole.WEAPONS.size())
	var along := data.cup - data.tee
	along.y = 0.0
	along = along.normalized()
	var across := along.cross(Vector3.UP).normalized()
	var seen: PackedStringArray = []
	var slots: Array[float] = []
	for node in guns:
		var pickup := node as GunPickup
		assert_not_null(pickup.stats)
		assert_true(pickup.laid_out)
		assert_false(seen.has(pickup.stats.resource_path), "each gun is unique")
		seen.append(pickup.stats.resource_path)
		var rel: Vector3 = pickup.position - data.cup
		rel.y = 0.0
		assert_almost_eq(rel.dot(along), ArenaHole.WEAPON_ROW, 0.2, "laid out in a row")
		slots.append(rel.dot(across))
		assert_almost_eq(
			pickup.position.y, data.cup.y + ArenaHole.WEAPON_REST, 0.05,
			"the guns sit on the pit floor"
		)
	slots.sort()
	assert_almost_eq(slots[1] - slots[0], ArenaHole.WEAPON_GAP, 0.05)
	for path in ArenaHole.WEAPONS:
		assert_true(seen.has(path), path)


func test_the_gate_faces_the_cart_path() -> void:
	var hole := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	var along := hole.cup - hole.tee
	along.y = 0.0
	along = along.normalized()
	var theta := float(ArenaHole.gate_center()) * TAU / float(ArenaHole.SIDES)
	var outward := Vector3(sin(theta), 0.0, cos(theta))
	assert_gt(outward.dot(along), 0.9, "the gap has to point down the hole")
	var opened := 0
	for side in ArenaHole.SIDES:
		if ArenaHole.is_gate_side(side):
			opened += 1
	assert_eq(opened, ArenaHole.GATE_BAYS)


func test_the_leave_lane_is_even_for_the_cart() -> void:
	var data := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	var along := data.cup - data.tee
	along.y = 0.0
	along = along.normalized()
	var side := along.cross(Vector3.UP).normalized()
	var deck := data.height.height_at(data.cup.x, data.cup.z)
	var far := maxf(data.bounds.size.x, data.bounds.size.y) * 0.5
	for d in range(0, int(far), 4):
		for offset in [-CartPath.PATH_WIDTH * 0.5, 0.0, CartPath.PATH_WIDTH * 0.5]:
			var p: Vector3 = data.cup + along * float(d) + side * offset
			if not data.bounds.has_point(Vector2(p.x, p.z)):
				continue
			assert_almost_eq(
				data.height.height_at(p.x, p.z), deck, 0.08,
				"the drive-out cannot step up at %.0f m" % float(d)
			)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	var arena := root.find_child(ArenaBuild.ROOT_NAME, true, false)
	for side_i in ArenaHole.SIDES:
		if not ArenaHole.is_gate_side(side_i):
			continue
		assert_null(arena.find_child("StepsXL_%d" % side_i, true, false))
		assert_null(arena.find_child("StepsL_%d" % side_i, true, false))
		assert_null(arena.find_child("StepsM_%d" % side_i, true, false))
	ArenaBuild.open_exit(root)
	assert_not_null(arena.find_child(ArenaBuild.APRON_NAME, false, false), "a slab has to cover the ridge")
	for child in arena.get_children():
		var node := child as Node3D
		if node == null or node.is_queued_for_deletion():
			continue
		if not String(node.name).begins_with("Steps"):
			continue
		var box := _mesh_aabb(node)
		assert_false(
			_aabb_blocks_leave(box, data.cup, along),
			"%s still ledges the cart path" % node.name
		)


func _aabb_blocks_leave(box: AABB, cup: Vector3, along: Vector3) -> bool:
	if box.size == Vector3.ZERO:
		return false
	var half := CartPath.PATH_WIDTH * 0.5
	for i in 8:
		var corner: Vector3 = box.get_endpoint(i)
		var rel := corner - cup
		rel.y = 0.0
		if rel.dot(along) < ArenaHole.floor_radius() - 2.0:
			continue
		if (rel - along * rel.dot(along)).length() <= half:
			return true
	return false


func _mesh_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var local: AABB = mesh.get_aabb()
		var xf: Transform3D = mesh.global_transform
		for i in 8:
			var corner := xf * local.get_endpoint(i)
			if first:
				box = AABB(corner, Vector3.ZERO)
				first = false
			else:
				box = box.expand(corner)
	return box


func test_opening_the_exit_clears_the_leave_bays() -> void:
	var data := HoleGenerator.generate(ArenaHole.INDEX, SEED)
	var root := HoleBuilder.build(data)
	add_child_autofree(root)
	var arena := root.find_child(ArenaBuild.ROOT_NAME, true, false)
	var center := "Wall_%d" % ArenaHole.gate_center()
	assert_not_null(arena.find_child(center, true, false))
	ArenaBuild.open_exit(root)
	for side in ArenaHole.SIDES:
		var wall := arena.find_child("Wall_%d" % side, true, false)
		assert_not_null(wall)
		if ArenaHole.is_gate_side(side):
			assert_true(wall.is_queued_for_deletion())
			for body in wall.find_children("*", "CollisionObject3D", true, false):
				assert_eq(body.collision_layer, 0, "the gap has to be walkable this frame")
		else:
			assert_false(wall.is_queued_for_deletion())


func test_the_round_waits_until_everyone_has_two_guns() -> void:
	assert_false(ArenaHole.all_armed([]))
	var player: Player = load("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(player)
	assert_false(ArenaHole.all_armed([player]))
	assert_true(player.weapon.add_gun(load("res://resources/weapons/rifle.tres")))
	assert_false(ArenaHole.all_armed([player]), "one gun is not a loadout")
	assert_true(player.weapon.add_gun(load("res://resources/weapons/shotgun.tres")))
	assert_true(ArenaHole.all_armed([player]))


func test_a_third_gun_stays_on_the_floor_until_the_round_starts() -> void:
	var player: Player = load("res://scenes/players/player.tscn").instantiate()
	add_child_autofree(player)
	var hole := HoleData.new()
	hole.index = ArenaHole.INDEX
	var flow := PrepFlow.new()
	flow.hole = hole
	player.flow = flow
	assert_true(player.weapon.add_gun(load("res://resources/weapons/rifle.tres")))
	assert_true(player.weapon.add_gun(load("res://resources/weapons/shotgun.tres")))
	assert_true(ArenaHole.choosing(player))
	assert_false(ArenaHole.can_pick(player))
	assert_false(ArenaHole.needs_gun(player))


func test_a_wipe_stands_you_back_up_for_the_next_hole() -> void:
	var world: Node3D = load("res://scenes/world.tscn").instantiate()
	add_child_autofree(world)
	var flow := world.get_node("MatchFlow") as MatchFlow
	var human := world.get_node("Players/Player2") as Player
	var cpu := world.get_node("Players/Player1") as Player
	flow.starting_hole = 5
	flow.start_in_clubhouse = false
	flow.cpu_drives_at_start = false
	flow.begin()
	await wait_physics_frames(6)
	assert_true(ArenaHole.applies(flow.hole))
	flow.start_play()
	human.health.take_damage(500.0)
	cpu.health.take_damage(500.0)
	assert_false(flow.finished, "a wipe is the hole, not the run")
	assert_true(human.health.is_alive(), "you have to stand up to leave")
	assert_true(cpu.health.is_alive())
	assert_eq(flow.phase, MatchFlow.Phase.TRANSIT)
	assert_eq(flow.score.results[ArenaHole.INDEX], ArenaHole.PAR)
	_assert_leave_gap_open(flow)


func test_a_wipe_during_warmup_still_opens_the_exit() -> void:
	var world: Node3D = load("res://scenes/world.tscn").instantiate()
	add_child_autofree(world)
	var flow := world.get_node("MatchFlow") as MatchFlow
	var human := world.get_node("Players/Player2") as Player
	var cpu := world.get_node("Players/Player1") as Player
	flow.starting_hole = 5
	flow.start_in_clubhouse = false
	flow.cpu_drives_at_start = false
	flow.begin()
	await wait_physics_frames(6)
	assert_eq(flow.phase, MatchFlow.Phase.PREP)
	human.health.take_damage(500.0)
	cpu.health.take_damage(500.0)
	assert_false(flow.finished, "dying in the pit is still just the hole")
	assert_true(human.health.is_alive(), "you have to stand up to leave")
	assert_eq(flow.phase, MatchFlow.Phase.TRANSIT)
	_assert_leave_gap_open(flow)


func _assert_leave_gap_open(flow: MatchFlow) -> void:
	var arena := flow.hole_root.find_child(ArenaBuild.ROOT_NAME, true, false)
	assert_not_null(arena)
	var gate := arena.find_child("Wall_%d" % ArenaHole.gate_center(), true, false)
	assert_not_null(gate)
	assert_true(gate.is_queued_for_deletion(), "the leave-side wall has to open")


class PrepFlow:
	var hole: HoleData
	var phase := 0
