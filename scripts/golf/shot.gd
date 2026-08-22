class_name Shot
extends Object
## Launch tuning for the single club, shared by the ball and by the hole
## generator so par can never drift away from how far the club actually hits.

const LAUNCH_DEG := 20.0
const MAX_SPEED := 41.0
const MIN_SPEED := 7.0
const CHIP_LAUNCH_DEG := 8.0
const CHIP_MIN_SPEED := 3.0
## Below this power a swing is a chip that blends into the full-swing curve.
const CHIP_BLEND := 0.4
## A stuffed putt rolls this many green-spans, so it can cross the dance floor
## with a little left and never fly off like a chip.
const PUTT_SPAN_MULT := 2.4
const PUTT_MIN_SPEED := 0.9
const GRAVITY := 9.8


## Flat-ground carry of a full swing off a clean lie, in metres.
static func max_carry() -> float:
	return MAX_SPEED * MAX_SPEED * sin(2.0 * deg_to_rad(LAUNCH_DEG)) / GRAVITY


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


static func launch_deg(power: float) -> float:
	var t := clampf(power / CHIP_BLEND, 0.0, 1.0)
	return lerpf(CHIP_LAUNCH_DEG, LAUNCH_DEG, t)


static func swing_speed(power: float) -> float:
	if power >= CHIP_BLEND:
		return lerpf(MIN_SPEED, MAX_SPEED, power)
	var full_at_blend := lerpf(MIN_SPEED, MAX_SPEED, CHIP_BLEND)
	return lerpf(CHIP_MIN_SPEED, full_at_blend, power / CHIP_BLEND)


static func aim_direction(yaw_deg: float, deviation_deg: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(yaw_deg + deviation_deg))


static func velocity(
	yaw_deg: float, deviation_deg: float, power: float,
	surface: Surface.Type, putting: bool, kit: ClubKit = null, green_span := 0.0
) -> Vector3:
	var clubs := kit if kit != null else ClubKit.starter()
	var direction := aim_direction(yaw_deg, deviation_deg)
	var lie_mult: float = Surface.POWER_MULT[surface]
	if putting or can_putt(surface):
		var putt := lerpf(PUTT_MIN_SPEED, putt_max_speed(clubs, green_span), power)
		return direction * putt * lie_mult
	var speed := swing_speed(power) * lie_mult * clubs.speed_scale
	var launch := deg_to_rad(launch_deg(power))
	return (direction * cos(launch) + Vector3.UP * sin(launch)) * speed
