class_name WaterTunnel
extends Node3D
## A swim tunnel joining two ponds on a custom hole.
##
## The dig is kept as the line it follows plus one bore size, so a whole
## corridor is a handful of numbers instead of a tile per metre. That choice is
## what keeps it cheap: a lookup is a closest-point test on a few segments, the
## run draws as one mesh, the ground is never re-cut, and the tunnel owns no
## collider at all. Swimmers are held inside the bore by PlayerSwim, which is
## what keeps them out of the rock the corridor runs through.

## Token path. The creator digs it; the catalog never offers it as a piece.
const TOKEN := "tunnel"
const GROUP := "water_tunnel"
const NODES := "nodes"
const BORE := "bore"
const DONE := "done"
## Wide enough to swim with the lens clear of the wall, narrow enough that a
## race through one is tight.
const BORE_MIN := 2.0
const BORE_MAX := 6.0
const BORE_STEP := 0.2
const BORE_DEFAULT := 2.6
## Corners in one run. Holds a lookup to a fixed small cost.
const MAX_NODES := 32
## Longest single press, so one R2 cannot drive a corridor across the hole.
const STEP_MAX := 26.0
## Shortest leg worth storing, so a jittery aim does not stack up corners.
const STEP_MIN := 1.2
## Rock frame around each mouth, wide enough to close the gap between the bore
## and the pond wall it breaks through.
const COLLAR := 1.2
## How far each mouth sits into the pond. The first node is a step into the
## bank, so without this the opening is inside the heightmap and you guess.
const LIP := 1.8
## Rock plate around the hole, tall enough to cover the lake wall from the
## pond floor to the water line. Without it, cutting the bank is a window
## onto the rest of the course.
const BULKHEAD_SIDE := 2.2
const BULKHEAD_UP := 4.0
const BULKHEAD_DOWN := 8.0
## Wet rock, lit by its own seams because there is no daylight down here. Not
## the pond's water look: the walls of a tunnel are the ground it was cut from,
## and being opaque is what makes the mouth read as a hole in the bank.
const LOOK := {
	"base": Color(0.035, 0.055, 0.06), "line": Color(0.16, 0.44, 0.42),
	"cell": 1.35, "energy": 1.6, "scroll": 0.0, "fill": 0.55,
	"fade_start": 40.0, "fade_end": 220.0,
}


var _nodes: Array[Vector3] = []
var _half := BORE_DEFAULT * 0.5


static func is_tunnel(path: String) -> bool:
	return path == TOKEN


static func clamp_bore(value: float) -> float:
	return snappedf(clampf(value, BORE_MIN, BORE_MAX), BORE_STEP)


static func bore_of(entry: Dictionary) -> float:
	return clamp_bore(float(entry.get(BORE, BORE_DEFAULT)))


static func half_of(entry: Dictionary) -> float:
	return bore_of(entry) * 0.5


## A dig that reached a second pond. An unfinished one is a dead end, so the
## creator refuses to play the hole until it lands.
static func is_done(entry: Dictionary) -> bool:
	return bool(entry.get(DONE, false))


## Open the lake wall at each mouth. The heightmap still stores the bank, so
## walking over the run is dry; only the sloped face in front of a hole is
## left undrawn, which is what lets you see into the bore from the pond.
static func cut_banks(field, listed: Array) -> void:
	if field == null:
		return
	field.cuts.clear()
	for entry in entries(listed):
		if not is_done(entry):
			continue
		var line := nodes_of(entry)
		if line.size() < 2:
			continue
		var half := half_of(entry)
		field.cuts.append(_wall_cut(field, listed, line[0], line[1], half))
		field.cuts.append(
			_wall_cut(field, listed, line[line.size() - 1], line[line.size() - 2], half)
		)
	# #region agent log
	var cf := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-5e45bb.log", FileAccess.READ_WRITE)
	if cf == null:
		cf = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-5e45bb.log", FileAccess.WRITE)
	else:
		cf.seek_end()
	if cf != null:
		var spots: Array = []
		for cut in field.cuts:
			var at: Vector3 = cut.get("position", Vector3.ZERO)
			var slope: float = field.slope_at(at.x, at.z)
			spots.append({
				"at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)],
				"r": snappedf(float(cut.get("radius", 0.0)), 0.01),
				"slope": snappedf(slope, 0.01),
				"ground": snappedf(field.height_at(at.x, at.z), 0.01),
				"pond": not WaterTile.pond_at(listed, at).is_empty(),
			})
		cf.store_line(JSON.stringify({
			"sessionId": "5e45bb",
			"runId": "post-fix",
			"hypothesisId": "A",
			"location": "water_tunnel.gd:cut_banks",
			"message": "bank cuts",
			"data": {
				"cuts": field.cuts.size(),
				"banks": field.mouth_banks(),
				"spots": spots,
			},
			"timestamp": int(Time.get_unix_time_from_system() * 1000.0),
		}))
		cf.close()
	# #endregion


## Walk from the last underground node toward this mouth and stop on the last
## dry cell. That is the bank the entrance already uses. The first pond cell
## sits on the water side of the 2.5 m ramp, which is why the exit wall stayed
## solid after the last reload.
static func _wall_cut(field, listed: Array, mouth: Vector3, other: Vector3, half: float) -> Dictionary:
	var axis: Vector3 = mouth - other
	axis.y = 0.0
	if axis.length_squared() < 0.0001:
		axis = Vector3.FORWARD
	else:
		axis = axis.normalized()
	var at: Vector3 = other
	var last_dry: Vector3 = other
	var wall: Vector3 = mouth
	var i := 0
	while i < 40:
		at += axis * 0.45
		if not WaterTile.pond_at(listed, at).is_empty():
			wall = last_dry
			break
		last_dry = at
		i += 1
	var reach: float = half
	if field != null:
		reach = maxf(half, float(field.cell) * 0.55)
	return {"position": wall, "radius": reach}


## Move the drawn ends onto the lake walls so the lip comes out of the bank
## the swimmer is looking at, not out of a node that landed in the pond.
static func place_mouths(tunnel, field, listed: Array) -> void:
	if tunnel == null or field == null or tunnel._nodes.size() < 2:
		return
	var half: float = tunnel._half
	var head: Dictionary = _wall_cut(field, listed, tunnel._nodes[0], tunnel._nodes[1], half)
	var tail: Dictionary = _wall_cut(
		field, listed, tunnel._nodes[tunnel._nodes.size() - 1],
		tunnel._nodes[tunnel._nodes.size() - 2], half
	)
	var a: Vector3 = head.get("position", tunnel._nodes[0])
	var b: Vector3 = tail.get("position", tunnel._nodes[tunnel._nodes.size() - 1])
	tunnel._nodes[0] = Vector3(a.x, tunnel._nodes[0].y, a.z)
	tunnel._nodes[tunnel._nodes.size() - 1] = Vector3(
		b.x, tunnel._nodes[tunnel._nodes.size() - 1].y, b.z
	)


static func nodes_of(entry: Dictionary) -> Array:
	var listed: Variant = entry.get(NODES, [])
	return listed if typeof(listed) == TYPE_ARRAY else []


static func entries(listed: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in listed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if is_tunnel(String(entry.get("path", ""))):
			out.append(entry)
	return out


## Where one dig runs closest to a point, and how far off the line that is.
static func closest_on(entry: Dictionary, point: Vector3) -> Dictionary:
	var line := nodes_of(entry)
	if line.size() < 2:
		return {}
	var best := {}
	var closest := INF
	for i in range(1, line.size()):
		var a: Vector3 = line[i - 1]
		var b: Vector3 = line[i]
		var on := Geometry3D.get_closest_point_to_segment(point, a, b)
		var span := on.distance_to(point)
		if span >= closest:
			continue
		closest = span
		var along := 0.5
		var ab: Vector3 = b - a
		if ab.length_squared() > 0.0001:
			along = (point - a).dot(ab) / ab.length_squared()
		best = {
			"center": on,
			"distance": span,
			"past": along < -0.0001 or along > 1.0001,
		}
	return best


## The bore this point sits in, or nothing on dry rock. Slack lets a caller ask
## about the shell just outside the wall, which is how a swimmer is pulled back.
static func sample(listed: Array, point: Vector3, slack := 0.0) -> Dictionary:
	var best := {}
	var closest := INF
	for entry in entries(listed):
		var half := half_of(entry)
		var near := closest_on(entry, point)
		if near.is_empty():
			continue
		var span := float(near["distance"])
		if span > half + slack or span >= closest:
			continue
		closest = span
		var center: Vector3 = near["center"]
		best = {
			"center": center,
			"half": half,
			"water_y": center.y + half,
			"floor_y": center.y - half,
			"past": bool(near.get("past", false)),
		}
	return best


## How much water is over this point inside a tunnel. -1 means it is not in one.
static func depth_at(listed: Array, point: Vector3) -> float:
	var found := sample(listed, point)
	if found.is_empty():
		return -1.0
	return float(found["water_y"]) - float(found["floor_y"])


## Pull a point back inside the bore. Cheaper and tighter than lining the run
## with colliders: the rock is never cut, so there is nothing to squeeze into.
static func hold(listed: Array, point: Vector3, margin: float) -> Vector3:
	var found := sample(listed, point, margin + 1.0)
	if found.is_empty():
		return point
	var center: Vector3 = found["center"]
	# A mouth is an open end, not a closed sphere. Pulling along the run past
	# the last node is what trapped a swimmer who had already reached the pond.
	if bool(found.get("past", false)):
		return point
	var limit := maxf(float(found["half"]) - margin, 0.05)
	var off := point - center
	if off.length_squared() <= limit * limit:
		return point
	return center + off.normalized() * limit


static func create(entry: Dictionary) -> WaterTunnel:
	var tunnel := WaterTunnel.new()
	tunnel.name = "WaterTunnel"
	tunnel._half = half_of(entry)
	for point in nodes_of(entry):
		if point is Vector3:
			tunnel._nodes.append(point)
	return tunnel


func _ready() -> void:
	add_to_group(GROUP)
	if get_child_count() == 0:
		_assemble()
	# #region agent log
	var bore := get_node_or_null("Bore") as MeshInstance3D
	if bore != null and bore.mesh != null:
		var box := bore.mesh.get_aabb()
		var lf := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-5e45bb.log", FileAccess.READ_WRITE)
		if lf == null:
			lf = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-5e45bb.log", FileAccess.WRITE)
		else:
			lf.seek_end()
		if lf != null:
			lf.store_line(JSON.stringify({
				"sessionId": "5e45bb",
				"hypothesisId": "C",
				"location": "water_tunnel.gd:_ready",
				"message": "bore mesh",
				"data": {
					"origin": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)],
					"aabb": [snappedf(box.position.x, 0.01), snappedf(box.position.y, 0.01), snappedf(box.position.z, 0.01), snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01), snappedf(box.size.z, 0.01)],
					"nodes": _nodes.size(),
					"half": snappedf(_half, 0.01),
					"lip": LIP,
				},
				"timestamp": int(Time.get_unix_time_from_system() * 1000.0),
			}))
			lf.close()
	# #endregion


## One mesh for the whole run: a square tube swept along the dig, walled in
## rock. It is wound inward, so with a one-sided material a swimmer sees the
## inside of the bore and nothing shows through the ground from the far side.
func _assemble() -> void:
	if _nodes.size() < 2:
		return
	position = _nodes[0]
	var rings: Array = []
	for i in _nodes.size():
		rings.append(_ring(i))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Flat shading, so a corner stays a corner and the two faces of a collar
	# keep the opposite normals they were given.
	st.set_smooth_group(-1)
	for i in range(1, rings.size()):
		var near: Array = rings[i - 1]
		var far: Array = rings[i]
		for c in 4:
			var d := (c + 1) % 4
			_quad(st, near[c], near[d], far[d], far[c])
	_mouth(st, 0)
	_mouth(st, _nodes.size() - 1)
	st.generate_normals()
	st.index()
	var mesh := MeshInstance3D.new()
	mesh.name = "Bore"
	mesh.mesh = st.commit()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	MeshFactory.apply_grid(mesh, LOOK)
	add_child(mesh)


## Four corners around one node, square to the way the dig is heading. Corners
## take the average of the legs either side so a turn does not tear open.
func _ring(index: int) -> Array:
	var dir := Vector3.ZERO
	if index > 0:
		dir += (_nodes[index] - _nodes[index - 1]).normalized()
	if index < _nodes.size() - 1:
		dir += (_nodes[index + 1] - _nodes[index]).normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized() * _half
	var up := right.normalized().cross(dir).normalized() * _half
	var at := _nodes[index] - _nodes[0]
	return [at + right + up, at - right + up, at - right - up, at + right - up]


## The dug node sits in the bank. This walks the last ring out into the pond
## and frames it there, so the hole is in the water you are swimming in.
func _mouth(st: SurfaceTool, index: int) -> void:
	var ring: Array = _ring(index)
	var out := _outward(index) * LIP
	var lip: Array = []
	for corner in ring:
		lip.append((corner as Vector3) + out)
	# Same travel as the sweep (along the run) so the lip walls stay inward.
	# At the start that means pond-to-bank; at the end, bank-to-pond.
	var from_ring := index > 0
	for c in 4:
		var d := (c + 1) % 4
		if from_ring:
			_quad(st, ring[c], ring[d], lip[d], lip[c])
		else:
			_quad(st, lip[c], lip[d], ring[d], ring[c])
	var at: Vector3 = (_nodes[index] - _nodes[0]) + out
	_collar(st, lip, at)
	_bulkhead(st, index, lip, at)


func _outward(index: int) -> Vector3:
	var dir := Vector3.ZERO
	if index <= 0:
		dir = _nodes[0] - _nodes[1]
	else:
		dir = _nodes[index] - _nodes[index - 1]
	if dir.length_squared() < 0.0001:
		return Vector3.FORWARD
	return dir.normalized()


## A rock rim around a mouth, so an opening reads as a hole in the bank rather
## than a pipe sticking out of it. Faced both ways, since a mouth is looked at
## from the pond on one side and from inside the run on the other.
func _collar(st: SurfaceTool, ring: Array, at: Vector3) -> void:
	var grow := (_half + COLLAR) / _half
	for c in 4:
		var d := (c + 1) % 4
		var near_a: Vector3 = ring[c]
		var near_b: Vector3 = ring[d]
		var far_b: Vector3 = at + (near_b - at) * grow
		var far_a: Vector3 = at + (near_a - at) * grow
		_quad(st, near_a, near_b, far_b, far_a)
		_quad(st, far_a, far_b, near_b, near_a)


## Closes the lake wall around the hole so a bank cut is a doorway, not a
## view of the rest of the course. Faced both ways.
func _bulkhead(st: SurfaceTool, index: int, ring: Array, at: Vector3) -> void:
	var dir := _outward(index)
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized() * BULKHEAD_SIDE
	var up := Vector3.UP
	var outer: Array = [
		at + right + up * BULKHEAD_UP,
		at - right + up * BULKHEAD_UP,
		at - right - up * BULKHEAD_DOWN,
		at + right - up * BULKHEAD_DOWN,
	]
	for c in 4:
		var d := (c + 1) % 4
		_quad(st, ring[c], ring[d], outer[d], outer[c])
		_quad(st, outer[c], outer[d], ring[d], ring[c])
	# #region agent log
	if index == 0:
		var bf := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-5e45bb.log", FileAccess.READ_WRITE)
		if bf == null:
			bf = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-5e45bb.log", FileAccess.WRITE)
		else:
			bf.seek_end()
		if bf != null:
			bf.store_line(JSON.stringify({
				"sessionId": "5e45bb",
				"runId": "post-fix",
				"hypothesisId": "A",
				"location": "water_tunnel.gd:_bulkhead",
				"message": "mouth plate",
				"data": {
					"side": BULKHEAD_SIDE,
					"up": BULKHEAD_UP,
					"down": BULKHEAD_DOWN,
					"half": snappedf(_half, 0.01),
				},
				"timestamp": int(Time.get_unix_time_from_system() * 1000.0),
			}))
			bf.close()
	# #endregion


## Wound so the face looks back at a-b-c-d rather than away from it, which for
## the sweep below means every wall of the bore faces the swimmer inside it.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)
	st.add_vertex(a)
	st.add_vertex(d)
	st.add_vertex(c)
