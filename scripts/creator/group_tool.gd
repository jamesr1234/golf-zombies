class_name GroupTool
extends RefCounted
## Turns a handful of placed pieces into a structure that can be dropped again
## whole. The group is saved as its own placement list, so it behaves exactly
## like the loose pieces it was made from once it lands back on a hole.
##
## Merging swallows the pieces it was made from: they leave the hole and one
## structure stands where they were. Otherwise the obstacles would still be
## lying around and nothing would look like it had happened.

signal changed
signal refused(reason: String)
signal saved(path: String)

const NAME := "GROUP"
const RADIUS_MIN := GridSnap.CELL * 2.0
const RADIUS_MAX := GridSnap.CELL * 24.0
const RADIUS_STEP := GridSnap.CELL * 2.0
const MIN_PARTS := 2

var hole: CustomHole
var radius := GridSnap.CELL * 8.0
var selected: Array[int] = []

var _at := Vector3.ZERO


func _init(for_hole: CustomHole) -> void:
	hole = for_hole


func label() -> String:
	return NAME


func aim(at: Vector3) -> void:
	_at = at


func center() -> Vector3:
	return _at


func grow(steps: float) -> void:
	radius = clampf(radius + steps * RADIUS_STEP, RADIUS_MIN, RADIUS_MAX)


## Everything inside the ring joins or leaves the selection together, which is
## quicker than clicking pieces one at a time.
func toggle() -> void:
	var inside := within()
	if inside.is_empty():
		refused.emit("NOTHING INSIDE THE RING")
		return
	var adding := false
	for index in inside:
		if not selected.has(index):
			adding = true
			break
	for index in inside:
		if adding and not selected.has(index):
			selected.append(index)
		elif not adding:
			selected.erase(index)
	changed.emit()


func within() -> Array[int]:
	var out: Array[int] = []
	for i in hole.placements.size():
		var entry: Dictionary = hole.placements[i]
		var near := (entry[CustomHole.POSITION] as Vector3).distance_to(_at) <= radius
		if not near and CustomHole.has_end(entry):
			near = (entry[CustomHole.END] as Vector3).distance_to(_at) <= radius
		if near:
			out.append(i)
	return out


func clear() -> void:
	selected.clear()
	changed.emit()


func is_selected(index: int) -> bool:
	return selected.has(index)


func parts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in selected:
		if index >= 0 and index < hole.placements.size():
			out.append(hole.placements[index])
	return out


func can_save() -> bool:
	return parts().size() >= MIN_PARTS


## A group made of another group would nest a record inside itself, which is
## only ever a way to lose track of what a piece really is. A gun is refused
## too: its line would not survive being flattened into a structure.
func save(title: String) -> bool:
	if title.strip_edges().is_empty():
		refused.emit("GIVE THE STRUCTURE A NAME FIRST")
		return false
	var picked := parts()
	if picked.size() < MIN_PARTS:
		refused.emit("SELECT AT LEAST %d PIECES" % MIN_PARTS)
		return false
	for part in picked:
		var path := String(part[CustomHole.PATH])
		if HoleStore.is_structure(path):
			refused.emit("A GROUP CANNOT BE BUILT OUT OF ANOTHER GROUP")
			return false
		if CustomHole.is_weapon(path):
			refused.emit("A WEAPON CANNOT GO IN A STRUCTURE")
			return false
	var saved_path := HoleStore.save_structure(title, picked)
	if saved_path.is_empty():
		refused.emit("COULD NOT SAVE THAT STRUCTURE")
		return false
	_merge(saved_path, HoleStore.centroid(picked))
	saved.emit(saved_path)
	return true


## The loose pieces come off the hole and the structure lands in their place, so
## what is on screen matches what is now one thing.
func _merge(path: String, center: Vector3) -> void:
	var doomed := selected.duplicate()
	doomed.sort()
	doomed.reverse()
	for index in doomed:
		hole.remove_placement(index)
	hole.add_placement(path, center)
	clear()


func summary() -> String:
	if selected.is_empty():
		return "RING THE PIECES   RING %d M" % roundi(radius)
	return "%d SELECTED   G MERGES THEM   RING %d M" % [selected.size(), roundi(radius)]
