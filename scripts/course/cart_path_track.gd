class_name CartPathTrack
extends Object
## Waypoints for the drive to the clubhouse. Windy turns on a level deck; trees
## are the boundary.

## [straight metres, turn degrees (left +), corner radius]
const LEGS: Array = [
	[50.0, 72.0, 20.0],
	[38.0, -88.0, 18.0],
	[34.0, 82.0, 18.0],
	[70.0, 68.0, 24.0],
	[42.0, 100.0, 16.0],
	[36.0, -155.0, 20.0],
	[52.0, -38.0, 22.0],
	[78.0, 90.0, 20.0],
	[46.0, -78.0, 18.0],
	[42.0, 62.0, 20.0],
	[85.0, 55.0, 22.0],
	[70.0, -85.0, 20.0],
	[100.0, 0.0, 0.0],
]
const JOIN := 1.1
const ARC_STEP_DEG := 10.0


static func centerline(origin: Vector3, heading: Vector3, start_h: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var pos := origin
	var dir := heading
	dir.y = 0.0
	dir = dir.normalized()
	var travelled := 0.0
	points.append(_lift(pos, start_h))
	for leg in LEGS:
		var dist := float(leg[0])
		var turn := float(leg[1])
		var radius := float(leg[2])
		pos = pos + dir * dist
		travelled += dist
		points.append(_lift(pos, start_h))
		if absf(turn) < 0.5 or radius < 1.0:
			continue
		var arc := _arc(pos, dir, radius, turn, start_h, travelled)
		for p in arc["points"]:
			points.append(p)
		pos = arc["pos"]
		dir = arc["dir"]
		travelled = float(arc["travelled"])
	return points


static func length_of(points: Array[Vector3]) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


static func finish_heading(points: Array[Vector3]) -> Vector3:
	if points.size() < 2:
		return Vector3.FORWARD
	var along := points[points.size() - 1] - points[points.size() - 2]
	along.y = 0.0
	return along.normalized()


static func turn_count() -> int:
	var total := 0
	for leg in LEGS:
		if absf(float(leg[1])) >= 40.0:
			total += 1
	return total


static func distance_to(points: Array[Vector3], point: Vector3) -> float:
	var p := Vector3(point.x, 0.0, point.z)
	var best := INF
	for i in range(1, points.size()):
		var a := Vector3(points[i - 1].x, 0.0, points[i - 1].z)
		var b := Vector3(points[i].x, 0.0, points[i].z)
		best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b)))
	return best


static func closest(points: Array[Vector3], point: Vector3) -> Vector3:
	if points.is_empty():
		return point
	var p := Vector3(point.x, 0.0, point.z)
	var best := points[0]
	var best_d := INF
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var a2 := Vector3(a.x, 0.0, a.z)
		var b2 := Vector3(b.x, 0.0, b.z)
		var on := Geometry3D.get_closest_point_to_segment(p, a2, b2)
		var d := p.distance_to(on)
		if d >= best_d:
			continue
		best_d = d
		var span := a2.distance_to(b2)
		var t := 0.0 if span < 0.0001 else a2.distance_to(on) / span
		best = a.lerp(b, t)
	return best


static func along(points: Array[Vector3], point: Vector3) -> float:
	var p := Vector3(point.x, 0.0, point.z)
	var travelled := 0.0
	var best := 0.0
	var best_d := INF
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var a2 := Vector3(a.x, 0.0, a.z)
		var b2 := Vector3(b.x, 0.0, b.z)
		var span := a2.distance_to(b2)
		var on := Geometry3D.get_closest_point_to_segment(p, a2, b2)
		var d := p.distance_to(on)
		if d < best_d:
			best_d = d
			best = travelled + a2.distance_to(on)
		travelled += span
	return best


static func at(points: Array[Vector3], distance: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	var target := clampf(distance, 0.0, length_of(points))
	var travelled := 0.0
	for i in range(1, points.size()):
		var span := points[i - 1].distance_to(points[i])
		if travelled + span >= target:
			var t := 0.0 if span < 0.0001 else (target - travelled) / span
			return points[i - 1].lerp(points[i], t)
		travelled += span
	return points[points.size() - 1]


static func heading_at(points: Array[Vector3], distance: float) -> Vector3:
	var here := at(points, distance)
	var ahead := at(points, distance + 1.5)
	var along := ahead - here
	along.y = 0.0
	if along.length_squared() < 0.0001:
		return finish_heading(points)
	return along.normalized()


static func _arc(
	origin: Vector3, heading: Vector3, radius: float, turn_deg: float,
	start_h: float, travelled: float
) -> Dictionary:
	var right := heading.cross(Vector3.UP).normalized()
	var inward := -right if turn_deg > 0.0 else right
	var center := origin + inward * radius
	var arm := origin - center
	var steps := maxi(3, int(absf(turn_deg) / ARC_STEP_DEG))
	var points: Array[Vector3] = []
	var pos := origin
	var dir := heading
	var dist := travelled
	for i in range(1, steps + 1):
		var rot := deg_to_rad(turn_deg) * (float(i) / float(steps))
		pos = center + arm.rotated(Vector3.UP, rot)
		dir = heading.rotated(Vector3.UP, rot).normalized()
		var step := radius * absf(deg_to_rad(turn_deg)) / float(steps)
		dist += step
		points.append(_lift(pos, start_h))
	return {"points": points, "pos": pos, "dir": dir, "travelled": dist}


static func _lift(point: Vector3, start_h: float) -> Vector3:
	return Vector3(point.x, start_h, point.z)
