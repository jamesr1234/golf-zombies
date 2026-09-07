class_name SpawnPack
extends Object
## One authored zombie pack on a custom hole: a point, a yard they stay in, and
## how many of each walker to plant there.

const KEYS: PackedStringArray = ["walker", "runner", "brute", "gunner"]
const LABELS: PackedStringArray = ["Walker", "Runner", "Brute", "Gunner"]
const STATS: PackedStringArray = [
	"res://resources/zombies/walker.tres",
	"res://resources/zombies/runner.tres",
	"res://resources/zombies/brute.tres",
	"res://resources/zombies/gunner.tres",
]
const MAX_EACH := 12
const RADIUS_MIN := 2.7
const RADIUS_MAX := 32.4
const DEFAULT_RADIUS := 10.8
const AGGRO_MIN := 2.7
const AGGRO_MAX := 54.0
const DEFAULT_AGGRO := 16.2
## Tall enough that a pack planted from a high camera still leashes on the grass.
const ROAM_HEIGHT := 24.0
const PATH := "path"
const POSITION := "position"
const RADIUS := "radius"
const AGGRO := "aggro"
const COUNTS := "counts"
const SPAWN := "spawn"


static func empty_counts() -> Dictionary:
	var out := {}
	for key in KEYS:
		out[key] = 0
	return out


static func clamp_counts(raw: Dictionary) -> Dictionary:
	var out := empty_counts()
	for key in KEYS:
		out[key] = clampi(int(raw.get(key, 0)), 0, MAX_EACH)
	return out


static func total(counts: Dictionary) -> int:
	var n := 0
	for key in KEYS:
		n += int(counts.get(key, 0))
	return n


static func clamp_radius(value: float) -> float:
	return clampf(value, RADIUS_MIN, RADIUS_MAX)


static func clamp_aggro(value: float) -> float:
	return clampf(value, AGGRO_MIN, AGGRO_MAX)


static func roam_at(center: Vector3, radius: float) -> AABB:
	var r := clamp_radius(radius)
	return AABB(
		Vector3(center.x - r, center.y - ROAM_HEIGHT * 0.5, center.z - r),
		Vector3(r * 2.0, ROAM_HEIGHT, r * 2.0)
	)


static func from_hole(custom, height = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if custom == null:
		return out
	for entry in custom.placements:
		if String(entry.get(PATH, "")) != SPAWN:
			continue
		var at: Vector3 = entry[POSITION]
		if height != null:
			at = Vector3(at.x, height.height_at(at.x, at.z), at.z)
		else:
			at = Vector3(at.x, 0.0, at.z)
		var radius := clamp_radius(float(entry.get(RADIUS, DEFAULT_RADIUS)))
		out.append({
			"position": at,
			"radius": radius,
			"aggro": clamp_aggro(float(entry.get(AGGRO, DEFAULT_AGGRO))),
			"roam": roam_at(at, radius),
			"counts": clamp_counts(entry.get(COUNTS, {})),
		})
	return out


static func stats_for(key: String) -> ZombieStats:
	var i := KEYS.find(key)
	if i < 0:
		return null
	return load(STATS[i]) as ZombieStats
