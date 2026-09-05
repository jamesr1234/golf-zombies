class_name ThrownGun
extends Node3D
## A gun lobbed past its line. It tumbles, floors the first rival it lands on,
## and is gone whether it hit or not. Nothing picks it back up.

const SPEED := 22.0
const LIFT := 0.2
const GRAVITY := 18.0
const MAX_FLIGHT := 2.4
## Body radius a throw still counts as a hit inside.
const HIT_PAD := 0.85
## Seconds a rival spends on the floor after a thrown gun lands on them.
const FLOOR_SECONDS := 3.0

var velocity := Vector3.ZERO
## Null on a client, which only shows the tumble and lets the host judge the hit.
var thrower: Player
var _age := 0.0
var _dead := false


static func spawn(
	root: Node, origin: Vector3, fly: Vector3, stats: WeaponStats, p_thrower: Player
) -> ThrownGun:
	if root == null:
		return null
	var gun := ThrownGun.new()
	var facing := fly.normalized() if fly.length_squared() > 0.0001 else Vector3.FORWARD
	gun.velocity = facing * SPEED + Vector3.UP * (SPEED * LIFT)
	gun.thrower = p_thrower
	gun.add_to_group("thrown_guns")
	root.add_child(gun)
	gun.global_position = origin
	gun.add_child(_visual(stats))
	return gun


## The gun that left your hands, shown at pickup scale so it reads mid-air.
static func _visual(stats: WeaponStats) -> Node3D:
	var vis := Node3D.new()
	vis.name = "Mesh"
	if stats == null:
		return vis
	if stats.visual == "rocket":
		Raygun.build_rocket(vis, Palette.PLAYER_ONE)
		vis.scale = Vector3.ONE * 2.0
	else:
		ShopProps.preview(vis, {"id": stats.visual})
	return vis


## Only a rival can be floored. Solo and co-op have no one to throw at, and a
## partner is on your side in co-op VS.
static func is_rival(thrower: Player, victim: Player) -> bool:
	if thrower == null or victim == null or thrower == victim:
		return false
	if not GameSettings.is_online():
		return false
	return victim != thrower.partner and thrower != victim.partner


static func floor_player(victim: Player, from: Vector3) -> void:
	if victim == null:
		return
	victim.knock_to_floor(FLOOR_SECONDS, from)


static func rival_near(thrower: Player, tree: SceneTree, at: Vector3) -> Player:
	if tree == null:
		return null
	var best: Player
	var best_d := INF
	for node in tree.get_nodes_in_group("players"):
		var player := node as Player
		if player == null or not is_rival(thrower, player):
			continue
		var centre := player.global_position + Vector3.UP * 0.9
		var dist := at.distance_to(centre)
		if dist <= HIT_PAD + 0.5 and dist < best_d:
			best = player
			best_d = dist
	return best


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_age += delta
	velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	var victim := rival_near(thrower, get_tree(), to)
	if victim != null:
		_arrive(to, victim)
		return
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.BULLET_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_arrive(hit["position"], hit.get("collider") as Player)
		return
	global_position = to
	rotation.x += delta * 9.0
	rotation.z += delta * 4.0
	if _age >= MAX_FLIGHT:
		_die()


func _arrive(at: Vector3, collider: Player) -> void:
	global_position = at
	var victim := collider if is_rival(thrower, collider) else rival_near(thrower, get_tree(), at)
	# Only the host decides who goes down; a client copy is a tumble and nothing else.
	if victim != null and thrower != null and not NetSession.defers_world():
		floor_player(victim, at)
	_die()


func _die() -> void:
	if _dead:
		return
	_dead = true
	queue_free()
