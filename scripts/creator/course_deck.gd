class_name CourseDeck
extends Object
## The titled holes one online match plays. The host packs Hole 1..12 from
## disk; joiners apply that pack so every machine builds the same course.
## Local 1-player and 2-player never touch this; they keep reading disk.

const INDEX := "index"
const HOLE := "hole"

static var _slots: Dictionary = {}


static func hole(index: int) -> CustomHole:
	if not _slots.has(index):
		return null
	return _slots[index] as CustomHole


## Disk only, so a leftover session cannot pack itself back onto the wire.
static func pack() -> Array:
	var rows: Array = []
	for index in GameState.HOLE_COUNT:
		var made := HoleStore.disk_course_hole(index)
		if made == null:
			continue
		rows.append({INDEX: index, HOLE: flatten(made).to_dict()})
	return rows


static func apply(rows: Array) -> void:
	clear()
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var index := int(row.get(INDEX, -1))
		if index < 0 or index >= GameState.HOLE_COUNT:
			continue
		var body = row.get(HOLE, {})
		if typeof(body) != TYPE_DICTIONARY or (body as Dictionary).is_empty():
			continue
		_slots[index] = CustomHole.from_dict(body)


static func clear() -> void:
	_slots.clear()


## Groups become the loose pieces they were made from, so a joiner does not
## need the host's user:// structures folder.
static func flatten(hole: CustomHole) -> CustomHole:
	if hole == null:
		return null
	var out := hole.copy()
	var listed: Array[Dictionary] = []
	for entry in hole.placements:
		listed.append_array(CustomOverlay.expand(entry))
	out.placements = listed
	return out
