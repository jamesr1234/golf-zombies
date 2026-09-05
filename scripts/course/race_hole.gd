class_name RaceHole
extends Object
## Hole 11: Test Hole 2. A four-thousand-yard par 5 on a wide out-and-back
## strip with a few sweeping U-turns. Drive through the hoop off the tee,
## then a drop onto the last five hundred yards.

const INDEX := 10
const YARDS := 4000
const METRE := 0.9144
const LENGTH := YARDS * METRE
const PAR := 5
## Four cart-lanes. Wide enough that neighbouring strips stay rough, not fairway.
const WIDTH := 52.0
const ARC_STEP := 10.0
## Sweeping 180s. Two radii fit the strip plus a rough gap between them.
const TURN_R := 70.0
const FOLDS := 3
const LONG := 160.0
## Drive target on the opening straight, inside a full-swing carry.
const HOOP_ALONG := 56.0
const DROP_YARDS := 500
const DROP_ALONG := 36.0
const DROP_SIDE := 14.0
const WARMUP := "Four thousand yards. Drive it through the hoop.\nYou reappear about five hundred yards from the cup."
const WARMUP_SHORT := "Four thousand yards. Drive it through the hoop."
const BOOST_LEN := 16.0
const BOOST_WIDTH := 14.0
const BOOST_FILL := 0.88
const BOOST_END := 7.0
const BOOST_PITCH := 28.0
const BOOST_SIDE := 8.0
const BOOST_DUAL := 48.0
const TEE_CLEAR := 20.0
const CAR_TEE_ALONG := 2.0
const CAR_TEE_SIDE := 0.0
const CAR_DROP_SIDE := 8.0
const RAMP_LEAD := 10.0
const RAMP_LAND := 32.0
const RAMP_NEED := 100.0
const HOOP_CLEAR := 88.0
const CUP_CLEAR := 90.0
const RUN_JOIN := 8.0


static func applies(data: HoleData) -> bool:
	return data != null and data.custom == null and data.index == INDEX


static func applies_index(index: int) -> bool:
	return index == INDEX


static func path() -> Dictionary:
	var headings: Array[float] = []
	var lengths: Array[float] = []
	var arcs: Array[bool] = []
	var locks: Array[bool] = []
	var heading := 0.0
	heading = _straight(headings, lengths, arcs, locks, heading, LONG)
	var sign := 1.0
	for _i in FOLDS:
		heading = _arc(headings, lengths, arcs, locks, heading, sign * 180.0, TURN_R)
		heading = _straight(headings, lengths, arcs, locks, heading, LONG)
		sign *= -1.0
	_scale(lengths, arcs, locks)
	return {"headings": headings, "lengths": lengths, "arcs": arcs}


static func infield_gap() -> float:
	return 2.0 * TURN_R - WIDTH


static func layout(data: HoleData, _headings: Array[float], _width: float) -> void:
	if data.centerline.size() < 2:
		return
	var a: Vector3 = data.centerline[0]
	var b: Vector3 = data.centerline[1]
	var span := a.distance_to(b)
	var along := minf(HOOP_ALONG, span * 0.72)
	data.race_hoop = a.lerp(b, along / maxf(span, 0.001))
	var back := -data.along_tee()
	data.race_hoop_yaw = rad_to_deg(atan2(-back.x, -back.z))
	_dress_track(data)
	# #region agent log
	_dbg_shape(data)
	# #endregion


static func drop_point(data: HoleData, rng: RandomNumberGenerator) -> Vector3:
	var remain := float(DROP_YARDS) * METRE
	var along := maxf(0.0, data.length() - remain)
	along += rng.randf_range(-DROP_ALONG, DROP_ALONG)
	along = clampf(along, 0.0, data.length())
	var t := along / maxf(data.length(), 0.001)
	var here := HoleGenerator.point_along(data, t)
	var ahead := HoleGenerator.point_along(data, minf(1.0, t + 0.008))
	var forward := ahead - here
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = data.along_cup()
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var spot := here + right * rng.randf_range(-DROP_SIDE, DROP_SIDE)
	return data.lift(spot)


static func remaining(data: HoleData, point: Vector3) -> float:
	return (1.0 - HeightField.along_t(data, point)) * data.length()


static func turn_angles() -> Array[float]:
	var track := path()
	var headings: Array = track["headings"]
	var arcs: Array = track["arcs"]
	var angles: Array[float] = []
	var acc := 0.0
	var active := false
	for i in headings.size():
		if not arcs[i]:
			if active:
				angles.append(acc)
				acc = 0.0
				active = false
			continue
		var prev: float = headings[i] if i == 0 else headings[i - 1]
		acc += headings[i] - prev
		active = true
	if active:
		angles.append(acc)
	return angles


static func _dress_track(data: HoleData) -> void:
	var total := data.length()
	for run in _straight_runs(data):
		var along0: float = run["along"]
		var span: float = run["length"]
		var along1 := along0 + span
		if along1 < TEE_CLEAR or along0 > total - CUP_CLEAR:
			continue
		var ramp_from := -1.0
		var ramp_to := -1.0
		var takeoff := maxf(along0 + RAMP_LEAD, HOOP_CLEAR)
		if (
			span >= RAMP_NEED
			and takeoff + JumpRamp.ground_run() + RAMP_LAND <= minf(along1 - 8.0, total - CUP_CLEAR)
		):
			ramp_from = takeoff
			ramp_to = ramp_from + JumpRamp.ground_run() + RAMP_LAND
			_add_ramp(data, ramp_from)
		var cursor := maxf(along0 + 5.0, TEE_CLEAR)
		var stop := along1 - BOOST_END
		var dual := span >= BOOST_DUAL
		while cursor + BOOST_LEN <= stop:
			var pad_end := cursor + BOOST_LEN
			if ramp_from >= 0.0 and cursor < ramp_to and pad_end > ramp_from:
				cursor = ramp_to
				continue
			if dual:
				_add_boost(data, cursor, pad_end, -BOOST_SIDE)
				_add_boost(data, cursor, pad_end, BOOST_SIDE)
			else:
				_add_boost(data, cursor, pad_end, 0.0)
			cursor += BOOST_PITCH


static func car_poses(data: HoleData) -> Array[Dictionary]:
	var poses: Array[Dictionary] = []
	if data == null or data.centerline.size() < 2:
		return poses
	poses.append(_offset_pose(_pose_at(data, CAR_TEE_ALONG), CAR_TEE_SIDE))
	var drop_along := maxf(0.0, data.length() - float(DROP_YARDS) * METRE)
	poses.append(_offset_pose(_pose_at(data, drop_along), CAR_DROP_SIDE))
	return poses


static func _add_ramp(data: HoleData, along: float) -> void:
	var pose := _pose_at(data, along)
	var run := JumpRamp.ground_run()
	var origin: Vector3 = _pose_at(data, along + run * 0.5)["position"]
	data.jumps.append({
		"position": origin,
		"yaw": pose["yaw"],
		"width": JumpRamp.WIDTH,
		"length": JumpRamp.LENGTH,
		"angle_deg": JumpRamp.ANGLE_DEG,
		"role": "takeoff",
	})


static func _add_boost(data: HoleData, from_along: float, to_along: float, side := 0.0) -> void:
	var from_pose := _offset_pose(_pose_at(data, from_along), side)
	var to_pose := _offset_pose(_pose_at(data, to_along), side)
	var from_at: Vector3 = from_pose["position"]
	var to_at: Vector3 = to_pose["position"]
	data.boosts.append({
		"from": from_at,
		"to": to_at,
		"width": BOOST_WIDTH,
		"fill": BOOST_FILL,
	})


static func _offset_pose(pose: Dictionary, side: float) -> Dictionary:
	if absf(side) < 0.01:
		return pose
	var at: Vector3 = pose["position"]
	var yaw := deg_to_rad(float(pose["yaw"]))
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := forward.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	return {"position": at + right * side, "yaw": pose["yaw"]}


static func _straight_runs(data: HoleData) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	if data.centerline.size() < 2:
		return runs
	var start: Vector3 = data.centerline[0]
	var along0 := 0.0
	var travelled := 0.0
	var run_len := 0.0
	var run_dir := Vector3.FORWARD
	for i in range(1, data.centerline.size()):
		var a: Vector3 = data.centerline[i - 1]
		var b: Vector3 = data.centerline[i]
		var delta := b - a
		delta.y = 0.0
		var step := delta.length()
		if step < 0.001:
			continue
		var dir := delta / step
		if run_len <= 0.001:
			start = a
			along0 = travelled
			run_dir = dir
			run_len = step
		elif dir.dot(run_dir) > cos(deg_to_rad(RUN_JOIN)):
			run_len += step
		else:
			if run_len >= BOOST_LEN:
				runs.append({"along": along0, "length": run_len, "from": start, "to": a})
			start = a
			along0 = travelled
			run_dir = dir
			run_len = step
		travelled += step
	if run_len >= BOOST_LEN:
		runs.append({
			"along": along0, "length": run_len, "from": start,
			"to": data.centerline[data.centerline.size() - 1],
		})
	return runs


static func _pose_at(data: HoleData, metres: float) -> Dictionary:
	var target := clampf(metres, 0.0, data.length())
	var travelled := 0.0
	for i in range(1, data.centerline.size()):
		var a: Vector3 = data.centerline[i - 1]
		var b: Vector3 = data.centerline[i]
		var step := a.distance_to(b)
		if travelled + step >= target:
			var t := (target - travelled) / maxf(step, 0.001)
			var forward := b - a
			forward.y = 0.0
			if forward.length_squared() < 0.0001:
				forward = data.along_tee()
			forward = forward.normalized()
			return {
				"position": a.lerp(b, t),
				"yaw": rad_to_deg(atan2(-forward.x, -forward.z)),
			}
		travelled += step
	return {"position": data.cup, "yaw": rad_to_deg(atan2(-data.along_cup().x, -data.along_cup().z))}


static func _straight(
	headings: Array[float],
	lengths: Array[float],
	arcs: Array[bool],
	locks: Array[bool],
	heading: float,
	metres: float,
	lock := false
) -> float:
	headings.append(heading)
	lengths.append(metres)
	arcs.append(false)
	locks.append(lock)
	return heading


static func _arc(
	headings: Array[float],
	lengths: Array[float],
	arcs: Array[bool],
	locks: Array[bool],
	heading: float,
	degrees: float,
	radius: float
) -> float:
	var steps := maxi(1, int(round(absf(degrees) / ARC_STEP)))
	var step_deg := degrees / float(steps)
	var step_len := absf(deg_to_rad(step_deg)) * radius
	for _i in steps:
		heading += step_deg
		headings.append(heading)
		lengths.append(step_len)
		arcs.append(true)
		locks.append(false)
	return heading


# #region agent log
static func _dbg_shape(data: HoleData) -> void:
	var inverted := 0
	var min_room := 999.0
	var min_r := 999.0
	for i in range(1, data.centerline.size() - 1):
		var a: Vector3 = data.centerline[i - 1]
		var b: Vector3 = data.centerline[i]
		var c: Vector3 = data.centerline[i + 1]
		var d0 := b - a
		var d1 := c - b
		d0.y = 0.0
		d1.y = 0.0
		var l0 := d0.length()
		var l1 := d1.length()
		if l0 < 0.05 or l1 < 0.05:
			continue
		var turn := absf(d0.normalized().angle_to(d1.normalized()))
		var radius := 999.0 if turn < 0.02 else ((l0 + l1) * 0.5) / turn
		min_r = minf(min_r, radius)
		var room := radius - WIDTH * 0.5
		min_room = minf(min_room, room)
		if room < 0.0:
			inverted += 1
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in data.centerline:
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.z)
	var size := hi - lo
	var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-8cf7b5.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-8cf7b5.log", FileAccess.WRITE)
	else:
		f.seek_end()
	if f != null:
		f.store_line(JSON.stringify({
			"sessionId": "8cf7b5",
			"runId": "post-fix",
			"hypothesisId": "A",
			"location": "race_hole.gd:layout",
			"message": "track shape",
			"data": {
				"width": WIDTH,
				"turn_r": TURN_R,
				"infield_gap": snappedf(infield_gap(), 0.01),
				"min_radius": snappedf(min_r, 0.01),
				"min_room": snappedf(min_room, 0.01),
				"inverted": inverted,
				"corners": turn_angles().size(),
				"bounds": [snappedf(size.x, 0.1), snappedf(size.y, 0.1)],
			},
			"timestamp": Time.get_ticks_msec(),
		}))
		f.close()
# #endregion


## Stretch only the open longs so the U-turns stay the same size.
static func _scale(lengths: Array[float], arcs: Array[bool], locks: Array[bool]) -> void:
	var fixed := 0.0
	var stretch := 0.0
	for i in lengths.size():
		if arcs[i] or locks[i]:
			fixed += lengths[i]
		else:
			stretch += lengths[i]
	var remain := LENGTH - fixed
	if stretch <= 0.0 or remain <= 0.0:
		if fixed + stretch <= 0.0:
			return
		var all := LENGTH / (fixed + stretch)
		for i in lengths.size():
			lengths[i] *= all
		return
	var factor := remain / stretch
	for i in lengths.size():
		if not arcs[i] and not locks[i]:
			lengths[i] *= factor
