class_name MechCombat
extends RefCounted
## Shoulder rockets and the stomp. Mag of eight, then Square to reload.

const MAG_SIZE := 8
const RELOAD := 2.4
const FIRE_GAP := 0.55
const STOMP_DAMAGE := 100.0
const STOMP_PUSH := 14.0
const ROCKET_DAMAGE := 110.0
const ROCKET_RADIUS := 13.0
const ROCKET_RANGE := 90.0

const _WorldFx := preload("res://scripts/net/world_fx.gd")

var mag := MAG_SIZE
var reload_left := 0.0
var cooldown := 0.0
var next_right := false
var _hit := {}


func tick(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if reload_left > 0.0:
		reload_left = maxf(0.0, reload_left - delta)
		if reload_left <= 0.0:
			mag = MAG_SIZE
			Sfx.play("reload_done")


func is_reloading() -> bool:
	return reload_left > 0.0


func try_reload() -> bool:
	if is_reloading() or mag >= MAG_SIZE:
		return false
	reload_left = RELOAD
	Sfx.play("reload")
	return true


func try_fire(suit: Node3D, view: Transform3D, shooter: Player) -> bool:
	if mag <= 0 or is_reloading() or cooldown > 0.0:
		if mag <= 0 and not is_reloading():
			Sfx.play("empty_click", suit)
		return false
	mag -= 1
	cooldown = FIRE_GAP
	var right := next_right
	next_right = not next_right
	var origin := _muzzle(suit, view, right)
	var fly := fly_to_crosshair(origin, view, aim_point(suit, view, ROCKET_RANGE))
	var rocket := Rocket.spawn_flight(
		_fx_root(suit), origin, fly, ROCKET_DAMAGE, ROCKET_RADIUS, ROCKET_RANGE
	)
	if rocket != null:
		rocket.shooter = shooter
		rocket.ignore_body(suit)
		_WorldFx.announce_rocket(
			suit, origin, fly, rocket.damage, rocket.blast_radius, rocket.max_range
		)
	Sfx.play("rocket_fire", suit)
	return true


## Camera look point, or the surface the crosshair is on. Shells start at the
## shoulder and fly here so they meet the reticle instead of running parallel.
static func aim_point(suit: Node3D, view: Transform3D, range_m: float) -> Vector3:
	var far := look_point(view, range_m)
	if suit == null or not suit.is_inside_tree():
		return far
	var world := suit.get_world_3d()
	if world == null:
		return far
	var query := PhysicsRayQueryParameters3D.create(view.origin, far, Layers.BULLET_MASK)
	if suit is CollisionObject3D:
		query.exclude = [(suit as CollisionObject3D).get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return far
	return hit["position"]


static func look_point(view: Transform3D, range_m: float) -> Vector3:
	return view.origin + (-view.basis.z) * range_m


static func fly_to_crosshair(origin: Vector3, view: Transform3D, aim_at: Vector3) -> Vector3:
	var fly := aim_at - origin
	if fly.length_squared() < 0.0001:
		return -view.basis.z
	return fly.normalized()


func stomp(suit: Node3D, area: Area3D, allies: Array) -> void:
	if area == null:
		return
	var moving := Vector2(suit.velocity.x, suit.velocity.z).length() > 1.2
	if not moving and not (suit as CharacterBody3D).is_on_floor():
		moving = true
	if not moving:
		return
	var push := -suit.global_transform.basis.z
	push.y = 0.0
	if push.length_squared() < 0.0001:
		push = Vector3.FORWARD
	else:
		push = push.normalized()
	for body in area.get_overlapping_bodies():
		var id := body.get_instance_id()
		if _hit.has(id) or allies.has(body):
			continue
		_hit[id] = true
		var zombie := body as Zombie
		if zombie != null and not zombie.is_allied() and not zombie.is_dying():
			var hit := zombie.global_position + Vector3.UP * zombie.stats.height * 0.22
			zombie.take_damage(STOMP_DAMAGE, push, hit)
			zombie.stagger(push * STOMP_PUSH)
			Sfx.play("crush", suit)
			continue
		var player := body as Player
		if player != null and player.health.is_alive():
			player.apply_hit(STOMP_DAMAGE, suit.global_position)
			Sfx.play("crush", suit)


func forget(body: Node) -> void:
	if body != null:
		_hit.erase(body.get_instance_id())


static func _muzzle(suit: Node3D, view: Transform3D, right: bool) -> Vector3:
	var node := suit.find_child("RightMuzzle" if right else "LeftMuzzle", true, false) as Node3D
	if node != null:
		return node.global_position
	var side := 1.12 * MechVisuals.SCALE if right else -1.12 * MechVisuals.SCALE
	return suit.to_global(Vector3(side, 3.72 * MechVisuals.SCALE, -0.48 * MechVisuals.SCALE))


static func _fx_root(from: Node) -> Node:
	if from == null or not from.is_inside_tree():
		return from
	var root := from.get_tree().get_first_node_in_group("fx_root")
	return root if root != null else from
