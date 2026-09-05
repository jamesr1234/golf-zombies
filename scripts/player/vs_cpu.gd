class_name VsCpu
extends RefCounted
## Online opponent on the owning peer. Writes an InputGhost so the pawn reads
## Godot Input like a human. Walks or carts to the team ball, dives if it
## finds the water, races the clubhouse circuit, then fights.

const SHOOT_RANGE := 22.0
const MELEE_RANGE := 2.1
const AIM_OK_DEG := 12.0
const CART_END := 16.0
const LOOK_AHEAD := 8.0
const WALK_RANGE := 16.0
const HOP_RANGE := 7.5
const WAIT_RANGE := 5.0

var _player: Player
var _ghost
var _shot_power := 0.5
var _think_left := 0.0
var _address_left := 0.0
var _power_slop := 0.0
var _contact_slop := 0.1
var _aim_slop := Vector3.ZERO
var _lined_up := false
var _rng := RandomNumberGenerator.new()


func setup(player: Player, pad) -> void:
	_player = player
	_ghost = pad
	_rng.seed = hash(player.peer_id if player != null else 0)
	_power_slop = _rng.randf_range(-0.1, 0.14)
	_contact_slop = _rng.randf_range(0.07, 0.18)
	_aim_slop = Vector3(_rng.randf_range(-2.2, 2.2), 0.0, _rng.randf_range(-2.2, 2.2))


func tick(delta: float) -> void:
	if _player == null or _ghost == null:
		return
	if _player.health != null and not _player.health.is_alive():
		return
	if _player.shopping:
		_ghost.tap("swap_gear")
		return
	if _player.talking:
		_ghost.tap("interact")
		return
	match _phase():
		VsMatchFlow.Phase.SHOP:
			_shop()
		VsMatchFlow.Phase.TRANSIT:
			_transit()
		_:
			_hole(delta)


func _hole(delta: float) -> void:
	if _player.partner != null and _player.partner.health != null and _player.partner.health.is_downed():
		_walk_toward(_player.partner.global_position)
		if _player.partner_needs_revive():
			_ghost.hold("revive")
		return
	if _arena_fight(delta):
		return
	if _can("can_retrieve_ball"):
		_ghost.tap("interact")
		return
	if _phase() == VsMatchFlow.Phase.RETRIEVE:
		_go_to_ball(delta)
		return
	if _can("can_start_play") and not _player.cpu_filled:
		_ghost.tap("interact")
		return
	if _go_to_ball(delta):
		return
	if _phase() == VsMatchFlow.Phase.PREP:
		_walk_toward(_tee())
		return
	_fight()


func _go_to_ball(delta: float) -> bool:
	var ball := _ball()
	if ball == null or ball.is_holed() or ball.is_stowed() or ball.is_closed():
		_lined_up = false
		return false
	var dest := ball.global_position
	var range := _flat_range(dest)
	if _player.is_golfing():
		_swing(_player.golf, delta)
		return true
	if _player.is_carrying_ball() or ball.is_carried() or _ball_in_water(ball):
		_lined_up = false
		return _water_retrieve()
	if ball.is_in_play():
		_lined_up = false
		if range > HOP_RANGE or _player.is_riding():
			return _ride_to(dest)
		return false
	if range > WALK_RANGE:
		return _ride_to(dest)
	if _player.is_riding():
		_ghost.tap("interact")
		return true
	if _may_strike() and _player.golf != null:
		return _address_or_claim(delta)
	if range > WAIT_RANGE:
		_walk_toward(dest)
		_ghost.hold("sprint", range > WALK_RANGE * 0.7)
		return true
	return false


func _address_or_claim(delta: float) -> bool:
	var golf := _player.golf
	if golf.is_golfing(_player):
		_swing(golf, delta)
		return true
	if golf.can_claim(_player):
		if not _lined_up:
			_lined_up = true
			_think_left = _rng.randf_range(0.7, 1.8)
			_shot_power = clampf(
				CpuBuddy.wanted_power(
					_player.global_position, golf.pin(), Shot.can_putt(golf.ball.current_surface()),
					_club_kit(), golf.green_span
				) + _power_slop,
				0.08,
				0.96
			)
		_look_at(golf.pin() + _aim_slop)
		if _think_left > 0.0:
			_think_left -= delta
			return true
		_ghost.tap("interact")
		_address_left = _rng.randf_range(0.8, 2.1)
		_lined_up = false
		return true
	if golf.is_available():
		_walk_toward(golf.ball.global_position)
		_look_at(golf.ball.global_position)
		return true
	return false


func _ride_to(dest: Vector3) -> bool:
	if _player.is_driving():
		if _flat_range(dest) <= HOP_RANGE:
			_ghost.tap("interact")
			return true
		_drive_toward(dest)
		return true
	if _player.is_riding():
		if _flat_range(dest) <= HOP_RANGE:
			_ghost.tap("interact")
		return true
	var cart := _cart()
	if cart == null:
		_walk_toward(dest)
		_ghost.hold("sprint")
		return true
	if cart.can_right(_player) or cart.can_board(_player):
		_ghost.tap("interact")
		return true
	_walk_toward(cart.global_position)
	_ghost.hold("sprint")
	return true


func _water_retrieve() -> bool:
	var ball := _ball()
	if ball == null:
		return false
	if _player.is_carrying_ball():
		return _throw_recovered()
	if ball.is_carried() and ball.carrier() != _player:
		return _leave_the_water()
	if _player.is_swimming():
		return _swim_for_ball()
	var dest := ball.global_position
	if _player.is_riding():
		if _flat_range(dest) <= HOP_RANGE or _water_depth(_player.global_position) >= 0.6:
			_ghost.tap("interact")
			return true
		if _player.is_driving():
			_drive_toward(dest)
		return true
	if _flat_range(dest) > WALK_RANGE:
		return _ride_to(dest)
	_walk_toward(dest)
	_ghost.hold("sprint", _flat_range(dest) > 8.0)
	return true


func _swim_for_ball() -> bool:
	var ball := _ball()
	if ball == null:
		return _leave_the_water()
	if _player.swim != null and _player.swim.can_grab_ball(_player):
		_ghost.tap("grab")
		return true
	_walk_toward(ball.global_position)
	if not _player.is_underwater():
		if _player.global_position.distance_to(ball.global_position) <= 6.0:
			_ghost.tap("shoot")
		return true
	var depth := ball.global_position.y - _player.global_position.y
	if depth < -0.3:
		_ghost.hold("melee")
	elif depth > 0.4:
		_ghost.hold("ascend")
	return true


func _throw_recovered() -> bool:
	if _player.is_underwater():
		_ghost.hold("ascend")
		return true
	var pin := _pin()
	_look_at(pin)
	if not _toss_reaches_land(pin):
		_walk_toward(pin)
		return true
	var from := _player.head.global_position if _player.head != null else _player.global_position
	if absf(CpuBuddy.yaw_error(_player.rotation.y, from, pin)) > AIM_OK_DEG:
		return true
	_ghost.tap("shoot")
	return true


func _ball_in_water(ball: GolfBall) -> bool:
	if ball == null or ball.is_carried():
		return false
	if ball.is_submerged():
		return true
	return _water_depth(ball.global_position) >= PlayerSwim.WADE_DEPTH


func _water_depth(at: Vector3) -> float:
	if _player.flow != null and _player.flow.hole != null:
		return _player.flow.hole.water_depth_at(at)
	return 0.0


func _toss_reaches_land(pin: Vector3) -> bool:
	if _player.flow == null or _player.flow.hole == null:
		return true
	var dir := pin - _player.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.04:
		return true
	dir = dir.normalized()
	for dist in [5.0, 9.0, 13.0]:
		if _water_depth(_player.global_position + dir * dist) < PlayerSwim.WADE_DEPTH:
			return true
	return false


func _leave_the_water() -> bool:
	if not _player.is_swimming():
		return false
	if _player.is_underwater():
		_ghost.hold("ascend")
		return true
	_ghost.tap("grab")
	return true


func _pin() -> Vector3:
	if _player.golf != null:
		return _player.golf.pin()
	if _player.flow != null and _player.flow.hole != null:
		return _player.flow.hole.cup
	return _player.global_position + Vector3(0.0, 0.0, -8.0)


func _drive_toward(world_point: Vector3) -> void:
	var cart := _player.cart
	var from := cart.global_position if cart != null else _player.global_position
	var heading := cart.rotation.y if cart != null else _player.rotation.y
	var dir := world_point - from
	dir.y = 0.0
	if dir.length_squared() < 0.04:
		return
	_look_at(from + dir.normalized() * LOOK_AHEAD)
	_ghost.move = CpuBuddy.cart_move(heading, dir)
	if dir.length() > 22.0:
		_ghost.hold("shoot")


func _may_strike() -> bool:
	if _player.flow == null:
		return true
	if _player.flow.has_method("is_practice") and _player.flow.is_practice():
		return true
	if _player.flow.has_method("can_strike"):
		return bool(_player.flow.can_strike(_player))
	return true


func _swing(golf: GolfController, delta: float) -> void:
	_look_at(golf.pin() + _aim_slop)
	if _address_left > 0.0:
		_address_left -= delta
		return
	var meter := golf.meter
	if meter.state == SwingMeter.State.READY:
		_ghost.tap("swing")
	elif meter.state == SwingMeter.State.BACKSWING and meter.value >= _shot_power:
		_ghost.tap("swing")
	elif meter.state == SwingMeter.State.DOWNSWING and meter.value <= _contact_slop:
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
	if cart != null and (cart.can_right(_player) or cart.can_board(_player)):
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
	var cart := _player.cart
	var from := cart.global_position if cart != null else _player.global_position
	var heading := cart.rotation.y if cart != null else _player.rotation.y
	var target := from + _path_heading() * LOOK_AHEAD
	var path := _cart_path()
	if path != null and path.centerline.size() >= 2:
		target = CartPathTrack.aim_at(path.centerline, from)
	_look_at(target)
	_ghost.move = CpuBuddy.race_move(heading, target - from)
	_ghost.hold("shoot")


func _shop() -> void:
	if _can("can_open_exit") and not _player.cpu_filled:
		_ghost.tap("interact")
		return
	var house := _clubhouse()
	if house != null:
		_walk_toward(house.exit_point())
		return
	_walk_toward(_tee())


func _fight() -> void:
	var armed := _player.weapon != null and _player.weapon.has_weapon()
	if armed and _player.weapon.mag() <= 0:
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
	if armed and on_target and range <= _hunt_range():
		_ghost.hold("shoot")
	if on_target and range <= MELEE_RANGE:
		_ghost.tap("melee")


func _arena_fight(_delta: float) -> bool:
	if _player.flow == null or not ArenaHole.applies(_player.flow.hole):
		return false
	var phase := _phase()
	if phase != VsMatchFlow.Phase.PREP and phase != VsMatchFlow.Phase.PLAYING:
		return false
	if ArenaHole.needs_gun(_player):
		var gun := ArenaHole.nearest_gun(_player)
		if gun != null:
			_walk_toward(gun.global_position)
			_ghost.hold("sprint", true)
		return true
	_fight()
	return true


func _hunt_range() -> float:
	if _player.flow != null and ArenaHole.applies(_player.flow.hole):
		return ArenaHole.HUNT_RANGE
	return SHOOT_RANGE


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


func _ball() -> GolfBall:
	if _player.golf != null:
		return _player.golf.ball
	return null


func _flat_range(world_point: Vector3) -> float:
	var offset := world_point - _player.global_position
	offset.y = 0.0
	return offset.length()


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
	var best_dist := _hunt_range()
	for node in _player.get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null or not is_instance_valid(zombie):
			continue
		var dist := _player.global_position.distance_to(zombie.global_position)
		if dist < best_dist:
			best = zombie
			best_dist = dist
	return best
