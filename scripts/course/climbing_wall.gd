@tool
class_name ClimbingWall
extends StaticBody3D
## Warm-up wall beside hole 1's practice tee. Holds sit on the front face;
## L1 and R1 plant a hand on the nearest one to the aimed spot.

const WIDTH := 18.0
const HEIGHT := 24.0
const THICK := 0.7
const TEE_SIDE := 14.0
const TEE_ALONG := 13.0
const COLS := 10
const ROWS := 18
const REACH := 2.25
const LATCH_DEPTH := 1.7
const HOLD_R := 0.13
const FIND := 18.0

var _w := WIDTH
var _h := HEIGHT
var _t := THICK
var _cols := COLS
var _rows := ROWS


static func create(prop: Dictionary) -> ClimbingWall:
	var wall := ClimbingWall.new()
	wall.name = "ClimbingWall"
	wall.collision_layer = Layers.WORLD
	wall.collision_mask = 0
	var size: Vector3 = prop.get("size", Vector3(WIDTH, HEIGHT, THICK))
	wall._w = size.x
	wall._h = size.y
	wall._t = maxf(size.z, THICK)
	wall._cols = maxi(4, roundi(wall._w / 1.65))
	wall._rows = maxi(6, roundi(wall._h / 1.2))
	wall.position = prop["position"] + Vector3.UP * wall._h * 0.5
	wall.rotation.y = deg_to_rad(prop["yaw"])
	wall._build()
	return wall


func to_prop() -> Dictionary:
	return {
		"kind": "climb_wall",
		"position": Vector3(position.x, 0.0, position.z),
		"size": Vector3(_w, _h, _t),
		"yaw": rad_to_deg(rotation.y),
	}


static func at_practice(practice_tee: Vector3, heading_deg: float) -> Dictionary:
	var forward := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(heading_deg))
	var right := forward.cross(Vector3.UP).normalized()
	var at := practice_tee + right * TEE_SIDE + forward * TEE_ALONG
	var toward := -right
	return {
		"kind": "climb_wall",
		"position": at,
		"size": Vector3(WIDTH, HEIGHT, THICK),
		"yaw": rad_to_deg(atan2(-toward.x, -toward.z)),
	}


static func nearest(who: Node3D) -> ClimbingWall:
	var best: ClimbingWall
	var best_d := INF
	if who == null or not who.is_inside_tree():
		return null
	for node in who.get_tree().get_nodes_in_group("climb_walls"):
		var wall := node as ClimbingWall
		if wall == null:
			continue
		var d := who.global_position.distance_to(wall.global_position)
		if d < maxf(FIND, wall._h * 0.5 + 6.0) and d < best_d:
			best = wall
			best_d = d
	return best


func _ready() -> void:
	add_to_group("climb_walls")
	if get_child_count() == 0:
		collision_layer = Layers.WORLD
		collision_mask = 0
		_cols = maxi(4, roundi(_w / 1.65))
		_rows = maxi(6, roundi(_h / 1.2))
		_build()


func _build() -> void:
	var slab := MeshFactory.box_body(
		Vector3(_w, _h, _t), Palette.WALL, Layers.WORLD, true, Palette.GLOW_FAINT
	)
	MeshFactory.apply_grid(slab, Surface.LOOK[Surface.Type.ROUGH])
	add_child(slab)
	var ledge := MeshFactory.box_body(
		Vector3(_w + 0.8, 0.32, 1.8), Palette.CYAN, Layers.WORLD, true, Palette.GLOW_SOFT
	)
	ledge.position = Vector3(0.0, _h * 0.5 + 0.12, -0.4)
	add_child(ledge)
	for hold in hold_locals():
		var jug := MeshFactory.box(Vector3(0.22, 0.16, 0.18), Palette.MAGENTA, Palette.GLOW_MEDIUM)
		jug.position = hold
		add_child(jug)
	var sign := Label3D.new()
	sign.text = "CLIMB"
	sign.font_size = 72
	sign.modulate = Palette.MAGENTA
	sign.outline_size = 12
	sign.outline_modulate = Palette.NIGHT
	sign.position = Vector3(0.0, _h * 0.5 + 1.0, -0.5)
	add_child(sign)


func hold_locals() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var face_z := -_t * 0.5 - 0.1
	var span_x := _w * 0.48
	var gap := (span_x * 2.0) / float(_cols - 1)
	for row in _rows:
		for col in _cols:
			var x := lerpf(-span_x, span_x, float(col) / float(_cols - 1))
			if row % 2 == 1:
				x = clampf(x + gap * 0.4, -span_x, span_x)
			var y := lerpf(-_h * 0.47, _h * 0.47, float(row) / float(_rows - 1))
			spots.append(Vector3(x, y, face_z))
	return spots


func holds() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for local in hold_locals():
		spots.append(to_global(local))
	return spots


func face_normal() -> Vector3:
	return -global_transform.basis.z


func can_latch(who: Node3D) -> bool:
	if who == null:
		return false
	var local := to_local(who.global_position)
	return (
		absf(local.x) <= _w * 0.55
		and local.y > -_h * 0.55
		and local.y < _h * 0.18
		and local.z < -_t * 0.15
		and local.z > -LATCH_DEPTH - _t
	)


func nearest_hold(point: Vector3, max_dist := REACH) -> Vector3:
	var best := Vector3.INF
	var best_d := max_dist
	for hold in holds():
		var d := point.distance_to(hold)
		if d < best_d:
			best = hold
			best_d = d
	return best


func aim_point(from: Vector3, stick: Vector2) -> Vector3:
	return aim_from(from, stick)


func aim_from(shoulder: Vector3, stick: Vector2, reach := REACH) -> Vector3:
	var local := to_local(shoulder)
	var dest := Vector3(
		local.x + stick.x * reach,
		local.y + (-stick.y) * reach,
		-_t * 0.5 - 0.1
	)
	dest.x = clampf(dest.x, -_w * 0.48, _w * 0.48)
	dest.y = clampf(dest.y, -_h * 0.48, _h * 0.48)
	var offset := Vector3(dest.x - local.x, dest.y - local.y, 0.0)
	if offset.length() > reach:
		offset = offset.limit_length(reach)
		dest.x = local.x + offset.x
		dest.y = local.y + offset.y
	return to_global(dest)


func hang_at(left: Vector3, right: Vector3) -> Vector3:
	var hands := 0
	var mid := Vector3.ZERO
	if left != Vector3.INF:
		mid += left
		hands += 1
	if right != Vector3.INF:
		mid += right
		hands += 1
	if hands == 0:
		return Vector3.INF
	mid /= float(hands)
	return mid + face_normal() * 0.55 + Vector3.DOWN * 0.45


func top_y() -> float:
	return global_position.y + _h * 0.5


func ledge_stand() -> Vector3:
	return to_global(Vector3(0.0, _h * 0.5 + 0.35, -0.2))
