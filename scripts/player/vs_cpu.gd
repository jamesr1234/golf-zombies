class_name VsCpu
extends RefCounted
## Online opponent on the owning peer. Writes an InputGhost so the pawn reads
## Godot Input like a human. Plays its own ball, fights, drives, and leaves shop.

const SHOOT_RANGE := 22.0
const MELEE_RANGE := 2.1
const AIM_OK_DEG := 12.0
const CONTACT_CLICK := 0.05
const CART_END := 16.0
const LOOK_AHEAD := 8.0

var _player: Player
var _ghost: InputGhost
var _shot_power := 0.5


func setup(player: Player, ghost: InputGhost) -> void:
	_player = player
	_ghost = ghost


func tick(_delta: float) -> void:
	if _player == null or _ghost == null:
		return
	if _player.health != null and not _player.health.is_alive():
		return
	if _player.shopping or _player.talking:
		_ghost.tap("interact")
		return
	match _phase():
		VsMatchFlow.Phase.SHOP:
			_shop()
		VsMatchFlow.Phase.TRANSIT:
			_transit()
		_:
			_hole()


func _hole() -> void:
	if _can("can_start_play"):
		_ghost.tap("interact")
		return
	if _play_golf():
		return
	if _phase() == VsMatchFlow.Phase.PREP:
		_walk_toward(_tee())
		return
	_fight()


func _play_golf() -> bool:
	var golf := _player.golf
	if golf == null or golf.ball == null:
		return false
	var ball := golf.ball
	if ball.is_holed() or ball.is_in_play() or ball.is_stowed() or ball.is_closed():
		return false
	if golf.is_golfing(_player):
		_swing(golf)
		return true
	if golf.can_claim(_player):
		_shot_power = CpuBuddy.wanted_power(
			_player.global_position, golf.pin(), Shot.can_putt(ball.current_surface()),
			_club_kit(), golf.green_span
		)
		_ghost.tap("interact")
		return true
	if golf.is_available():
		_walk_toward(ball.global_position)
		_look_at(ball.global_position)
		return true
	return false


func _swing(golf: GolfController) -> void:
	_look_at(golf.pin())
	var meter := golf.meter
	if meter.state == SwingMeter.State.READY:
		_ghost.tap("swing")
	elif meter.state == SwingMeter.State.BACKSWING and meter.value >= _shot_power:
		_ghost.tap("swing")
	elif meter.state == SwingMeter.State.DOWNSWING and meter.value <= CONTACT_CLICK:
		_ghost.tap("swing")


func _transit() -> void:
	if _player.is_driving():
		_drive()
		return
	if _player.is_riding():
		if _near_clubhouse():
			_ghost.tap("interact")
		return
	if _can("can_open_doors"):
		_ghost.tap("interact")
		return
	var cart := _cart()
	if cart != null and cart.can_board(_player):
		_ghost.tap("interact")
		return
	if cart != null:
		_walk_toward(cart.global_position)
		return
	_walk_toward(_tee())


func _drive() -> void:
	if _near_clubhouse():
		_ghost.tap("interact")
		return
	var along := _path_heading()
	_look_at(_player.global_position + along * LOOK_AHEAD)
	_ghost.move = CpuBuddy.local_move(_player.global_transform.basis, along)
	_ghost.hold("shoot")


func _shop() -> void:
	if _can("can_open_exit"):
		_ghost.tap("interact")
		return
	var house := _clubhouse()
	if house != null:
		_walk_toward(house.exit_point())
		return
	_walk_toward(_tee())


func _fight() -> void:
	if _player.weapon != null and _player.weapon.mag() <= 0:
		_ghost.tap("reload")
	var zombie := _nearest_zombie()
	if zombie == null:
		return
	var aim_at := zombie.global_position + Vector3.UP * 1.1
	var yaw_err := CpuBuddy.yaw_error(_player.rotation.y, _player.head.global_position, aim_at)
	var pitch_err := CpuBuddy.pitch_error(_player.head.rotation.x, _player.head.global_position, aim_at)
	_ghost.look = CpuBuddy.look_stick(yaw_err, pitch_err)
	var range := _player.global_position.distance_to(zombie.global_position)
	var on_target := absf(yaw_err) < AIM_OK_DEG and absf(pitch_err) < AIM_OK_DEG
	if on_target and range <= SHOOT_RANGE:
		_ghost.hold("shoot")
	if on_target and range <= MELEE_RANGE:
		_ghost.tap("melee")


func _walk_toward(world_point: Vector3) -> void:
	var dir := world_point - _player.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.04:
		return
	_ghost.move = CpuBuddy.local_move(_player.global_transform.basis, dir.normalized())
	_look_at(world_point)


func _look_at(world_point: Vector3) -> void:
	var from := _player.head.global_position if _player.head != null else _player.global_position
	_ghost.look = CpuBuddy.look_stick(
		CpuBuddy.yaw_error(_player.rotation.y, from, world_point),
		CpuBuddy.pitch_error(_player.head.rotation.x if _player.head != null else 0.0, from, world_point)
	)


func _phase() -> int:
	if _player.flow == null:
		return VsMatchFlow.Phase.PLAYING
	return int(_player.flow.phase)


func _can(method: String) -> bool:
	return _player.flow != null and _player.flow.has_method(method) and _player.flow.call(method, _player)


func _tee() -> Vector3:
	if _player.flow != null and _player.flow.hole != null:
		return _player.flow.hole.tee
	return _player.global_position


func _cart() -> GolfCart:
	if _player.flow != null and _player.flow.has_method("cart_for"):
		return _player.flow.cart_for(_player)
	return _player.cart


func _clubhouse() -> Clubhouse:
	if _player.flow == null or _player.flow.course == null:
		return null
	return _player.flow.course.clubhouse


func _cart_path() -> CartPath:
	if _player.flow == null or _player.flow.course == null:
		return null
	return _player.flow.course.cart_path


func _path_heading() -> Vector3:
	var path := _cart_path()
	if path == null or path.centerline.is_empty():
		var nose := -_player.global_transform.basis.z
		nose.y = 0.0
		return nose.normalized() if nose.length_squared() > 0.0001 else Vector3.FORWARD
	var along := CartPathTrack.along(path.centerline, _player.global_position)
	return CartPathTrack.heading_at(path.centerline, along)


func _near_clubhouse() -> bool:
	var path := _cart_path()
	if path != null:
		return _player.global_position.distance_to(path.tee) < CART_END
	var house := _clubhouse()
	if house != null:
		return _player.global_position.distance_to(house.door_point()) < CART_END
	return false


func _club_kit() -> ClubKit:
	if _player.score != null:
		return _player.score.club_kit()
	return ClubKit.starter()


func _nearest_zombie() -> Zombie:
	if not _player.is_inside_tree():
		return null
	var best: Zombie
	var best_dist := SHOOT_RANGE
	for node in _player.get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null or not is_instance_valid(zombie):
			continue
		var dist := _player.global_position.distance_to(zombie.global_position)
		if dist < best_dist:
			best = zombie
			best_dist = dist
	return best
