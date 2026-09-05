class_name ShapeDrop
extends RigidBody3D
## One crate from a Shape Remote dump. Rain a pile, then L1 yeets them clear.

const GROUP := "shape_drops"
const PILE_GROUP := "shape_drop_piles"
const COUNT := 30
const LIFETIME := 30.0
const MAX_PILES := 2
const SCATTER := 5.0
const FALL_MIN := 20.0
const FALL_MAX := 35.0
const SIZE := 2.0
const GRAVITY_SCALE := 2.0
const MASS_KG := 12.0
const YEET_SPEED := 32.0
const YEET_UP := 12.0
const YEET_SPIN := 18.0
const COLORS: Array[Color] = [
	Palette.CYAN, Palette.AMBER, Palette.MAGENTA, Palette.VIOLET, Palette.ICE, Palette.LIME,
]

var visual_only := false
var _life := LIFETIME


static func rain(
	root: Node, at: Vector3, count := COUNT, seed := 1, p_visual_only := false
) -> Node3D:
	if root == null or count <= 0:
		return null
	_cull_old_piles(root.get_tree())
	var pile := Node3D.new()
	pile.add_to_group(PILE_GROUP)
	root.add_child(pile)
	pile.global_position = at
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else 1
	for i in count:
		spawn_one(pile, _scatter(at, rng), i, rng, p_visual_only)
	return pile


static func spawn_one(
	root: Node, at: Vector3, kind := 0, rng: RandomNumberGenerator = null, p_visual_only := false
) -> RigidBody3D:
	if root == null:
		return null
	if rng == null:
		rng = RandomNumberGenerator.new()
	var crate := new()
	crate.visual_only = p_visual_only
	crate.mass = MASS_KG
	crate.gravity_scale = GRAVITY_SCALE
	crate.continuous_cd = true
	crate.collision_layer = 0 if p_visual_only else Layers.PROP
	crate.collision_mask = Layers.WORLD | Layers.PROP
	if not p_visual_only:
		crate.collision_mask |= Layers.PLAYER | Layers.BALL
	crate.add_to_group(GROUP)
	root.add_child(crate)
	crate.global_position = at
	crate._build(kind, COLORS[kind % COLORS.size()])
	crate.rotation = Vector3(
		rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU)
	)
	crate.angular_velocity = Vector3(
		rng.randf_range(-2.0, 2.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-2.0, 2.0)
	)
	return crate


static func aim_point(world: World3D, origin: Vector3, fly: Vector3, range_m: float) -> Vector3:
	var direction := fly.normalized()
	var far := origin + direction * maxf(1.0, range_m)
	if world == null:
		return far
	var query := PhysicsRayQueryParameters3D.create(origin, far, Layers.BULLET_MASK)
	var hit := world.direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit["position"]
	return ground_under(world, far)


static func ground_under(world: World3D, at: Vector3) -> Vector3:
	if world == null:
		return at
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * 2.0, at + Vector3.DOWN * 80.0, Layers.WORLD | Layers.PROP
	)
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return at
	return hit["position"]


static func yeet_in_arc(
	tree: SceneTree, origin: Vector3, forward: Vector3, strength := 1.0,
	range_m := 2.9, arc_deg := 70.0
) -> int:
	if tree == null:
		return 0
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var hit := 0
	for node in tree.get_nodes_in_group(GROUP):
		var crate := node as RigidBody3D
		if crate == null or not is_instance_valid(crate):
			continue
		if not _in_arc(origin, flat, crate.global_position, range_m, arc_deg):
			continue
		yeet(crate, origin, strength)
		hit += 1
	return hit


static func yeet(body: RigidBody3D, origin: Vector3, strength := 1.0) -> void:
	if body == null or not is_instance_valid(body):
		return
	var away := body.global_position - origin
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3.FORWARD
	away = away.normalized()
	var scale := maxf(0.35, strength)
	body.sleeping = false
	body.freeze = false
	body.linear_velocity = away * YEET_SPEED * scale + Vector3.UP * YEET_UP * scale
	body.angular_velocity = Vector3(
		YEET_SPIN * scale, YEET_SPIN * scale * 0.6, -YEET_SPIN * scale * 0.4
	)


static func _scatter(at: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var angle := rng.randf() * TAU
	var radius := sqrt(rng.randf()) * SCATTER
	return at + Vector3(
		cos(angle) * radius, rng.randf_range(FALL_MIN, FALL_MAX), sin(angle) * radius
	)


static func _in_arc(
	origin: Vector3, flat_forward: Vector3, target: Vector3, range_m: float, arc_deg: float
) -> bool:
	var to_target := target - origin
	to_target.y = 0.0
	if to_target.length() > range_m or to_target.length_squared() < 0.001:
		return false
	return rad_to_deg(flat_forward.angle_to(to_target.normalized())) <= arc_deg * 0.5


static func _cull_old_piles(tree: SceneTree) -> void:
	if tree == null:
		return
	var piles := tree.get_nodes_in_group(PILE_GROUP)
	while piles.size() >= MAX_PILES:
		var old: Node = piles.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _build(kind: int, color: Color) -> void:
	var shape := CollisionShape3D.new()
	match kind % 3:
		1:
			var cyl := CylinderShape3D.new()
			cyl.radius = SIZE * 0.42
			cyl.height = SIZE
			shape.shape = cyl
			add_child(MeshFactory.cylinder(cyl.radius, cyl.height, color, Palette.GLOW_SOFT))
		2:
			var box := BoxShape3D.new()
			box.size = Vector3(SIZE, SIZE * 0.55, SIZE)
			shape.shape = box
			var wedge := PrismMesh.new()
			wedge.size = box.size
			var vis := MeshInstance3D.new()
			vis.mesh = wedge
			vis.material_override = MeshFactory.material(color, false, Palette.GLOW_SOFT)
			add_child(vis)
		_:
			var cube := BoxShape3D.new()
			cube.size = Vector3.ONE * SIZE
			shape.shape = cube
			add_child(MeshFactory.box(cube.size, color, Palette.GLOW_SOFT))
	add_child(shape)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
