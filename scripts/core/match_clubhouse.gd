class_name MatchClubhouse
extends RefCounted
## Clubhouse doors, transit path, and the attach/restore dance between holes.
## MatchFlow still owns phase and score; this only moves the scenery.

const _Music := preload("res://scripts/fx/music.gd")


func leave(flow: MatchFlow) -> void:
	if flow.finished:
		return
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
	flow._rally_cpus()
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
	flow.phase = MatchFlow.Phase.SHOP
	flow.spawner.stop()
	flow.spawner.clear_zombies()
	if flow.cart_path != null:
		flow.cart_path.hide_arrows()
	if flow.clubhouse != null:
		flow.clubhouse.open_doors()
	flow._cover_fade()
	attach_next_hole(flow)
	flow._reveal_fade()
	flow.scorecard_changed.emit()
	_Music.enter_clubhouse()


func begin_transit(flow: MatchFlow) -> void:
	flow._close_shop()
	flow.phase = MatchFlow.Phase.TRANSIT
	var forward := flow._along_hole()
	flow.cart_path = CartPath.build(
		flow.hole.cup, forward, flow.hole.bounds, flow.hole.height, flow._hole_node, flow.hole.green_radius
	)
	flow._hole_node.add_child(flow.cart_path)
	open_clubhouse(flow)
	flow.spawner.begin_transit(flow.score.hole_index, flow.cart_path.spawn_points)
	flow.scorecard_changed.emit()
	flow._flash_message(
		"Next tee",
		"Follow the arrows through the gate and run them down.\nOpen the clubhouse doors when you arrive."
	)


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


func attach_next_hole(flow: MatchFlow) -> void:
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


func place_at_exit(flow: MatchFlow) -> void:
	var forward := flow._along_hole()
	flow.clubhouse.global_position = ClubhouseBuild.at_exit(flow.hole.practice_tee, forward)
	flow.clubhouse.rotation.y = deg_to_rad(ClubhouseBuild.yaw_at_exit(forward))


func capture_in_clubhouse(flow: MatchFlow) -> Array[Dictionary]:
	var snaps: Array[Dictionary] = []
	if flow.clubhouse == null or not is_instance_valid(flow.clubhouse):
		return snaps
	var house_yaw := flow.clubhouse.rotation.y
	for player in flow._players:
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
	for i in mini(flow._players.size(), snaps.size()):
		var local: Vector3 = snaps[i]["local"]
		var yaw := house_yaw + float(snaps[i]["yaw"])
		if not flow.clubhouse.covers_local(local):
			var side := -1.0 if i == 0 else 1.0
			local = Vector3(side * 1.4, 1.2, ClubhouseBuild.DEPTH * 0.5 - 2.8)
			yaw = house_yaw
		flow._players[i].spawn_at(flow.clubhouse.to_global(local), rad_to_deg(yaw))
