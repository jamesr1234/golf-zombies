class_name MountainHole
extends Object
## Hole 3: a fairway strip that falls away on both sides. Climb the face,
## then jump the cart to the green. There is no walk-around and no drive-on.

const RISE := 4.5
const TOP := 34.0
const WALL_ALONG := 12.0
const GAP := 22.0
const DROP := 28.0
const LIP := 1.2
const RAMP_LENGTH := 26.0
const RAMP_ANGLE := 22.0


static func applies(data: HoleData) -> bool:
	return data != null and data.custom == null and data.index == 2


static func layout(data: HoleData, _headings: Array[float], width: float) -> void:
	var t := _peak_t(data)
	var at := HoleGenerator.point_along(data, t)
	var forward := _along(data, t)
	var right := forward.cross(Vector3.UP).normalized()
	var yaw := rad_to_deg(atan2(-forward.x, -forward.z))
	data.mountain = at
	data.cart_pad = at - forward * (TOP * 0.2) + right * 4.2
	data.cart_yaw = yaw
	var water_along := GAP * 0.72
	var water_at := HoleGenerator.point_along(
		data, clampf((WALL_ALONG + TOP + GAP * 0.45) / maxf(data.length(), 80.0), 0.2, 0.9)
	)
	data.patches.append({
		"type": Surface.Type.WATER,
		"position": water_at,
		"size": Vector2(width, water_along),
		"yaw": yaw,
		"round": false,
	})
	var run := JumpRamp.ground_run(RAMP_LENGTH, RAMP_ANGLE)
	data.jumps.append({
		"position": water_at - forward * (water_along * 0.5 + run * 0.5),
		"yaw": yaw,
		"width": JumpRamp.WIDTH,
		"length": RAMP_LENGTH,
		"angle_deg": RAMP_ANGLE,
		"role": "takeoff",
	})
	var toward := -forward
	data.props.append({
		"kind": "climb_wall",
		"position": HoleGenerator.point_along(data, _wall_t(data)),
		"size": Vector3(width, RISE, 0.7),
		"yaw": rad_to_deg(atan2(-toward.x, -toward.z)),
	})


static func raise(field: HeightField, data: HoleData) -> void:
	if not applies(data) or not data.has_mountain():
		return
	var peak := field.height_at(data.tee.x, data.tee.z) + RISE
	var half := _strip_half(data)
	var span := data.length()
	for z in field.depth:
		for x in field.width:
			var wx := field.origin.x + float(x) * field.cell
			var wz := field.origin.y + float(z) * field.cell
			var point := Vector3(wx, 0.0, wz)
			var along := HeightField.along_t(data, point) * span
			if along < WALL_ALONG + 1.2 or along > WALL_ALONG + TOP:
				continue
			if HoleGenerator.distance_to_centerline(data, point) > half:
				continue
			field.samples[z * field.width + x] = peak


## After the rest of the hole is paved, drop everything that is not the strip.
static func clip(field: HeightField, data: HoleData) -> void:
	if not applies(data):
		return
	var floor := field.height_at(data.tee.x, data.tee.z) - DROP
	var half := _strip_half(data) + LIP
	for z in field.depth:
		for x in field.width:
			var wx := field.origin.x + float(x) * field.cell
			var wz := field.origin.y + float(z) * field.cell
			if keeps(data, Vector3(wx, 0.0, wz), half):
				continue
			field.samples[z * field.width + x] = floor


static func keeps(data: HoleData, point: Vector3, half := -1.0) -> bool:
	var lip := half if half >= 0.0 else _strip_half(data) + LIP
	if ClubhouseBuild.covers_exit_ground(data.practice_tee, data.cup - data.tee, point, 6.0):
		return true
	if point.distance_to(data.practice_center()) < PracticeGreen.FLAT + 2.0:
		return true
	if point.distance_to(data.tee) < 11.0:
		return true
	if point.distance_to(data.cup) < data.green_radius + HoleGenerator.FRINGE_WIDTH + 2.0:
		return true
	if HoleGenerator.distance_to_centerline(data, point) > lip:
		return false
	return HeightField.along_t(data, point) <= 1.04


static func covers(data: HoleData, spot: Vector3, extra := 4.0) -> bool:
	if not applies(data) or not data.has_mountain():
		return false
	var along := HeightField.along_t(data, spot) * data.length()
	if along < WALL_ALONG - extra or along > WALL_ALONG + TOP + extra:
		return false
	return HoleGenerator.distance_to_centerline(data, spot) < _strip_half(data) + extra


static func _strip_half(data: HoleData) -> float:
	return HoleGenerator.fairway_width(data.par, data.index) * 0.5


static func _wall_t(data: HoleData) -> float:
	return WALL_ALONG / maxf(data.length(), 80.0)


static func _peak_t(data: HoleData) -> float:
	return (WALL_ALONG + TOP * 0.5) / maxf(data.length(), 80.0)


static func _along(data: HoleData, t: float) -> Vector3:
	var here := HoleGenerator.point_along(data, t)
	var ahead := HoleGenerator.point_along(data, minf(1.0, t + 0.06))
	var step := ahead - here
	step.y = 0.0
	if step.length_squared() < 0.0001:
		step = data.cup - data.tee
		step.y = 0.0
	return step.normalized()
