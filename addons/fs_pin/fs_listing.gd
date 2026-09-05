@tool
extends RefCounted
## Paths and drag payload for the pinned FileSystem panel.


const ROOT := "res://"
const SORT_NAME := "name"
const SORT_SIZE := "size"


static func is_hidden(file_name: String) -> bool:
	return file_name.begins_with(".") or file_name.ends_with(".import") or file_name.ends_with(".uid")


static func is_dir(path: String) -> bool:
	return not FileAccess.file_exists(path) and DirAccess.open(path) != null


static func join(dir_path: String, file_name: String) -> String:
	if dir_path == ROOT:
		return ROOT + file_name
	return dir_path.path_join(file_name)


static func is_immersive(window_mode: int, distraction_free: bool) -> bool:
	if distraction_free:
		return true
	return (
		window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or window_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)


static func list_dir(path: String) -> PackedStringArray:
	var dir := DirAccess.open(path)
	if dir == null:
		return PackedStringArray()
	var dirs: PackedStringArray = []
	var files: PackedStringArray = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not is_hidden(name):
			var child := join(path, name)
			if dir.current_is_dir():
				dirs.append(child)
			else:
				files.append(child)
		name = dir.get_next()
	dirs.sort()
	files.sort()
	return dirs + files


static func default_expand_paths() -> PackedStringArray:
	var wanted := PackedStringArray(
		["res://assets", "res://scenes/course/props", "res://scenes/course/structures"]
	)
	var out: PackedStringArray = []
	for path in wanted:
		var acc := "res:/"
		for part in path.trim_prefix("res://").split("/"):
			acc += "/" + part
			if not out.has(acc):
				out.append(acc)
	return out


static func should_expand(path: String) -> bool:
	return path == ROOT or default_expand_paths().has(path)


static func is_placeable(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext in ["png", "jpg", "jpeg", "webp", "svg", "glb", "gltf", "tscn", "scn"]


static func list_files_under(path: String, mode: String = SORT_NAME) -> PackedStringArray:
	var files := PackedStringArray()
	var dirs: PackedStringArray = []
	for child in list_dir(path):
		if is_dir(child):
			dirs.append(child)
		elif is_placeable(child):
			files.append(child)
	if files.is_empty():
		for dir_path in dirs:
			files.append_array(list_files_under(dir_path, mode))
	return sort_paths(files, mode)


static func sort_paths(paths: PackedStringArray, mode: String = SORT_NAME) -> PackedStringArray:
	if mode == SORT_SIZE:
		return PieceCatalog.sort_by_size(paths)
	var rows: Array = []
	for path in paths:
		rows.append(path)
	rows.sort()
	return PackedStringArray(rows)


static func drag_payload(paths: PackedStringArray) -> Dictionary:
	return {"type": "files", "files": paths}
