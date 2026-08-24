class_name Rocket
extends Node3D
## Slow glowing shell. Hitscan guns share one code path; this is the other:
## fly until something solid is in the way, then pay the blast radius.

const SPEED := 48.0
const COLOR := Palette.HOT_PINK

var damage := 110.0
var blast_radius := 6.5
var max_range := 90.0
var direction := Vector3.FORWARD

var visual_only := false
var shooter: Player
var _exclude: Array[RID] = []
var _travelled := 0.0
var _dead := false


func ignore_body(body: Node) -> void:
	var solid := body as CollisionObject3D
	if solid != null:
		_exclude.append(solid.get_rid())


static func spawn(
	root: Node, origin: Vector3, fly: Vector3, stats: WeaponStats
) -> Rocket:
	if stats == null:
		return null
	return spawn_flight(
		root, origin, fly, stats.damage, stats.blast_radius, stats.range_m
	)


static func spawn_flight(
	root: Node, origin: Vector3, fly: Vector3, damage: float, radius: float, range_m: float,
	p_visual_only := false
) -> Rocket:
	if root == null:
		return null
	var rocket := Rocket.new()
	rocket.damage = damage
	rocket.blast_radius = radius
	rocket.max_range = range_m
	rocket.direction = fly.normalized()
	rocket.visual_only = p_visual_only
	rocket.add_to_group("rockets")
	root.add_child(rocket)
	rocket.global_position = origin
	rocket._build()
	return rocket


## Full damage to every living zombie inside the sphere. Kept as a static so
## the blast can be checked without waiting on a flying shell.
static func detonate(
	tree: SceneTree, at: Vector3, amount: float, radius: float, fx: Node = null,
	shooter: Player = null
) -> int:
	var hits := 0
	if tree == null:
		return 0
	var nets: Array[NetTrap] = []
	for node in tree.get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null or not is_instance_valid(zombie) or zombie.is_dying():
			continue
		var centre := zombie.global_position + Vector3.UP * zombie.stats.height * 0.5
		var away := centre - at
		if not in_blast(away.length(), radius):
			continue
		var trap := zombie.net_trap() as NetTrap
		if trap != null and not nets.has(trap):
			nets.append(trap)
		var push := away if away.length_squared() > 0.0001 else Vector3.UP
		var hit := Melee.hit_point(at, zombie.global_position, zombie.stats.height, zombie.stats.radius)
		zombie.take_damage(amount, push.normalized(), hit)
		hits += 1
	for trap in nets:
		trap.burst()
	for node in tree.get_nodes_in_group("mechs"):
		var mech := node as MechSuit
		if mech == null or not is_instance_valid(mech):
			continue
		var hull := mech.blast_point()
		if in_blast(hull.distance_to(at), radius + MechVisuals.WIDTH * 0.35):
			mech.take_rocket(shooter)
	HitFx.blast(fx, at, radius, COLOR)
	Sfx.play("rocket_explode")
	return hits


static func in_blast(distance: float, radius: float) -> bool:
	return distance <= radius


func _build() -> void:
	var shell := MeshFactory.cylinder(0.07, 0.38, COLOR, Palette.GLOW_STRONG)
	shell.rotation.x = deg_to_rad(90.0)
	add_child(shell)
	var nose := MeshFactory.sphere(0.09, Palette.AMBER, Palette.GLOW_STRONG)
	nose.position.z = -0.22
	add_child(nose)
	var lamp := OmniLight3D.new()
	lamp.light_color = COLOR
	lamp.light_energy = 4.0
	lamp.omni_range = 8.0
	add_child(lamp)
	if direction.length_squared() > 0.0001:
		look_at(global_position + direction)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var step := SPEED * delta
	var from := global_position
	var to := from + direction * step
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.BULLET_MASK)
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_explode(hit["position"])
		return
	global_position = to
	_travelled += step
	if _travelled >= max_range:
		_explode(to)


func _explode(at: Vector3) -> void:
	if _dead:
		return
	_dead = true
	var root := get_tree().get_first_node_in_group("fx_root")
	if visual_only:
		HitFx.blast(root, at, blast_radius, COLOR)
		Sfx.play("rocket_explode")
	else:
		detonate(get_tree(), at, damage, blast_radius, root, shooter)
	queue_free()
