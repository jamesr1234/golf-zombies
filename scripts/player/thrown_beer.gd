class_name ThrownBeer
extends Node3D
## A tossed can. Zombies catch it if it reaches them; everything else just
## knocks it out of the air.

const SPEED := 16.5
const LIFT := 0.22
const GRAVITY := 18.0
const MAX_FLIGHT := 1.8
const CATCH_PAD := 0.55
const _BeerCan := preload("res://scripts/player/beer_can.gd")


var velocity := Vector3.ZERO
var visual_only := false
var _age := 0.0
var _dead := false


static func spawn(
	root: Node, origin: Vector3, fly: Vector3, p_visual_only := false
) -> ThrownBeer:
	if root == null:
		return null
	var can := ThrownBeer.new()
	var facing := fly.normalized() if fly.length_squared() > 0.0001 else Vector3.FORWARD
	can.velocity = facing * SPEED + Vector3.UP * (SPEED * LIFT)
	can.visual_only = p_visual_only
	can.add_to_group("thrown_beers")
	root.add_child(can)
	can.global_position = origin
	can.add_child(_BeerCan.create(1.15))
	return can


static func catcher_near(tree: SceneTree, at: Vector3) -> Zombie:
	if tree == null:
		return null
	var best: Zombie
	var best_d := INF
	for node in tree.get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null or not zombie.can_catch():
			continue
		var centre := zombie.global_position + Vector3.UP * zombie.stats.height * 0.55
		var reach := zombie.stats.radius + CATCH_PAD
		var dist := at.distance_to(centre)
		if dist <= reach and dist < best_d:
			best = zombie
			best_d = dist
	return best


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_age += delta
	velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.BULLET_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var at := to
	if not hit.is_empty():
		at = hit["position"]
		_arrive(at, hit.get("collider"))
		return
	var catcher := catcher_near(get_tree(), to)
	if catcher != null:
		_arrive(to, catcher)
		return
	global_position = to
	rotation.x += delta * 10.0
	if _age >= MAX_FLIGHT:
		_die()


func _arrive(at: Vector3, collider: Object) -> void:
	global_position = at
	var zombie := collider as Zombie
	if zombie == null:
		zombie = catcher_near(get_tree(), at)
	if zombie != null and not visual_only:
		zombie.catch_beer()
	_die()


func _die() -> void:
	if _dead:
		return
	_dead = true
	queue_free()
