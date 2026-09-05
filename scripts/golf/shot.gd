class_name Shot
extends Object
## Launch tuning for the single club, shared by the ball and by the hole
## generator so par can never drift away from how far the club actually hits.

const LAUNCH_DEG := 20.0
const MAX_SPEED := 41.0
const MIN_SPEED := 7.0
const CHIP_LAUNCH_DEG := 8.0
const CHIP_MIN_SPEED := 3.0
## Experiment: full swings and chips carry this many times farther. Putts stay
## put. Hole length still plans around max_carry() so existing holes do not grow.
const DISTANCE_SCALE := 3.0
## Below this power a swing is a chip that blends into the full-swing curve.
const CHIP_BLEND := 0.4
## A stuffed putt rolls this many green-spans, so it can cross the dance floor
## with a little left and never fly off like a chip.
const PUTT_SPAN_MULT := 2.4
const PUTT_MIN_SPEED := 0.9
const GRAVITY := 9.8
## Stick-up flop and stick-down punch, applied on top of the power loft.
const MIN_LAUNCH_DEG := 4.0
const MAX_LAUNCH_DEG := 52.0
const LOFT_BIAS_MIN := -16.0
const LOFT_BIAS_MAX := 32.0
const FLIGHT_DT := 0.05
const FLIGHT_MAX_TIME := 20.0
const FLIGHT_MAX_POINTS := 400


## Flat-ground carry of a full swing off a clean lie, in metres.
static func max_carry() -> float:
	return MAX_SPEED * MAX_SPEED * sin(2.0 * deg_to_rad(LAUNCH_DEG)) / GRAVITY


## Peak height of a swing in metres, vacuum flight.
static func apex_height(power := 1.0, loft_bias := 0.0) -> float:
	var speed := _play_speed(power)
	var vy := speed * sin(deg_to_rad(launch_deg(power, loft_bias)))
	return vy * vy / (2.0 * GRAVITY)


## How far a swing travels before it falls back to `height` metres above the tee.
static func carry_to_height(height: float, power := 1.0, loft_bias := 0.0) -> float:
	var speed := _play_speed(power)
	var launch := deg_to_rad(launch_deg(power, loft_bias))
	var vy := speed * sin(launch)
	var disc := vy * vy - 2.0 * GRAVITY * height
	if disc <= 0.0:
		return 0.0
	return speed * cos(launch) / GRAVITY * (vy + sqrt(disc))


static func default_green_span() -> float:
	return HoleData.DEFAULT_GREEN_RADIUS * 2.0


## How far a stuffed putt runs on the green before the grass kills it.
static func putt_run(kit: ClubKit = null, green_span := 0.0) -> float:
	var clubs := kit if kit != null else ClubKit.starter()
	var span := green_span if green_span > 0.0 else default_green_span()
	return span * PUTT_SPAN_MULT * clubs.putt_speed_scale


static func putt_max_speed(kit: ClubKit = null, green_span := 0.0) -> float:
	return putt_run(kit, green_span) * Surface.LINEAR_DAMP[Surface.Type.GREEN]


static func can_putt(surface: Surface.Type) -> bool:
	return Surface.looks_like_green(surface)


static func launch_deg(power: float, loft_bias := 0.0) -> float:
	var t := clampf(power / CHIP_BLEND, 0.0, 1.0)
	var base := lerpf(CHIP_LAUNCH_DEG, LAUNCH_DEG, t)
	return clampf(base + loft_bias, MIN_LAUNCH_DEG, MAX_LAUNCH_DEG)


static func swing_speed(power: float) -> float:
	if power >= CHIP_BLEND:
		return lerpf(MIN_SPEED, MAX_SPEED, power)
	var full_at_blend := lerpf(MIN_SPEED, MAX_SPEED, CHIP_BLEND)
	return lerpf(CHIP_MIN_SPEED, full_at_blend, power / CHIP_BLEND)


static func _play_speed(power: float) -> float:
	return swing_speed(power) * sqrt(DISTANCE_SCALE)


static func aim_direction(yaw_deg: float, deviation_deg: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(yaw_deg + deviation_deg))


static func velocity(
	yaw_deg: float, deviation_deg: float, power: float,
	surface: Surface.Type, putting: bool, kit: ClubKit = null, green_span := 0.0,
	loft_bias := 0.0
) -> Vector3:
	var clubs := kit if kit != null else ClubKit.starter()
	var direction := aim_direction(yaw_deg, deviation_deg)
	var lie_mult: float = Surface.POWER_MULT[surface]
	if putting or can_putt(surface):
		var putt := lerpf(PUTT_MIN_SPEED, putt_max_speed(clubs, green_span), power)
		return direction * putt * lie_mult
	var speed := _play_speed(power) * lie_mult * clubs.speed_scale
	var launch := deg_to_rad(launch_deg(power, loft_bias))
	return (direction * cos(launch) + Vector3.UP * sin(launch)) * speed


## Perfect-contact flight, no slice. The aim line uses this so height you pick
## is the height you see. Lie defaults to a clean fairway (or green, if putting)
## so old callers still draw a full shot; the controller passes the real lie.
static func flight_points(
	origin: Vector3, yaw_deg: float, power: float, loft_bias := 0.0,
	putting := false, kit: ClubKit = null, green_span := 0.0,
	surface: Surface.Type = Surface.Type.FAIRWAY
) -> PackedVector3Array:
	var lie := surface
	if putting and not can_putt(lie):
		lie = Surface.Type.GREEN
	var launch := velocity(
		yaw_deg, 0.0, power, lie, putting, kit, green_span, loft_bias
	)
	var points := PackedVector3Array()
	points.append(origin)
	if putting:
		var run: float = launch.length() / float(Surface.LINEAR_DAMP[lie])
		var along := aim_direction(yaw_deg, 0.0)
		for i in range(1, 13):
			points.append(origin + along * run * (float(i) / 12.0))
		return points
	var pos := origin
	var vel := launch
	var elapsed := 0.0
	while elapsed < FLIGHT_MAX_TIME and points.size() < FLIGHT_MAX_POINTS:
		var next := pos + vel * FLIGHT_DT + Vector3.DOWN * GRAVITY * 0.5 * FLIGHT_DT * FLIGHT_DT
		vel.y -= GRAVITY * FLIGHT_DT
		elapsed += FLIGHT_DT
		if elapsed > FLIGHT_DT * 2.0 and next.y <= origin.y:
			var drop := pos.y - next.y
			var t := (pos.y - origin.y) / drop if drop > 0.001 else 1.0
			points.append(pos.lerp(next, clampf(t, 0.0, 1.0)))
			break
		pos = next
		points.append(pos)
	return points
