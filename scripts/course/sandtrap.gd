class_name SandTrap
extends Object
## A round bunker on a custom hole. Size is a free circle, not a tile fill, then
## a second pass sets how deep the bowl sits under the turf.

const RADIUS := "radius"
const DEPTH := "depth"
const RADIUS_MIN := 2.0
const RADIUS_MAX := 16.0
const DEFAULT_RADIUS := 5.4
const DEPTH_MIN := 0.3
const DEPTH_MAX := 2.4
const DEFAULT_DEPTH := 0.9
## Soft lip outside the painted sand so the bowl does not end in a cliff.
const BANK := 0.8


static func clamp_radius(value: float) -> float:
	return clampf(value, RADIUS_MIN, RADIUS_MAX)


static func clamp_depth(value: float) -> float:
	return clampf(value, DEPTH_MIN, DEPTH_MAX)


static func radius_of(entry: Dictionary) -> float:
	return clamp_radius(float(entry.get(RADIUS, DEFAULT_RADIUS)))


static func depth_of(entry: Dictionary) -> float:
	return clamp_depth(float(entry.get(DEPTH, DEFAULT_DEPTH)))


static func covers(entry: Dictionary, point: Vector3) -> bool:
	if String(entry.get("path", "")) != "sandtrap":
		return false
	var at: Vector3 = entry["position"]
	return Vector2(point.x - at.x, point.z - at.z).length() <= radius_of(entry) + 0.04


static func patch_from(entry: Dictionary) -> Dictionary:
	var radius := radius_of(entry)
	var patch := HoleGenerator.surface_patch(
		Surface.Type.BUNKER,
		entry["position"],
		Vector2(radius * 2.0, radius * 2.0),
		0.0,
		true
	)
	patch[DEPTH] = depth_of(entry)
	return patch


static func cuts_from(data) -> Array:
	var out: Array = []
	for patch in data.patches:
		if patch["type"] != Surface.Type.BUNKER:
			continue
		if float(patch.get(DEPTH, 0.0)) <= 0.001:
			continue
		var size: Vector2 = patch["size"]
		out.append({"position": patch["position"], RADIUS: size.x * 0.5})
	return out


## Bowls the heightmap under every bunker that was given a depth, so the sand
## sits in a hollow instead of being painted on flat grass.
static func sink(field, data) -> void:
	var bowls: Array[Dictionary] = []
	for patch in data.patches:
		if patch["type"] != Surface.Type.BUNKER:
			continue
		if float(patch.get(DEPTH, 0.0)) <= 0.001:
			continue
		bowls.append(patch)
	if bowls.is_empty() or field.width < 2 or field.depth < 2:
		return
	for z in field.depth:
		for x in field.width:
			var at: int = z * field.width + x
			var point := Vector3(
				field.origin.x + float(x) * field.cell,
				0.0,
				field.origin.y + float(z) * field.cell
			)
			field.samples[at] = _bowl_height(bowls, point, field.samples[at])


static func _bowl_height(bowls: Array[Dictionary], point: Vector3, dry: float) -> float:
	var h := dry
	for patch in bowls:
		var edge := HeightField._edge_distance(point, patch)
		if edge < -BANK:
			continue
		var depth := float(patch.get(DEPTH, DEFAULT_DEPTH))
		var bank := clampf((edge + BANK) / BANK, 0.0, 1.0)
		var sink := depth * smoothstep(0.0, _blend(patch), maxf(edge, 0.0))
		h = minf(h, lerpf(dry, dry - sink, smoothstep(0.0, 1.0, bank)))
	return h


static func _blend(patch: Dictionary) -> float:
	var size: Vector2 = patch["size"]
	return clampf(size.x * 0.28, 1.0, 2.6)
