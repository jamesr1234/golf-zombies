class_name GolfController
extends Node3D
## Owns golf mode: who is swinging, where they are aiming, the swing meter, and
## the third-person camera framing. Only one player can hold the ball at a time
## and the claim is released as soon as the shot resolves, so the golfer always
## has to walk back to the ball.

signal stroke_taken()
signal golfer_changed(golfer: Node)
signal sweet_struck()

const CLAIM_RANGE := 3.6
const MOUSE_AIM_DEG := 0.12
const STICK_AIM_DEG_PER_SEC := 80.0
## Pulled well back so the golfer, the club and the ball are all in frame.
const CAMERA_DISTANCE := 8.5
const CAMERA_HEIGHT := 3.4
const CAMERA_LOOK_HEIGHT := 1.2
## Shifted off the aim line, away from the golfer, so they do not stand in front
## of their own ball.
const CAMERA_SIDE := 0.8
## The golfer turns with the club, which is what sells a swing on a body with no
## arms to animate.
const BODY_TURN_RATIO := 0.22
const SHAKE_AMP := 0.55
const SHAKE_DECAY := 2.8
const SHAKE_ROLL := 0.05

var ball: GolfBall
var golfer: Node = null
var aim_yaw := 0.0
## Extra launch degrees on top of the power loft. Stick up raises the shot.
var aim_loft := 0.0
var meter := SwingMeter.new()
var club_kit: ClubKit = ClubKit.starter()
## Diameter of the green this stroke is playing to. A stuffed putt runs 2.4x this.
var green_span := 0.0

var _cup := Vector3.ZERO
var _arrow: Node3D
var _preview: ShotPreview
var _club: GolfClub
var _shot_eye := Vector3.ZERO
## Where the ball was addressed. Held while the ball is in the air so the golfer
## and the club stay planted on the lie instead of riding the shot.
var _lie := Vector3.ZERO
## Locked at contact. Online clients never mark their own ball in play, so this
## is what keeps the stance from tracking the synced flight.
var _lie_locked := false
var _shake := 0.0


func _ready() -> void:
	_arrow = _build_arrow()
	add_child(_arrow)
	_arrow.visible = false
	_preview = ShotPreview.new()
	add_child(_preview)
	_preview.visible = false
	_club = GolfClub.new()
	add_child(_club)
	_club.visible = false


func setup(p_ball: GolfBall, cup: Vector3, p_green_span := 0.0) -> void:
	if ball != p_ball:
		ball = p_ball
		ball.came_to_rest.connect(func(_position: Vector3) -> void: release())
		ball.entered_hazard.connect(func(_kind: String) -> void: release())
		ball.holed.connect(release)
	_cup = cup
	green_span = p_green_span if p_green_span > 0.0 else Shot.default_green_span()
	_apply_kit()
	release()


func pin() -> Vector3:
	return _cup


func is_golfing(player: Node) -> bool:
	return golfer == player


func is_available() -> bool:
	if golfer != null or ball == null or ball.is_in_play():
		return false
	return not (
		ball.is_submerged() or ball.is_carried() or ball.is_holed() or ball.is_stowed()
		or ball.is_closed()
	)


func can_claim(player: Node) -> bool:
	if not is_available():
		return false
	if ball != null and not ball.is_owned_by(player):
		return false
	if player.has_method("is_swimming") and player.is_swimming():
		return false
	var reach := CLAIM_RANGE
	if player.has_method("golf_claim_range"):
		reach = player.golf_claim_range()
	return _horizontal_distance(player) <= reach


func try_toggle(player: Node) -> void:
	if golfer == player:
		release()
	elif can_claim(player):
		_claim(player)


func release() -> void:
	_lie_locked = false
	if golfer == null:
		return
	var previous := golfer
	golfer = null
	meter.reset()
	aim_loft = 0.0
	_arrow.visible = false
	if _preview != null:
		_preview.visible = false
	_club.visible = false
	if previous.has_method("exit_golf_mode"):
		previous.exit_golf_mode()
	golfer_changed.emit(null)


## Interrupted mid-swing: the stroke does not count.
func cancel_swing() -> void:
	if meter.is_swinging():
		meter.reset()


func click() -> void:
	if golfer == null or _is_watching_shot():
		return
	meter.click()
	if meter.state == SwingMeter.State.DOWNSWING:
		_shot_eye = get_camera_transform().origin
		Sfx.play("swing_click", self)
	elif meter.is_done():
		_strike()
	else:
		Sfx.play("swing_click", self)


func aim_by(degrees: float) -> void:
	if golfer == null or meter.is_swinging():
		return
	aim_yaw = wrapf(aim_yaw + degrees, -180.0, 180.0)


func aim_height_by(degrees: float) -> void:
	if golfer == null or meter.is_swinging() or _is_putting():
		return
	aim_loft = clampf(aim_loft + degrees, Shot.LOFT_BIAS_MIN, Shot.LOFT_BIAS_MAX)


func get_camera_transform() -> Transform3D:
	var pivot := ball.global_position if ball != null else global_position
	if _is_watching_shot():
		return _with_shake(_look_from(_shot_eye, pivot))
	var forward := Shot.aim_direction(aim_yaw, 0.0)
	var look_along := _preview_look_along()
	var back := CAMERA_DISTANCE
	var height := CAMERA_HEIGHT
	if golfer is Player and (golfer as Player).is_in_mech():
		back += 16.0
		height += 10.0
	var eye := (
		pivot - forward * (back + look_along * 0.18)
		+ Vector3.UP * (height + look_along * 0.035)
		+ forward.cross(Vector3.UP) * CAMERA_SIDE
	)
	return _with_shake(_look_from(eye, pivot + forward * look_along + Vector3.UP * CAMERA_LOOK_HEIGHT))


func _process(delta: float) -> void:
	_shake = move_toward(_shake, 0.0, SHAKE_DECAY * delta)
	if golfer == null:
		return
	if meter.is_swinging():
		meter.tick(delta)
		if meter.is_done():
			_strike()
	_refresh_lie()
	_pose_arrow()
	_pose_preview()
	_pose_swing(delta)


## World space, not local: online the session lives on the ball, and leftover
## flight spin would otherwise twist the arrow off the aim line after the tee shot.
func _pose_arrow() -> void:
	_arrow.global_transform = Transform3D(
		Basis.looking_at(Shot.aim_direction(aim_yaw, 0.0), Vector3.UP), _lie
	)


func _pose_preview() -> void:
	if _preview == null:
		return
	if golfer == null or _is_watching_shot():
		_preview.visible = false
		return
	_preview.visible = true
	_preview.draw(Shot.flight_points(
		_lie, aim_yaw, 1.0, aim_loft, _is_putting(), _shot_kit(), green_span,
		_preview_surface()
	))


func _preview_look_along() -> float:
	var carry := Shot.putt_run(club_kit, green_span) if _is_putting() else Shot.carry_to_height(
		0.0, 1.0, aim_loft
	)
	return clampf(carry * 0.3, 0.0, 28.0)


## Holds the golfer at address beside the ball and swings the club through it.
## Standing them there is what makes the swing land on the ball at all: the claim
## can be made from a few metres out.
func _pose_swing(delta: float) -> void:
	_club.pose(_lie, aim_yaw, meter.value, delta, _is_putting())
	if golfer.has_method("stand_at"):
		var stance := GolfClub.stance_point(_lie, aim_yaw)
		if golfer.has_method("golf_stance_point"):
			stance = golfer.golf_stance_point(_lie, aim_yaw)
		golfer.stand_at(
			stance, aim_yaw + _club.angle * BODY_TURN_RATIO
		)


func _claim(player: Node) -> void:
	golfer = player
	meter.reset()
	_apply_kit()
	_lie_locked = false
	_lie = ball.global_position
	aim_yaw = _yaw_towards(_cup)
	aim_loft = 0.0
	_arrow.visible = true
	_club.visible = true
	if player.has_method("enter_golf_mode"):
		player.enter_golf_mode()
	golfer_changed.emit(player)
	Sfx.play("golf_claim", self)


func _strike() -> void:
	_lock_lie()
	_apply_kit()
	var sweet := meter.sweet
	ball.strike(aim_yaw, meter.deviation_deg, meter.power, _shot_kit(), green_span, aim_loft)
	if sweet:
		_celebrate_sweet()
	meter.reset()
	_arrow.visible = false
	if _preview != null:
		_preview.visible = false
	_club.start_follow_through()
	stroke_taken.emit()
	Sfx.play("putt" if _is_putting() else "club_hit", self)


func _celebrate_sweet() -> void:
	_shake = 1.0
	var root := _fx_root()
	var at := _lie
	if at == Vector3.ZERO and ball != null:
		at = ball.global_position
	if root != null and (ball != null or _lie != Vector3.ZERO):
		HitFx.burst(root, at + Vector3.UP * GolfBall.RADIUS, Palette.LIME)
	sweet_struck.emit()


func _fx_root() -> Node:
	if not is_inside_tree():
		return null
	var root := get_tree().get_first_node_in_group("fx_root")
	return root if root != null else get_tree().current_scene


func _with_shake(xform: Transform3D) -> Transform3D:
	if _shake <= 0.0:
		return xform
	var t := Time.get_ticks_msec() * 0.001
	var amp := _shake * SHAKE_AMP
	xform.origin += xform.basis.x * sin(t * 58.0) * amp
	xform.origin += xform.basis.y * cos(t * 67.0) * amp
	xform.basis = xform.basis.rotated(xform.basis.z, sin(t * 53.0) * _shake * SHAKE_ROLL)
	xform.basis = xform.basis.rotated(xform.basis.x, cos(t * 71.0) * _shake * SHAKE_ROLL)
	return xform


func _shot_kit() -> ClubKit:
	var kit := club_kit if club_kit != null else ClubKit.starter()
	var who := golfer as Player
	if who != null and who.is_in_mech():
		kit = ClubKit.mech()
	if who == null:
		return kit
	return kit.boosted(who.buzz.strength_mult())


func _apply_kit() -> void:
	var kit := club_kit if club_kit != null else ClubKit.starter()
	var who := golfer as Player
	if who != null and who.is_in_mech():
		kit = ClubKit.mech()
	meter.kit = kit
	if _club != null:
		_club.apply_kit(kit)


func _lock_lie() -> void:
	if not _lie_locked and _shot_eye == Vector3.ZERO:
		_shot_eye = get_camera_transform().origin
	_lie_locked = true


func _refresh_lie() -> void:
	if _lie_locked or ball == null or ball.is_in_play():
		return
	_lie = ball.global_position


func _is_watching_shot() -> bool:
	return _lie_locked or (ball != null and ball.is_in_play())


func _is_putting() -> bool:
	return ball != null and ball.is_putting()


func _preview_surface() -> Surface.Type:
	if ball == null:
		return Surface.Type.FAIRWAY
	return ball.current_surface()


func _yaw_towards(target: Vector3) -> float:
	var to_target := target - ball.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.001:
		return aim_yaw
	# Vector3.FORWARD is -Z, so the yaw that points at the target is measured
	# from that axis.
	return rad_to_deg(atan2(-to_target.x, -to_target.z))


func _horizontal_distance(player: Node) -> float:
	var from: Vector3 = (player as Node3D).global_position
	if player.has_method("golf_claim_origin"):
		from = player.golf_claim_origin()
	var offset: Vector3 = from - ball.global_position
	offset.y = 0.0
	return offset.length()


func _look_from(eye: Vector3, target: Vector3) -> Transform3D:
	var transform := Transform3D(Basis(), eye)
	return transform.looking_at(target, Vector3.UP)


func _build_arrow() -> Node3D:
	var root := Node3D.new()
	var shaft := MeshFactory.box(
		Vector3(0.18, 0.02, 3.0), Palette.AIM_ARROW, Palette.GLOW_STRONG
	)
	shaft.position = Vector3(0.0, 0.05, -1.8)
	var tip := MeshFactory.box(Vector3(0.5, 0.02, 0.7), Palette.AIM_ARROW, Palette.GLOW_STRONG)
	tip.position = Vector3(0.0, 0.05, -3.5)
	root.add_child(shaft)
	root.add_child(tip)
	return root
