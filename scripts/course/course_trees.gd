class_name CourseTrees
extends Object
## Trees that frame a hole: a line just off the fairway, and a belt around the
## bounds so the course sits in woods instead of empty rough.

const FAIRWAY_SPACING := 11.0
const PERIMETER_SPACING := 10.0
const PERIMETER_RINGS := 2
const PERIMETER_INSET := 7.0
const PERIMETER_RING_GAP := 10.0
const MIN_GAP := 4.4
const EXIT_HALF := 16.0


static func plant(
	data: HoleData, rng: RandomNumberGenerator, width: float, blocked: Callable
) -> void:
	_along_fairway(data, rng, width, blocked)
	_around_bounds(data, rng, blocked)


static func _along_fairway(
	data: HoleData, rng: RandomNumberGenerator, width: float, blocked: Callable
) -> void:
	var next := FAIRWAY_SPACING * 0.4
	var travelled := 0.0
	for i in range(1, data.centerline.size()):
		var a: Vector3 = data.centerline[i - 1]
		var b: Vector3 = data.centerline[i]
		var along := b - a
		along.y = 0.0
		var span := along.length()
		if span < 0.4:
			continue
		var dir := along / span
		var right := dir.cross(Vector3.UP).normalized()
		travelled += span
		while next <= travelled + 0.01:
			var t := 1.0 - (travelled - next) / span
			var at := a.lerp(b, clampf(t, 0.0, 1.0))
			for side in [-1.0, 1.0]:
				var offset := width * 0.5 + rng.randf_range(7.0, 16.0)
				_try_tree(data, rng, at + right * side * offset, blocked)
			next += FAIRWAY_SPACING


static func _around_bounds(data: HoleData, rng: RandomNumberGenerator, blocked: Callable) -> void:
	for ring in PERIMETER_RINGS:
		var inset := PERIMETER_INSET + float(ring) * PERIMETER_RING_GAP
		var inner := data.bounds.grow(-inset)
		if inner.size.x < 8.0 or inner.size.y < 8.0:
			continue
		var corners := [
			inner.position,
			Vector2(inner.end.x, inner.position.y),
			inner.end,
			Vector2(inner.position.x, inner.end.y),
		]
		for i in 4:
			_walk_edge(data, rng, corners[i], corners[(i + 1) % 4], blocked)


static func _walk_edge(
	data: HoleData, rng: RandomNumberGenerator, from: Vector2, to: Vector2, blocked: Callable
) -> void:
	var delta := to - from
	var span := delta.length()
	if span < 4.0:
		return
	var steps := maxi(1, int(span / PERIMETER_SPACING))
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var jitter := Vector2(rng.randf_range(-2.2, 2.2), rng.randf_range(-2.2, 2.2))
		var at := from.lerp(to, t) + jitter
		_try_tree(data, rng, Vector3(at.x, 0.0, at.y), blocked)


static func _try_tree(
	data: HoleData, rng: RandomNumberGenerator, spot: Vector3, blocked: Callable
) -> void:
	if not data.bounds.has_point(Vector2(spot.x, spot.z)):
		return
	if blocked.call(spot):
		return
	if in_exit_corridor(data, spot):
		return
	if _too_close(data, spot):
		return
	data.props.append({
		"kind": "tree",
		"position": spot,
		"size": Vector3(rng.randf_range(0.55, 1.05), rng.randf_range(5.5, 10.0), 0.0),
		"yaw": rng.randf_range(0.0, 360.0),
	})


static func in_exit_corridor(data: HoleData, spot: Vector3) -> bool:
	var along := data.cup - data.tee
	along.y = 0.0
	if along.length_squared() < 0.0001:
		return false
	along = along.normalized()
	var local := spot - data.cup
	local.y = 0.0
	if local.dot(along) < data.green_radius:
		return false
	return (local - along * local.dot(along)).length() < EXIT_HALF


static func _too_close(data: HoleData, spot: Vector3) -> bool:
	for prop in data.props:
		if spot.distance_to(prop["position"]) < MIN_GAP:
			return true
	return false
