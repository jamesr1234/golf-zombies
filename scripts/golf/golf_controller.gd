class_name GolfController
extends Node3D
## Owns golf mode: who is swinging, where they are aiming, the swing meter, and
## the third-person camera framing. Only one player can hold the ball at a time
## and the claim is released as soon as the shot resolves, so the golfer always
## has to walk back to the ball.

signal stroke_taken()
signal golfer_changed(golfer: Node)

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

var ball: GolfBall
var golfer: Node = null
var aim_yaw := 0.0
var meter := SwingMeter.new()
var club_kit: ClubKit = ClubKit.starter()
## Diameter of the green this stroke is playing to. A stuffed putt runs 2.4x this.
var green_span := 0.0

var _cup := Vector3.ZERO
var _arrow: Node3D
var _club: GolfClub
var _shot_eye := Vector3.ZERO
## Where the ball was addressed. Held while the ball is in the air so the golfer
## and the club stay planted on the lie instead of riding the shot.
var _lie := Vector3.ZERO


func _ready() -> void:
	_arrow = _build_arrow()
	add_child(_arrow)
	_arrow.visible = false
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
	return _horizontal_distance(player) <= CLAIM_RANGE


func try_toggle(player: Node) -> void:
	if golfer == player:
		release()
	elif can_claim(player):
		_claim(player)


func release() -> void:
	if golfer == null:
		return
	var previous := golfer
	golfer = null
	meter.reset()
	_arrow.visible = false
	_club.visible = false
	if previous.has_method("exit_golf_mode"):
		previous.exit_golf_mode()
	golfer_changed.emit(null)


## Interrupted mid-swing: the stroke does not count.
func cancel_swing() -> void:
	if meter.is_swinging():
		meter.reset()


func click() -> void:
	if golfer == null or ball.is_in_play():
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


func get_camera_transform() -> Transform3D:
	var pivot := ball.global_position if ball != null else global_position
	if ball != null and ball.is_in_play():
		return _look_from(_shot_eye, pivot)
	var forward := Shot.aim_direction(aim_yaw, 0.0)
	var eye := (
		pivot - forward * CAMERA_DISTANCE + Vector3.UP * CAMERA_HEIGHT
		+ forward.cross(Vector3.UP) * CAMERA_SIDE
	)
	return _look_from(eye, pivot + Vector3.UP * CAMERA_LOOK_HEIGHT)


func _process(delta: float) -> void:
	if golfer == null:
		return
	if meter.is_swinging():
		meter.tick(delta)
		if meter.is_done():
			_strike()
	if not ball.is_in_play():
		_lie = ball.global_position
	_arrow.global_position = _lie
	_arrow.rotation = Vector3(0.0, deg_to_rad(aim_yaw), 0.0)
	_pose_swing(delta)


## Holds the golfer at address beside the ball and swings the club through it.
## Standing them there is what makes the swing land on the ball at all: the claim
## can be made from a few metres out.
func _pose_swing(delta: float) -> void:
	_club.pose(_lie, aim_yaw, meter.value, delta, _is_putting())
	if golfer.has_method("stand_at"):
		golfer.stand_at(
			GolfClub.stance_point(_lie, aim_yaw), aim_yaw + _club.angle * BODY_TURN_RATIO
		)


func _claim(player: Node) -> void:
	golfer = player
	meter.reset()
	_apply_kit()
	_lie = ball.global_position
	aim_yaw = _yaw_towards(_cup)
	_arrow.visible = true
	_club.visible = true
	if player.has_method("enter_golf_mode"):
		player.enter_golf_mode()
	golfer_changed.emit(player)
	Sfx.play("golf_claim", self)


func _strike() -> void:
	_apply_kit()
	ball.strike(aim_yaw, meter.deviation_deg, meter.power, _shot_kit(), green_span)
	meter.reset()
	_arrow.visible = false
	_club.start_follow_through()
	stroke_taken.emit()
	Sfx.play("putt" if _is_putting() else "club_hit", self)


func _shot_kit() -> ClubKit:
	var kit := club_kit if club_kit != null else ClubKit.starter()
	var who := golfer as Player
	if who == null:
		return kit
	return kit.boosted(who.buzz.strength_mult())


func _apply_kit() -> void:
	if club_kit == null:
		club_kit = ClubKit.starter()
	meter.kit = club_kit
	if _club != null:
		_club.apply_kit(club_kit)


func _is_putting() -> bool:
	return ball != null and ball.is_putting()


func _yaw_towards(target: Vector3) -> float:
	var to_target := target - ball.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.001:
		return aim_yaw
	# Vector3.FORWARD is -Z, so the yaw that points at the target is measured
	# from that axis.
	return rad_to_deg(atan2(-to_target.x, -to_target.z))


func _horizontal_distance(player: Node) -> float:
	var offset: Vector3 = (player as Node3D).global_position - ball.global_position
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
