class_name VsCourse
extends Node
## Builds the shared hole and parks players, balls, and the four carts.

const PLAYER_SPREAD := 2.2
const BALL_SPREAD := 1.2
const CART_BACK := 2.0
const CART_SIDE := 8.0
const CART_GAP := 5.5
const CART_COUNT := 4
const _Music := preload("res://scripts/fx/music.gd")

var hole: HoleData
var hole_node: Node3D
var cart_path: CartPath
var clubhouse: Clubhouse
var cart_girl: CartGirl
var shop: Shop

@onready var hole_root: Node3D = $"../HoleRoot"


func rebuild(index: int, seed: int) -> HoleData:
	cart_girl = null
	cart_path = null
	if hole_node != null:
		hole_root.remove_child(hole_node)
		hole_node.queue_free()
		hole_node = null
	hole = HoleGenerator.generate(index, seed)
	hole_node = HoleBuilder.build(hole)
	hole_root.add_child(hole_node)
	HoleBuilder.bake_navigation(hole_node)
	return hole


func along_hole() -> Vector3:
	var forward := hole.cup - hole.tee
	forward.y = 0.0
	return forward.normalized()


func place_players(players: Array[Player]) -> void:
	var n := maxi(1, players.size())
	for player in players:
		if NetSession.is_active() and not player.is_multiplayer_authority():
			continue
		place_player(player, n)


func place_player(player: Player, count: int) -> void:
	if hole == null or player == null:
		return
	var seat := NetSession.seat_for(player.peer_id)
	if seat < 0:
		seat = 0
	var pose := player_pose(seat, count)
	player.spawn_at(pose["at"], pose["yaw"])


func player_pose(seat: int, count: int) -> Dictionary:
	var n := maxi(1, count)
	var forward := along_hole()
	var lateral := forward.cross(Vector3.UP).normalized()
	var yaw := rad_to_deg(atan2(-forward.x, -forward.z))
	var spot := hole.practice_tee + forward * 1.8 + lateral * tee_offset(seat, n)
	return {"at": hole.lift(spot) + Vector3.UP * 0.2, "yaw": yaw}


static func tee_offset(seat: int, count: int) -> float:
	return (float(seat) - float(maxi(1, count) - 1) * 0.5) * PLAYER_SPREAD


func place_balls(balls: Array[GolfBall]) -> void:
	_seat_balls(balls, hole.practice_tee)


## Circle on the tee: every ball lands on the box at once, spaced so they
## do not stack.
func place_tee_balls(balls: Array[GolfBall]) -> void:
	_seat_balls(balls, hole.tee)


func _seat_balls(balls: Array[GolfBall], origin: Vector3) -> void:
	if hole == null:
		return
	var n := maxi(1, balls.size())
	var lateral := along_hole().cross(Vector3.UP).normalized()
	for i in balls.size():
		if balls[i] == null:
			continue
		var seat := NetSession.seat_for(balls[i].owner_peer)
		if seat < 0:
			seat = i
		balls[i].place_at(hole.lift(origin + lateral * ball_offset(seat, n)))
		balls[i].bounds = hole.bounds


static func ball_offset(seat: int, count: int) -> float:
	return (float(seat) - float(maxi(1, count) - 1) * 0.5) * BALL_SPREAD


func place_carts(carts: Array[GolfCart]) -> void:
	if hole == null:
		return
	var forward := along_hole()
	var lateral := forward.cross(Vector3.UP).normalized()
	var yaw := rad_to_deg(atan2(-forward.x, -forward.z))
	for i in carts.size():
		if carts[i] == null:
			continue
		var slot := cart_slot(carts[i], i)
		var spot := hole.tee - forward * CART_BACK + lateral * cart_offset(slot)
		carts[i].place_at(hole.lift(spot) + Vector3.UP * 0.4, yaw)


## Two left of the tee, two right. Inner pair sits at CART_SIDE so nothing
## overlaps the 8 m tee box; the outer pair steps out by CART_GAP.
static func cart_offset(index: int) -> float:
	var wing := -1.0 if index < 2 else 1.0
	return wing * (CART_SIDE + float(index % 2) * CART_GAP)


## Cart0/1 stay left, Cart2/3 stay right, even if the array order differs
## between host and joiner.
static func cart_slot(cart: Node, fallback: int) -> int:
	if cart == null:
		return fallback
	var label := String(cart.name)
	if label.begins_with("Cart"):
		var tail := label.substr(4)
		if tail.is_valid_int():
			return int(tail)
	return fallback


func place_cart_girl() -> void:
	cart_girl = null
	if hole == null or hole_node == null:
		return
	cart_girl = CartGirl.spawn_at_hole(hole)
	hole_node.add_child(cart_girl)
	cart_girl.set_multiplayer_authority(1)
	NetSync.attach_cart_girl(cart_girl)


func aim_practice(sessions: Array) -> void:
	if hole == null:
		return
	for session in sessions:
		var golf := session as GolfController
		if golf == null or golf.ball == null:
			continue
		golf.release()
		golf.setup(golf.ball, hole.practice_cup, PracticeGreen.span())


func aim_play(sessions: Array) -> void:
	if hole == null:
		return
	var balls: Array[GolfBall] = []
	for session in sessions:
		var golf := session as GolfController
		if golf == null or golf.ball == null:
			continue
		golf.release()
		balls.append(golf.ball)
		golf.setup(golf.ball, hole.cup, hole.green_span())
	place_tee_balls(balls)


func begin_transit(carts: Array[GolfCart]) -> CartPath:
	var forward := along_hole()
	cart_path = CartPath.build(
		hole.cup, forward, hole.bounds, hole.height, hole_node, hole.green_radius
	)
	hole_node.add_child(cart_path)
	_open_clubhouse()
	_park_carts_for_transit(carts)
	return cart_path


func _park_carts_for_transit(carts: Array[GolfCart]) -> void:
	var forward := along_hole()
	var lateral := forward.cross(Vector3.UP).normalized()
	var yaw := rad_to_deg(atan2(-forward.x, -forward.z))
	for i in carts.size():
		if carts[i] == null:
			continue
		var slot := cart_slot(carts[i], i)
		var spot := hole.cup - forward * 6.0 + lateral * cart_offset(slot)
		if carts[i].global_position.distance_to(hole.lift(hole.cup)) > 24.0:
			carts[i].place_at(hole.lift(spot) + Vector3.UP * 0.4, yaw)


func _open_clubhouse() -> void:
	shop = Shop.new()
	var forward := along_hole()
	if cart_path != null:
		forward = cart_path.heading
	var tee := hole.lift(hole.cup)
	if cart_path != null:
		tee = cart_path.tee
	var spot := ClubhouseBuild.at_tee(tee, forward)
	clubhouse = Clubhouse.create(spot, ClubhouseBuild.yaw_at_tee(tee, spot))
	hole_node.add_child(clubhouse)


func attach_next_hole(index: int, seed: int, players: Array[Player], carts: Array[GolfCart]) -> void:
	for cart in carts:
		cart.eject_all()
	var snaps := _capture_in_clubhouse(players)
	if clubhouse != null and is_instance_valid(clubhouse) and clubhouse.get_parent() != hole_root:
		clubhouse.get_parent().remove_child(clubhouse)
		hole_root.add_child(clubhouse)
	cart_path = null
	rebuild(index, seed)
	if clubhouse != null and is_instance_valid(clubhouse):
		_place_clubhouse_at_exit()
		_restore_in_clubhouse(players, snaps)
	place_carts(carts)
	place_cart_girl()


func _place_clubhouse_at_exit() -> void:
	var forward := along_hole()
	clubhouse.global_position = ClubhouseBuild.at_exit(hole.practice_tee, forward)
	clubhouse.rotation.y = deg_to_rad(ClubhouseBuild.yaw_at_exit(forward))


func _capture_in_clubhouse(players: Array[Player]) -> Array[Dictionary]:
	var snaps: Array[Dictionary] = []
	if clubhouse == null or not is_instance_valid(clubhouse):
		return snaps
	var house_yaw := clubhouse.rotation.y
	for player in players:
		snaps.append({
			"local": clubhouse.to_local(player.global_position),
			"yaw": player.rotation.y - house_yaw,
		})
	return snaps


func _restore_in_clubhouse(players: Array[Player], snaps: Array[Dictionary]) -> void:
	if clubhouse == null or snaps.is_empty():
		return
	var house_yaw := clubhouse.rotation.y
	for i in mini(players.size(), snaps.size()):
		var local: Vector3 = snaps[i]["local"]
		var yaw := house_yaw + float(snaps[i]["yaw"])
		if not clubhouse.covers_local(local):
			var side := (float(i) - float(players.size() - 1) * 0.5) * 1.4
			local = Vector3(side, 1.2, ClubhouseBuild.DEPTH * 0.5 - 2.8)
			yaw = house_yaw
		players[i].spawn_at(clubhouse.to_global(local), rad_to_deg(yaw))


func close_shop(players: Array[Player]) -> void:
	shop = null
	if clubhouse != null and is_instance_valid(clubhouse):
		clubhouse.queue_free()
	clubhouse = null
	for player in players:
		player.close_shop()
		player.stop_talk()


func leave_to_prep(players: Array[Player]) -> void:
	if clubhouse != null and is_instance_valid(clubhouse):
		clubhouse.open_exit()
	shop = null
	for player in players:
		player.close_shop()
		player.stop_talk()
	if cart_girl == null or not is_instance_valid(cart_girl):
		place_cart_girl()
	aim_practice(_sessions_from(players))
	_Music.play_lounge()


func _sessions_from(players: Array[Player]) -> Array:
	var sessions: Array = []
	for player in players:
		if player.golf != null:
			sessions.append(player.golf)
	return sessions
