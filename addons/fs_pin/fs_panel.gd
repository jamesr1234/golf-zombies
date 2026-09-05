@tool
extends VBoxContainer
## Folder tree plus thumbnail grid of placeable assets.

const _Listing := preload("res://addons/fs_pin/fs_listing.gd")
const _START := "res://assets"

var _tree: Tree
var _list: ItemList
var _sort: OptionButton
var _folder := _START
var _sort_mode := _Listing.SORT_NAME


func _ready() -> void:
	custom_minimum_size = Vector2(280, 420)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	var title := Label.new()
	title.text = "FileSystem"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	_sort = OptionButton.new()
	_sort.add_item("Alphabetical")
	_sort.add_item("Size")
	_sort.select(0)
	_sort.item_selected.connect(_on_sort_selected)
	bar.add_child(_sort)
	add_child(bar)
	_tree = Tree.new()
	_tree.custom_minimum_size.y = 120
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.size_flags_stretch_ratio = 0.35
	_tree.hide_root = false
	_tree.item_selected.connect(_on_tree_selected)
	_tree.item_collapsed.connect(_on_item_collapsed)
	add_child(_tree)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.size_flags_stretch_ratio = 0.65
	_list.icon_mode = ItemList.ICON_MODE_TOP
	_list.fixed_icon_size = Vector2i(72, 72)
	_list.fixed_column_width = 92
	_list.max_columns = 0
	_list.same_column_width = true
	_list.set_drag_forwarding(_list_drag, Callable(), Callable())
	_list.item_activated.connect(_on_list_activated)
	add_child(_list)
	_rebuild()


func _rebuild() -> void:
	if _tree == null:
		return
	_tree.clear()
	var root := _tree.create_item()
	root.set_text(0, "res://")
	root.set_metadata(0, _Listing.ROOT)
	_fill(root)
	_expand_defaults(root)
	_select_path(_START)


func _clear_children(item: TreeItem) -> void:
	var wipe := item.get_first_child()
	while wipe:
		var nxt := wipe.get_next()
		item.remove_child(wipe)
		wipe.free()
		wipe = nxt


func _fill(item: TreeItem) -> void:
	_clear_children(item)
	for child_path in _Listing.list_dir(str(item.get_metadata(0))):
		if not _Listing.is_dir(child_path):
			continue
		var node := _tree.create_item(item)
		node.set_text(0, child_path.get_file())
		node.set_metadata(0, child_path)
		node.set_tooltip_text(0, child_path)
		var dummy := _tree.create_item(node)
		dummy.set_text(0, "...")
		dummy.set_selectable(0, false)
		node.collapsed = true
	item.set_meta("filled", true)


func _ensure_filled(item: TreeItem) -> void:
	if not item.get_meta("filled", false):
		_fill(item)


func _expand_defaults(item: TreeItem) -> void:
	if not _Listing.should_expand(str(item.get_metadata(0))):
		return
	_ensure_filled(item)
	item.collapsed = false
	var child := item.get_first_child()
	while child:
		_expand_defaults(child)
		child = child.get_next()


func _select_path(path: String) -> void:
	var item := _find_item(_tree.get_root(), path)
	if item == null:
		_show_files(path)
		return
	item.select(0)
	_tree.scroll_to_item(item)
	_show_files(path)


func _find_item(item: TreeItem, path: String) -> TreeItem:
	if item == null:
		return null
	if str(item.get_metadata(0)) == path:
		return item
	var child := item.get_first_child()
	while child:
		var hit := _find_item(child, path)
		if hit:
			return hit
		child = child.get_next()
	return null


func _on_item_collapsed(item: TreeItem) -> void:
	if not item.collapsed:
		_ensure_filled(item)


func _on_tree_selected() -> void:
	var item := _tree.get_selected()
	if item:
		_show_files(str(item.get_metadata(0)))


func _on_sort_selected(index: int) -> void:
	_sort_mode = _Listing.SORT_SIZE if index == 1 else _Listing.SORT_NAME
	_show_files(_folder)


func _show_files(dir_path: String) -> void:
	_folder = dir_path
	_list.clear()
	for path in _Listing.list_files_under(dir_path, _sort_mode):
		var idx := _list.add_item(path.get_basename().get_file(), _file_icon(path))
		_list.set_item_metadata(idx, path)
		_list.set_item_tooltip(idx, path)
		_queue_preview(path, idx)


func _file_icon(path: String) -> Texture2D:
	if path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "svg"]:
		var tex := load(path) as Texture2D
		if tex:
			return tex
	if not Engine.is_editor_hint():
		return null
	var theme := EditorInterface.get_editor_theme()
	var ext := path.get_extension().to_lower()
	if ext in ["glb", "gltf"]:
		return theme.get_icon("MeshInstance3D", "EditorIcons")
	return theme.get_icon("PackedScene", "EditorIcons")


func _queue_preview(path: String, idx: int) -> void:
	if not Engine.is_editor_hint():
		return
	if path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "svg"]:
		return
	EditorInterface.get_resource_previewer().queue_resource_preview(path, self, "_on_preview", idx)


func _on_preview(path: String, preview: Texture2D, _thumb: Texture2D, userdata: Variant) -> void:
	var idx: int = userdata
	if preview == null or idx < 0 or idx >= _list.item_count:
		return
	if str(_list.get_item_metadata(idx)) == path:
		_list.set_item_icon(idx, preview)


func _list_drag(at_position: Vector2) -> Variant:
	var idx := _list.get_item_at_position(at_position, true)
	if idx < 0:
		return null
	var path := str(_list.get_item_metadata(idx))
	var preview := TextureRect.new()
	preview.texture = _list.get_item_icon(idx)
	preview.custom_minimum_size = Vector2(72, 72)
	_list.set_drag_preview(preview)
	return _Listing.drag_payload(PackedStringArray([path]))


func _on_list_activated(index: int) -> void:
	if not Engine.is_editor_hint():
		return
	var path := str(_list.get_item_metadata(index))
	if not path.is_empty():
		EditorInterface.select_file(path)
