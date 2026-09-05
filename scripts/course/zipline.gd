@tool
class_name Zipline
extends Node3D
## Two decks and a cable. Stand on the high deck, grab, and slide to the low one.
## Drag the Start and End markers; the platforms ride with them and the cable
## follows. A flat line still runs Start to End.

const CELL := 1.35
const USE_RANGE := 2.8
const DECK := 0.34
const DECK_CELLS := 2.0
const POST_H := 3.2
const POST_R := 0.1
const CABLE_R := 0.045
const HANG := 2.35
const TROLLEY_DROP := 0.4
const GRIP_HALF := 0.17
const BASE_SPEED := 9.0
const STEEP_SPEED := 12.0
const DEFAULT_RUN := 6.0
const DEFAULT_DROP := 3.0
const LEVEL_EPS := 0.05


var _last_a := Vector3.INF
var _last_b := Vector3.INF


static func nearest(who: Node3D) -> Zipline:
	var best: Zipline
	var best_d := INF
	if who == null or not who.is_inside_tree():
		return null
	for node in who.get_tree().get_nodes_in_group("ziplines"):
		var line := node as Zipline
		if line == null or not line.can_use(who):
			continue
		var d := who.global_position.distance_to(line.board_at())
		if d < best_d:
			best = line
			best_d = d
	return best


func _ready() -> void:
	add_to_group("ziplines")
	_ensure_markers()
	_build_ends()
	_build_cable()
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_markers()
	var a := hang_at(start_mark())
	var b := hang_at(end_mark())
	if a.distance_squared_to(_last_a) > 0.0001 or b.distance_squared_to(_last_b) > 0.0001:
		_build_cable()


func start_mark() -> Marker3D:
	return get_node_or_null("Start") as Marker3D


func end_mark() -> Marker3D:
	return get_node_or_null("End") as Marker3D


## Park the far deck on the start so the creator can drop one point at a time.
func collapse_end() -> void:
	_ensure_markers()
	end_mark().position = Vector3.ZERO
	end_mark().visible = false
	var cable := get_node_or_null("Cable")
	if cable != null:
		cable.visible = false


## Local offset of the far deck. Rebuilds the cable once the end has moved.
func set_end_local(at: Vector3) -> void:
	_ensure_markers()
	var finish := end_mark()
	finish.visible = true
	if finish.position.distance_squared_to(at) < 0.0001 and get_node_or_null("Cable") != null:
		return
	finish.position = at
	if is_inside_tree():
		_build_cable()


## World start and end. Rotation stays, so a turned deck keeps facing the same way.
func span(from: Vector3, to: Vector3) -> void:
	position = from
	var local := to - from
	if not is_equal_approx(rotation.y, 0.0):
		local = Basis(Vector3.UP, -rotation.y) * local
	set_end_local(local)


func high_mark() -> Marker3D:
	var start := start_mark()
	var finish := end_mark()
	if start == null:
		return finish
	if finish == null:
		return start
	if hang_at(finish).y - hang_at(start).y > LEVEL_EPS:
		return finish
	return start


func low_mark() -> Marker3D:
	var start := start_mark()
	var finish := end_mark()
	return finish if high_mark() == start else start


func hang_at(mark: Node3D) -> Vector3:
	return _local_of(mark, Vector3(0.0, DECK + POST_H, 0.0))


func board_at() -> Vector3:
	return _deck_top(high_mark())


func land_at() -> Vector3:
	return _deck_top(low_mark())


func point_on_cable(t: float) -> Vector3:
	return hang_at(high_mark()).lerp(hang_at(low_mark()), clampf(t, 0.0, 1.0))


func ride_at(t: float) -> Vector3:
	return point_on_cable(t) - Vector3.UP * HANG


func trolley_side() -> Vector3:
	var side := along().cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = along().cross(Vector3.RIGHT)
	return side.normalized()


func grip_at(t: float, sign: float) -> Vector3:
	return point_on_cable(t) - Vector3.UP * TROLLEY_DROP + trolley_side() * GRIP_HALF * sign


func along() -> Vector3:
	var delta := hang_at(low_mark()) - hang_at(high_mark())
	if delta.length_squared() < 0.0001:
		return Vector3.FORWARD
	return delta.normalized()


func cable_length() -> float:
	return hang_at(high_mark()).distance_to(hang_at(low_mark()))


func ride_speed() -> float:
	return BASE_SPEED + STEEP_SPEED * maxf(0.0, -along().y)


func land_yaw() -> float:
	var dir := along()
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return 0.0
	dir = dir.normalized()
	return rad_to_deg(atan2(-dir.x, -dir.z))


func can_use(who: Node3D) -> bool:
	if who == null or not is_inside_tree():
		return false
	if who.get("health") != null and who.health.has_method("is_alive"):
		if not who.health.is_alive():
			return false
	if who.get("shopping") == true or who.get("talking") == true:
		return false
	if who.get("state") != null and int(who.state) != 0:
		return false
	return who.global_position.distance_to(board_at()) <= USE_RANGE


func try_board(player: Node) -> bool:
	if player == null or not player.has_method("begin_zipline"):
		return false
	if not can_use(player):
		return false
	return bool(player.begin_zipline(self))


func _deck_top(mark: Node3D) -> Vector3:
	return _local_of(mark, Vector3(0.0, DECK, 0.0))


func _local_of(mark: Node3D, local: Vector3) -> Vector3:
	if mark == null:
		return local
	if mark.is_inside_tree():
		return mark.to_global(local)
	return mark.position + local


func _ensure_markers() -> void:
	if start_mark() == null:
		var start := Marker3D.new()
		start.name = "Start"
		add_child(start)
	if end_mark() == null:
		var finish := Marker3D.new()
		finish.name = "End"
		finish.position = Vector3(CELL * DEFAULT_RUN, -CELL * DEFAULT_DROP, 0.0)
		add_child(finish)


func _build_ends() -> void:
	_build_end(start_mark())
	_build_end(end_mark())


func _build_end(mark: Marker3D) -> void:
	if mark == null:
		return
	for child in mark.get_children():
		child.free()
	var size := Vector3(DECK_CELLS * CELL, DECK, DECK_CELLS * CELL)
	var deck := MeshFactory.box_body(size, Palette.WALL, Layers.WORLD, true, Palette.GLOW_FAINT)
	deck.name = "Deck"
	deck.position.y = DECK * 0.5
	mark.add_child(deck)
	var lip := MeshFactory.box(Vector3(size.x * 1.02, 0.05, size.z * 1.02), Palette.CYAN, Palette.GLOW_SOFT)
	lip.name = "Lip"
	lip.position.y = size.y * 0.5
	lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deck.add_child(lip)
	var post := MeshFactory.cylinder_body(POST_R, POST_H, Palette.TOWER, Layers.WORLD, Palette.GLOW_FAINT)
	post.name = "Post"
	post.position.y = DECK + POST_H * 0.5
	mark.add_child(post)
	var cap := MeshFactory.sphere(POST_R + 0.06, Palette.CYAN, Palette.GLOW_MEDIUM)
	cap.name = "Cap"
	cap.position.y = DECK + POST_H
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.add_child(cap)


func _build_cable() -> void:
	var old := get_node_or_null("Cable")
	if old != null:
		old.free()
	var a := hang_at(start_mark())
	var b := hang_at(end_mark())
	_last_a = a
	_last_b = b
	var span := maxf(a.distance_to(b), 0.05)
	var cable := MeshFactory.cylinder(CABLE_R, span, Palette.CYAN, Palette.GLOW_MEDIUM)
	cable.name = "Cable"
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cable)
	_align_y(cable, a, b)


func _align_y(node: Node3D, from: Vector3, to: Vector3) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.0001:
		return
	var y := delta / length
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	var mid := (from + to) * 0.5
	var basis := Basis(x, y, z)
	if is_inside_tree():
		node.global_position = mid
		node.global_transform.basis = basis
	else:
		node.position = mid
		node.transform.basis = basis
