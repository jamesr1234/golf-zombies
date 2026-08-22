class_name Melee
extends Node
## Close-range shove. The hit point on the zombie decides the launch: high hits
## pop them up, low hits send them sliding, and a blow off to one side spins
## them that way. A shove always pops them into fireworks after a short flight.

const RANGE := 2.9
const ARC_DEG := 70.0
const DAMAGE := 40.0
const COOLDOWN := 0.85
## How long the first-person gun and the robot arms take to swing.
const SWING_TIME := 0.42
## Fraction of the swing that is wind-up into the hit.
const CONTACT_T := 0.38
## Fraction of the swing that is follow-through before the pose recovers.
const FOLLOW_T := 0.72
## Horizontal speed of a clean centre hit on a walker.
const LAUNCH_SPEED := 18.0
const UP_MIN := 5.0
const UP_PER_HEIGHT := 14.0
const SIDE_KICK := 12.0

var _cooldown := 0.0


func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


func is_ready() -> bool:
	return _cooldown <= 0.0


func shove(origin: Vector3, forward: Vector3, strength := 1.0, attacker: Player = null) -> bool:
	if not is_ready():
		return false
	_cooldown = COOLDOWN
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null:
			continue
		if zombie.has_method("is_allied") and zombie.is_allied():
			continue
		if not in_arc(origin, flat_forward, zombie.global_position, RANGE, ARC_DEG):
			continue
		if attacker != null:
			zombie.last_hit_by = attacker
		zombie.melee_hit(origin, strength)
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player == null or player == attacker:
			continue
		if not in_arc(origin, flat_forward, player.global_position, RANGE, ARC_DEG):
			continue
		shove_player(attacker, player, origin, strength)
	return true


static func in_arc(
	origin: Vector3, flat_forward: Vector3, target: Vector3, range_m: float, arc_deg: float
) -> bool:
	var to_target := target - origin
	to_target.y = 0.0
	if to_target.length() > range_m or to_target.length_squared() < 0.001:
		return false
	return rad_to_deg(flat_forward.angle_to(to_target.normalized())) <= arc_deg * 0.5


static func shove_player(
	attacker: Player, victim: Player, origin: Vector3, strength := 1.0
) -> void:
	if victim == null or attacker == victim:
		return
	if victim.is_driving():
		var ride := victim.cart
		if ride == null and victim.flow != null and victim.flow.has_method("cart_for"):
			ride = victim.flow.cart_for(victim)
		if ride != null:
			ride.try_hijack(attacker)
			return
	victim.apply_knockback(origin, 10.0 * maxf(0.35, strength))


## How much of the melee pose to show. Full through the hit, then a fade so the
## walk cycle (or the gun at rest) takes back over instead of snapping.
static func swing_weight(progress: float) -> float:
	var t := clampf(progress, 0.0, 1.0)
	if t <= FOLLOW_T:
		return 1.0
	return 1.0 - (t - FOLLOW_T) / (1.0 - FOLLOW_T)


## Three-pose club swing: wind-up, contact, follow-through, then ease back to
## rest (the zero vector). Ease-in into the hit so the strike reads as a snap.
static func swing_arc(progress: float, windup: Vector3, contact: Vector3, follow: Vector3) -> Vector3:
	var t := clampf(progress, 0.0, 1.0)
	if t < CONTACT_T:
		return windup.lerp(contact, ease(t / CONTACT_T, 1.7))
	if t < FOLLOW_T:
		return contact.lerp(follow, (t - CONTACT_T) / (FOLLOW_T - CONTACT_T))
	return follow.lerp(Vector3.ZERO, ease((t - FOLLOW_T) / (1.0 - FOLLOW_T), 0.45))


## Closest point on the zombie's capsule to the attacker. That is the hit: a
## shove aimed at the head and one aimed at the knees are not the same blow.
static func hit_point(
	origin: Vector3, body_origin: Vector3, height: float, radius: float
) -> Vector3:
	var axis_start := body_origin + Vector3.UP * radius
	var axis_end := body_origin + Vector3.UP * maxf(radius, height - radius)
	var on_axis := Geometry3D.get_closest_point_to_segment(origin, axis_start, axis_end)
	var offset := origin - on_axis
	if offset.length_squared() < 0.0001:
		return on_axis
	return on_axis + offset.normalized() * minf(radius, offset.length())


## 0 at the feet, 1 at the head.
static func hit_height(hit: Vector3, body_origin: Vector3, height: float) -> float:
	return clampf((hit.y - body_origin.y) / maxf(0.1, height), 0.0, 1.0)


## Launch the zombie from the hit. Direction is from the attacker through the
## contact, vertical from how high it landed, and a side kick from how far off
## centre the blow was.
static func impulse(
	origin: Vector3, hit: Vector3, body_origin: Vector3, height: float, resistance: float,
	strength := 1.0
) -> Vector3:
	var through := hit - origin
	if through.length_squared() < 0.0001:
		through = (body_origin + Vector3.UP * height * 0.5) - origin
	var horizontal := Vector3(through.x, 0.0, through.z)
	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3.FORWARD
	horizontal = horizontal.normalized()
	var scale := 1.0 / maxf(0.1, resistance)
	var height_t := hit_height(hit, body_origin, height)
	var up := (UP_MIN + height_t * UP_PER_HEIGHT) * scale
	var along := LAUNCH_SPEED * (1.22 - height_t * 0.5) * scale
	var launch := horizontal * along + Vector3.UP * up
	var centre := body_origin + Vector3.UP * height * 0.5
	var side := Vector3(hit.x - centre.x, 0.0, hit.z - centre.z)
	if side.length_squared() > 0.0001:
		launch += side.normalized() * SIDE_KICK * scale
	return launch * maxf(0.1, strength)
