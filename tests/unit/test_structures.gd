extends GutTest
## Composed obstacle scenes in scenes/course/structures, ready to drop on a hole.

const DIR := "res://scenes/course/structures"
const CELL := 1.35
const _Listing := preload("res://addons/fs_pin/fs_listing.gd")
const _KINDS := [
	"arch", "cube", "escalator", "ladder", "pillar", "platform", "ramp", "steps",
	"tunnel", "wall",
]
const _MAZE_STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


func test_there_are_a_hundred_and_one_structure_scenes() -> void:
	var paths := _scene_paths()
	assert_eq(paths.size(), 101)
	for path in paths:
		assert_true(_Listing.is_placeable(path), path)


func test_the_maze_is_a_large_wall_grid() -> void:
	var root := _maze_root()
	var walls := 0
	var min_x := 0.0
	var max_x := 0.0
	var min_z := 0.0
	var max_z := 0.0
	for child in root.get_children():
		var path := String(child.get("scene_file_path"))
		if path.contains("wall_"):
			walls += 1
		var node := child as Node3D
		min_x = minf(min_x, node.position.x)
		max_x = maxf(max_x, node.position.x)
		min_z = minf(min_z, node.position.z)
		max_z = maxf(max_z, node.position.z)
	assert_gte(walls, 180)
	assert_gte(max_x - min_x, CELL * 36.0)
	assert_gte(max_z - min_z, CELL * 36.0)


func test_the_maze_path_runs_from_start_to_end() -> void:
	var blocked := _maze_blocked(_maze_root())
	var size := _maze_span(blocked)
	var gates := _maze_gates(blocked, size)
	var start := _maze_inside(gates, blocked, true, size)
	var finish := _maze_inside(gates, blocked, false, size)
	assert_ne(start, Vector2i(-1, -1), "start")
	assert_ne(finish, Vector2i(-1, -1), "end")
	assert_true(_maze_reaches(blocked, size, start, finish))


func test_the_maze_has_exactly_two_gates() -> void:
	var blocked := _maze_blocked(_maze_root())
	var size := _maze_span(blocked)
	var gates := _maze_gates(blocked, size)
	assert_eq(_maze_gate_groups(gates).size(), 2)
	var north := 0
	var south := 0
	for gate in gates:
		if gate.y == 0:
			north += 1
		elif gate.y == size - 1:
			south += 1
	assert_eq(north, 2)
	assert_eq(south, 2)


func test_the_maze_is_sealed_except_the_gates() -> void:
	var blocked := _maze_blocked(_maze_root())
	var size := _maze_span(blocked)
	var sealed := blocked.duplicate()
	for gate in _maze_gates(blocked, size):
		sealed[gate] = true
	var seen := {Vector2i(-1, -1): true}
	var queue: Array[Vector2i] = [Vector2i(-1, -1)]
	while not queue.is_empty():
		var here: Vector2i = queue.pop_back()
		for step in _MAZE_STEPS:
			var next := here + step
			if next.x < -1 or next.y < -1 or next.x > size or next.y > size:
				continue
			if next.x >= 0 and next.y >= 0 and next.x < size and next.y < size and sealed.has(next):
				continue
			if seen.has(next):
				continue
			seen[next] = true
			queue.append(next)
	for cell in seen:
		if cell.x < 0 or cell.y < 0 or cell.x >= size or cell.y >= size:
			continue
		assert_true(sealed.has(cell), "leak at %s" % cell)


func test_the_maze_packs_forty_mostly_walkers() -> void:
	var maze := _maze_root() as Maze
	var plan := maze.pack_plan()
	assert_eq(plan.size(), Maze.PACK)
	var names := {}
	var roam := maze.roam_aabb()
	for entry in plan:
		var stats: ZombieStats = entry["stats"]
		names[stats.display_name] = int(names.get(stats.display_name, 0)) + 1
		var at: Vector3 = maze.to_global(entry["position"])
		assert_true(
			at.x >= roam.position.x and at.x <= roam.position.x + roam.size.x
			and at.z >= roam.position.z and at.z <= roam.position.z + roam.size.z,
			"a resident has to stand inside the yard"
		)
		var a: Vector3 = entry["patrol_a"]
		var b: Vector3 = entry["patrol_b"]
		assert_gte(a.distance_to(b), Maze.CELL * float(Maze.MIN_RUN - 1) - 0.05)
		assert_true(
			is_equal_approx(a.x, b.x) or is_equal_approx(a.z, b.z),
			"a beat has to be a straight aisle, not a diagonal through walls"
		)
	assert_eq(int(names.get("Walker", 0)), 24)
	assert_eq(int(names.get("Runner", 0)), 10)
	assert_eq(int(names.get("Gunner", 0)), 4)
	assert_eq(int(names.get("Brute", 0)), 2)
	assert_gt(int(names.get("Walker", 0)), int(names.get("Runner", 0)))
	assert_gt(int(names.get("Runner", 0)), int(names.get("Gunner", 0)))
	assert_gt(int(names.get("Gunner", 0)), int(names.get("Brute", 0)))


func test_the_maze_gates_stop_zombies_not_players() -> void:
	var maze := _maze_root() as Maze
	maze.seal_gates()
	var gates := 0
	for child in maze.get_children():
		if not String(child.name).begins_with(Maze.GATE):
			continue
		var body := child as StaticBody3D
		assert_not_null(body)
		assert_eq(body.collision_layer, Layers.FORT)
		assert_eq(body.collision_mask, 0)
		gates += 1
	assert_eq(gates, 2)
	assert_eq(Layers.PLAYER_MASK & Layers.FORT, 0)
	assert_gt(Layers.ZOMBIE_MASK & Layers.FORT, 0)


func test_the_maze_aisles_step_along_open_cells() -> void:
	var maze := _maze_root() as Maze
	var sections := maze.patrol_sections()
	assert_gte(sections.size(), 8)
	var ends: Array = sections[0]
	var from: Vector3 = maze.to_global(maze._cell_origin(ends[0]))
	var to: Vector3 = maze.to_global(maze._cell_origin(ends[1]))
	var next := maze.next_toward(from, to)
	assert_true(next.is_finite())
	assert_lt(next.distance_to(to), from.distance_to(to))
	assert_true(maze.contains_world(next))


func test_the_pin_panel_opens_the_structures_folder() -> void:
	assert_true(_Listing.default_expand_paths().has(DIR))
	assert_true(_Listing.list_dir("res://scenes/course").has(DIR))


func test_every_structure_is_obstacle_pieces_on_the_grid() -> void:
	var kinds := {}
	for path in _scene_paths():
		var packed := load(path) as PackedScene
		assert_not_null(packed, path)
		var root: Node3D = packed.instantiate()
		add_child_autofree(root)
		assert_gte(root.get_child_count(), 4, path)
		for child in root.get_children():
			var file_path := String(child.get("scene_file_path"))
			assert_true(file_path.begins_with("res://assets/obstacles/"), path)
			assert_true(file_path.ends_with(".glb"), path)
			kinds[file_path.get_file().get_basename().get_slice("_", 0)] = true
			var node := child as Node3D
			assert_not_null(node, path)
			for axis in range(3):
				var steps := roundf(node.position[axis] / (CELL * 0.5))
				assert_almost_eq(node.position[axis], steps * CELL * 0.5, 0.02, path)
	for kind in _KINDS:
		assert_true(kinds.has(kind), kind)


func _scene_paths() -> PackedStringArray:
	var paths: PackedStringArray = []
	var dir := DirAccess.open(DIR)
	assert_not_null(dir, DIR)
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".tscn"):
			paths.append("%s/%s" % [DIR, name])
		name = dir.get_next()
	paths.sort()
	return paths


func _maze_root() -> Node3D:
	var packed := load("res://scenes/course/structures/maze.tscn") as PackedScene
	assert_not_null(packed)
	var root: Node3D = packed.instantiate()
	add_child_autofree(root)
	return root


func _maze_blocked(root: Node3D) -> Dictionary:
	var blocked := {}
	for child in root.get_children():
		var node := child as Node3D
		var kind := String(node.get("scene_file_path")).get_file().get_basename()
		var ox := int(roundf(node.position.x / CELL))
		var oz := int(roundf(node.position.z / CELL))
		var rotated := node.transform.basis.x.z < -0.5
		if kind == "wall_small" and rotated:
			for dz in 2:
				blocked[Vector2i(ox - 1, -oz + dz)] = true
		elif kind == "wall_small":
			for dx in 2:
				blocked[Vector2i(ox + dx, -oz)] = true
		elif kind == "pillar_small" or kind == "cube_extra_small":
			blocked[Vector2i(ox, -oz)] = true
		elif kind == "arch_small":
			blocked[Vector2i(ox, -oz)] = true
			blocked[Vector2i(ox + 3, -oz)] = true
	return blocked


func _maze_span(blocked: Dictionary) -> int:
	var span := 0
	for cell in blocked:
		span = maxi(span, (cell as Vector2i).x + 1)
		span = maxi(span, (cell as Vector2i).y + 1)
	return span


func _maze_gates(blocked: Dictionary, size: int) -> Array[Vector2i]:
	var gates: Array[Vector2i] = []
	for i in size:
		if not blocked.has(Vector2i(i, 0)):
			gates.append(Vector2i(i, 0))
		if not blocked.has(Vector2i(i, size - 1)):
			gates.append(Vector2i(i, size - 1))
	for i in range(1, size - 1):
		if not blocked.has(Vector2i(0, i)):
			gates.append(Vector2i(0, i))
		if not blocked.has(Vector2i(size - 1, i)):
			gates.append(Vector2i(size - 1, i))
	return gates


func _maze_gate_groups(gates: Array[Vector2i]) -> Array:
	var left: Array[Vector2i] = gates.duplicate()
	var groups: Array = []
	while not left.is_empty():
		var queue: Array[Vector2i] = [left.pop_back()]
		var group: Array[Vector2i] = [queue[0]]
		while not queue.is_empty():
			var here: Vector2i = queue.pop_back()
			for i in range(left.size() - 1, -1, -1):
				var other: Vector2i = left[i]
				if absi(other.x - here.x) + absi(other.y - here.y) != 1:
					continue
				left.remove_at(i)
				queue.append(other)
				group.append(other)
		groups.append(group)
	return groups


func _maze_inside(gates: Array[Vector2i], blocked: Dictionary, start: bool, size: int) -> Vector2i:
	var edge := 0 if start else size - 1
	var inward := 1 if start else -1
	for gate in gates:
		if gate.y != edge:
			continue
		var inner := Vector2i(gate.x, gate.y + inward)
		if not blocked.has(inner):
			return inner
	return Vector2i(-1, -1)


func _maze_reaches(blocked: Dictionary, size: int, from: Vector2i, goal: Vector2i) -> bool:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var here: Vector2i = queue.pop_back()
		if here == goal:
			return true
		for step in _MAZE_STEPS:
			var next := here + step
			if next.x < 0 or next.y < 0 or next.x >= size or next.y >= size:
				continue
			if blocked.has(next) or seen.has(next):
				continue
			seen[next] = true
			queue.append(next)
	return false
