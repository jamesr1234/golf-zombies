class_name CartWobble
extends Object
## Floppy cabin, like a ragdoll strapped to the chassis. Lean has mass, the
## canopy lags, and letting go rocks it back past center.

const REF_SPEED := 35.0 * 5.0 / 6.0
const CRAWL := 2.5
const STEER_DEAD := 0.15
## Only a near-full lock at speed can actually go over.
const STEER_LOCK := 0.85
const SPEED_LOCK := 0.9
const UNSTABLE := 0.82
const TIP := 1.05
const LEAN_MAX := 1.25
const TIP_HOLD := 0.7
## A slide buys more time, but a locked drift still goes over if you keep it.
const TIP_HOLD_DRIFT := 1.25
const TIP_SNAP := 0.28
const RIGHT_TIME := 1.15
const RIGHT_HZ := 2.7
const RIGHT_DAMP := 3.8
const RIGHT_AMP := 0.72
const SPRING := 26.0
const DAMP := 6.4
const TIP_PULL := 5.5
const DRIFT_LEAN := 0.35
const DRIFT_PULL := 0.4
const SHEAR_SPRING := 13.0
const SHEAR_DAMP := 4.0
const PITCH_COUPLE := 0.04
const MAX_PITCH := deg_to_rad(7.0)
const LIMIT_BOUNCE := 0.2
const LAND_JOLT := 1.6
const MAX_ROLL := deg_to_rad(28.0)
const TIP_ROLL := deg_to_rad(88.0)
const SKEW := 0.24
## Godot +Z roll lifts the right side, so a right-hand lean has to go negative.
const ROLL_SIGN := -1.0


static func speed_ratio(speed: float, max_speed := REF_SPEED) -> float:
	return clampf(absf(speed) / maxf(1.0, max_speed), 0.0, 1.35)


static func demand(steer: float, speed: float, drift: float, max_speed := REF_SPEED) -> float:
	if absf(speed) < CRAWL:
		return 0.0
	if absf(steer) < STEER_DEAD:
		return 0.0
	return (
		clampf(steer, -1.0, 1.0)
		* speed_ratio(speed, max_speed)
		* (1.0 + DRIFT_LEAN * clampf(drift, 0.0, 1.0))
	)


static func same_way(steer: float, lean: float) -> bool:
	return steer * lean > 0.0


## x is lean, y is angular vel. Semi-implicit so a flick overshoots.
static func next_state(
	lean: float, vel: float, steer: float, speed: float, drift: float, delta: float,
	max_speed := REF_SPEED
) -> Vector2:
	var wanted := demand(steer, speed, drift, max_speed)
	var accel := SPRING * (wanted - lean) - DAMP * vel
	if can_fall(lean, steer, speed, max_speed):
		var pull := TIP_PULL
		if drift > 0.0:
			pull *= lerpf(1.0, DRIFT_PULL, clampf(drift, 0.0, 1.0))
		accel += signf(lean) * pull
	vel += accel * delta
	var next := lean + vel * delta
	if next > LEAN_MAX or next < -LEAN_MAX:
		vel *= -LIMIT_BOUNCE
	return Vector2(clampf(next, -LEAN_MAX, LEAN_MAX), vel)


static func next_follow(
	pos: float, vel: float, target: float, delta: float, spring := SHEAR_SPRING, damp := SHEAR_DAMP
) -> Vector2:
	vel += (spring * (target - pos) - damp * vel) * delta
	return Vector2(pos + vel * delta, vel)


static func pitch_from_vel(vel: float) -> float:
	return clampf(vel * PITCH_COUPLE, -MAX_PITCH, MAX_PITCH)


static func land_jolt(vel: float, lean: float, strength: float) -> float:
	if absf(lean) < STEER_DEAD or strength <= 0.0:
		return vel
	return vel + signf(lean) * strength * LAND_JOLT


static func can_fall(
	lean: float, steer: float, speed: float, max_speed := REF_SPEED
) -> bool:
	return (
		absf(lean) > UNSTABLE
		and same_way(steer, lean)
		and absf(steer) >= STEER_LOCK
		and speed_ratio(speed, max_speed) >= SPEED_LOCK
	)


static func should_charge_tip(
	lean: float, steer: float, _drift := 0.0, speed := REF_SPEED, max_speed := REF_SPEED
) -> bool:
	return absf(lean) >= TIP and can_fall(lean, steer, speed, max_speed)


## Once the cabin is in the danger zone the jiggle must not zero the meter.
static func next_tip_hold(
	hold: float, lean: float, steer: float, delta: float, drift := 0.0,
	speed := REF_SPEED, max_speed := REF_SPEED
) -> float:
	if should_charge_tip(lean, steer, drift, speed, max_speed):
		return hold + delta
	if not can_fall(lean, steer, speed, max_speed):
		return 0.0
	return hold


static func tip_need(drift := 0.0) -> float:
	return lerpf(TIP_HOLD, TIP_HOLD_DRIFT, clampf(drift, 0.0, 1.0))


static func should_tip(hold: float, drift := 0.0) -> bool:
	return hold >= tip_need(drift)


static func is_tipped(age: float) -> bool:
	return age >= 0.0


static func is_righting(age: float) -> bool:
	return age >= 0.0 and age < RIGHT_TIME


static func tip_blend(age: float) -> float:
	if age < 0.0:
		return 0.0
	return clampf(age / TIP_SNAP, 0.0, 1.0)


static func right_basis(age: float, tip_sign := 1.0) -> Basis:
	var t := clampf(age / RIGHT_TIME, 0.0, 1.0)
	var up := t * t * (3.0 - 2.0 * t)
	var wob := exp(-RIGHT_DAMP * age) * sin(TAU * RIGHT_HZ * age)
	var side := 1.0 if tip_sign >= 0.0 else -1.0
	var lean := side * ((1.0 - up) + wob * RIGHT_AMP)
	var shear := side * ((1.0 - up) + wob * 0.9)
	var pitch := wob * deg_to_rad(10.0)
	var tip := clampf(1.0 - up * 1.35, 0.0, 1.0)
	return body_basis(lean, shear, pitch, tip, side)


static func body_basis(
	lean: float, shear := 0.0, pitch := 0.0, tipped := 0.0, tip_sign := 1.0
) -> Basis:
	var roll := ROLL_SIGN * lean * MAX_ROLL
	var nod := pitch
	var skew := shear
	var blend := clampf(tipped, 0.0, 1.0)
	if blend > 0.0:
		var side := 1.0 if tip_sign >= 0.0 else -1.0
		roll = lerpf(roll, ROLL_SIGN * side * TIP_ROLL, blend)
		nod = lerpf(nod, 0.0, blend)
		skew = lerpf(skew, side, blend)
	var pose := Basis.from_euler(Vector3(nod, 0.0, roll))
	pose.y += pose.x * skew * SKEW
	return pose
