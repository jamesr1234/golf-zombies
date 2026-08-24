class_name Grappler
extends RefCounted
## Fires a claw at a cart or mech. Once it bites, the rope tows you along until
## you jump off, fire again, or grab the ball.

const RANGE := 36.0
const MIN_SLACK := 2.4
const STIFF := 16.0
const REEL := 9.0
const SWING := 7.5
const YANK := 6.0
const FOV := 98.0
const HOOK_MASK := Layers.HOOK_MASK


var target: Node3D
var local := Vector3.ZERO
var slack := 0.0
var _hook: Node3D


func is_latched() -> bool:
	return target != null and is_instance_valid(target)


func is_flying() -> bool:
	return _hook != null and is_instance_valid(_hook)


func is_active() -> bool:
	return is_latched() or is_flying()


func attach_world() -> Vector3:
	if not is_latched():
		return Vector3.INF
	return target.to_global(local)


func line_end() -> Vector3:
	if is_latched():
		return attach_world()
	if is_flying():
		return _hook.global_position
	return Vector3.INF


func fire(player: Player, origin: Vector3, direction: Vector3, visual_only := false) -> bool:
	if player == null or is_active() or direction.length_squared() < 0.0001:
		return false
	var dir := direction.normalized()
	var exclude: Array[RID] = []
	var body := player as CollisionObject3D
	if body != null:
		exclude.append(body.get_rid())
	var hit := trace(player.get_world_3d(), origin, dir, exclude)
	var hook := GrappleHook.spawn(_fx_root(player), origin, dir, player, visual_only)
	if hook == null:
		return false
	_hook = hook
	var ride := hitchable(hit.get("collider")) if not hit.is_empty() else null
	if ride != null:
		hook.lock_on(ride, ride.to_local(hit["position"]))
	else:
		var end: Vector3 = origin + dir * RANGE
		if not hit.is_empty():
			end = hit["position"]
		hook.fly_to(end)
	Sfx.play("grapple_fire", player)
	return true


func latch(player: Player, on: Node3D, at: Vector3) -> bool:
	if player == null or on == null or not is_instance_valid(on):
		return false
	if hitchable(on) == null:
		return false
	_clear_hook()
	target = on
	local = on.to_local(at)
	slack = clampf(player.global_position.distance_to(at), MIN_SLACK, RANGE)
	var toward := at - player.global_position
	if toward.length_squared() > 0.001:
		player.velocity += toward.normalized() * YANK
	Sfx.play("grapple_latch", player)
	return true


func tick(player: Player, delta: float) -> bool:
	if not is_latched() or player.health == null or not player.health.is_alive():
		return false
	if player.input.just_pressed("jump") or player.input.just_pressed("grapple"):
		return false
	if player.motion.sprinting(player):
		slack = move_toward(slack, MIN_SLACK, REEL * delta)
	var hook := attach_world()
	var ride_vel := _ride_velocity()
	var next := tow_velocity(
		player.global_position, player.velocity, hook, ride_vel, slack, delta,
		_swing(player)
	)
	player.velocity = next
	player.move_and_slide()
	var taut := taut_offset(player.global_position, hook, slack)
	if taut.length_squared() > 0.0001:
		player.global_position += taut
	return true


func drop() -> void:
	_clear_hook()
	target = null
	local = Vector3.ZERO
	slack = 0.0


func cancel_flight() -> void:
	_clear_hook()


static func hitchable(node: Object) -> Node3D:
	var walk := node as Node
	while walk != null:
		if walk is GolfCart or walk is CartGirl or walk is MechSuit:
			return walk as Node3D
		walk = walk.get_parent()
	return null


static func trace(
	world: World3D, from: Vector3, direction: Vector3, exclude: Array[RID] = []
) -> Dictionary:
	if world == null or direction.length_squared() < 0.0001:
		return {}
	var dir := direction.normalized()
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE, HOOK_MASK)
	query.exclude = exclude
	return world.direct_space_state.intersect_ray(query)


static func taut_offset(from: Vector3, hook: Vector3, length: float) -> Vector3:
	var away := from - hook
	var dist := away.length()
	if dist <= length or dist < 0.001:
		return Vector3.ZERO
	return away.normalized() * (length - dist)


static func tow_velocity(
	from: Vector3, current: Vector3, hook: Vector3, ride_vel: Vector3, length: float,
	delta: float, swing := Vector3.ZERO
) -> Vector3:
	var to_hook := hook - from
	var dist := to_hook.length()
	var vel := ride_vel + swing
	if dist > length and dist > 0.001:
		vel += to_hook / dist * (dist - length) * STIFF
	elif dist + 0.4 < length:
		vel.y += current.y * 0.25
		vel += Vector3(0.0, -18.0, 0.0) * delta
	return vel


static func muzzle_of(player: Player) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.raygun != null and player.raygun.visible:
		var tip := player.raygun.forward_extent()
		if tip < -0.01:
			return player.raygun.to_global(Vector3(0.0, 0.0, tip))
	if player.head != null:
		return player.head.global_position
	return player.global_position + Vector3.UP * 1.4


func _swing(player: Player) -> Vector3:
	var stick: Vector2 = player.motion.walk_stick(player)
	if stick.length_squared() < 0.04:
		return Vector3.ZERO
	var side: Vector3 = player.transform.basis.x * stick.x - player.transform.basis.z * stick.y
	side.y = 0.0
	if side.length_squared() < 0.001:
		return Vector3.ZERO
	return side.normalized() * stick.length() * SWING


func _ride_velocity() -> Vector3:
	var body := target as CharacterBody3D
	if body == null:
		return Vector3.ZERO
	return body.velocity


func _clear_hook() -> void:
	if _hook != null and is_instance_valid(_hook):
		_hook.queue_free()
	_hook = null


func _fx_root(from: Node) -> Node:
	if from == null or not from.is_inside_tree():
		return from
	var root := from.get_tree().get_first_node_in_group("fx_root")
	if root != null:
		return root
	return from
