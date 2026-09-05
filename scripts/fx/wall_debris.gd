class_name WallDebris
extends Object
## Chunks thrown out of a rocket hole. They bounce on scenery, then shrink away.

const GROUP := "wall_debris"
const COUNT := 18
const MAX_LIVE := 48
const LIFE := 3.4


static func toss(from: Node, at: Vector3, seed: int) -> int:
	if from == null or not from.is_inside_tree():
		return 0
	var root := from.get_tree().get_first_node_in_group("fx_root")
	if root == null:
		root = from
	cull(from.get_tree())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else 1
	for i in COUNT:
		var chunk := _chunk(at, i, rng)
		root.add_child(chunk)
		chunk.global_position = at + chunk.position
		var fade := chunk.create_tween()
		fade.tween_interval(LIFE)
		fade.tween_property(chunk, "scale", Vector3.ONE * 0.05, 0.3)
		fade.tween_callback(chunk.queue_free)
	return COUNT


static func cull(tree: SceneTree) -> int:
	if tree == null:
		return 0
	var live := tree.get_nodes_in_group(GROUP)
	var dropped := 0
	while live.size() >= MAX_LIVE:
		var old: Node = live.pop_front()
		if is_instance_valid(old):
			old.queue_free()
			dropped += 1
	return dropped


static func _chunk(at: Vector3, index: int, rng: RandomNumberGenerator) -> RigidBody3D:
	var chunk := RigidBody3D.new()
	chunk.add_to_group(GROUP)
	chunk.mass = rng.randf_range(0.8, 2.2)
	chunk.gravity_scale = 1.6
	chunk.collision_layer = 0
	chunk.collision_mask = Layers.WORLD | Layers.PROP
	var size := Vector3(
		rng.randf_range(0.08, 0.28),
		rng.randf_range(0.06, 0.22),
		rng.randf_range(0.1, 0.32)
	)
	var color := Palette.WALL if index % 3 != 0 else Palette.WALL_TRIM
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	chunk.add_child(shape)
	chunk.add_child(MeshFactory.box(size, color, Palette.GLOW_SOFT if index % 3 == 0 else 0.0))
	chunk.position = Vector3(
		rng.randf_range(-0.2, 0.2), rng.randf_range(0.05, 0.35), rng.randf_range(-0.2, 0.2)
	)
	var away := Vector3(
		rng.randf_range(-1.0, 1.0), rng.randf_range(0.35, 1.2), rng.randf_range(-1.0, 1.0)
	).normalized()
	chunk.linear_velocity = away * rng.randf_range(6.5, 13.5)
	chunk.angular_velocity = Vector3(
		rng.randf_range(-10.0, 10.0), rng.randf_range(-12.0, 12.0), rng.randf_range(-10.0, 10.0)
	)
	return chunk
