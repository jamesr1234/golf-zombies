class_name HoleGenerator
extends Object
## Deterministic hole layout. Par comes from a fixed nine-hole template and the
## length is then drawn from the band that matches that par, so par always
## agrees with how far the one club can actually hit the ball.

const PAR_TEMPLATE: PackedInt32Array = [4, 4, 4, 5, 4, 3, 4, 5, 4]
const BOUNDS_MARGIN := 58.0
const PROP_KINDS: PackedStringArray = ["tree", "rock", "wall"]
const _SniperTower := preload("res://scripts/course/sniper_tower.gd")
const _Trees := preload("res://scripts/course/course_trees.gd")
const _Overlay := preload("res://scripts/course/hole_overlay.gd")
## Six body-heights at the narrowest, so a pond is somewhere you swim rather than
## a puddle you step over.
const WATER_MIN_SPAN := 1.8 * 6.0
## Collar around the green you can still putt from.
const FRINGE_WIDTH := 3.0
const GREEN_RADIUS_MIN := 8.0
const GREEN_RADIUS_MAX := 11.0


static func _setpiece(data: HoleData) -> bool:
	return MountainHole.applies(data) or CulvertHole.applies(data)


static func pars() -> PackedInt32Array:
	return PAR_TEMPLATE.duplicate()


static func par_for_length(length: float) -> int:
	var carry := Shot.max_carry()
	if length <= carry * 1.02:
		return 3
	if length <= carry * 2.0:
		return 4
	return 5


static func length_range(par: int) -> Vector2:
	var carry := Shot.max_carry()
	match par:
		3:
			return Vector2(carry * 0.45, carry * 0.98)
		4:
			return Vector2(carry * 1.15, carry * 1.9)
		_:
			return Vector2(carry * 2.1, carry * 2.75)


static func fairway_width(par: int) -> float:
	return 26.0 if par == 3 else (23.0 if par == 4 else 21.0)


static func generate(index: int, base_seed: int) -> HoleData:
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed + index * 7919

	var data := HoleData.new()
	data.index = index
	data.par = PAR_TEMPLATE[index % PAR_TEMPLATE.size()]
	var width := fairway_width(data.par)
	var band := length_range(data.par)
	var segment_count := 1 if data.par == 3 or CulvertHole.applies(data) else (2 if data.par == 4 else 3)
	var headings := _headings(segment_count, rng)
	var lengths := _split(rng.randf_range(band.x, band.y), segment_count, rng)

	var point := Vector3.ZERO
	data.centerline.append(point)
	for i in segment_count:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(headings[i]))
		var next := point + direction * lengths[i]
		data.centerline.append(next)
		data.patches.append(_patch(
			Surface.Type.FAIRWAY, point.lerp(next, 0.5),
			Vector2(width, lengths[i] + 4.0), headings[i]
		))
		point = next

	data.tee = data.centerline[0]
	data.cup = data.centerline[data.centerline.size() - 1]
	data.green_radius = rng.randf_range(GREEN_RADIUS_MIN, GREEN_RADIUS_MAX)
	data.patches.append(_patch(Surface.Type.TEE, data.tee, Vector2(8.0, 10.0), headings[0]))
	var fringe_radius := data.green_radius + FRINGE_WIDTH
	data.patches.append(_patch(
		Surface.Type.FRINGE, data.cup,
		Vector2(fringe_radius * 2.0, fringe_radius * 2.0), 0.0, true
	))
	data.patches.append(_patch(
		Surface.Type.GREEN, data.cup,
		Vector2(data.green_radius * 2.0, data.green_radius * 2.0), 0.0, true
	))
	_add_practice_green(data, headings[0])
	_add_climb_wall(data, headings[0])
	if MountainHole.applies(data):
		MountainHole.layout(data, headings, width)
	elif CulvertHole.applies(data):
		CulvertHole.layout(data, headings, width)
	else:
		_add_hazards(data, rng, width, headings)
	data.bounds = _bounds(data)
	_Overlay.harvest(data)
	if not _setpiece(data):
		_add_towers(data, width)
		_add_props(data, rng, width)
		_Trees.plant(data, rng, width, func(spot): return blocks_prop(data, spot, width))
	_add_spawn_points(data, rng, width)
	data.height = HeightField.generate(data, rng)
	_lift(data)
	return data


## Everything was planned on a flat plane. Once the heightmap exists, the tee,
## cup, patches and props all sit on it so nothing floats or buries itself.
static func _lift(data: HoleData) -> void:
	data.tee = data.height.lift(data.tee)
	data.cup = data.height.lift(data.cup)
	for i in data.centerline.size():
		data.centerline[i] = data.height.lift(data.centerline[i])
	for patch in data.patches:
		var position: Vector3 = patch["position"]
		patch["position"] = data.height.lift(position)
	for prop in data.props:
		var position: Vector3 = prop["position"]
		if String(prop.get("kind", "")) == "climb_wall":
			var yaw := deg_to_rad(float(prop.get("yaw", 0.0)))
			var face := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var foot := position + face * 2.0
			prop["position"] = Vector3(
				position.x, data.height.height_at(foot.x, foot.z), position.z
			)
		else:
			prop["position"] = data.height.lift(position)
	for jump in data.jumps:
		var origin: Vector3 = jump["position"]
		var rear := JumpRamp.rear_of(jump)
		jump["position"] = Vector3(
			origin.x, data.height.height_at(rear.x, rear.z), origin.z
		)
	for i in data.spawn_points.size():
		data.spawn_points[i] = data.height.lift(data.spawn_points[i])
	data.practice_tee = data.height.lift(data.practice_tee)
	data.practice_cup = data.height.lift(data.practice_cup)
	if data.has_mountain():
		data.mountain = data.height.lift(data.mountain)
	if data.has_culvert():
		data.culvert = data.height.lift(data.culvert)
	if data.has_cart_pad():
		data.cart_pad = data.height.lift(data.cart_pad)
	if data.has_mech_pad():
		data.mech_pad = data.height.lift(data.mech_pad)


## Every hole opens with somewhere to warm up. It shares the flat shelf the tee
## already gets, so a practice putt rolls true.
static func _add_practice_green(data: HoleData, heading: float) -> void:
	var center := PracticeGreen.center(data.tee, heading)
	var ends := PracticeGreen.putt_ends(center, heading)
	data.practice_tee = ends[0]
	data.practice_cup = ends[1]
	var fringe := Vector2(
		PracticeGreen.WIDTH + FRINGE_WIDTH * 2.0,
		PracticeGreen.LENGTH + FRINGE_WIDTH * 2.0
	)
	data.patches.append(_patch(Surface.Type.FRINGE, center, fringe, heading))
	data.patches[-1]["practice"] = true
	data.patches.append(_patch(
		Surface.Type.GREEN, center,
		Vector2(PracticeGreen.WIDTH, PracticeGreen.LENGTH), heading
	))
	data.patches[-1]["practice"] = true


## Hole 1 only: a climb wall beside the practice tee, before you start the hole.
static func _add_climb_wall(data: HoleData, heading: float) -> void:
	if data.index != 0:
		return
	data.props.append(ClimbingWall.at_practice(data.practice_tee, heading))


static func _headings(count: int, rng: RandomNumberGenerator) -> Array[float]:
	var headings: Array[float] = [0.0]
	for i in range(1, count):
		var turn := rng.randf_range(10.0, 30.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		headings.append(headings[i - 1] + turn)
	return headings


static func _split(total: float, count: int, rng: RandomNumberGenerator) -> Array[float]:
	var parts: Array[float] = []
	var remaining := total
	for i in range(count - 1):
		var share: float = total / float(count) * rng.randf_range(0.85, 1.15)
		parts.append(share)
		remaining -= share
	parts.append(remaining)
	return parts


static func _add_hazards(
	data: HoleData, rng: RandomNumberGenerator, width: float, headings: Array[float]
) -> void:
	for _i in rng.randi_range(1, 3):
		var angle := rng.randf_range(0.0, TAU)
		var distance: float = data.green_radius + rng.randf_range(3.0, 8.0)
		var radius := rng.randf_range(3.0, 5.5)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * distance
		data.patches.append(_patch(
			Surface.Type.BUNKER, data.cup + offset,
			Vector2(radius * 2.0, radius * 2.0), 0.0, true
		))

	var last := data.centerline.size() - 1
	if data.par > 3 and rng.randf() < 0.75:
		var radius := rng.randf_range(4.0, 6.5)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var along: Vector3 = data.centerline[last - 1].lerp(data.centerline[last], rng.randf_range(0.2, 0.6))
		var lateral := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(headings[last - 1]))
		data.patches.append(_patch(
			Surface.Type.BUNKER, along + lateral * side * (width * 0.5 + radius * 0.6),
			Vector2(radius * 2.0, radius * 2.0), 0.0, true
		))

	# Hole 1 stays dry so the opener is a fairway, not a swim. Later par-4/5s
	# still roll a pond; hole 3 keeps its mountain gap.
	if data.index != 0 and data.par > 3 and rng.randf() < 0.45:
		var t := rng.randf_range(0.35, 0.7)
		var along := rng.randf_range(WATER_MIN_SPAN * 1.6, WATER_MIN_SPAN * 2.2)
		_add_water(data, width, headings, t, along)


static func _add_water(
	data: HoleData, width: float, headings: Array[float], t: float, along: float
) -> Dictionary:
	var last := data.centerline.size() - 1
	var center: Vector3 = data.centerline[last - 1].lerp(data.centerline[last], t)
	# Long enough across the hole to be a carry, and wide enough along it to
	# swim out to the middle and dive without touching both banks.
	var patch := _patch(
		Surface.Type.WATER, center,
		Vector2(maxf(width + 44.0, WATER_MIN_SPAN), along), headings[last - 1]
	)
	data.patches.append(patch)
	return patch


static func _add_props(data: HoleData, rng: RandomNumberGenerator, width: float) -> void:
	var target := 18 + data.index * 3
	var placed := 0
	var attempts := 0
	while placed < target and attempts < target * 12:
		attempts += 1
		var spot := Vector3(
			rng.randf_range(data.bounds.position.x, data.bounds.end.x), 0.0,
			rng.randf_range(data.bounds.position.y, data.bounds.end.y)
		)
		if blocks_prop(data, spot, width):
			continue
		# Parkland first: rocks and walls still scatter, but most of the rough is trees.
		var kind := "tree" if rng.randf() < 0.7 else PROP_KINDS[rng.randi() % PROP_KINDS.size()]
		var size := Vector3.ONE
		match kind:
			"tree":
				size = Vector3(rng.randf_range(0.5, 0.9), rng.randf_range(5.0, 9.0), 0.0)
			"rock":
				size = Vector3(rng.randf_range(1.2, 2.6), rng.randf_range(0.8, 1.8), rng.randf_range(1.2, 2.6))
			_:
				size = Vector3(rng.randf_range(4.0, 9.0), rng.randf_range(1.6, 3.4), 0.6)
		data.props.append({
			"kind": kind,
			"position": spot,
			"size": size,
			"yaw": rng.randf_range(0.0, 360.0),
		})
		placed += 1


## Most zombies walk in down the landing strip, not out of the trees. A few
## still come from the rough so a packed fairway is not the only threat.
static func _add_spawn_points(data: HoleData, rng: RandomNumberGenerator, width: float) -> void:
	var steps := 10
	var half := width * 0.5
	for i in steps:
		var t := lerpf(0.28, 0.8, float(i) / float(steps - 1))
		var center := _point_along(data, t)
		if center.distance_to(data.cup) < data.green_radius + 4.0:
			continue
		var lateral := _lateral_at(data, t)
		for _i in 2:
			var offset := rng.randf_range(-half * 0.72, half * 0.72)
			_try_spawn_point(data, center + lateral * offset)
		if i % 3 != 0 or _setpiece(data):
			continue
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		_try_spawn_point(data, center + lateral * side * (half + rng.randf_range(10.0, 18.0)))


static func _patch(
	type: Surface.Type, position: Vector3, size: Vector2, yaw: float, round_shape := false
) -> Dictionary:
	return {
		"type": type,
		"position": position,
		"size": size,
		"yaw": yaw,
		"round": round_shape,
	}


static func _bounds(data: HoleData) -> Rect2:
	var rect := Rect2(Vector2(data.tee.x, data.tee.z), Vector2.ZERO)
	for point in data.centerline:
		rect = rect.expand(Vector2(point.x, point.z))
	for patch in data.patches:
		var position: Vector3 = patch["position"]
		var extent: Vector2 = patch["size"]
		var reach: float = maxf(extent.x, extent.y) * 0.5
		rect = rect.expand(Vector2(position.x - reach, position.z - reach))
		rect = rect.expand(Vector2(position.x + reach, position.z + reach))
	return rect.grow(BOUNDS_MARGIN)


static func _try_spawn_point(data: HoleData, spot: Vector3) -> void:
	if not data.bounds.has_point(Vector2(spot.x, spot.z)):
		return
	if MountainHole.applies(data) and not MountainHole.keeps(data, spot):
		return
	if CulvertHole.applies(data) and not CulvertHole.keeps(data, spot):
		return
	if spot.distance_to(data.cup) < data.green_radius + 2.0:
		return
	# Walkers arrive on dry land, not wading up out of a pond.
	if _in_a_pond(data, spot, HeightField.WATER_BANK + HeightField.CELL):
		return
	if _on_a_jump(data, spot):
		return
	data.spawn_points.append(spot)


static func _lateral_at(data: HoleData, t: float) -> Vector3:
	var here := _point_along(data, t)
	var ahead := _point_along(data, minf(1.0, t + 0.03))
	var forward := ahead - here
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = data.cup - data.tee
		forward.y = 0.0
	return forward.normalized().cross(Vector3.UP).normalized()


static func patch_covers(patch: Dictionary, point: Vector3) -> bool:
	return _patch_covers(patch, point)


## Fairway, greens, water, ramps and the tee stay clear so a tree never sits
## where you play, swim, or jump.
static func blocks_prop(data: HoleData, spot: Vector3, width: float) -> bool:
	if _distance_to_centerline(data, spot) < width * 0.5 + 5.0:
		return true
	if spot.distance_to(data.cup) < data.green_radius + 8.0:
		return true
	if spot.distance_to(data.tee) < 12.0:
		return true
	if spot.distance_to(data.practice_center()) < PracticeGreen.FLAT + 4.0:
		return true
	if ClubhouseBuild.covers_exit_ground(data.practice_tee, data.cup - data.tee, spot, 4.0):
		return true
	if _near_tower(data, spot):
		return true
	if _near_climb(data, spot):
		return true
	if MountainHole.covers(data, spot):
		return true
	if CulvertHole.covers(data, spot):
		return true
	if _Trees.in_exit_corridor(data, spot):
		return true
	return _in_a_pond(data, spot) or _on_a_jump(data, spot)


static func _near_climb(data: HoleData, spot: Vector3) -> bool:
	for prop in data.props:
		if String(prop.get("kind", "")) != "climb_wall":
			continue
		var size: Vector3 = prop.get("size", Vector3(ClimbingWall.WIDTH, 1.0, 1.0))
		if spot.distance_to(prop["position"]) < size.x * 0.5 + 5.0:
			return true
	return false


static func _near_tower(data: HoleData, spot: Vector3) -> bool:
	for prop in data.props:
		if String(prop["kind"]) != "tower":
			continue
		if spot.distance_to(prop["position"]) < 8.0:
			return true
	return false


static func _add_towers(data: HoleData, width: float) -> void:
	var placed := 0
	for plan in [[0.58, 1.0], [0.72, -1.0], [0.46, -1.0], [0.84, 1.0]]:
		if placed >= 2:
			return
		if _try_tower(data, width, float(plan[0]), float(plan[1])):
			placed += 1


static func _try_tower(data: HoleData, width: float, t: float, side: float) -> bool:
	var center := _point_along(data, t)
	var lateral := _lateral_at(data, t)
	var spot := center + lateral * side * (width * 0.5 + _SniperTower.SIDE_GAP)
	var far := minf(_SniperTower.MIN_TEE, data.length() * 0.5)
	if spot.distance_to(data.tee) < far:
		return false
	if spot.distance_to(data.cup) < data.green_radius + 10.0:
		return false
	if spot.distance_to(data.practice_center()) < PracticeGreen.FLAT + 8.0:
		return false
	if ClubhouseBuild.covers_exit_ground(data.practice_tee, data.cup - data.tee, spot, 8.0):
		return false
	if _in_a_pond(data, spot) or _on_a_jump(data, spot):
		return false
	if MountainHole.covers(data, spot, 8.0):
		return false
	if CulvertHole.covers(data, spot, 8.0):
		return false
	var to_tee := data.tee - spot
	to_tee.y = 0.0
	var yaw := 0.0
	if to_tee.length_squared() > 0.0001:
		yaw = rad_to_deg(atan2(-to_tee.x, -to_tee.z))
	data.props.append({
		"kind": "tower",
		"position": spot,
		"size": Vector3(_SniperTower.DECK, _SniperTower.HEIGHT, _SniperTower.DECK),
		"yaw": yaw,
	})
	return true


## Inside a water hazard, or on the levelled bank that runs around it.
static func _in_a_pond(data: HoleData, spot: Vector3, margin := HeightField.WATER_BANK) -> bool:
	for patch in data.patches:
		if patch["type"] != Surface.Type.WATER:
			continue
		var grown := patch.duplicate()
		var size: Vector2 = grown["size"]
		grown["size"] = size + Vector2(margin, margin) * 2.0
		if _patch_covers(grown, spot):
			return true
	return false


static func _on_a_jump(data: HoleData, spot: Vector3) -> bool:
	for jump in data.jumps:
		if JumpRamp.contains(jump, spot):
			return true
	return false


static func _patch_covers(patch: Dictionary, point: Vector3) -> bool:
	var origin: Vector3 = patch["position"]
	var size: Vector2 = patch["size"]
	var local := (point - origin).rotated(Vector3.UP, -deg_to_rad(patch["yaw"]))
	if patch["round"]:
		return Vector2(local.x, local.z).length() <= size.x * 0.5
	return absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.y * 0.5


static func _point_along(data: HoleData, t: float) -> Vector3:
	var total := data.length()
	if total <= 0.0:
		return data.tee
	var target := total * clampf(t, 0.0, 1.0)
	var travelled := 0.0
	for i in range(1, data.centerline.size()):
		var step: float = data.centerline[i - 1].distance_to(data.centerline[i])
		if travelled + step >= target:
			return data.centerline[i - 1].lerp(data.centerline[i], (target - travelled) / step)
		travelled += step
	return data.cup


static func point_along(data: HoleData, t: float) -> Vector3:
	return _point_along(data, t)


static func distance_to_centerline(data: HoleData, point: Vector3) -> float:
	return _distance_to_centerline(data, point)


static func _distance_to_centerline(data: HoleData, point: Vector3) -> float:
	var closest := INF
	for i in range(1, data.centerline.size()):
		var segment := Geometry3D.get_closest_point_to_segment(
			point, data.centerline[i - 1], data.centerline[i]
		)
		closest = minf(closest, point.distance_to(segment))
	return closest
