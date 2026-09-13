@tool
class_name PieceLadder
extends Object
## Obstacle sizes as odd multiples of the extra-small cube. Saved holes from
## the old 1/2/3/5/7 ladder are stretched here so neighbours stay flush.

const CELLS := {
	"extra_small": 1.0, "small": 3.0, "medium": 5.0, "large": 7.0, "extra_large": 9.0,
}
const LEGACY := {
	"extra_small": 1.0, "small": 2.0, "medium": 3.0, "large": 5.0, "extra_large": 7.0,
}


static func size_name(path: String) -> String:
	var stem := path.get_file().get_basename()
	var found := ""
	for size in CELLS:
		if stem != size and not stem.ends_with("_%s" % size):
			continue
		if size.length() > found.length():
			found = size
	return found


static func kind_of(path: String) -> String:
	return path.get_file().get_basename().get_slice("_", 0)


static func extent_cells(path: String, legacy: bool) -> Vector3:
	if kind_of(path) == "escalator":
		return Vector3(2.0, 5.0, 10.0) if legacy else Vector3(3.0, 7.0, 9.0)
	var key := size_name(path)
	var n := float((LEGACY if legacy else CELLS).get(key, 0.0))
	if n <= 0.0:
		return Vector3.ZERO
	match kind_of(path):
		"cube", "steps":
			return Vector3(n, n, n)
		"wall":
			return Vector3(n, n, 1.0)
		"platform":
			return Vector3(n, 1.0, n)
		"pillar", "ladder":
			return Vector3(1.0, n, 1.0)
		"ramp":
			return Vector3(n, n * 0.5, n)
		"tunnel":
			return Vector3(n, n + 2.0, n + 2.0)
		"arch":
			return Vector3(n + 2.0, n + 1.0, 1.0)
		_:
			return Vector3.ZERO


static func faced(extent: Vector3, yaw: float) -> Vector3:
	var angle := fposmod(absf(yaw), 180.0)
	if angle > 45.0 and angle < 135.0:
		return Vector3(extent.z, extent.y, extent.x)
	return extent


## Stretch centre-snapped placements so a flush pair stays flush after growth.
static func remap_centers(placements: Array) -> void:
	var items: Array = []
	for entry in placements:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var path := String(entry.get(CustomHole.PATH, ""))
		var yaw := float(entry.get(CustomHole.YAW, 0.0))
		var old_e := faced(extent_cells(path, true), yaw) * GridSnap.CELL
		var new_e := faced(extent_cells(path, false), yaw) * GridSnap.CELL
		items.append({
			"entry": entry,
			"at": entry[CustomHole.POSITION] as Vector3,
			"old": old_e,
			"new": new_e,
		})
		if CustomHole.has_end(entry):
			items.append({
				"entry": entry,
				"at": CustomHole.end_of(entry),
				"old": old_e,
				"new": new_e,
				"end": true,
			})
	_sweep_centers(items, 0)
	_sweep_centers(items, 2)
	_sweep_bottoms(items)
	for item in items:
		var at: Vector3 = item["at"]
		at.x = snappedf(at.x, GridSnap.CELL)
		at.y = snappedf(at.y, GridSnap.CELL * 0.5)
		at.z = snappedf(at.z, GridSnap.CELL)
		var entry: Dictionary = item["entry"]
		if item.get("end", false):
			entry[CustomHole.END] = at
		else:
			entry[CustomHole.POSITION] = at


static func _sweep_centers(items: Array, axis: int) -> void:
	var other := 2 if axis == 0 else 0
	var order: Array = []
	for i in items.size():
		order.append(i)
	order.sort_custom(
		func(a, b): return (items[a]["at"] as Vector3)[axis] < (items[b]["at"] as Vector3)[axis]
	)
	var neu := {}
	for i in order.size():
		var pi: int = order[i]
		var p: Dictionary = items[pi]
		if i == 0:
			neu[pi] = (p["at"] as Vector3)[axis]
			continue
		var pred := -1
		for j in range(i - 1, -1, -1):
			var qi: int = order[j]
			var q: Dictionary = items[qi]
			if absf((p["at"] as Vector3)[axis] - (q["at"] as Vector3)[axis]) < GridSnap.CELL * 0.26:
				continue
			if _overlap(p, q, other):
				pred = qi
				break
		if pred < 0:
			neu[pi] = (p["at"] as Vector3)[axis]
			continue
		var q: Dictionary = items[pred]
		var old_gap := (
			(p["at"] as Vector3)[axis] - (p["old"] as Vector3)[axis] * 0.5
			- ((q["at"] as Vector3)[axis] + (q["old"] as Vector3)[axis] * 0.5)
		)
		neu[pi] = float(neu[pred]) + (q["new"] as Vector3)[axis] * 0.5 + old_gap + (p["new"] as Vector3)[axis] * 0.5
	for i in items.size():
		var at: Vector3 = items[i]["at"]
		at[axis] = float(neu[i])
		items[i]["at"] = at


static func _sweep_bottoms(items: Array) -> void:
	var order: Array = []
	for i in items.size():
		order.append(i)
	order.sort_custom(
		func(a, b): return (items[a]["at"] as Vector3).y < (items[b]["at"] as Vector3).y
	)
	var neu := {}
	for i in order.size():
		var pi: int = order[i]
		var p: Dictionary = items[pi]
		var pred := -1
		var best := -INF
		for j in i:
			var qi: int = order[j]
			var q: Dictionary = items[qi]
			if not _overlap(p, q, 0) or not _overlap(p, q, 2):
				continue
			var top: float = (q["at"] as Vector3).y + (q["old"] as Vector3).y
			if top > best:
				best = top
				pred = qi
		if pred < 0:
			neu[pi] = (p["at"] as Vector3).y
			continue
		var q: Dictionary = items[pred]
		var old_gap: float = (p["at"] as Vector3).y - ((q["at"] as Vector3).y + (q["old"] as Vector3).y)
		neu[pi] = float(neu[pred]) + (q["new"] as Vector3).y + old_gap
	for i in items.size():
		var at: Vector3 = items[i]["at"]
		at.y = float(neu[i])
		items[i]["at"] = at


static func _overlap(a: Dictionary, b: Dictionary, axis: int) -> bool:
	var ah: float = (a["old"] as Vector3)[axis] * 0.5
	var bh: float = (b["old"] as Vector3)[axis] * 0.5
	if ah <= 0.0 and bh <= 0.0:
		return true
	return absf((a["at"] as Vector3)[axis] - (b["at"] as Vector3)[axis]) <= ah + bh + GridSnap.CELL * 0.26
