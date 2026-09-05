class_name CartBrake
extends Object
## L2 is a panic brake: the cart sheds speed fast, but it still rolls a bit
## before it stops. Anyone in the passenger seat keeps going, ragdoll first.

## Half a second from top speed — hard enough that shotgun keeps going.
const DECEL := 54.0
const YEET_MIN := 7.0
const NOD := deg_to_rad(16.0)
const NOD_LIMIT := deg_to_rad(24.0)
const PITCH_SPRING := 55.0
const PITCH_DAMP := 4.5
const PITCH_KICK := 7.0
## Hang time is tuned so max regular cart speed throws about thirty metres.
const YEET_LIFT := 11.0
const YEET_HEIGHT := 0.8
const YEET_LOCK := 1.8
const FLOOR_TIME := 2.2
const AHEAD := 1.7
const RANGE_AT_MAX := 30.0
const _GRAVITY := 9.8 * PlayerMotion.GRAVITY_SCALE


static func next_speed(speed: float, delta: float) -> float:
	return move_toward(speed, 0.0, DECEL * delta)


## x is pitch, y is angular vel. Negative pitch drops the nose.
static func next_pitch(
	pitch: float, vel: float, braking: bool, speed: float, delta: float
) -> Vector2:
	var wanted := 0.0
	if braking:
		wanted = -NOD * clampf(speed / GolfCart.MAX_SPEED, -1.35, 1.35)
	vel += (PITCH_SPRING * (wanted - pitch) - PITCH_DAMP * vel) * delta
	pitch = clampf(pitch + vel * delta, -NOD_LIMIT, NOD_LIMIT)
	return Vector2(pitch, vel)


static func kick_pitch(pitch: float, vel: float, speed: float) -> Vector2:
	var ratio := clampf(absf(speed) / GolfCart.MAX_SPEED, 0.0, 1.35)
	if ratio <= 0.0:
		return Vector2(pitch, vel)
	return Vector2(pitch, vel - PITCH_KICK * ratio * signf(speed))


static func should_toss(speed: float) -> bool:
	return absf(speed) >= YEET_MIN


static func travel_dir(cart: Node3D, speed: float) -> Vector3:
	var nose := Vector3(-sin(cart.rotation.y), 0.0, -cos(cart.rotation.y))
	if absf(speed) < 0.05:
		var flat := Vector3(cart.velocity.x, 0.0, cart.velocity.z)
		if flat.length_squared() > 0.01:
			return flat.normalized()
		return nose
	return nose if speed > 0.0 else -nose


static func toss_speed(speed: float) -> float:
	return absf(speed)


static func hang_time(height := YEET_HEIGHT) -> float:
	return (YEET_LIFT + sqrt(YEET_LIFT * YEET_LIFT + 2.0 * _GRAVITY * height)) / _GRAVITY


static func throw_range(speed: float, height := YEET_HEIGHT) -> float:
	return toss_speed(speed) * hang_time(height)


static func slam(cart: GolfCart, speed: float) -> void:
	if cart == null:
		return
	var nod := kick_pitch(cart._brake_pitch, cart._brake_pitch_vel, speed)
	cart._brake_pitch = nod.x
	cart._brake_pitch_vel = nod.y
	if absf(speed) > 1.0:
		Sfx.play("brake", cart)
	if not should_toss(speed):
		return
	var rider := cart.passenger
	if rider == null:
		return
	toss(cart, rider, travel_dir(cart, speed), speed)
	cart._broadcast_seats()


static func toss(cart: GolfCart, player: Player, along: Vector3, speed: float) -> void:
	if cart == null or player == null or not cart.is_riding(player):
		return
	var dir := Vector3(along.x, 0.0, along.z)
	if dir.length_squared() < 0.0001:
		dir = travel_dir(cart, speed)
	dir = dir.normalized()
	cart.unseat_at(player, cart.windshield_drop(dir))
	player.fling(dir, toss_speed(speed), YEET_LIFT, YEET_LOCK)
	player.knock_to_floor(FLOOR_TIME, player.global_position - dir * 2.0, 0.0)
