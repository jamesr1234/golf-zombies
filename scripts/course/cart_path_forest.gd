class_name CartPathForest
extends Object
## Woods around the clubhouse drive. Level ground; trees stand close on both
## sides as the boundary. Never redraws the hole.

const HALF_WIDTH := 56.0
const ROAD_WIDTH := 25.0
const CELL := 3.0
const ROAD_FLAT := 1.6
const TEE_FLAT := 22.0
const ROW_OFFSETS: Array[float] = [14.85, 22.25, 34.25, 46.25]
const CHEAP_ROWS: Array[float] = [14.85, 34.25]
const TREE_SPACING := 9.0
const LANE_CLEAR := 13.9
const START_CLEAR := 16.0
const TEE_CLEAR := 20.0
const HOST_BATCH := 4
const CHEAP_BATCH := 12


static func should_spread(active: bool) -> bool:
	return active


static func should_cheap(active: bool, _is_server := false) -> bool:
	return active


static func dress(path: Node3D, keep_out: Rect2) -> void:
	queue(path, keep_out, false)
	flush(path)


static func queue(path: Node3D, keep_out: Rect2, cheap: bool) -> void:
	path.set("woods_keep_out", keep_out)
	path.set("woods_cheap", cheap)
	path.set("woods_need_field", not cheap)
	if cheap:
		path.set("woods_spots", _spots(path, keep_out, true))
	else:
		path.set("woods_spots", [] as Array[Dictionary])


static func busy(path: Node3D) -> bool:
	if bool(path.get("woods_need_field")):
		return true
	var spots: Array = path.get("woods_spots")
	return spots != null and not spots.is_empty()


static func flush(path: Node3D) -> void:
	while step(path):
		pass


static func step(path: Node3D) -> bool:
	if bool(path.get("woods_need_field")):
		_lay_ground(path, path.get("woods_keep_out"))
		path.set("woods_need_field", false)
		path.set("woods_spots", _spots(path, path.get("woods_keep_out"), false))
		return busy(path)
	var spots: Array = path.get("woods_spots")
	if spots == null or spots.is_empty():
		return false
	var cap := CHEAP_BATCH if bool(path.get("woods_cheap")) else HOST_BATCH
	var n := 0
	while n < cap and not spots.is_empty():
		_plant_spot(path, spots.pop_back())
		n += 1
	path.set("woods_spots", spots)
	return busy(path)


static func _lay_ground(path: Node3D, keep_out: Rect2) -> void:
	var field := _field(path, keep_out)
	path.set("forest_height", field)
	var ground := field.make_body()
	ground.name = "ForestGround"
	path.add_child(ground)


static func _field(path: Node3D, keep_out: Rect2) -> HeightField:
	var centerline: Array[Vector3] = path.get("centerline")
	var heading: Vector3 = path.get("heading")
	var tee: Vector3 = path.get("tee")
	var plaza := ClubhouseBuild.at_tee(tee, heading)
	var yaw := ClubhouseBuild.yaw_at_tee(tee, plaza)
	var rect := _bounds(centerline)
	var field := HeightField.new()
	field.origin = rect.position
	field.cell = CELL
	field.hide = keep_out
	field.width = maxi(2, int(ceil(rect.size.x / CELL)) + 1)
	field.depth = maxi(2, int(ceil(rect.size.y / CELL)) + 1)
	field.samples.resize(field.width * field.depth)
	field.min_height = INF
	field.max_height = -INF
	var pit := INF
	for z in field.depth:
		for x in field.width:
			var wx := field.origin.x + float(x) * CELL
			var wz := field.origin.y + float(z) * CELL
			var at := z * field.width + x
			if keep_out.has_point(Vector2(wx, wz)):
				if CartPathTrack.distance_to(centerline, Vector3(wx, 0.0, wz)) < ROAD_WIDTH * 0.5 + ROAD_FLAT:
					var h := _height_at(centerline, tee, plaza, yaw, Vector3(wx, 0.0, wz))
					field.samples[at] = h
					field.min_height = minf(field.min_height, h)
					field.max_height = maxf(field.max_height, h)
					pit = minf(pit, h)
					continue
				field.samples[at] = 0.0
				continue
			var h := _height_at(centerline, tee, plaza, yaw, Vector3(wx, 0.0, wz))
			field.samples[at] = h
			field.min_height = minf(field.min_height, h)
			field.max_height = maxf(field.max_height, h)
			pit = minf(pit, h)
	if pit == INF:
		pit = 0.0
		field.min_height = 0.0
		field.max_height = 0.0
	var buried := pit - HeightField.SKIRT - 8.0
	for z in field.depth:
		for x in field.width:
			var wx := field.origin.x + float(x) * CELL
			var wz := field.origin.y + float(z) * CELL
			if keep_out.has_point(Vector2(wx, wz)):
				if CartPathTrack.distance_to(centerline, Vector3(wx, 0.0, wz)) < ROAD_WIDTH * 0.5 + ROAD_FLAT:
					continue
				field.samples[z * field.width + x] = buried
	return field


static func _height_at(
	centerline: Array[Vector3], tee: Vector3, plaza: Vector3, yaw: float, point: Vector3
) -> float:
	var road := CartPathTrack.closest(centerline, point)
	var h := road.y
	h = lerpf(h, tee.y, 1.0 - clampf((point.distance_to(tee) - TEE_FLAT) / 8.0, 0.0, 1.0))
	var edge := ClubhouseBuild.pad_edge(plaza, yaw, point)
	if edge >= 0.0:
		return tee.y
	h = lerpf(h, tee.y, 1.0 - clampf(-edge / ClubhouseBuild.PAD_BLEND, 0.0, 1.0))
	return h


static func _bounds(centerline: Array[Vector3]) -> Rect2:
	var rect := Rect2(Vector2(centerline[0].x, centerline[0].z), Vector2.ZERO)
	for point in centerline:
		rect = rect.expand(Vector2(point.x, point.z))
	return rect.grow(HALF_WIDTH)


static func _spots(path: Node3D, keep_out: Rect2, cheap: bool) -> Array[Dictionary]:
	var centerline: Array[Vector3] = path.get("centerline")
	var tee: Vector3 = path.get("tee")
	var heading: Vector3 = path.get("heading")
	var plaza := ClubhouseBuild.at_tee(tee, heading)
	var yaw := ClubhouseBuild.yaw_at_tee(tee, plaza)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260816 + int(centerline[0].x * 11.0) + int(centerline[0].z * 19.0)
	var rows: Array[float] = CHEAP_ROWS if cheap else ROW_OFFSETS
	var next := TREE_SPACING * 0.4
	var travelled := 0.0
	var spots: Array[Dictionary] = []
	for i in range(1, centerline.size()):
		var a := centerline[i - 1]
		var b := centerline[i]
		var along := b - a
		along.y = 0.0
		var span := along.length()
		if span < 0.8:
			continue
		var dir := along / span
		var right := dir.cross(Vector3.UP).normalized()
		travelled += span
		while next <= travelled + 0.01:
			var t := 1.0 - (travelled - next) / span
			var at := a.lerp(b, clampf(t, 0.0, 1.0))
			for offset in rows:
				for side in [-1.0, 1.0]:
					if rng.randf() < 0.1:
						continue
					var spot := at + dir * rng.randf_range(-2.2, 2.2)
					spot += right * side * (offset + rng.randf_range(-1.6, 1.6))
					var planted := _spot_at(path, centerline, tee, plaza, yaw, keep_out, rng, spot, cheap)
					if not planted.is_empty():
						spots.append(planted)
			next += TREE_SPACING
	return spots


static func _spot_at(
	path: Node3D, centerline: Array[Vector3], tee: Vector3, plaza: Vector3, yaw: float,
	keep_out: Rect2, rng: RandomNumberGenerator, spot: Vector3, cheap: bool
) -> Dictionary:
	if keep_out.has_point(Vector2(spot.x, spot.z)):
		return {}
	if CartPathTrack.distance_to(centerline, spot) < LANE_CLEAR:
		return {}
	if spot.distance_to(centerline[0]) < START_CLEAR:
		return {}
	if spot.distance_to(tee) < TEE_CLEAR:
		return {}
	if ClubhouseBuild.covers_ground(plaza, yaw, spot, 4.0):
		return {}
	var field: HeightField = path.get("forest_height")
	if field != null:
		spot.y = field.height_at(spot.x, spot.z)
	elif not centerline.is_empty():
		spot.y = CartPathTrack.closest(centerline, spot).y
	return {
		"kind": "tree",
		"position": spot,
		"size": Vector3(rng.randf_range(0.55, 1.1), rng.randf_range(6.0, 11.0), 0.0),
		"yaw": rng.randf_range(0.0, 360.0),
		"cheap": cheap,
	}


static func _plant_spot(path: Node3D, prop: Dictionary) -> void:
	if prop.is_empty():
		return
	var tree := HoleBuilder.create_prop(prop)
	tree.add_to_group("forest_trees")
	path.add_child(tree)
