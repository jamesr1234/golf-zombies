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
const TREE_SPACING := 9.0
const LANE_CLEAR := 13.9
const START_CLEAR := 16.0
const TEE_CLEAR := 20.0


static func dress(path: Node3D, keep_out: Rect2) -> void:
	var field := _field(path, keep_out)
	path.set("forest_height", field)
	var ground := field.make_body()
	ground.name = "ForestGround"
	path.add_child(ground)
	_plant(path, keep_out)


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


static func _plant(path: Node3D, keep_out: Rect2) -> void:
	var centerline: Array[Vector3] = path.get("centerline")
	var tee: Vector3 = path.get("tee")
	var heading: Vector3 = path.get("heading")
	var plaza := ClubhouseBuild.at_tee(tee, heading)
	var yaw := ClubhouseBuild.yaw_at_tee(tee, plaza)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260816 + int(centerline[0].x * 11.0) + int(centerline[0].z * 19.0)
	var next := TREE_SPACING * 0.4
	var travelled := 0.0
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
			for offset in ROW_OFFSETS:
				for side in [-1.0, 1.0]:
					if rng.randf() < 0.1:
						continue
					var spot := at + dir * rng.randf_range(-2.2, 2.2)
					spot += right * side * (offset + rng.randf_range(-1.6, 1.6))
					_try_tree(path, centerline, tee, plaza, yaw, keep_out, rng, spot)
			next += TREE_SPACING


static func _try_tree(
	path: Node3D, centerline: Array[Vector3], tee: Vector3, plaza: Vector3, yaw: float,
	keep_out: Rect2, rng: RandomNumberGenerator, spot: Vector3
) -> void:
	if keep_out.has_point(Vector2(spot.x, spot.z)):
		return
	if CartPathTrack.distance_to(centerline, spot) < LANE_CLEAR:
		return
	if spot.distance_to(centerline[0]) < START_CLEAR:
		return
	if spot.distance_to(tee) < TEE_CLEAR:
		return
	if ClubhouseBuild.covers_ground(plaza, yaw, spot, 4.0):
		return
	var field: HeightField = path.get("forest_height")
	if field != null:
		spot.y = field.height_at(spot.x, spot.z)
	var size := Vector3(rng.randf_range(0.55, 1.1), rng.randf_range(6.0, 11.0), 0.0)
	var tree := HoleBuilder.create_prop({
		"kind": "tree",
		"position": spot,
		"size": size,
		"yaw": rng.randf_range(0.0, 360.0),
	})
	tree.add_to_group("forest_trees")
	path.add_child(tree)
