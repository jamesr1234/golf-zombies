class_name PlayerLook
extends RefCounted
## Yaw / pitch, view kick, FOV, and the cheer pull-back. Camera3D still lives in
## its SubViewport and copies whatever get_view_transform returns.

const _Shield := preload("res://scripts/player/shield.gd")
const _HexBarrier := preload("res://scripts/player/hex_barrier.gd")

const MOUSE_DEG_PER_PIXEL := 0.12
const STICK_DEG_PER_SEC := 130.0
const PITCH_LIMIT := 85.0
const BASE_FOV := 85.0
const ADS_FOV := 60.0
const DRIVER_FOV := 105.0
const DRIVER_PITCH := -8.0
const VIEW_KICK_DEG := 5.5
const VIEW_KICK_RECOVER := 22.0
const MELEE_VIEW_KICK := 4.0
const CHEER_CAM_BACK := 3.6
const CHEER_CAM_SIDE := 1.15
const CHEER_CAM_HEIGHT := 1.9
const CHEER_CAM_LOOK := 1.15
const CHEER_FOV := 70.0

var yaw := 0.0
var pitch := 0.0
var mouse_delta := Vector2.ZERO
var view_kick := 0.0
## Driver and mech: L1 pulls the camera out behind the vehicle.
var cart_chase := false
var cheer_left := 0.0


func add_mouse(player: Player, relative: Vector2) -> void:
	if player.uses_mouse:
		mouse_delta += relative


func add_kick(amount: float) -> void:
	view_kick += amount


func tick(player: Player, delta: float) -> void:
	view_kick = move_toward(view_kick, 0.0, VIEW_KICK_RECOVER * delta)
	if player.is_driving():
		if player.input.just_pressed("melee"):
			cart_chase = not cart_chase
		mouse_delta = Vector2.ZERO
		return
	if player.is_in_mech() and player.input.just_pressed("melee"):
		cart_chase = not cart_chase
	if player.is_celebrating():
		mouse_delta = Vector2.ZERO
		return
	if player.is_climbing():
		return
	var look := Vector2.ZERO
	if player.uses_mouse:
		look += mouse_delta * MOUSE_DEG_PER_PIXEL
	# Co-op keyboard seats must not also read the stick, or one pad turns both
	# viewports. Solo and online still stack mouse and pad on the same body.
	if not player.uses_mouse or GameSettings.mode != GameSettings.Mode.COOP:
		look += player.input.stick_look() * STICK_DEG_PER_SEC * delta
	mouse_delta = Vector2.ZERO
	var zoom := 1.0
	if player.weapon != null:
		zoom = player.weapon.zoom_mult()
	if zoom > 1.0:
		look /= zoom
	if player.state == Player.State.GOLFING:
		player.golf.aim_by(-look.x)
		player.golf.aim_height_by(-look.y - player.input.move_vector().y * STICK_DEG_PER_SEC * delta)
		return
	if player.shopping:
		player.shop.turn(player, look, delta)
		return
	yaw = wrapf(yaw - look.x, -180.0, 180.0)
	pitch = clampf(pitch - look.y, -PITCH_LIMIT, PITCH_LIMIT)
	player.rotation.y = deg_to_rad(yaw)
	player.head.rotation.x = deg_to_rad(clampf(pitch + view_kick, -PITCH_LIMIT, PITCH_LIMIT))


func view_transform(player: Player) -> Transform3D:
	if player.is_climbing():
		return player.climber.view_transform(player)
	if player.is_celebrating():
		return cheer_view(player)
	if player.state == Player.State.GOLFING and player.golf != null:
		return player.golf.get_camera_transform()
	if player.is_in_mech() and player.mech != null:
		if cart_chase:
			return player.mech.chase_view_transform()
		return drunk_view(player, player.mech.pilot_view_transform(pitch))
	if player.is_driving():
		if cart_chase:
			return player.cart.chase_view_transform()
		return drunk_view(player, player.cart.driver_view_transform())
	if player.is_shielding():
		return drunk_view(player, _Shield.view_transform(player.global_position, yaw, pitch))
	if player.is_placing():
		return drunk_view(
			player, _HexBarrier.view_transform(player.global_position, yaw, player.place.look_at(player))
		)
	if player.shopping:
		return drunk_view(player, player.shop.view_transform(player))
	return drunk_view(player, player.head.global_transform)


func drunk_view(player: Player, xform: Transform3D) -> Transform3D:
	var sway := player.buzz.sway_amount()
	if sway <= 0.0:
		return xform
	var t := Time.get_ticks_msec() * 0.001
	xform.basis = xform.basis.rotated(xform.basis.z, sin(t * 1.35) * sway)
	xform.basis = xform.basis.rotated(xform.basis.y, cos(t * 1.05) * sway * 0.55)
	return xform


func view_fov(player: Player) -> float:
	var bump := player.buzz.fov_bump() if player.wants_drunk_fx() else 0.0
	if player.is_climbing():
		return Climber.CAM_FOV
	if player.is_grappling():
		return Grappler.FOV
	if player.is_celebrating():
		return CHEER_FOV
	if player.is_in_mech():
		if cart_chase:
			return MechSuit.CHASE_FOV + bump
		if player.aiming:
			return ADS_FOV + bump
		return BASE_FOV + bump
	if player.is_driving():
		return (GolfCart.CHASE_FOV if cart_chase else DRIVER_FOV) + bump
	if player.is_shielding():
		return _Shield.CAM_FOV
	if player.is_placing():
		return _HexBarrier.CAM_FOV
	if player.shopping:
		return player.shop.cam_fov()
	var base := BASE_FOV
	if player.aiming and player.state == Player.State.NORMAL:
		if player.weapon != null and player.weapon.is_scoped():
			base = BASE_FOV / player.weapon.zoom_mult()
		else:
			base = ADS_FOV
	return base + bump


func celebrate(player: Player) -> void:
	if player.is_cpu() or not player.health.is_alive():
		return
	if player.is_riding() or player.is_swimming() or player.is_golfing() or player.is_in_mech():
		return
	player._drop_grapple()
	player._cancel_place()
	if player.state == Player.State.SHIELDING:
		player.state = Player.State.NORMAL
		if player._shield != null:
			player._shield.set_raised(false)
	cheer_left = PlayerBody.CHEER_TIME
	player.velocity = Vector3.ZERO


func tick_cheer(delta: float) -> void:
	if cheer_left <= 0.0:
		return
	cheer_left = maxf(0.0, cheer_left - delta)


func cheer_view(player: Player) -> Transform3D:
	var eye := (
		player.global_position + player.transform.basis.z * CHEER_CAM_BACK
		+ player.transform.basis.x * CHEER_CAM_SIDE + Vector3.UP * CHEER_CAM_HEIGHT
	)
	var target := player.global_position + Vector3.UP * CHEER_CAM_LOOK
	return Transform3D(Basis(), eye).looking_at(target, Vector3.UP)


func sit_driver(player: Player, sit_at: Vector3, facing_yaw: float) -> void:
	player.global_position = sit_at
	yaw = facing_yaw
	pitch = DRIVER_PITCH
	mouse_delta = Vector2.ZERO
	player.rotation.y = deg_to_rad(yaw)
	player.head.rotation.x = deg_to_rad(pitch)


func hides_own_cabin(player: Player) -> bool:
	if player.is_underwater() or player.is_in_mech():
		return true
	return player.is_driving() and not cart_chase
