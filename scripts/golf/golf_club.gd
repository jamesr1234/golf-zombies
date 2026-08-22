class_name GolfClub
extends Node3D
## The one club, drawn as a glowing shaft hanging from the golfer's grip down to
## the ball. Its pose is read straight off the swing meter, so the swing you watch
## is the swing you are timing rather than a canned animation played beside it.
##
## This also owns the stance: how far to the side of the ball the golfer stands and
## how high they hold the grip. The shaft is built to span exactly that gap, which
## is what puts the head on the ball at address and through it on contact.

const SIDE := 0.85
const HAND_HEIGHT := 1.2
const BACKSWING_ARC := 165.0
const FOLLOW_THROUGH_ARC := 155.0
## A putt is a short pendulum, not the same full swing used off the tee.
const PUTT_BACKSWING_ARC := 42.0
const PUTT_FOLLOW_THROUGH_ARC := 38.0
const FOLLOW_THROUGH_TIME := 0.225

## Where the club is pointing: 0 is address, negative is behind the golfer,
## positive is past the ball.
var angle := 0.0

var _follow_left := 0.0
var _head: MeshInstance3D


func _ready() -> void:
	# Tilted across to the ball, so the swing rotation sweeps the head along the
	# aim line at the ball's distance from the golfer rather than through them.
	var drop := HAND_HEIGHT - GolfBall.RADIUS
	var length := Vector2(SIDE, drop).length()
	var shaft := Node3D.new()
	shaft.rotation.z = atan2(SIDE, drop)
	add_child(shaft)
	var pole := MeshFactory.box(
		Vector3(0.05, length, 0.05), Palette.FLAGPOLE, Palette.GLOW_MEDIUM
	)
	pole.position.y = -length * 0.5
	shaft.add_child(pole)
	_head = MeshFactory.box(Vector3(0.28, 0.13, 0.17), Palette.CYAN, Palette.GLOW_STRONG)
	_head.position.y = -length
	shaft.add_child(_head)


func apply_kit(kit: ClubKit) -> void:
	if _head == null:
		return
	var clubs := kit if kit != null else ClubKit.starter()
	_head.material_override = MeshFactory.material(clubs.color, false, Palette.GLOW_STRONG)


## Called every frame the ball is owned.
func pose(
	lie: Vector3, aim_yaw_deg: float, meter_value: float, delta: float, putting := false
) -> void:
	if _follow_left > 0.0:
		_follow_left = maxf(0.0, _follow_left - delta)
		angle = follow_angle_deg(1.0 - _follow_left / FOLLOW_THROUGH_TIME, putting)
	else:
		angle = swing_angle_deg(meter_value, putting)
	var facing := Basis.looking_at(Shot.aim_direction(aim_yaw_deg, 0.0), Vector3.UP)
	var swing := Basis(Vector3.RIGHT, deg_to_rad(angle))
	global_transform = Transform3D(facing * swing, hands_point(lie, aim_yaw_deg))


## Contact happened: carry the club through instead of stopping it on the ball.
func start_follow_through() -> void:
	_follow_left = FOLLOW_THROUGH_TIME


## Where the golfer plants their feet: level with the ball, one step to the side of
## the aim line.
static func stance_point(lie: Vector3, aim_yaw_deg: float) -> Vector3:
	var right := Shot.aim_direction(aim_yaw_deg, 0.0).cross(Vector3.UP)
	return lie - Vector3.UP * GolfBall.RADIUS - right * SIDE


static func hands_point(lie: Vector3, aim_yaw_deg: float) -> Vector3:
	return stance_point(lie, aim_yaw_deg) + Vector3.UP * HAND_HEIGHT


static func swing_angle_deg(meter_value: float, putting := false) -> float:
	return -_backswing_arc(putting) * clampf(meter_value, 0.0, 1.0)


## Eased so the finish decelerates rather than snapping to a stop.
static func follow_angle_deg(fraction: float, putting := false) -> float:
	return _follow_arc(putting) * ease(clampf(fraction, 0.0, 1.0), 0.45)


static func _backswing_arc(putting: bool) -> float:
	return PUTT_BACKSWING_ARC if putting else BACKSWING_ARC


static func _follow_arc(putting: bool) -> float:
	return PUTT_FOLLOW_THROUGH_ARC if putting else FOLLOW_THROUGH_ARC
