class_name Climber
extends RefCounted
## Hold L1 / R1 to grip. One hand swings you; both hands lock you. Left stick
## aims the left arm, right stick the right, including above the body.

const ARM := 1.05
const GRAVITY := 18.0
const DAMP := 0.55
const STIFF := 10.0
const SWING := 42.0
const CATCH := 0.3
const CAM_BACK := 4.2
const CAM_SIDE := 1.35
const CAM_HEIGHT := 2.1
const CAM_LOOK := 1.35
const CAM_FOV := 70.0
const MOUSE_STICK := 0.07


const LADDER_SPEED := 5.6
const MANTLE_TIME := 0.72

var wall: ClimbingWall
var left := Vector3.INF
var right := Vector3.INF
var left_aim := Vector3.ZERO
var right_aim := Vector3.ZERO
var aim := Vector3.ZERO
var _angle := 0.0
var _ang_vel := 0.0
var _catch := 0.0
var _braced := true
var _rail_t := 0.0
var _mantle_t := -1.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO


func is_active() -> bool:
	return wall != null and is_instance_valid(wall)


func latch(player: Player, on: ClimbingWall) -> bool:
	if on == null or not on.can_latch(player):
		return false
	wall = on
	if on is LeanLadder:
		return _latch_ladder(player, on as LeanLadder)
	var chest := player.global_position + Vector3.UP * 1.15
	left = on.nearest_hold(chest + player.global_transform.basis.x * -0.25)
	right = on.nearest_hold(chest + player.global_transform.basis.x * 0.25)
	if left == Vector3.INF and right == Vector3.INF:
		wall = null
		return false
	left_aim = left if left != Vector3.INF else chest
	right_aim = right if right != Vector3.INF else chest
	aim = left_aim
	_catch = CATCH
	_angle = 0.0
	_ang_vel = 0.0
	_braced = true
	_mantle_t = -1.0
	_face_wall(player)
	_snap_to_hang(player)
	return true


func tick(player: Player, delta: float) -> bool:
	if not is_active() or player.health == null or not player.health.is_alive():
		return false
	if is_mantling():
		return _tick_mantle(player, delta)
	if wall is LeanLadder:
		if not (wall as LeanLadder).is_live():
			return false
		return _tick_ladder(player, delta)
	_catch = maxf(0.0, _catch - delta)
	var left_stick := _face_stick(player.input.move_vector())
	var right_stick := _face_stick(_right_stick(player))
	_aim_hands(player, left_stick, right_stick)
	_tick_grip(true, player.input.pressed("melee"))
	_tick_grip(false, player.input.pressed("shield"))
	if _can_mantle(player):
		_start_mantle(player)
		return _tick_mantle(player, delta)
	if player.input.just_pressed("jump"):
		return false
	if left == Vector3.INF and right == Vector3.INF:
		return false
	_move_body(player, delta, left_stick.x + right_stick.x)
	return true


func drop() -> void:
	wall = null
	left = Vector3.INF
	right = Vector3.INF
	left_aim = Vector3.ZERO
	right_aim = Vector3.ZERO
	aim = Vector3.ZERO
	_catch = 0.0
	_angle = 0.0
	_ang_vel = 0.0
	_braced = true
	_rail_t = 0.0
	_mantle_t = -1.0
	_mantle_from = Vector3.ZERO
	_mantle_to = Vector3.ZERO


func pose_left() -> Vector3:
	return left if left != Vector3.INF else left_aim


func pose_right() -> Vector3:
	return right if right != Vector3.INF else right_aim


func is_mantling() -> bool:
	return _mantle_t >= 0.0 and wall != null and is_instance_valid(wall)


func mantle_progress() -> float:
	return clampf(_mantle_t, 0.0, 1.0)


func view_transform(player: Player) -> Transform3D:
	var back := CAM_BACK + (1.4 if is_mantling() else 0.0)
	var side := CAM_SIDE + (0.35 if is_mantling() else 0.0)
	var eye := (
		player.global_position + player.transform.basis.z * back
		+ player.transform.basis.x * side + Vector3.UP * CAM_HEIGHT
	)
	var target := player.global_position + Vector3.UP * CAM_LOOK
	return Transform3D(Basis(), eye).looking_at(target, Vector3.UP)


func _face_stick(stick: Vector2) -> Vector2:
	# Facing the wall, wall +X is your left. Flip so stick right aims right.
	return Vector2(-stick.x, stick.y)


func _right_stick(player: Player) -> Vector2:
	var stick := player.input.stick_look()
	if player.uses_mouse:
		stick = (stick + player._mouse_delta * MOUSE_STICK).limit_length(1.0)
		player._mouse_delta = Vector2.ZERO
	return stick


func _aim_hands(player: Player, left_stick: Vector2, right_stick: Vector2) -> void:
	left_aim = wall.aim_from(_shoulder(player, true), left_stick)
	right_aim = wall.aim_from(_shoulder(player, false), right_stick)
	aim = left_aim


func _latch_ladder(player: Player, on: LeanLadder) -> bool:
	_rail_t = on.rail_t_at(player.global_position)
	_catch = 0.0
	_angle = 0.0
	_ang_vel = 0.0
	_braced = true
	_face_wall(player)
	_snap_to_rail(player)
	_grab_rail_hands(player)
	return true


func _tick_ladder(player: Player, delta: float) -> bool:
	var ladder := wall as LeanLadder
	if player.input.just_pressed("jump"):
		if _rail_t >= 0.82:
			_mantle(player)
		return false
	var climb := -player.input.move_vector().y
	_rail_t = clampf(_rail_t + climb * LADDER_SPEED / maxf(ladder.rail_length(), 0.01) * delta, 0.0, 1.0)
	_snap_to_rail(player)
	_grab_rail_hands(player)
	if _rail_t >= 1.0:
		_mantle(player)
		return false
	return true


func _snap_to_rail(player: Player) -> void:
	var ladder := wall as LeanLadder
	if ladder == null:
		return
	player.global_position = ladder.point_on_rail(_rail_t)
	player.velocity = Vector3.ZERO
	_face_wall(player)


func _grab_rail_hands(player: Player) -> void:
	var chest := player.global_position + Vector3.UP * 1.15
	left = wall.nearest_hold(chest + player.global_transform.basis.x * -0.22)
	right = wall.nearest_hold(chest + player.global_transform.basis.x * 0.22)
	left_aim = left if left != Vector3.INF else chest
	right_aim = right if right != Vector3.INF else chest
	aim = left_aim


func _shoulder(player: Player, is_left: bool) -> Vector3:
	var side := -0.32 if is_left else 0.32
	return player.global_position + Vector3.UP * 1.42 + player.global_transform.basis.x * side


func _tick_grip(is_left: bool, holding: bool) -> void:
	if holding or _catch > 0.0:
		if (left if is_left else right) == Vector3.INF:
			_grab(is_left)
		return
	if is_left:
		left = Vector3.INF
	else:
		right = Vector3.INF


func _grab(is_left: bool) -> void:
	var hold := wall.nearest_hold(left_aim if is_left else right_aim, ClimbingWall.REACH)
	if hold == Vector3.INF:
		return
	if is_left:
		left = hold
	else:
		right = hold
	Sfx.play("jump")


func _move_body(player: Player, delta: float, lean: float) -> void:
	if left != Vector3.INF and right != Vector3.INF:
		var hang := wall.hang_at(left, right)
		if hang != Vector3.INF:
			player.global_position = player.global_position.move_toward(hang, STIFF * delta)
		player.velocity = Vector3.ZERO
		_angle = 0.0
		_ang_vel = 0.0
		_braced = true
		_face_wall(player)
		return
	var pivot := left if left != Vector3.INF else right
	if _braced:
		var along := wall.to_local(player.global_position) - wall.to_local(pivot)
		_angle = clampf(atan2(along.x, -along.y), -1.15, 1.15)
		_ang_vel = 0.0
		_braced = false
	_ang_vel += (-sin(_angle) * GRAVITY / ARM + lean * SWING) * delta
	_ang_vel *= exp(-DAMP * delta)
	_angle = clampf(_angle + _ang_vel * delta, -1.15, 1.15)
	var local := wall.to_local(pivot)
	local.x += sin(_angle) * ARM
	local.y -= cos(_angle) * ARM
	local.z = -ClimbingWall.THICK * 0.5 - 0.55
	player.global_position = wall.to_global(local)
	player.velocity = Vector3.ZERO
	_face_wall(player)


func _snap_to_hang(player: Player) -> void:
	var hang := wall.hang_at(left, right)
	if hang != Vector3.INF:
		player.global_position = hang
	player.velocity = Vector3.ZERO


func _face_wall(player: Player) -> void:
	var into := -wall.face_normal()
	player.rotation.y = atan2(-into.x, -into.z)
	player._yaw = rad_to_deg(player.rotation.y)


func _can_mantle(_player: Player) -> bool:
	return wall != null and (wall.at_lip(left) or wall.at_lip(right))


func _mantle(player: Player) -> void:
	if wall is LeanLadder:
		player.global_position = wall.ledge_stand(player)
		player.velocity = Vector3.ZERO
		Sfx.play("jump")
		drop()
		return
	_start_mantle(player)


func _start_mantle(player: Player) -> void:
	if is_mantling() or wall == null:
		return
	_mantle_t = 0.0
	_mantle_from = player.global_position
	_mantle_to = wall.ledge_stand(player)
	Sfx.play("jump")


func _tick_mantle(player: Player, delta: float) -> bool:
	_mantle_t = minf(1.0, _mantle_t + delta / MANTLE_TIME)
	player.global_position = _mantle_point(_mantle_t)
	player.velocity = Vector3.ZERO
	if _mantle_t >= 1.0:
		player.global_position = _mantle_to
		drop()
		return false
	return true


func _mantle_point(t: float) -> Vector3:
	var u := t * t * (3.0 - 2.0 * t)
	var from_l := wall.to_local(_mantle_from)
	var to_l := wall.to_local(_mantle_to)
	var crest := Vector3(from_l.x, to_l.y + 0.2, -wall._t * 0.5 - 0.28)
	if u < 0.5:
		return wall.to_global(from_l.lerp(crest, u / 0.5))
	return wall.to_global(crest.lerp(to_l, (u - 0.5) / 0.5))
