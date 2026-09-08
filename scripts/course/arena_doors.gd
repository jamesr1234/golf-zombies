class_name ArenaDoors
extends Node3D
## Pair of hinged leaves across the hole-5 gate. 0 is shut; 1 is swung inward.

const NAME := "ArenaDoors"
const OPEN_ANGLE := 96.0
const HEIGHT := 16.0
const THICK := 1.1
const POST := 2.4
const LINTEL := 1.6
const OPEN_BACK := 42.0
const OPEN_NEAR := 24.0
const CLOSE_BACK := 28.0

var _left: Node3D
var _right: Node3D
var _amount := 0.0


static func of(host: Node) -> ArenaDoors:
	if host == null:
		return null
	return host.find_child(NAME, true, false) as ArenaDoors


func build(cup: Vector3) -> void:
	name = NAME
	var span := _span(cup)
	var mid: Vector3 = span["mid"]
	var inward: Vector3 = span["inward"]
	var width: float = span["width"]
	position = Vector3(mid.x, cup.y, mid.z)
	basis = Basis.looking_at(inward, Vector3.UP)
	var half := width * 0.5
	_left = _leaf(-1.0, half)
	_right = _leaf(1.0, half)
	add_child(_post(-half))
	add_child(_post(half))
	add_child(_lintel(width))
	apply(0.0)


func apply(amount: float) -> void:
	_amount = clampf(amount, 0.0, 1.0)
	var yaw := deg_to_rad(OPEN_ANGLE) * _amount
	if _left != null:
		_left.rotation.y = yaw
	if _right != null:
		_right.rotation.y = -yaw


func snap(open: bool) -> void:
	apply(1.0 if open else 0.0)


func is_open() -> bool:
	return _amount >= 0.999


func amount() -> float:
	return _amount


func view(opening: bool, t: float) -> Transform3D:
	var u := _ease(clampf(t, 0.0, 1.0))
	if opening:
		var origin := to_global(Vector3(0.0, lerpf(12.0, 9.0, u), lerpf(OPEN_BACK, OPEN_NEAR, u)))
		var look := to_global(Vector3(0.0, HEIGHT * 0.45, -6.0))
		return Transform3D(Basis.looking_at(look - origin, Vector3.UP), origin)
	var origin := to_global(Vector3(0.0, 8.0, -CLOSE_BACK))
	var look := to_global(Vector3(0.0, HEIGHT * 0.4, 0.0))
	return Transform3D(Basis.looking_at(look - origin, Vector3.UP), origin)


func _leaf(side: float, half: float) -> Node3D:
	var hinge := Node3D.new()
	hinge.name = "Left" if side < 0.0 else "Right"
	hinge.position = Vector3(side * half, 0.0, 0.0)
	var slab := MeshFactory.box_body(
		Vector3(half, HEIGHT, THICK), Palette.DOOR, Layers.WORLD, true, Palette.GLOW_SOFT
	)
	slab.position = Vector3(-side * half * 0.5, HEIGHT * 0.5, 0.0)
	var seam := MeshFactory.box(
		Vector3(0.22, HEIGHT * 0.92, THICK + 0.1), Palette.ICE, Palette.GLOW_MEDIUM
	)
	seam.position = Vector3(-side * (half - 0.18), HEIGHT * 0.5, 0.0)
	hinge.add_child(slab)
	hinge.add_child(seam)
	add_child(hinge)
	return hinge


func _post(x: float) -> StaticBody3D:
	var post := MeshFactory.box_body(
		Vector3(POST, HEIGHT + LINTEL, POST), Palette.CART_FRAME, Layers.WORLD, true, Palette.GLOW_FAINT
	)
	post.name = "Post"
	post.position = Vector3(x, (HEIGHT + LINTEL) * 0.5, 0.0)
	return post


func _lintel(width: float) -> StaticBody3D:
	var beam := MeshFactory.box_body(
		Vector3(width + POST, LINTEL, POST), Palette.CART_FRAME, Layers.WORLD, true, Palette.GLOW_FAINT
	)
	beam.name = "Lintel"
	beam.position = Vector3(0.0, HEIGHT + LINTEL * 0.5, 0.0)
	return beam


static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func _span(cup: Vector3) -> Dictionary:
	var first := -1
	var last := -1
	for side in ArenaHole.SIDES:
		if not ArenaHole.is_door_side(side):
			continue
		if first < 0:
			first = side
		last = side
	var step := TAU / float(ArenaHole.SIDES)
	var radius := ArenaHole.floor_radius() + ArenaHole.STAND_DEPTH
	var left := cup + _ring(float(first) * step - step * 0.5, radius)
	var right := cup + _ring(float(last) * step + step * 0.5, radius)
	var mid := (left + right) * 0.5
	mid.y = cup.y
	var inward := cup - mid
	inward.y = 0.0
	if inward.length_squared() < 0.0001:
		inward = Vector3(0.0, 0.0, -1.0)
	else:
		inward = inward.normalized()
	return {"mid": mid, "inward": inward, "width": left.distance_to(right)}


static func _ring(theta: float, radius: float) -> Vector3:
	return Vector3(sin(theta), 0.0, cos(theta)) * radius
