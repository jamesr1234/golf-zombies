class_name CartPath
extends Node3D
## Drive from the finished green to a staging tee. Trees are the boundary; fly
## into them and you explode back onto the path. Windmill pillars on the racing
## line throw you off first, then the blast lands a second later.

const PATH_WIDTH := 25.0
const PATH_THICKNESS := 1.4
const GATE_WIDTH := 36.0
const ARROW_SPACING := 18.0
## Above the trees, so the clubhouse route stays readable from the cart.
const ARROW_HEIGHT := 12.0
const WALL_HEIGHT := 3.2
const WALL_THICKNESS := 0.7
const TEE_SIZE := Vector2(12.0, 14.0)
const START_INSIDE := 6.0
const GREEN_CLEAR := 8.0
## Clubhouse sits on the right of the last straight. That wall stops short of
## the tee so you can walk onto the plaza.
const TEE_OPEN := 16.0
const LANE_LIMIT := PATH_WIDTH * 0.5 + 1.8
const CRASH_BACK := 10.0
const CRASH_COOL := 1.15
const _Gate := preload("res://scripts/course/cart_path_gate.gd")
const _Forest := preload("res://scripts/course/cart_path_forest.gd")
const _Boost := preload("res://scripts/course/cart_path_boost.gd")
const _Windmill := preload("res://scripts/course/cart_path_windmill.gd")

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
var _crash_cool := 0.0
var _pending: Array[Dictionary] = []


static func build(
	cup: Vector3, along: Vector3, bounds: Rect2, height: HeightField, hole_node: Node3D,
	green_radius := 10.0, spread := false, cheap := false
) -> CartPath:
	var path := CartPath.new()
	path.name = "CartPath"
	path.heading = along
	path.heading.y = 0.0
	path.heading = path.heading.normalized()
	var exit_at := _exit_point(cup, path.heading, bounds)
	var start := _start_point(cup, path.heading, bounds, height, green_radius)
	var deck := height.height_at(start.x, start.z)
	start.y = deck
	path.keep_out = bounds
	path.centerline = CartPathTrack.centerline(start, path.heading, deck)
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
	return CartPathTrack.distance_to(centerline, at) > LANE_LIMIT


func reset_from(crash: Vector3) -> Dictionary:
	var along := CartPathTrack.along(centerline, crash)
	var back := maxf(0.0, along - CRASH_BACK)
	var at := CartPathTrack.at(centerline, back)
	var face := CartPathTrack.heading_at(centerline, back)
	return {
		"position": at + Vector3.UP * 0.4,
		"yaw": rad_to_deg(_yaw_along(face)),
	}


func tick_crash(cart: Node3D, delta: float) -> bool:
	_crash_cool = maxf(0.0, _crash_cool - delta)
	if _tick_pending(delta):
		return true
	if _crash_cool > 0.0 or cart == null or is_flung(cart):
		return false
	if not off_path(cart.global_position):
		return false
	_crash_now(cart)
	return true


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
	_pending.append({"body": body, "left": _Windmill.EXPLODE_DELAY})
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
			_crash_now(body)
			exploded = true
	return exploded


func _pending_of(body: Node3D) -> int:
	if body == null:
		return -1
	for i in _pending.size():
		if _pending[i].get("body") == body:
			return i
	return -1


func _crash_now(body: Node3D) -> void:
	var at := body.global_position if body.is_inside_tree() else body.position
	var pose := reset_from(at)
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


static func _open_gate(hole_node: Node3D, cup: Vector3, along: Vector3, gate_at: Vector3) -> void:
	var far := _farthest_barrier(hole_node, cup, along)
	if far == null:
		return
	var size := _box_size(far)
	if size == Vector3.ZERO:
		far.queue_free()
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
	far.queue_free()


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
