@tool
class_name PieceCatalog
extends Object
## Everything the hole creator can drop on a course. The list is committed to
## resources/course/pieces.json rather than scanned, because DirAccess over
## res:// cannot see source .glb files once the project is exported.

const MANIFEST := "res://resources/course/pieces.json"
const VERSION := 1

const OBSTACLES := "obstacles"
const PROPS := "props"
const VEHICLES := "vehicles"
const WEAPONS := "weapons"

const OBSTACLE_DIR := "res://assets/obstacles"
const PROP_DIR := "res://scenes/course/props"
const VEHICLE_DIR := "res://scenes/vehicles"
const WEAPON_DIR := CustomHole.WEAPON_DIR

## Props that stand on their own. The rest are either paired with a setpiece or
## built from HoleData by the generator, so dropping one bare leaves it dead.
const LOOSE_PROPS: PackedStringArray = [
	"climbing_wall", "folding_steps", "grapple_point", "rock",
	"sniper_tower", "speed_rectangle", "spiral_track", "wall", "windmill",
	"zipline",
]

const _SIZES: PackedStringArray = [
	"extra_small", "small", "medium", "large", "extra_large",
]

static var _cache: Dictionary = {}


## Bundled structure scenes are not offered any more: a player builds their own
## by grouping obstacles, and the hand-authored holes keep using the scenes
## directly.
static func categories() -> PackedStringArray:
	return PackedStringArray([OBSTACLES, PROPS, VEHICLES, WEAPONS])


static func entries(category: String) -> PackedStringArray:
	if _cache.is_empty():
		_cache = read_manifest()
	return _cache.get(category, PackedStringArray())


static func has_piece(path: String) -> bool:
	for category in categories():
		if entries(category).has(path):
			return true
	return false


static func label_for(path: String) -> String:
	return path.get_file().get_basename().replace("_", " ").to_upper()


## Kind first, then small to large, so a palette row reads arch, cube, ladder
## rather than alphabetical noise.
static func sort_by_size(paths: PackedStringArray) -> PackedStringArray:
	var rows: Array = []
	for path in paths:
		rows.append(path)
	rows.sort_custom(func(a: String, b: String) -> bool: return _sort_key(a) < _sort_key(b))
	return PackedStringArray(rows)


static func read_manifest() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(MANIFEST):
		return build()
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	if file == null:
		return build()
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return build()
	for category in categories():
		var listed = parsed.get(category, [])
		var paths: PackedStringArray = []
		for path in listed:
			paths.append(String(path))
		out[category] = paths
	return out


## Truth from disk. Only reachable with the source tree present, so it is the
## editor path and what the drift test measures the manifest against.
static func build() -> Dictionary:
	return {
		OBSTACLES: sort_by_size(_scan(OBSTACLE_DIR, ".glb")),
		PROPS: _loose(_scan(PROP_DIR, ".tscn")),
		VEHICLES: _scan(VEHICLE_DIR, ".tscn"),
		WEAPONS: _scan(WEAPON_DIR, ".tres"),
	}


static func write_manifest() -> bool:
	var built := build()
	var body := {"version": VERSION}
	for category in categories():
		body[category] = Array(built[category] as PackedStringArray)
	var file := FileAccess.open(MANIFEST, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(body, "\t") + "\n")
	file.close()
	_cache = {}
	return true


static func _loose(paths: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for path in paths:
		if LOOSE_PROPS.has(path.get_file().get_basename()):
			out.append(path)
	return out


static func _scan(dir_path: String, suffix: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(suffix):
			out.append("%s/%s" % [dir_path, name])
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


static func _sort_key(path: String) -> Array:
	var stem := path.get_file().get_basename()
	return [stem.get_slice("_", 0), _size_rank(stem), stem]


static func _size_rank(stem: String) -> int:
	var found := ""
	for size in _SIZES:
		if stem != size and not stem.ends_with("_%s" % size):
			continue
		if size.length() > found.length():
			found = size
	if found.is_empty():
		return _SIZES.size()
	return _SIZES.find(found)
