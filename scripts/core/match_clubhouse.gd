class_name MatchClubhouse
extends RefCounted
## Clubhouse doors, transit path, and the attach/restore dance between holes.
## MatchFlow still owns phase and score; this only moves the scenery.

const _Music := preload("res://scripts/fx/music.gd")


func leave(flow: MatchFlow) -> void:
	if flow.finished:
		return
	if flow.next_hole != null and is_instance_valid(flow.next_hole_node):
		adopt_planted(flow)
	if flow.hole == null or flow.hole.index != flow.score.hole_index:
		flow.start_hole(flow.score.hole_index)
		return
	if flow.clubhouse != null and is_instance_valid(flow.clubhouse):
		PokerTable.stand_everyone(flow.clubhouse.get_tree())
		flow.clubhouse.open_exit()
	flow.phase = MatchFlow.Phase.PREP
	flow.shop = null
	for player in flow._players:
		player.close_shop()
		player.stop_talk()
	flow._refresh_team()
	flow._sync_cpu_presence()
	if not ArenaHole.applies(flow.hole):
		if flow.cart_girl == null or not is_instance_valid(flow.cart_girl):
			flow._place_cart_girl()
		flow._aim_at_practice()
	flow.scorecard_changed.emit()
	_Music.follow_clubhouse(flow._clubhouse_fade_far())
	flow._update_clubhouse_music()


## First interact at the doors: they open, the swarm is gone, and the next hole
## is already waiting out the back.
func arrive(flow: MatchFlow) -> void:
	if flow.phase != MatchFlow.Phase.TRANSIT:
		return
	flow.skip_preview(false)
	flow.phase = MatchFlow.Phase.SHOP
	flow.spawner.stop()
	flow.spawner.clear_zombies()
	if flow.cart_path != null:
		flow.cart_path.hide_arrows()
	if flow.clubhouse != null:
		flow.clubhouse.open_doors()
	flow._cover_fade()
	if flow.next_hole != null and is_instance_valid(flow.next_hole_node):
		adopt_planted(flow)
	else:
		attach_next_hole(flow)
	flow._reveal_fade()
	flow._sync_cpu_presence()
	flow.scorecard_changed.emit()
	_Music.enter_clubhouse()


func begin_transit(flow: MatchFlow) -> void:
	flow._close_shop()
	flow.phase = MatchFlow.Phase.TRANSIT
	flow._sync_cpu_presence()
	var next_index := flow.score.hole_index if flow.plant_index < 0 else flow.plant_index
	if ArenaHole.applies_index(next_index):
		plant_arena_beside(flow)
		flow.cart_path = null
		flow.scorecard_changed.emit()
		return
	var forward := flow._along_hole()
	var short := not flow.visits_clubhouse()
	flow.cart_path = CartPath.build(
		flow.hole.cup, forward, flow.hole.bounds, flow.hole.height, flow._hole_node,
		flow.hole.green_radius, false, false, short
	)
	flow._hole_node.add_child(flow.cart_path)
	CartPath.open_across(flow._hole_node, flow.cart_path.centerline, flow.hole.height)
	if not short:
		open_clubhouse(flow)
		_hold_clubhouse(flow)
	plant_next(flow)
	flow.spawner.begin_transit(flow.score.hole_index, flow.cart_path.spawn_points)
	flow.scorecard_changed.emit()
	flow.begin_preview()


func park_cart_for_transit(flow: MatchFlow) -> void:
	var cup := flow.hole.lift(flow.hole.cup)
	if flow.cart.global_position.distance_to(cup) <= MatchFlow.CART_RECALL_RANGE:
		return
	var forward := flow._along_hole()
	var lateral := forward.cross(Vector3.UP).normalized()
	var yaw := rad_to_deg(atan2(-forward.x, -forward.z))
	var spot := flow.hole.cup - forward * 6.0 + lateral * 5.5
	flow.cart.place_at(flow.hole.lift(spot) + Vector3.UP * 0.4, yaw)


func place_cart_on_path(flow: MatchFlow) -> void:
	if flow.cart_path == null or flow.cart_path.centerline.size() < 2:
		park_cart_for_transit(flow)
		return
	var a: Vector3 = flow.cart_path.centerline[0]
	var b: Vector3 = flow.cart_path.centerline[1]
	var along := b - a
	along.y = 0.0
	if along.length_squared() < 0.0001:
		along = flow.cart_path.heading
	along = along.normalized()
	var yaw := rad_to_deg(atan2(-along.x, -along.z))
	var spot := a + along * 10.0
	spot.y = a.y
	flow.cart.place_at(spot + Vector3.UP * 0.4, yaw)


func board_cart(flow: MatchFlow) -> void:
	var yaw := rad_to_deg(flow.cart.rotation.y)
	var humans: Array[Player] = []
	var cpus: Array[Player] = []
	for player in flow._players:
		if player == null or not player.is_on_course():
			continue
		if player.is_cpu():
			cpus.append(player)
		else:
			humans.append(player)
	for player in humans + cpus:
		player.spawn_at(flow.cart.global_position + Vector3.UP * 1.0, yaw)
		flow.cart.board(player)


func open_clubhouse(flow: MatchFlow) -> void:
	flow.shop = Shop.new()
	var forward := flow._along_hole()
	if flow.cart_path != null:
		forward = flow.cart_path.heading
	var tee := flow.hole.lift(flow.hole.cup)
	if flow.cart_path != null:
		tee = flow.cart_path.tee
	var spot := ClubhouseBuild.at_tee(tee, forward)
	flow.clubhouse = Clubhouse.create(spot, ClubhouseBuild.yaw_at_tee(tee, spot))
	flow._hole_node.add_child(flow.clubhouse)
	flow.scorecard_changed.emit()


## Hole 5 sits just past the 4th green. No cart path, no staging wall.
func plant_arena_beside(flow: MatchFlow) -> void:
	if flow.next_hole != null and is_instance_valid(flow.next_hole_node):
		return
	if flow.hole == null or flow.score == null:
		return
	var index := flow.score.hole_index if flow.plant_index < 0 else flow.plant_index
	if not ArenaHole.applies_index(index):
		return
	var data := HoleStore.layout(index, flow.course_seed)
	var node := HoleBuilder.build(data)
	var along := flow.hole.cup - flow.hole.tee
	along.y = 0.0
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD
	else:
		along = along.normalized()
	var target := flow.hole.cup + along * (flow.hole.green_radius + 22.0)
	var door_at := data.cup + ArenaHole.leave_along(data) * (
		ArenaHole.floor_radius() + ArenaHole.STAND_DEPTH
	)
	var offset := HoleData.align_offset(door_at, target)
	node.position = offset
	data.shift(offset)
	HoleBuilder.mute_navigation(node)
	flow.hole_root.add_child(node)
	MechSuit.plant_on_hole(node, data)
	CartPath._open_gate(flow._hole_node, flow.hole.cup, along, target)
	flow.next_hole = data
	flow.next_hole_node = node


func plant_next(flow: MatchFlow) -> void:
	if flow.score == null or flow.score.is_course_complete():
		return
	var index := flow.score.hole_index if flow.plant_index < 0 else flow.plant_index
	var data := (
		CustomLayout.build(GameSettings.custom_hole, flow.course_seed) if GameSettings.is_custom()
		else HoleStore.layout(index, flow.course_seed)
	)
	var incoming := Vector3.FORWARD
	var target := flow.hole.cup
	if flow.cart_path != null:
		incoming = flow.cart_path.heading
		target = flow.cart_path.tee
	if flow.clubhouse != null and is_instance_valid(flow.clubhouse):
		incoming = _exit_heading(flow.clubhouse)
		target = flow.clubhouse.global_position + incoming * (
			ClubhouseBuild.DEPTH * 0.5 + ClubhouseBuild.EXIT_GAP
		)
		data.open_tee_end = false
	else:
		data.open_tee_end = true
	var line: Array[Vector3] = []
	if flow.cart_path != null:
		line = flow.cart_path.centerline
	data.pave_for_path(line, incoming, target)
	var node := HoleBuilder.build(data)
	data.face_arrival(node, incoming, target)
	flow.hole_root.add_child(node)
	MechSuit.plant_on_hole(node, data)
	if flow.cart_path != null:
		CartPath.open_across(node, flow.cart_path.centerline, data.height)
	HoleBuilder.bake_navigation(node)
	flow.next_hole = data
	flow.next_hole_node = node


func adopt_planted(flow: MatchFlow) -> void:
	if flow.next_hole == null or not is_instance_valid(flow.next_hole_node):
		return
	_hold_clubhouse(flow)
	var snaps := capture_in_clubhouse(flow)
	var old := flow._hole_node
	flow.hole = flow.next_hole
	flow._hole_node = flow.next_hole_node
	flow.next_hole = null
	flow.next_hole_node = null
	flow._sync_ball_bounds()
	flow.cart_path = null
	flow.cart_girl = null
	if old != null and is_instance_valid(old):
		old.queue_free()
	if ArenaHole.applies(flow.hole):
		HoleBuilder.bake_navigation(flow._hole_node)
	flow.hole_time_left = GameSettings.hole_seconds() + flow.score.take_bonus_seconds()
	flow.freeze_left = flow.score.take_freeze_seconds()
	if flow.clubhouse != null and is_instance_valid(flow.clubhouse):
		restore_in_clubhouse(flow, snaps)
	flow.spawner.clear_zombies()
	flow.spawner.plant_mazes(flow._hole_node)
	flow._sync_loadouts()


func _exit_heading(house: Clubhouse) -> Vector3:
	var incoming := -house.global_transform.basis.z
	incoming.y = 0.0
	if incoming.length_squared() < 0.0001:
		return Vector3.FORWARD
	return incoming.normalized()


func _hold_clubhouse(flow: MatchFlow) -> void:
	if flow.clubhouse == null or not is_instance_valid(flow.clubhouse):
		return
	if flow.clubhouse.get_parent() == flow.hole_root:
		return
	flow.clubhouse.get_parent().remove_child(flow.clubhouse)
	flow.hole_root.add_child(flow.clubhouse)


func attach_next_hole(flow: MatchFlow) -> void:
	if flow.next_hole != null and is_instance_valid(flow.next_hole_node):
		adopt_planted(flow)
		return
	if flow.hole != null and flow.hole.index == flow.score.hole_index:
		return
	if flow.cart != null:
		flow.cart.eject_all()
	var snaps := capture_in_clubhouse(flow)
	if flow.clubhouse != null and is_instance_valid(flow.clubhouse) and flow.clubhouse.get_parent() != flow.hole_root:
		flow.clubhouse.get_parent().remove_child(flow.clubhouse)
		flow.hole_root.add_child(flow.clubhouse)
	flow.cart_path = null
	flow._rebuild_hole(flow.score.hole_index)
	flow.hole_time_left = GameSettings.hole_seconds() + flow.score.take_bonus_seconds()
	flow.freeze_left = flow.score.take_freeze_seconds()
	if flow.clubhouse != null and is_instance_valid(flow.clubhouse):
		place_at_exit(flow)
		restore_in_clubhouse(flow, snaps)
	flow._place_cart()
	flow._place_cart_girl()
	flow.spawner.clear_zombies()
	flow.spawner.plant_mazes(flow._hole_node)
	flow._sync_loadouts()


func place_at_exit(flow: MatchFlow) -> void:
	var forward := flow._along_hole()
	flow.clubhouse.global_position = ClubhouseBuild.at_exit(flow.hole.arrival_point(), forward)
	flow.clubhouse.rotation.y = deg_to_rad(ClubhouseBuild.yaw_at_exit(forward))


func capture_in_clubhouse(flow: MatchFlow) -> Array[Dictionary]:
	var snaps: Array[Dictionary] = []
	if flow.clubhouse == null or not is_instance_valid(flow.clubhouse):
		return snaps
	var house_yaw := flow.clubhouse.rotation.y
	for player in flow._players:
		if player == null or player.brain != null:
			continue
		snaps.append({
			"local": flow.clubhouse.to_local(player.global_position),
			"yaw": player.rotation.y - house_yaw,
		})
	return snaps


func restore_in_clubhouse(flow: MatchFlow, snaps: Array[Dictionary]) -> void:
	if flow.clubhouse == null or not is_instance_valid(flow.clubhouse) or snaps.is_empty():
		return
	flow._refresh_team()
	var house_yaw := flow.clubhouse.rotation.y
	var i := 0
	for player in flow._players:
		if player == null or player.brain != null:
			continue
		if i >= snaps.size():
			break
		var local: Vector3 = snaps[i]["local"]
		var yaw := house_yaw + float(snaps[i]["yaw"])
		if not flow.clubhouse.covers_local(local):
			local = Vector3(-1.4 if i == 0 else 1.4, 1.2, ClubhouseBuild.DEPTH * 0.5 - 2.8)
			yaw = house_yaw
		player.spawn_at(flow.clubhouse.to_global(local), rad_to_deg(yaw))
		i += 1
