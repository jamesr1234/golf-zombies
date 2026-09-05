class_name HoleStore
extends Object
## Player-made holes and the structures they grouped, kept under user:// as
## versioned JSON. A hole titled Hole 1 through Hole 12 replaces that slot on
## the regular course. Nothing here talks to a network; the records are shaped
## so that uploading one later is a transport on top, not a rewrite.

const LIVE_ROOT := "user://holes"
const TEST_ROOT := "user://holes_test"
const SUFFIX := ".json"
const VERSION := 1
const PARTS := "parts"
## Live saves sit in LIVE_ROOT. Tests flip this so a GUT run can never wipe a
## hole someone actually made.
static var ROOT := LIVE_ROOT
static var STRUCTURE_ROOT := LIVE_ROOT + "/structures"


static func _static_init() -> void:
	for arg in OS.get_cmdline_args():
		if String(arg).contains("gut"):
			sandbox()
			return


## Point every read and write at the throwaway folder. Call this before a test
## wipes anything.
static func sandbox() -> void:
	ROOT = TEST_ROOT
	STRUCTURE_ROOT = TEST_ROOT + "/structures"


static func clear_sandbox() -> void:
	sandbox()
	for row in list_holes():
		delete_hole(String(row["id"]))
	for path in list_structures():
		delete_structure(path)


static func hole_path(id: String) -> String:
	return "%s/%s%s" % [ROOT, _slug(id), SUFFIX]


static func structure_path(id: String) -> String:
	return "%s/%s%s" % [STRUCTURE_ROOT, _slug(id), SUFFIX]


static func save_hole(hole: CustomHole) -> bool:
	if hole == null or hole.id.is_empty():
		return false
	return _write(hole_path(hole.id), hole.to_dict())


static func load_hole(id: String) -> CustomHole:
	var body := _read(hole_path(id))
	if body.is_empty():
		return null
	return CustomHole.from_dict(body)


static func delete_hole(id: String) -> bool:
	return _remove(hole_path(id))


## "Hole 1" through "Hole 12" take that slot on the regular course. Anything
## else is only playable from the creator browser.
static func course_slot(title: String) -> int:
	var key := title.strip_edges().to_lower()
	if not key.begins_with("hole "):
		return -1
	var rest := key.substr(5).strip_edges()
	if not rest.is_valid_int():
		return -1
	var number := rest.to_int()
	if number < 1 or number > GameState.HOLE_COUNT:
		return -1
	return number - 1


## Newest playable hole titled for this slot, or null to keep the generated one.
static func course_hole(index: int) -> CustomHole:
	if index < 0 or index >= GameState.HOLE_COUNT:
		return null
	for row in list_holes():
		if course_slot(String(row["title"])) != index:
			continue
		if not bool(row["playable"]):
			continue
		return load_hole(String(row["id"]))
	return null


static func course_pars() -> PackedInt32Array:
	var pars := HoleGenerator.pars()
	for i in pars.size():
		var hole := course_hole(i)
		if hole != null:
			pars[i] = hole.par()
	return pars


## The hole that plays in a regular round. A saved Hole 1..12 takes that slot.
static func layout(index: int, seed: int) -> HoleData:
	var override := course_hole(index)
	if override != null:
		return CustomLayout.build(override, seed, index)
	return HoleGenerator.generate(index, seed)


## Newest first, because the hole you just made is the one you want to play.
static func list_holes() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for path in _list(ROOT):
		var body := _read(path)
		if body.is_empty():
			continue
		var hole := CustomHole.from_dict(body)
		rows.append({
			"id": hole.id,
			"title": hole.title,
			"par": hole.par(),
			"length": hole.length(),
			"pieces": hole.pieces.size(),
			"placements": hole.placements.size(),
			"created_at": hole.created_at,
			"playable": hole.is_playable(),
		})
	rows.sort_custom(func(a, b): return int(a["created_at"]) > int(b["created_at"]))
	return rows


## Where a group sits once it is one piece: the middle of what it was made from,
## flattened so it drops onto whatever ground is under it.
static func centroid(parts: Array[Dictionary]) -> Vector3:
	if parts.is_empty():
		return Vector3.ZERO
	var center := Vector3.ZERO
	for part in parts:
		center += part[CustomHole.POSITION] as Vector3
	center /= float(parts.size())
	center.y = 0.0
	return center


## Parts arrive in world space. They are stored around their own middle so the
## group can be dropped anywhere later.
static func save_structure(title: String, parts: Array[Dictionary]) -> String:
	if title.strip_edges().is_empty() or parts.is_empty():
		return ""
	var center := centroid(parts)
	var listed: Array = []
	for part in parts:
		var at: Vector3 = part[CustomHole.POSITION]
		var row := {
			CustomHole.PATH: String(part[CustomHole.PATH]),
			CustomHole.POSITION: CustomHole.to_array(at - center),
			CustomHole.YAW: float(part[CustomHole.YAW]),
		}
		if CustomHole.has_end(part):
			row[CustomHole.END] = CustomHole.to_array((part[CustomHole.END] as Vector3) - center)
		listed.append(row)
	var id := _slug(title)
	if not _write(structure_path(id), {"version": VERSION, "title": title, PARTS: listed}):
		return ""
	return structure_path(id)


static func structure_parts(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var body := _read(path)
	for entry in body.get(PARTS, []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		out.append(CustomHole.placement(
			String(entry.get(CustomHole.PATH, "")),
			CustomHole.to_vector(entry.get(CustomHole.POSITION, [])),
			float(entry.get(CustomHole.YAW, 0.0)),
			CustomHole.NO_GATE,
			CustomHole.to_vector(entry[CustomHole.END]) if entry.has(CustomHole.END) else CustomHole.NO_END
		))
	return out


static func structure_title(path: String) -> String:
	var body := _read(path)
	if body.is_empty():
		return path.get_file().get_basename().replace("_", " ").to_upper()
	return String(body.get("title", "")).to_upper()


static func list_structures() -> PackedStringArray:
	return _list(STRUCTURE_ROOT)


## A name the prompt can open with, so a pad can confirm a merge without a
## keyboard. Counts up past whatever is already saved rather than overwriting.
static func suggest_structure_title() -> String:
	var taken := list_structures()
	var n := taken.size() + 1
	while taken.has(structure_path("structure_%d" % n)):
		n += 1
	return "STRUCTURE %d" % n


static func delete_structure(path: String) -> bool:
	return _remove(path)


static func is_structure(path: String) -> bool:
	return path.begins_with(STRUCTURE_ROOT)


static func _list(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(SUFFIX):
			out.append("%s/%s" % [dir_path, name])
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


static func _write(path: String, body: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(body, "\t"))
	file.close()
	return true


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func _remove(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


## A record is named from its own title or id, so a stray slash or dot never
## writes outside the holes folder.
static func _slug(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_":
			out += c
		elif c == " " or c == "-":
			out += "_"
	return out if not out.is_empty() else "untitled"
