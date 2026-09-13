class_name ChipScale
extends Object
## Distance-to-cup remaps a stuffed swing so a collar chip dies just short of
## the hole. Lives in its own script so a stale Shot class_name cache cannot
## hide the extra argument from the ball and the controller.

## Same collar as HoleGenerator.FRINGE_WIDTH: just outside the putting surface.
const COLLAR_FRINGE := 3.0
## A stuffed chip from the collar lands this far short so it can roll in.
const CHIP_SHORT := 1.0
## Extra near-hole carry at LOFT_BIAS_MAX. High shots check up, so they go a bit
## further. Punches get none.
const CHIP_LOFT_EXTRA := 0.12


## Horizontal distance from the cup to just outside the putting collar.
static func putting_collar(green_span := 0.0) -> float:
	var span := green_span if green_span > 0.0 else Shot.default_green_span()
	return span * 0.5 + COLLAR_FRINGE


## Power-1.0 carry in metres once distance-to-cup has remapped the swing.
static func chip_max_carry(
	hole_dist: float, loft_bias := 0.0, kit: ClubKit = null, green_span := 0.0
) -> float:
	var clubs := kit if kit != null else ClubKit.starter()
	var full := _full_play_carry(loft_bias, clubs)
	if hole_dist <= 0.0:
		return full
	var collar := putting_collar(green_span)
	var far := maxf(collar + 1.0, clubs.scaled_carry())
	var t := clampf((hole_dist - collar) / (far - collar), 0.0, 1.0)
	var loft_t := clampf(loft_bias / Shot.LOFT_BIAS_MAX, 0.0, 1.0)
	var near := maxf(hole_dist - CHIP_SHORT, 0.5) * (1.0 + CHIP_LOFT_EXTRA * loft_t)
	return lerpf(near, full, t)


## Speed multiplier so a stuffed meter carries `chip_max_carry`. `hole_dist` of 0
## leaves the swing alone so old callers still get a full drive.
static func chip_speed_scale(
	hole_dist: float, loft_bias := 0.0, kit: ClubKit = null, green_span := 0.0
) -> float:
	if hole_dist <= 0.0:
		return 1.0
	var full := _full_play_carry(loft_bias, kit)
	if full <= 0.001:
		return 1.0
	return sqrt(minf(1.0, chip_max_carry(hole_dist, loft_bias, kit, green_span) / full))


static func scale_launch(
	launch: Vector3, hole_dist: float, loft_bias := 0.0, kit: ClubKit = null, green_span := 0.0
) -> Vector3:
	return launch * chip_speed_scale(hole_dist, loft_bias, kit, green_span)


## Vacuum carry scales with speed squared, so the preview path is a uniform
## scale of the unscaled flight from the origin.
static func scale_flight(
	points: PackedVector3Array, hole_dist: float, loft_bias := 0.0,
	kit: ClubKit = null, green_span := 0.0
) -> PackedVector3Array:
	var speed := chip_speed_scale(hole_dist, loft_bias, kit, green_span)
	if points.is_empty() or speed >= 0.999:
		return points
	var origin: Vector3 = points[0]
	var dist_scale := speed * speed
	var scaled := PackedVector3Array()
	scaled.resize(points.size())
	for i in points.size():
		scaled[i] = origin + (points[i] - origin) * dist_scale
	return scaled


static func _full_play_carry(loft_bias: float, kit: ClubKit = null) -> float:
	var clubs := kit if kit != null else ClubKit.starter()
	var scale := clubs.speed_scale
	return Shot.carry_to_height(0.0, 1.0, loft_bias) * scale * scale
