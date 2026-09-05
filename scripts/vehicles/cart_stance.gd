class_name CartStance
extends Object
## Plants the cart's wheelbase on uneven ground. A single floor normal pitches
## around the origin, so the nose digs into a ramp and the rear tires hang.

const WHEELBASE := CartVisuals.WHEEL_Z * 2.0
const PROBE_UP := 3.0
const PROBE_DOWN := 2.5
## A wheel that far above its probe has left the ground.
const PLANT_REACH := 0.85
## Highest vertical lip the cart will hop. Tarmac strips sit ~14 cm up; this
## also clears a sizeable dirt ridge without turning walls into ramps.
const STEP_MAX := 1.15
## Past the front axle, just beyond the box nose, so the lip is seen before
## the collider eats it as a wall.
const STEP_LOOK := 0.5
const STEP_EPS := 0.03
const MASK := Layers.WORLD | Layers.PROP | Layers.FORT | Layers.MECH


static func pitch_from_axles(front_y: float, rear_y: float, wheelbase := WHEELBASE) -> float:
	return atan2(front_y - rear_y, wheelbase)


static func ride_height(front_y: float, rear_y: float) -> float:
	return (front_y + rear_y) * 0.5


static func blend_normal(front: Vector3, rear: Vector3) -> Vector3:
	var n := front + rear
	if n.length_squared() < 0.0001:
		return Vector3.UP
	return n.normalized()


static func axle_point(origin: Vector3, yaw: float, local_z: float) -> Vector3:
	return origin + Vector3(sin(yaw), 0.0, cos(yaw)) * local_z


static func is_planted(wheel_y: float, hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	var at: Vector3 = hit.position
	return at.y >= wheel_y - PLANT_REACH


static func both_planted(
	front_wheel_y: float, rear_wheel_y: float, front: Dictionary, rear: Dictionary
) -> bool:
	return is_planted(front_wheel_y, front) and is_planted(rear_wheel_y, rear)


static func look_z(axle: float, reverse := false) -> float:
	return (axle + STEP_LOOK) if reverse else (-axle - STEP_LOOK)


static func can_step(current_y: float, hit: Dictionary, max_step := STEP_MAX) -> bool:
	if hit.is_empty():
		return false
	var rise: float = hit.position.y - current_y
	return rise > STEP_EPS and rise <= max_step


## A ramp takeoff keeps the nose up. Following vertical speed would plant it
## the moment the front tires leave the lip.
static func holds_air_pitch(pitch: float, on_floor: bool, launching := false) -> bool:
	return pitch > 0.0 and (not on_floor or launching)


## Soft landings just settle. A real jump compresses, then the springs overshoot.
const LAND_MIN := 4.0
const LAND_LIFT := 0.2
const LAND_NOD := 0.18
const LAND_HZ := 3.1
const LAND_DAMP := 4.6
const LAND_DONE := 0.04


static func land_strength(down_speed: float) -> float:
	if down_speed < LAND_MIN:
		return 0.0
	return clampf((down_speed - LAND_MIN) / 10.0, 0.0, 1.0)


## x is a vertical drop (negative compresses), y is extra pitch (negative nods).
static func bounce_offset(strength: float, age: float) -> Vector2:
	if strength <= 0.0 or age < 0.0:
		return Vector2.ZERO
	var decay := exp(-LAND_DAMP * age)
	if decay < LAND_DONE:
		return Vector2.ZERO
	var wave := cos(TAU * LAND_HZ * age)
	return Vector2(
		-LAND_LIFT * strength * decay * wave,
		-LAND_NOD * strength * decay * cos(TAU * LAND_HZ * age + 0.4)
	)


static func probe(
	space: PhysicsDirectSpaceState3D,
	origin: Vector3,
	yaw: float,
	local_z: float,
	exclude: Array[RID]
) -> Dictionary:
	if space == null:
		return {}
	var at := axle_point(origin, yaw, local_z)
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * PROBE_UP, at + Vector3.DOWN * PROBE_DOWN
	)
	query.collision_mask = MASK
	query.exclude = exclude
	return space.intersect_ray(query)


static func probe_down(
	space: PhysicsDirectSpaceState3D,
	at: Vector3,
	exclude: Array[RID],
	up := STEP_MAX + 0.5,
	down := 0.4
) -> Dictionary:
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * up, at + Vector3.DOWN * down
	)
	query.collision_mask = MASK
	query.exclude = exclude
	query.hit_from_inside = true
	return space.intersect_ray(query)
