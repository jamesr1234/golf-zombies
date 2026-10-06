@tool
class_name WaterTile
extends StaticBody3D
## One cell of a custom-hole pond. Tiles are laid as a rectangle, then locked
## with a single depth, which is the hole you swim in. WaterTunnel digs between
## two finished ponds; nothing here knows about that.

const GROUP := "water"
const SCENE := "res://scenes/course/props/water.tscn"
const SPAN := 1.35
const DEPTH := "depth"
const POOL := "pool"
const SURFACE := "surface"
const DEPTH_STEP := 0.5
const DEPTH_MIN := 1.2
const DEPTH_MAX := 12.0
const DEFAULT_DEPTH := 3.0
## Surface.Type.WATER, kept as a number so this script never imports Surface.
const LIE := 6


var _tiles: Array[Dictionary] = []


static func from_group(group: Array) -> WaterTile:
	var packed := load(SCENE) as PackedScene
	var water := packed.instantiate() as WaterTile
	for entry in group:
		if typeof(entry) == TYPE_DICTIONARY:
			water._tiles.append(entry)
	return water


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 0
	collision_mask = 0
	if get_child_count() == 0:
		_assemble()


static func is_tile(path: String) -> bool:
	return path == SCENE or path.get_file() == "water.tscn"


static func clamp_depth(value: float) -> float:
	return snappedf(clampf(value, DEPTH_MIN, DEPTH_MAX), DEPTH_STEP)


static func depth_of(entry: Dictionary) -> float:
	return clamp_depth(float(entry.get(DEPTH, DEFAULT_DEPTH)))


static func has_depth(entry: Dictionary) -> bool:
	return entry.has(DEPTH) and float(entry[DEPTH]) > 0.001


static func surface_of(entry: Dictionary, fallback := 0.0) -> float:
	return float(entry.get(SURFACE, fallback))


static func pool_of(entry: Dictionary) -> Vector3:
	var point: Variant = entry.get(POOL, Vector3.INF)
	return point as Vector3 if point is Vector3 else Vector3.INF


static func tile_covers(tile_at: Vector3, point: Vector3) -> bool:
	var half := SPAN * 0.5 + 0.02
	return maxf(absf(point.x - tile_at.x), absf(point.z - tile_at.z)) <= half


static func covers_any(placements: Array, point: Vector3) -> bool:
	for entry in placements:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not is_tile(String(entry.get("path", ""))):
			continue
		if tile_covers(entry["position"] as Vector3, point):
			return true
	return false


static func cells_between(from: Vector3, to: Vector3) -> Array[Vector3]:
	var ax := snappedf(from.x, SPAN)
	var az := snappedf(from.z, SPAN)
	var bx := snappedf(to.x, SPAN)
	var bz := snappedf(to.z, SPAN)
	var x0 := minf(ax, bx)
	var x1 := maxf(ax, bx)
	var z0 := minf(az, bz)
	var z1 := maxf(az, bz)
	var out: Array[Vector3] = []
	var x := x0
	while x <= x1 + 0.001:
		var z := z0
		while z <= z1 + 0.001:
			out.append(Vector3(x, 0.0, z))
			z += SPAN
		x += SPAN
	return out


static func neighbors_of(cell: Vector3) -> Array[Vector3]:
	return [
		cell + Vector3(SPAN, 0.0, 0.0),
		cell - Vector3(SPAN, 0.0, 0.0),
		cell + Vector3(0.0, 0.0, SPAN),
		cell - Vector3(0.0, 0.0, SPAN),
	]


static func touches_any(placements: Array, point: Vector3) -> bool:
	for cell in neighbors_of(point):
		if covers_any(placements, cell):
			return true
	return false


static func tile_at(placements: Array, point: Vector3) -> Dictionary:
	for entry in placements:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not is_tile(String(entry.get("path", ""))):
			continue
		if tile_covers(entry["position"] as Vector3, point):
			return entry
	return {}


## The finished pond nearest a point, searched flat so a dig underneath one
## still finds the water it belongs to.
static func pond_at(listed: Array, point: Vector3, reach := 0.0) -> Dictionary:
	var best := {}
	var closest := INF
	for entry in listed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not is_tile(String(entry.get("path", ""))) or not has_depth(entry):
			continue
		var at: Vector3 = entry["position"]
		var span := Vector2(at.x - point.x, at.z - point.z).length()
		if span > SPAN * 0.5 + reach + 0.02 or span >= closest:
			continue
		closest = span
		best = entry
	return best


static func spots(listed: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for entry in listed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not is_tile(String(entry.get("path", ""))):
			continue
		out.append(entry["position"] as Vector3)
	return out


## Drop the ground under every finished pond so there is water to swim in.
static func sink(field, listed: Array) -> void:
	if field == null or field.width < 2 or field.depth < 2:
		return
	var bowls: Array[Dictionary] = []
	for entry in listed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not is_tile(String(entry.get("path", ""))) or not has_depth(entry):
			continue
		bowls.append(entry)
	if bowls.is_empty():
		return
	for z in field.depth:
		for x in field.width:
			var at: int = z * field.width + x
			var point := Vector3(
				field.origin.x + float(x) * field.cell,
				0.0,
				field.origin.y + float(z) * field.cell
			)
			for entry in bowls:
				if not tile_covers(entry["position"] as Vector3, point):
					continue
				var water_y := surface_of(entry, field.samples[at])
				field.samples[at] = minf(field.samples[at], water_y - depth_of(entry))


static func sample(listed: Array, point: Vector3) -> Dictionary:
	var entry := tile_at(listed, point)
	if entry.is_empty() or not has_depth(entry):
		return {}
	var water_y := surface_of(entry, point.y)
	return {"water_y": water_y, "floor_y": water_y - depth_of(entry)}


static func depth_at(listed: Array, point: Vector3) -> float:
	var found := sample(listed, point)
	if found.is_empty():
		return -1.0
	return maxf(0.0, float(found["water_y"]) - float(found["floor_y"]))


func _assemble() -> void:
	if _tiles.is_empty():
		_tiles.append({"position": Vector3.ZERO, SURFACE: 0.0, DEPTH: DEFAULT_DEPTH})
	var origin := _centroid(_tiles)
	position = Vector3(origin.x, 0.0, origin.z)
	var lie := Area3D.new()
	lie.name = "Lie"
	lie.collision_layer = Layers.SURFACE
	lie.collision_mask = Layers.BALL
	lie.monitorable = false
	add_child(lie)
	for entry in _tiles:
		var at: Vector3 = entry["position"]
		var local := Vector3(at.x - origin.x, 0.0, at.z - origin.z)
		var water_y := surface_of(entry)
		add_child(_surface_at(local, water_y))
		if has_depth(entry):
			lie.add_child(_volume_at(local, water_y, depth_of(entry)))
	if not lie.body_entered.is_connected(_on_ball_entered):
		lie.body_entered.connect(_on_ball_entered)
	if not lie.body_exited.is_connected(_on_ball_exited):
		lie.body_exited.connect(_on_ball_exited)


func _surface_at(offset: Vector3, water_y: float) -> MeshInstance3D:
	var look := _water_look()
	var mesh := MeshFactory.flat_quad(Vector2(SPAN, SPAN), look["line"])
	mesh.name = "Surface"
	mesh.position = Vector3(offset.x, water_y + 0.04, offset.z)
	MeshFactory.apply_grid(mesh, look)
	return mesh


func _water_look() -> Dictionary:
	return {
		"base": Color(0.02, 0.03, 0.14), "line": Color(0.2, 0.5, 1.0),
		"cell": SPAN, "energy": 2.4, "scroll": 0.35, "opacity": 0.52,
	}


func _volume_at(offset: Vector3, water_y: float, depth: float) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var span := depth + 0.4
	box.size = Vector3(SPAN, span, SPAN)
	node.shape = box
	node.position = Vector3(offset.x, water_y - span * 0.5 + 0.2, offset.z)
	return node


func _centroid(tiles: Array[Dictionary]) -> Vector3:
	var origin := Vector3.ZERO
	for entry in tiles:
		origin += entry["position"] as Vector3
	return origin / float(tiles.size())


func _on_ball_entered(body: Node3D) -> void:
	if body.has_method("enter_surface"):
		body.enter_surface(LIE)


func _on_ball_exited(body: Node3D) -> void:
	if body.has_method("exit_surface"):
		body.exit_surface(LIE)
