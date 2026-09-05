class_name CulvertHole
extends Object
## Hole 2: a ridge blocks the drive. The only way through is a culvert under
## the hill. Drive down, through the pipe, and back up to the green.

const RISE := 12.0
const DEPTH := 7.0
const APPROACH := 22.0
const RAMP := 18.0
const PIPE := 32.0
const WIDTH := 8.0
const HEIGHT := 7.0
const DROP := 28.0
const LIP := 1.2
const FACE := 3.0


static func applies(data: HoleData) -> bool:
	return data != null and data.custom == null and data.index == 1


static func layout(data: HoleData, _headings: Array[float], _width: float) -> void:
	var t := _pipe_t(data)
	var at := HoleGenerator.point_along(data, t)
	var forward := _along(data, t)
	var yaw := rad_to_deg(atan2(-forward.x, -forward.z))
	data.culvert = at
	data.props.append({
		"kind": "culvert",
		"position": at,
		"size": Vector3(WIDTH, HEIGHT, PIPE),
		"yaw": yaw,
	})


static func raise(field: HeightField, data: HoleData) -> void:
	if not applies(data) or not data.has_culvert():
		return
	var tee_h := field.height_at(data.tee.x, data.tee.z)
	var peak := tee_h + RISE
	var half := _strip_half(data)
	var span := data.length()
	var start := APPROACH
	var end := _ridge_end()
	for z in field.depth:
		for x in field.width:
			var wx := field.origin.x + float(x) * field.cell
			var wz := field.origin.y + float(z) * field.cell
			var point := Vector3(wx, 0.0, wz)
			var along := HeightField.along_t(data, point) * span
			if along < start or along > end:
				continue
			if HoleGenerator.distance_to_centerline(data, point) > half:
				continue
			var face := 1.0
			if along < start + FACE:
				face = (along - start) / FACE
			elif along > end - FACE:
				face = (end - along) / FACE
			var at := z * field.width + x
			field.samples[at] = lerpf(field.samples[at], peak, clampf(face, 0.0, 1.0))


## Road through the ridge: down a cart-grade ramp, flat pipe floor, back up.
static func cut(field: HeightField, data: HoleData) -> void:
	if not applies(data) or not data.has_culvert():
		return
	var tee_h := field.height_at(data.tee.x, data.tee.z)
	var floor := tee_h - DEPTH
	var trench_half := WIDTH * 0.5 + 0.8
	var half := _strip_half(data)
	var span := data.length()
	var drop_start := APPROACH
	var pipe_start := APPROACH + RAMP
	var pipe_end := pipe_start + PIPE
	var rise_end := pipe_end + RAMP
	for z in field.depth:
		for x in field.width:
			var wx := field.origin.x + float(x) * field.cell
			var wz := field.origin.y + float(z) * field.cell
			var point := Vector3(wx, 0.0, wz)
			var along := HeightField.along_t(data, point) * span
			var off := HoleGenerator.distance_to_centerline(data, point)
			var at := z * field.width + x
			if along > rise_end - 1.0 and (off <= half or point.distance_to(data.cup) < data.green_radius + HoleGenerator.FRINGE_WIDTH + 2.0):
				field.samples[at] = tee_h
				continue
			if off > trench_half:
				continue
			if along >= pipe_start and along <= pipe_end:
				field.samples[at] = floor
			elif along >= drop_start and along < pipe_start:
				field.samples[at] = lerpf(tee_h, floor, (along - drop_start) / RAMP)
			elif along > pipe_end and along <= rise_end:
				field.samples[at] = lerpf(floor, tee_h, (along - pipe_end) / RAMP)


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
	if not applies(data) or not data.has_culvert():
		return false
	var along := HeightField.along_t(data, spot) * data.length()
	if along < APPROACH - extra or along > _ridge_end() + extra:
		return false
	return HoleGenerator.distance_to_centerline(data, spot) < _strip_half(data) + extra


static func ridge_peak_at(data: HoleData) -> Vector3:
	var t := _pipe_t(data)
	var at := HoleGenerator.point_along(data, t)
	return at + _along(data, t).cross(Vector3.UP).normalized() * (WIDTH * 0.5 + 3.0)


static func _ridge_end() -> float:
	return APPROACH + RAMP + PIPE + RAMP


static func _strip_half(data: HoleData) -> float:
	return HoleGenerator.fairway_width(data.par, data.index) * 0.5


static func _pipe_t(data: HoleData) -> float:
	return (APPROACH + RAMP + PIPE * 0.5) / maxf(data.length(), 80.0)


static func _along(data: HoleData, t: float) -> Vector3:
	var here := HoleGenerator.point_along(data, t)
	var ahead := HoleGenerator.point_along(data, minf(1.0, t + 0.06))
	var step := ahead - here
	step.y = 0.0
	if step.length_squared() < 0.0001:
		step = data.cup - data.tee
		step.y = 0.0
	return step.normalized()
