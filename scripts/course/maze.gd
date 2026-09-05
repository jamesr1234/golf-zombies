class_name Maze
extends Node3D
## Wall grid with two gates. Residents patrol a corridor until a player is
## close, then they chase through the aisles. FORT slabs fill the openings.

const CELL := 1.35
const PACK := 40
const AGGRO := 7.0
const MIN_RUN := 4
const SECTION := 6
const GATE := "Gate"
const STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
const WALKER := preload("res://resources/zombies/walker.tres")
const RUNNER := preload("res://resources/zombies/runner.tres")
const GUNNER := preload("res://resources/zombies/gunner.tres")
const BRUTE := preload("res://resources/zombies/brute.tres")
const MIX: Array[int] = [24, 10, 4, 2]

var _blocked: Dictionary = {}


func blocked_cells() -> Dictionary:
	if not _blocked.is_empty():
		return _blocked
	for child in get_children():
		var node := child as Node3D
		if node == null or String(node.name).begins_with(GATE):
			continue
		var kind := String(node.get("scene_file_path")).get_file().get_basename()
		var ox := int(roundf(node.position.x / CELL))
		var oz := int(roundf(node.position.z / CELL))
		var rotated := node.transform.basis.x.z < -0.5
		if kind == "wall_small" and rotated:
			for dz in 2:
				_blocked[Vector2i(ox - 1, -oz + dz)] = true
		elif kind == "wall_small":
			for dx in 2:
				_blocked[Vector2i(ox + dx, -oz)] = true
		elif kind == "pillar_small" or kind == "cube_extra_small":
			_blocked[Vector2i(ox, -oz)] = true
		elif kind == "arch_small":
			_blocked[Vector2i(ox, -oz)] = true
			_blocked[Vector2i(ox + 3, -oz)] = true
	return _blocked


func span() -> int:
	var size := 0
	for cell in blocked_cells():
		size = maxi(size, (cell as Vector2i).x + 1)
		size = maxi(size, (cell as Vector2i).y + 1)
	return size


func gate_cells() -> Array[Vector2i]:
	var blocked := blocked_cells()
	var size := span()
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


func pack_plan() -> Array[Dictionary]:
	var sections := patrol_sections()
	var types := _mix()
	var n := mini(PACK, types.size())
	if sections.is_empty():
		return []
	var plan: Array[Dictionary] = []
	for i in n:
		var ends: Array = sections[i % sections.size()]
		var a: Vector2i = ends[0]
		var b: Vector2i = ends[1]
		plan.append({
			"position": _cell_origin(a if i % 2 == 0 else b),
			"patrol_a": _cell_origin(a),
			"patrol_b": _cell_origin(b),
			"stats": types[i],
		})
	return plan


func patrol_sections() -> Array:
	var sections: Array = []
	for run in _runs():
		var start := 0
		while start < run.size():
			var left: int = run.size() - start
			if left < MIN_RUN:
				break
			var take := mini(SECTION, left)
			if left - take > 0 and left - take < MIN_RUN:
				take = left
			sections.append([run[start], run[start + take - 1]])
			start += take
	return sections


func roam_aabb() -> AABB:
	var size := float(span())
	var local := AABB(
		Vector3(CELL, -8.0, -(size - 1.0) * CELL),
		Vector3((size - 2.0) * CELL, 24.0, (size - 2.0) * CELL)
	)
	var global := AABB(to_global(local.position), Vector3.ZERO)
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				global = global.expand(to_global(local.position + local.size * Vector3(x, y, z)))
	return global


func contains_world(at: Vector3) -> bool:
	var cell := world_to_cell(at)
	var size := span()
	if cell.x < 0 or cell.y < 0 or cell.x >= size or cell.y >= size:
		return false
	return not blocked_cells().has(cell)


func world_to_cell(at: Vector3) -> Vector2i:
	var local := to_local(at)
	return Vector2i(int(floor(local.x / CELL)), int(floor(-local.z / CELL)))


## First open cell toward `to`, or INF if the aisles cannot reach it.
func next_toward(from: Vector3, to: Vector3) -> Vector3:
	var start := _open_near(world_to_cell(from))
	var goal := world_to_cell(to)
	if not contains_world(to):
		goal = _open_near(goal)
	if start == Vector2i(-1, -1) or goal == Vector2i(-1, -1):
		return Vector3.INF
	if start == goal:
		return to if contains_world(to) else to_global(_cell_origin(start))
	var came := _bfs(start, goal)
	if not came.has(goal):
		return Vector3.INF
	var step := goal
	while came[step] != start:
		step = came[step]
	return to_global(_cell_origin(step))


func seal_gates() -> void:
	if has_node(GATE):
		return
	var n := 0
	for group in _gate_groups():
		_add_gate(group, n)
		n += 1


func _mix() -> Array[ZombieStats]:
	var kinds: Array[ZombieStats] = [WALKER, RUNNER, GUNNER, BRUTE]
	var types: Array[ZombieStats] = []
	for i in MIX.size():
		for _n in MIX[i]:
			types.append(kinds[i])
	return types


func _cell_origin(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) + 0.5) * CELL, 0.2, -(float(cell.y) + 0.5) * CELL)


func _runs() -> Array:
	var blocked := blocked_cells()
	var size := span()
	var runs: Array = []
	for y in range(1, size - 1):
		_collect_run(runs, blocked, size, y, true)
	for x in range(1, size - 1):
		_collect_run(runs, blocked, size, x, false)
	return runs


func _collect_run(runs: Array, blocked: Dictionary, size: int, fixed: int, across: bool) -> void:
	var run: Array[Vector2i] = []
	for i in range(1, size - 1):
		var cell := Vector2i(i, fixed) if across else Vector2i(fixed, i)
		if blocked.has(cell):
			if run.size() >= MIN_RUN:
				runs.append(run.duplicate())
			run = []
		else:
			run.append(cell)
	if run.size() >= MIN_RUN:
		runs.append(run)


func _open_near(cell: Vector2i) -> Vector2i:
	var blocked := blocked_cells()
	var size := span()
	if cell.x >= 0 and cell.y >= 0 and cell.x < size and cell.y < size and not blocked.has(cell):
		return cell
	var best := Vector2i(-1, -1)
	var best_d := 99
	for x in range(1, size - 1):
		for y in range(1, size - 1):
			var open := Vector2i(x, y)
			if blocked.has(open):
				continue
			var d := absi(open.x - cell.x) + absi(open.y - cell.y)
			if d < best_d:
				best_d = d
				best = open
	return best


func _bfs(start: Vector2i, goal: Vector2i) -> Dictionary:
	var blocked := blocked_cells()
	var size := span()
	var came := {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var here: Vector2i = queue[head]
		head += 1
		if here == goal:
			return came
		for step in STEPS:
			var next := here + step
			if next.x < 0 or next.y < 0 or next.x >= size or next.y >= size:
				continue
			if blocked.has(next) or came.has(next):
				continue
			came[next] = here
			queue.append(next)
	return came


func _gate_groups() -> Array:
	var left: Array[Vector2i] = gate_cells()
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


func _add_gate(group: Array, index: int) -> void:
	if group.is_empty():
		return
	var min_c: Vector2i = group[0]
	var max_c: Vector2i = group[0]
	for cell in group:
		min_c.x = mini(min_c.x, cell.x)
		min_c.y = mini(min_c.y, cell.y)
		max_c.x = maxi(max_c.x, cell.x)
		max_c.y = maxi(max_c.y, cell.y)
	var across := max_c.x > min_c.x
	var body := StaticBody3D.new()
	body.name = GATE if index == 0 else "%s%d" % [GATE, index + 1]
	body.collision_layer = Layers.FORT
	body.collision_mask = 0
	var box := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	if across:
		shape.size = Vector3(float(max_c.x - min_c.x + 1) * CELL, 4.0, CELL * 0.45)
	else:
		shape.size = Vector3(CELL * 0.45, 4.0, float(max_c.y - min_c.y + 1) * CELL)
	box.shape = shape
	body.add_child(box)
	var mid := Vector2((float(min_c.x + max_c.x) + 1.0) * 0.5, (float(min_c.y + max_c.y) + 1.0) * 0.5)
	body.position = Vector3(mid.x * CELL, 2.0, -mid.y * CELL)
	add_child(body)
