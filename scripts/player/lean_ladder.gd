class_name LeanLadder
extends ClimbingWall
## A purchased ladder you lean on a wall. Walk into it to slide up the rails.

const _SCRIPT := preload("res://scripts/player/lean_ladder.gd")

const LEAN := deg_to_rad(28.0)
const PLACE_RANGE := 36.0
const MIN_WALL := 0.42
const MIN_REACH := 1.6
const MIN_LEN := 2.4
const MAX_LEN := 16.0
const RUNG := 0.45
const RAIL_W := 0.72
const STAND := 0.42
const MOUNT := 1.35
const THROW := 2.4
const FALL := 0.72


var _length := 9.6
var _ghost := false
var _falling := false
var _fall_t := 0.0
var _lean_x := LEAN


static func spawn(parent: Node, foot: Vector3, yaw_deg: float, length: float):
	if parent == null:
		return null
	var ladder = _SCRIPT.new()
	ladder._length = clampf(length, MIN_LEN, MAX_LEN)
	parent.add_child(ladder)
	ladder.global_transform = pose_at(foot, yaw_deg)
	Sfx.play("place_ladder", ladder)
	return ladder


static func preview():
	var ladder = _SCRIPT.new()
	ladder._ghost = true
	ladder._length = 9.6
	ladder.top_level = true
	return ladder


static func pose_at(foot: Vector3, yaw_deg: float) -> Transform3D:
	var xform := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), foot)
	xform.basis = xform.basis.rotated(xform.basis.x, LEAN)
	return xform


static func add_preview(parent: Node3D, scale := 0.22) -> void:
	if parent == null:
		return
	var mount := Node3D.new()
	mount.scale = Vector3.ONE * scale
	mount.rotation.x = -LEAN
	parent.add_child(mount)
	_draw(mount, 4.2, false)


static func plant_point(world: World3D, from: Vector3, direction: Vector3) -> Dictionary:
	var miss := {"ok": false, "foot": from, "yaw": 0.0, "length": MIN_LEN}
	if world == null or direction.length_squared() < 0.0001:
		return miss
	var dir := direction.normalized()
	var hit := world.direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from + dir * PLACE_RANGE, Layers.WORLD)
	)
	if hit.is_empty():
		return miss
	var normal: Vector3 = hit["normal"]
	if normal.y > MIN_WALL:
		return miss
	var out := Vector3(normal.x, 0.0, normal.z)
	if out.length_squared() < 0.0001:
		return miss
	out = out.normalized()
	var wall: Vector3 = hit["position"]
	var near := _floor_at(world, wall + out * 0.4 + Vector3.UP * 0.5)
	if near == Vector3.INF:
		return miss
	var reach := wall.y - near.y
	if reach < MIN_REACH:
		return miss
	var length := clampf(reach / cos(LEAN), MIN_LEN, MAX_LEN)
	var foot := _floor_at(world, wall + out * (length * sin(LEAN)) + Vector3.UP * 0.5)
	if foot == Vector3.INF:
		return miss
	return {
		"ok": true,
		"foot": foot,
		"yaw": rad_to_deg(atan2(-out.x, -out.z)),
		"length": length,
	}


func _ready() -> void:
	if not _ghost:
		add_to_group("climb_walls")
	name = "LeanLadder"
	_h = _length
	_w = RAIL_W
	_t = 0.12
	collision_layer = 0 if _ghost else Layers.WORLD
	collision_mask = 0
	if get_child_count() == 0:
		_build()


func set_span(length: float) -> void:
	var next := clampf(length, MIN_LEN, MAX_LEN)
	if absf(next - _length) < 0.08 and get_child_count() > 0:
		return
	_length = next
	_h = _length
	for child in get_children():
		remove_child(child)
		child.free()
	_build()


func set_ghost_visible(on: bool) -> void:
	visible = on


func face_normal() -> Vector3:
	var away := -global_transform.basis.z
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return Vector3.FORWARD
	return away.normalized()


func rail_dir() -> Vector3:
	return global_transform.basis.y


func rail_length() -> float:
	return _length


func point_on_rail(t: float) -> Vector3:
	return global_position + rail_dir() * (clampf(t, 0.0, 1.0) * _length) + face_normal() * STAND


func rail_t_at(point: Vector3) -> float:
	var along := (point - global_position).dot(rail_dir())
	return clampf(along / maxf(_length, 0.01), 0.0, 1.0)


func is_live() -> bool:
	return not _ghost and not _falling


func is_falling() -> bool:
	return _falling


static func nearest_throw(who: Node3D) -> LeanLadder:
	var best: LeanLadder
	var best_d := THROW
	if who == null or not who.is_inside_tree():
		return null
	for node in who.get_tree().get_nodes_in_group("climb_walls"):
		var ladder := node as LeanLadder
		if ladder == null or not ladder.can_throw(who):
			continue
		var d := who.global_position.distance_to(ladder.ledge_stand())
		if d < best_d:
			best = ladder
			best_d = d
	return best


func can_throw(who: Node3D) -> bool:
	if not is_live() or who == null:
		return false
	if who is Player and (who as Player).is_climbing():
		return false
	return (
		who.global_position.y >= top_y() - 1.15
		and who.global_position.distance_to(ledge_stand()) <= THROW
	)


func try_throw(player: Player) -> void:
	if not can_throw(player):
		return
	if NetSession.defers_world():
		player._request_throw_ladder.rpc_id(1)
		return
	host_throw(player)


func host_throw(player: Player) -> void:
	if not can_throw(player):
		return
	kick()
	WorldFx.announce_ladder_fall(player, global_position)


func kick() -> void:
	if _falling or _ghost:
		return
	_falling = true
	_fall_t = 0.0
	_lean_x = rotation.x
	remove_from_group("climb_walls")
	collision_layer = 0
	for child in get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			shape.disabled = true
	_drop_climbers()
	Sfx.play("throw_ladder", self)
	set_process(true)


func can_latch(who: Node3D) -> bool:
	if not is_live() or who == null:
		return false
	var t := rail_t_at(who.global_position)
	return t <= 0.58 and who.global_position.distance_to(point_on_rail(t)) <= MOUNT


func hold_locals() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var rows := maxi(3, roundi(_length / RUNG))
	for row in rows:
		var y := lerpf(0.18, _length - 0.18, float(row) / float(rows - 1))
		spots.append(Vector3(-RAIL_W * 0.38, y, -0.05))
		spots.append(Vector3(RAIL_W * 0.38, y, -0.05))
	return spots


func ledge_stand(_who: Node3D = null) -> Vector3:
	return global_position + rail_dir() * _length + Vector3.UP * 0.2 - face_normal() * 0.4


func top_y() -> float:
	return point_on_rail(1.0).y


func _process(delta: float) -> void:
	if not _falling:
		return
	_fall_t += delta
	var u := clampf(_fall_t / FALL, 0.0, 1.0)
	var flat := -PI * 0.5
	if u < 0.78:
		var t := u / 0.78
		rotation.x = lerpf(_lean_x, flat, t * t)
	else:
		rotation.x = flat + sin((u - 0.78) / 0.22 * PI) * 0.14
	if u >= 1.0:
		rotation.x = flat
		set_process(false)


func _drop_climbers() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("players"):
		var climber := node as Player
		if climber == null or climber.climber.wall != self:
			continue
		climber._drop_climb()
		climber.velocity.y = minf(climber.velocity.y, -2.0)


func _build() -> void:
	_draw(self, _length, _ghost)
	var slab := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(RAIL_W + 0.08, _length, 0.1)
	slab.shape = box
	slab.position = Vector3(0.0, _length * 0.5, 0.0)
	slab.disabled = _ghost
	add_child(slab)


static func _draw(host: Node3D, length: float, ghost: bool) -> void:
	var glow := Palette.GLOW_SOFT if ghost else Palette.GLOW_MEDIUM
	var paint := Palette.AMBER.darkened(0.12)
	var fly := Palette.AMBER.darkened(0.02)
	var steel := Palette.NIGHT.lightened(0.22)
	var shoe := Palette.NIGHT.lightened(0.08)
	var half := RAIL_W * 0.38
	var base_top := length * 0.62
	var fly_from := length * 0.32
	_channel(host, -half, 0.04, base_top, 0.0, 1.0, paint, glow)
	_channel(host, half, 0.04, base_top, 0.0, -1.0, paint, glow)
	_channel(host, -half + 0.04, fly_from, length - 0.04, 0.07, 1.0, fly, glow)
	_channel(host, half - 0.04, fly_from, length - 0.04, 0.07, -1.0, fly, glow)
	_rungs(host, -half + 0.05, half - 0.05, 0.16, base_top - 0.1, 0.0, paint, steel, glow)
	_rungs(host, -half + 0.09, half - 0.09, fly_from + 0.14, length - 0.16, 0.07, fly, steel, glow)
	_part(host, MeshFactory.box(Vector3(0.1, 0.07, 0.08), shoe, glow), Vector3(-half, 0.04, 0.0))
	_part(host, MeshFactory.box(Vector3(0.1, 0.07, 0.08), shoe, glow), Vector3(half, 0.04, 0.0))
	_lock(host, -half - 0.04, fly_from + 0.1, steel, glow)
	_lock(host, half + 0.04, fly_from + 0.1, steel, glow)
	var pulley := MeshFactory.torus(0.012, 0.05, steel, glow)
	pulley.rotation.z = PI * 0.5
	_part(host, pulley, Vector3(0.0, base_top - 0.05, 0.04))
	_part(host, MeshFactory.cylinder(0.008, base_top - 0.28, steel, glow), Vector3(half, (base_top + 0.2) * 0.5, 0.05))


static func _channel(
	host: Node3D, x: float, y0: float, y1: float, z: float, open: float, color: Color, glow: float
) -> void:
	var span := y1 - y0
	var mid := (y0 + y1) * 0.5
	_part(host, MeshFactory.box(Vector3(0.03, span, 0.08), color, glow), Vector3(x, mid, z))
	_part(host, MeshFactory.box(Vector3(0.08, span, 0.018), color, glow), Vector3(x + open * 0.025, mid, z - 0.032))
	_part(host, MeshFactory.box(Vector3(0.08, span, 0.018), color, glow), Vector3(x + open * 0.025, mid, z + 0.032))
	_part(host, MeshFactory.box(Vector3(0.08, 0.03, 0.08), color, glow), Vector3(x, y0 + 0.015, z))
	_part(host, MeshFactory.box(Vector3(0.08, 0.03, 0.08), color, glow), Vector3(x, y1 - 0.015, z))


static func _rungs(
	host: Node3D, x0: float, x1: float, y0: float, y1: float, z: float, paint: Color, steel: Color, glow: float
) -> void:
	var rows := maxi(2, roundi((y1 - y0) / RUNG))
	for row in rows:
		var y := lerpf(y0, y1, float(row) / float(rows - 1))
		_part(host, MeshFactory.cylinder(0.028, x1 - x0, paint, glow), Vector3(0.0, y, z)).rotation.z = PI * 0.5
		_part(host, MeshFactory.box(Vector3(x1 - x0, 0.012, 0.05), paint, glow), Vector3(0.0, y + 0.02, z))
		_part(host, MeshFactory.cylinder(0.034, 0.03, steel, glow), Vector3(x0, y, z)).rotation.z = PI * 0.5
		_part(host, MeshFactory.cylinder(0.034, 0.03, steel, glow), Vector3(x1, y, z)).rotation.z = PI * 0.5


static func _lock(host: Node3D, x: float, y: float, steel: Color, glow: float) -> void:
	_part(host, MeshFactory.box(Vector3(0.05, 0.07, 0.05), steel, glow), Vector3(x, y, 0.0))
	_part(host, MeshFactory.box(Vector3(0.03, 0.08, 0.03), steel, glow), Vector3(x, y - 0.05, 0.0))


static func _part(host: Node3D, mesh: MeshInstance3D, at: Vector3) -> MeshInstance3D:
	mesh.position = at
	host.add_child(mesh)
	return mesh


static func _floor_at(world: World3D, from: Vector3) -> Vector3:
	var hit := world.direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 14.0, Layers.WORLD)
	)
	if hit.is_empty():
		return Vector3.INF
	var normal: Vector3 = hit["normal"]
	if normal.y < HexBarrier.MIN_FLOOR:
		return Vector3.INF
	return hit["position"]
