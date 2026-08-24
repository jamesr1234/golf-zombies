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
const MANTLE := 0.95
const CAM_BACK := 4.2
const CAM_SIDE := 1.35
const CAM_HEIGHT := 2.1
const CAM_LOOK := 1.35
const CAM_FOV := 70.0
const MOUSE_STICK := 0.07


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


func is_active() -> bool:
	return wall != null and is_instance_valid(wall)


func latch(player: Player, on: ClimbingWall) -> bool:
	if on == null or not on.can_latch(player):
		return false
	wall = on
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
	_face_wall(player)
	_snap_to_hang(player)
	return true


func tick(player: Player, delta: float) -> bool:
	if not is_active() or player.health == null or not player.health.is_alive():
		return false
	_catch = maxf(0.0, _catch - delta)
	var left_stick := player.input.move_vector()
	var right_stick := _right_stick(player)
	_aim_hands(player, left_stick, right_stick)
	_tick_grip(true, player.input.pressed("melee"))
	_tick_grip(false, player.input.pressed("shield"))
	if player.input.just_pressed("jump"):
		if _can_mantle(player):
			_mantle(player)
			return false
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


func pose_left() -> Vector3:
	return left if left != Vector3.INF else left_aim


func pose_right() -> Vector3:
	return right if right != Vector3.INF else right_aim


func view_transform(player: Player) -> Transform3D:
	var eye := (
		player.global_position + player.transform.basis.z * CAM_BACK
		+ player.transform.basis.x * CAM_SIDE + Vector3.UP * CAM_HEIGHT
	)
	var target := player.global_position + Vector3.UP * CAM_LOOK
	return Transform3D(Basis(), eye).looking_at(target, Vector3.UP)


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


func _can_mantle(player: Player) -> bool:
	return wall != null and player.global_position.y >= wall.top_y() - MANTLE


func _mantle(player: Player) -> void:
	player.global_position = wall.ledge_stand()
	player.velocity = Vector3.ZERO
	Sfx.play("jump")
	drop()
