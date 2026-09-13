class_name CartPath
extends Node3D
## Drive from the finished green to a staging tee. A forcefield on both lips
## tries to keep you on the tarmac; slip into the trees and you reappear on the
## line beside the crash. Windmill pillars throw the cart skyward first, then
## the blast drops you well behind the mill.

const PATH_WIDTH := 25.0
const PATH_THICKNESS := 1.4
const GATE_WIDTH := 36.0
const ARROW_SPACING := 18.0
## Above the trees, so the clubhouse route stays readable from the cart.
const ARROW_HEIGHT := 12.0
const WALL_THICKNESS := 0.7
const FIELD_GROUP := "cart_path_field"
const TEE_SIZE := Vector2(12.0, 14.0)
const START_INSIDE := 6.0
const GREEN_CLEAR := 8.0
## Clubhouse sits on the right of the last straight. That wall stops short of
## the tee so you can walk onto the plaza.
const TEE_OPEN := 16.0
const LANE_LIMIT := PATH_WIDTH * 0.5 + 1.8
## Past the tarmac lip. The field sits on the edge; this is the slip through it.
const ROUGH_SLIP := 0.8
const CRASH_COOL := 1.15
const _Gate := preload("res://scripts/course/cart_path_gate.gd")
const _Forest := preload("res://scripts/course/cart_path_forest.gd")
const _Boost := preload("res://scripts/course/cart_path_boost.gd")
const _Windmill := preload("res://scripts/course/cart_path_windmill.gd")
const _FairwayField := preload("res://scripts/course/fairway_field.gd")

var tee := Vector3.ZERO
var heading := Vector3.FORWARD
var spawn_points: Array[Vector3] = []
var track_length := 0.0
var centerline: Array[Vector3] = []
var forest_height: HeightField
var keep_out := Rect2()
var woods_spots: Array[Dictionary] = []
var woods_keep_out := Rect2()
var woods_need_field := false
var woods_cheap := false
var short := false
var _crash_cool := 0.0
var _pending: Array[Dictionary] = []


static func build(
	cup: Vector3, along: Vector3, bounds: Rect2, height: HeightField, hole_node: Node3D,
	green_radius := 10.0, spread := false, cheap := false, short := false
) -> CartPath:
	var path := CartPath.new()
	path.name = "CartPath"
	path.short = short
	path.heading = along
	path.heading.y = 0.0
	path.heading = path.heading.normalized()
	var exit_at := _exit_point(cup, path.heading, bounds)
	var start := _start_point(cup, path.heading, bounds, height, green_radius)
	var deck := height.height_at(start.x, start.z)
	start.y = deck
	path.keep_out = bounds
	path.centerline = CartPathTrack.centerline(start, path.heading, deck, short)
	path.track_length = CartPathTrack.length_of(path.centerline)
	path.tee = path.centerline[path.centerline.size() - 1]
	path.heading = CartPathTrack.finish_heading(path.centerline)
	if spread:
		_Forest.queue(path, bounds, cheap)
		path.set_process(true)
	else:
		_Forest.dress(path, bounds)
		path.set_process(false)
	path._build_road()
	CartPathRails.dress(path)
	if not short:
		_Boost.dress(path)
		path._build_end_cap()
	path._build_tee_pad()
	path._build_arrows(cup, height, deck)
	if path.centerline.size() >= 2:
		path.add_child(_Gate.create(path.centerline[0], path.centerline[1] - path.centerline[0]))
	path._build_spawns()
	_Windmill.dress(path)
	_open_gate(hole_node, cup, along, exit_at)
	_hide_old_pin(hole_node)
	return path


func _process(_delta: float) -> void:
	if not _Forest.step(self):
		set_process(false)


func hide_arrows() -> void:
	for child in get_children():
		if child.is_in_group("transit_arrows"):
			child.visible = false


func off_path(at: Vector3) -> bool:
	if keep_out.has_point(Vector2(at.x, at.z)):
		return false
	if at.distance_to(tee) < TEE_OPEN + 6.0:
		return false
	return CartPathTrack.distance_to(centerline, at) > PATH_WIDTH * 0.5 + ROUGH_SLIP


func reset_from(crash: Vector3, back := 0.0) -> Dictionary:
	var along := maxf(0.0, CartPathTrack.along(centerline, crash) - back)
	var on := CartPathTrack.at(centerline, along)
	var face := CartPathTrack.heading_at(centerline, along)
	return {
		"position": on + Vector3.UP * 0.4,
		"yaw": rad_to_deg(_yaw_along(face)),
	}


func tick_crash(body: Node3D, delta: float) -> bool:
	var bodies: Array[Node3D] = []
	if body != null:
		bodies.append(body)
	return tick_bodies(bodies, delta)


func tick_bodies(bodies: Array, delta: float) -> bool:
	_crash_cool = maxf(0.0, _crash_cool - delta)
	if _tick_pending(delta):
		return true
	if _crash_cool > 0.0:
		return false
	for body in bodies:
		var node := body as Node3D
		if node == null or is_flung(node):
			continue
		var at := node.global_position if node.is_inside_tree() else node.position
		if not off_path(at):
			continue
		_crash_now(node, node is GolfCart)
		return true
	return false


func fling_off(body: Node3D, from: Vector3) -> bool:
	if body == null or is_flung(body):
		return false
	if body is GolfCart and not NetSession.should_simulate(body):
		return false
	var player := body as Player
	if player != null and player.net_driven and not player.is_multiplayer_authority():
		return false
	var shove := _Windmill.shove_from(self, body, from)
	if body.has_method("fling"):
		body.fling(shove, _Windmill.FLING_SPEED, _Windmill.FLING_LIFT, _Windmill.EXPLODE_DELAY)
	_pending.append({
		"body": body,
		"left": _Windmill.EXPLODE_DELAY,
		"crash": from,
		"back": _Windmill.FLING_BACK,
	})
	return true


func is_flung(body: Node3D) -> bool:
	return _pending_of(body) >= 0


func _tick_pending(delta: float) -> bool:
	var exploded := false
	for i in range(_pending.size() - 1, -1, -1):
		var item: Dictionary = _pending[i]
		item["left"] = float(item["left"]) - delta
		_pending[i] = item
		if float(item["left"]) > 0.0:
			continue
		var body := item["body"] as Node3D
		_pending.remove_at(i)
		if body != null and is_instance_valid(body):
			var crash: Vector3 = item.get("crash", Vector3.INF)
			_crash_now(body, true, float(item.get("back", 0.0)), crash)
			exploded = true
	return exploded


func _pending_of(body: Node3D) -> int:
	if body == null:
		return -1
	for i in _pending.size():
		if _pending[i].get("body") == body:
			return i
	return -1


func _crash_now(body: Node3D, blast := true, back := 0.0, reset_at := Vector3.INF) -> void:
	var at := body.global_position if body.is_inside_tree() else body.position
	var from := at if not reset_at.is_finite() else reset_at
	var pose := reset_from(from, back)
	if blast:
		_explode(at)
	if body.has_method("recover_at"):
		body.recover_at(pose["position"], pose["yaw"])
	elif body.has_method("spawn_at"):
		body.spawn_at(pose["position"], pose["yaw"])
	_crash_cool = CRASH_COOL


func _explode(at: Vector3) -> void:
	var root: Node = get_tree().get_first_node_in_group("fx_root") if is_inside_tree() else null
	if root == null and is_inside_tree():
		root = get_tree().current_scene
	HitFx.blast(root, at + Vector3.UP * 0.8, 4.2, Palette.AMBER)
	Sfx.play("rocket_explode", self)


static func _exit_point(cup: Vector3, along: Vector3, bounds: Rect2) -> Vector3:
	var point := Vector3(cup.x, cup.y, cup.z)
	var step := 2.0
	var travelled := 0.0
	while bounds.has_point(Vector2(point.x, point.z)) and travelled < 240.0:
		point += along * step
		travelled += step
	return point


static func _start_point(
	cup: Vector3, along: Vector3, bounds: Rect2, height: HeightField, green_radius: float
) -> Vector3:
	var exit_at := _exit_point(cup, along, bounds)
	var span := Vector2(exit_at.x - cup.x, exit_at.z - cup.z).length()
	var dist := green_radius + GREEN_CLEAR
	if dist > span - 4.0:
		dist = maxf(START_INSIDE, span - 4.0)
	var start := cup + along * dist
	start.y = height.height_at(start.x, start.z)
	return start


func _build_road() -> void:
	for i in range(1, centerline.size()):
		_path_strip(centerline[i - 1], centerline[i])


func _path_strip(a: Vector3, b: Vector3) -> void:
	var delta := b - a
	var flat := Vector2(delta.x, delta.z).length()
	if flat < 0.4:
		return
	var yaw := _yaw_along(Vector3(delta.x, 0.0, delta.z))
	var pitch := -atan2(delta.y, flat)
	var mid := a.lerp(b, 0.5)
	# Cheap online woods skip the forest heightmap. The tarmac still has to
	# hold walkers and carts on every peer, so the deck is a real floor.
	var deck := MeshFactory.box_body(
		Vector3(PATH_WIDTH, PATH_THICKNESS, flat + CartPathTrack.JOIN),
		Palette.CART, Layers.WORLD, false
	)
	deck.add_to_group("cart_path_deck")
	deck.position = mid + Vector3.UP * (0.14 - PATH_THICKNESS * 0.5)
	deck.rotation.y = yaw
	deck.rotation.x = pitch
	add_child(deck)
	var mesh := MeshFactory.box(
		Vector3(PATH_WIDTH, 0.14, flat + CartPathTrack.JOIN),
		Palette.CART, Palette.GLOW_FAINT
	)
	MeshFactory.apply_grid(mesh, Surface.LOOK[Surface.Type.FAIRWAY])
	mesh.position = mid + Vector3.UP * 0.07
	mesh.rotation.y = yaw
	mesh.rotation.x = pitch
	add_child(mesh)


func _build_end_cap() -> void:
	var tall := 8.0
	var back := tee + heading * 4.0
	var cap := MeshFactory.box_body(
		Vector3(PATH_WIDTH + 4.0, tall, WALL_THICKNESS),
		Palette.WALL, Layers.BARRIER
	)
	cap.name = "EndCap"
	cap.position = Vector3(back.x, tee.y + tall * 0.5, back.z)
	cap.rotation.y = _yaw_along(heading)
	add_child(cap)


func _build_tee_pad() -> void:
	var pad := MeshFactory.box_body(
		Vector3(TEE_SIZE.x, 0.28, TEE_SIZE.y), Palette.CYAN, Layers.WORLD, true, Palette.GLOW_SOFT
	)
	MeshFactory.apply_grid(pad, Surface.LOOK[Surface.Type.TEE])
	pad.position = tee + Vector3.UP * 0.12
	pad.rotation.y = _yaw_along(heading)
	add_child(pad)
	var marker := HoleBuilder.pin_beam()
	marker.name = "NextTeeBeam"
	marker.position = tee
	add_child(marker)
	var sign := Label3D.new()
	sign.text = "NEXT TEE"
	sign.font_size = 64
	sign.modulate = Palette.CYAN
	sign.outline_size = 12
	sign.outline_modulate = Palette.NIGHT
	sign.position = tee + Vector3.UP * 3.4
	add_child(sign)


func _build_arrows(from: Vector3, height: HeightField, deck: float) -> void:
	var travelled := 0.0
	var next_mark := ARROW_SPACING
	var first := centerline[0]
	_place_arrow(from, first, from, height, deck)
	for i in range(1, centerline.size()):
		var a := centerline[i - 1]
		var b := centerline[i]
		var span := a.distance_to(b)
		travelled += span
		while next_mark <= travelled + 0.01:
			var over := travelled - next_mark
			var t := 1.0 - over / maxf(span, 0.001)
			var at := a.lerp(b, clampf(t, 0.0, 1.0))
			_place_arrow(at, b, from, height, deck)
			next_mark += ARROW_SPACING


func _place_arrow(
	at: Vector3, toward: Vector3, cup: Vector3, height: HeightField, deck: float
) -> void:
	var point := at
	var start := centerline[0]
	if point.distance_to(cup) + 1.0 < start.distance_to(cup) and height != null:
		point.y = height.height_at(point.x, point.z)
	else:
		point.y = at.y
	var along := toward - at
	along.y = 0.0
	if along.length_squared() < 0.04:
		along = heading
	var arrow := _arrow()
	arrow.position = point + Vector3.UP * ARROW_HEIGHT
	arrow.rotation.y = _yaw_along(along)
	add_child(arrow)


func _build_spawns() -> void:
	for i in range(1, centerline.size() - 1):
		var a := centerline[i - 1]
		var b := centerline[i]
		var along := b - a
		along.y = 0.0
		if along.length() < 0.8:
			continue
		var t := float(i) / float(centerline.size())
		if t < 0.08 or t > 0.9:
			continue
		spawn_points.append(b + Vector3.UP * 0.2)
		if i % 2 == 0:
			spawn_points.append(a.lerp(b, 0.5) + Vector3.UP * 0.2)


func _arrow() -> Node3D:
	var root := Node3D.new()
	root.add_to_group("transit_arrows")
	var shaft := MeshFactory.box(
		Vector3(1.1, 1.1, 5.2), Palette.CYAN, Palette.GLOW_STRONG
	)
	shaft.position = Vector3(0.0, 0.0, -2.4)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tip := MeshFactory.box(Vector3(2.6, 1.1, 2.6), Palette.CYAN, Palette.GLOW_STRONG)
	tip.position = Vector3(0.0, 0.0, -5.6)
	tip.rotation.y = deg_to_rad(45.0)
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shaft)
	root.add_child(tip)
	return root


static func _yaw_along(along: Vector3) -> float:
	return atan2(-along.x, -along.z)


static func _hide_old_pin(hole_node: Node3D) -> void:
	var beam := hole_node.find_child("PinBeam", true, false) as Node3D
	if beam != null:
		beam.visible = false


## Punch OOB walls and fairway lips wherever the cart path crosses them.
## Flatten the current hole's heightmap under the tarmac so a hill cannot block it.
static func open_across(
	hole_node: Node3D, centerline: Array[Vector3], height: HeightField = null
) -> void:
	if hole_node == null or centerline.size() < 2:
		return
	if height != null:
		height.pave_lane(centerline, HeightField.LANE_HALF, HeightField.DECK)
		var ground := _find_ground(hole_node)
		if ground != null:
			height.refresh_body(ground)
	var walls: Array[StaticBody3D] = []
	for child in hole_node.get_children():
		var body := child as StaticBody3D
		if body != null and (body.collision_layer & Layers.BARRIER) != 0:
			walls.append(body)
	for body in walls:
		var gates := _crossings_on(hole_node, body, centerline)
		if not gates.is_empty():
			_punch_gates(hole_node, body, gates)
	_FairwayField.open_across(hole_node, centerline)


static func _crossings_on(hole_node: Node3D, body: StaticBody3D, centerline: Array[Vector3]) -> PackedFloat32Array:
	var size := _box_size(body)
	if size == Vector3.ZERO:
		return PackedFloat32Array()
	var along_x := size.x >= size.z
	var gates := PackedFloat32Array()
	for i in range(1, centerline.size()):
		var a := hole_node.to_local(centerline[i - 1])
		var b := hole_node.to_local(centerline[i])
		var hit := _segment_hits_wall(a, b, body.position, size, along_x)
		if hit == INF:
			hit = _segment_near_wall(a, b, body.position, size, along_x)
		if hit == INF:
			continue
		var fresh := true
		for g in gates:
			if absf(g - hit) < GATE_WIDTH * 0.4:
				fresh = false
				break
		if fresh:
			gates.append(hit)
	return gates


static func _segment_hits_wall(
	a: Vector3, b: Vector3, at: Vector3, size: Vector3, along_x: bool
) -> float:
	if along_x:
		if (a.z - at.z) * (b.z - at.z) > 0.0:
			return INF
		var span := b.z - a.z
		var t := 0.0 if absf(span) < 0.0001 else (at.z - a.z) / span
		var x := a.x + (b.x - a.x) * clampf(t, 0.0, 1.0)
		if x < at.x - size.x * 0.5 - 1.0 or x > at.x + size.x * 0.5 + 1.0:
			return INF
		return x
	if (a.x - at.x) * (b.x - at.x) > 0.0:
		return INF
	var span_x := b.x - a.x
	var u := 0.0 if absf(span_x) < 0.0001 else (at.x - a.x) / span_x
	var z := a.z + (b.z - a.z) * clampf(u, 0.0, 1.0)
	if z < at.z - size.z * 0.5 - 1.0 or z > at.z + size.z * 0.5 + 1.0:
		return INF
	return z


## Path can graze a fence without crossing its mid-plane. Treat a near miss
## as a gate so a turning exit is not still walled off.
static func _segment_near_wall(
	a: Vector3, b: Vector3, at: Vector3, size: Vector3, along_x: bool
) -> float:
	var keep := PATH_WIDTH * 0.5 + 2.0
	var half := size * 0.5
	var min_p := at - half
	var max_p := at + half
	var steps := maxi(2, int(ceil(Vector2(a.x - b.x, a.z - b.z).length() / 2.0)))
	var best := INF
	var best_g := INF
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		var dx := 0.0
		if p.x < min_p.x:
			dx = min_p.x - p.x
		elif p.x > max_p.x:
			dx = p.x - max_p.x
		var dz := 0.0
		if p.z < min_p.z:
			dz = min_p.z - p.z
		elif p.z > max_p.z:
			dz = p.z - max_p.z
		var d := Vector2(dx, dz).length()
		if d > keep:
			continue
		var g := p.x if along_x else p.z
		if d < best:
			best = d
			best_g = g
	return best_g


static func _find_ground(hole_node: Node3D) -> StaticBody3D:
	for node in hole_node.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if body == null or (body.collision_layer & Layers.WORLD) == 0:
			continue
		for child in body.get_children():
			var shape := child as CollisionShape3D
			if shape != null and shape.shape is HeightMapShape3D:
				return body
	return null


static func _punch_gates(hole_node: Node3D, body: StaticBody3D, gates: PackedFloat32Array) -> void:
	var size := _box_size(body)
	if size == Vector3.ZERO:
		return
	var mid_y := body.position.y
	var half := GATE_WIDTH * 0.5
	var cuts: Array[float] = []
	for g in gates:
		cuts.append(g)
	cuts.sort()
	if size.x >= size.z:
		var left := body.position.x - size.x * 0.5
		var right := body.position.x + size.x * 0.5
		var cursor := left
		for g in cuts:
			_add_wall(
				hole_node,
				Vector3((cursor + g - half) * 0.5, mid_y, body.position.z),
				Vector3(maxf(0.0, g - half - cursor), size.y, size.z)
			)
			cursor = g + half
		_add_wall(
			hole_node,
			Vector3((cursor + right) * 0.5, mid_y, body.position.z),
			Vector3(maxf(0.0, right - cursor), size.y, size.z)
		)
	else:
		var near := body.position.z - size.z * 0.5
		var far := body.position.z + size.z * 0.5
		var cursor := near
		for g in cuts:
			_add_wall(
				hole_node,
				Vector3(body.position.x, mid_y, (cursor + g - half) * 0.5),
				Vector3(size.x, size.y, maxf(0.0, g - half - cursor))
			)
			cursor = g + half
		_add_wall(
			hole_node,
			Vector3(body.position.x, mid_y, (cursor + far) * 0.5),
			Vector3(size.x, size.y, maxf(0.0, far - cursor))
		)
	if body.get_parent() == hole_node:
		hole_node.remove_child(body)
	body.free()


static func _open_gate(hole_node: Node3D, cup: Vector3, along: Vector3, gate_at: Vector3) -> void:
	var far := _farthest_barrier(hole_node, cup, along)
	if far == null:
		return
	var size := _box_size(far)
	if size == Vector3.ZERO:
		if far.get_parent() == hole_node:
			hole_node.remove_child(far)
		far.free()
		return
	var half_gate := GATE_WIDTH * 0.5
	var mid_y := far.position.y
	if size.x >= size.z:
		var left := far.position.x - size.x * 0.5
		var right := far.position.x + size.x * 0.5
		var gx := gate_at.x
		_add_wall(
			hole_node,
			Vector3((left + gx - half_gate) * 0.5, mid_y, far.position.z),
			Vector3(maxf(0.8, gx - half_gate - left), size.y, size.z)
		)
		_add_wall(
			hole_node,
			Vector3((right + gx + half_gate) * 0.5, mid_y, far.position.z),
			Vector3(maxf(0.8, right - gx - half_gate), size.y, size.z)
		)
	else:
		var near := far.position.z - size.z * 0.5
		var far_z := far.position.z + size.z * 0.5
		var gz := gate_at.z
		_add_wall(
			hole_node,
			Vector3(far.position.x, mid_y, (near + gz - half_gate) * 0.5),
			Vector3(size.x, size.y, maxf(0.8, gz - half_gate - near))
		)
		_add_wall(
			hole_node,
			Vector3(far.position.x, mid_y, (far_z + gz + half_gate) * 0.5),
			Vector3(size.x, size.y, maxf(0.8, far_z - gz - half_gate))
		)
	if far.get_parent() == hole_node:
		hole_node.remove_child(far)
	far.free()


static func _farthest_barrier(hole_node: Node3D, cup: Vector3, along: Vector3) -> StaticBody3D:
	var far: StaticBody3D
	var best := -INF
	for child in hole_node.get_children():
		var body := child as StaticBody3D
		if body == null or (body.collision_layer & Layers.BARRIER) == 0:
			continue
		var along_dot := (body.position - cup).dot(along)
		if along_dot > best:
			best = along_dot
			far = body
	return far


static func _box_size(body: StaticBody3D) -> Vector3:
	for child in body.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node != null and shape_node.shape is BoxShape3D:
			return (shape_node.shape as BoxShape3D).size
	return Vector3.ZERO


static func _add_wall(hole_node: Node3D, at: Vector3, size: Vector3) -> void:
	if size.x < 0.6 or size.z < 0.6:
		return
	var wall := MeshFactory.box_body(size, Color.WHITE, Layers.BARRIER, false)
	wall.position = at
	hole_node.add_child(wall)
