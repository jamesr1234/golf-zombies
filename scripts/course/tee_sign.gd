class_name TeeSign
extends Node3D
## Neon marker beside the tee. Local +Z is the readable face. Header copy and a
## top-down of the hole all sit inside the magenta frame.

const BOARD := Vector2(2.45, 3.55)
const BOARD_Y := 3.05
const INSET := 0.16
const FACE_Z := 0.08
const HEADER := 0.38
## Inset from the inner plate so outline does not kiss the neon.
const COPY_MARGIN := 0.10
## Clear air between hole number and yardage on the header row.
const COPY_GAP := 0.22
const COPY_PIXEL := 0.0065


static func create(data: HoleData, at: Vector3, face: Vector3) -> TeeSign:
	var sign := TeeSign.new()
	sign.name = "TeeSign"
	sign.add_to_group("hole_signs")
	sign.position = at
	var toward := face
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		toward = Vector3.FORWARD
	toward = toward.normalized()
	sign.rotation.y = atan2(toward.x, toward.z)
	sign._posts()
	sign._board()
	sign._copy(data)
	sign._plan(data)
	sign._lamp()
	return sign


func _posts() -> void:
	var half := BOARD.x * 0.5 - 0.28
	for side in [-1.0, 1.0]:
		var post := MeshFactory.cylinder(0.07, 3.2, Palette.FLAGPOLE, Palette.GLOW_SOFT)
		post.position = Vector3(side * half, 1.6, 0.0)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(post)
		var ring := MeshFactory.cylinder(0.11, 0.08, Palette.MAGENTA, Palette.GLOW_MEDIUM)
		ring.position = Vector3(side * half, 2.55, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
	var foot := MeshFactory.box(Vector3(BOARD.x * 0.7, 0.1, 0.4), Palette.WALL, Palette.GLOW_FAINT)
	foot.position.y = 0.05
	add_child(foot)


func _board() -> void:
	var back := MeshFactory.box(Vector3(BOARD.x, BOARD.y, 0.08), Palette.NIGHT, 0.2)
	back.position = Vector3(0.0, BOARD_Y, 0.0)
	_unshaded(back)
	add_child(back)
	_frame(
		BOARD + Vector2(0.12, 0.12), 0.07, BOARD_Y, 0.03, Palette.MAGENTA, Palette.GLOW_MEDIUM
	)
	_frame(BOARD - Vector2(0.08, 0.08), 0.045, BOARD_Y, 0.05, Palette.CYAN, Palette.GLOW_SOFT)
	var plate := MeshFactory.box(
		Vector3(BOARD.x - INSET * 2.0, BOARD.y - INSET * 2.0, 0.03), Palette.NIGHT, 0.12
	)
	plate.position = Vector3(0.0, BOARD_Y, 0.06)
	_unshaded(plate)
	add_child(plate)


func _frame(
	size: Vector2, thick: float, y: float, z: float, color: Color, glow: float
) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var bars := [
		[Vector3(0.0, y + hy - thick * 0.5, z), Vector3(size.x, thick, 0.04)],
		[Vector3(0.0, y - hy + thick * 0.5, z), Vector3(size.x, thick, 0.04)],
		[Vector3(-hx + thick * 0.5, y, z), Vector3(thick, size.y - thick * 2.0, 0.04)],
		[Vector3(hx - thick * 0.5, y, z), Vector3(thick, size.y - thick * 2.0, 0.04)],
	]
	for bar in bars:
		var mesh := MeshFactory.box(bar[1], color, glow)
		mesh.position = bar[0]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_unshaded(mesh)
		add_child(mesh)


func _copy(data: HoleData) -> void:
	var top := BOARD_Y + BOARD.y * 0.5 - INSET - HEADER * 0.5
	var edge := BOARD.x * 0.5 - INSET - COPY_MARGIN
	var box := (edge - COPY_GAP * 0.5) / COPY_PIXEL
	var hole := _label("HoleCopy", "HOLE %d" % [data.index + 1], Palette.CYAN, 32, COPY_PIXEL)
	hole.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hole.width = box
	hole.position = Vector3(-edge, top, FACE_Z)
	add_child(hole)
	var yard := _label("YardCopy", data.yardage_label(), Palette.AMBER, 32, COPY_PIXEL)
	yard.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	yard.width = box
	yard.position = Vector3(edge, top, FACE_Z)
	add_child(yard)


func _label(node_name: String, text: String, color: Color, font_size: int, pixel: float) -> Label3D:
	var copy := Label3D.new()
	copy.name = node_name
	copy.text = text
	copy.font_size = font_size
	copy.pixel_size = pixel
	copy.modulate = color
	copy.outline_size = 8
	copy.outline_modulate = Palette.NIGHT
	copy.double_sided = false
	copy.shaded = false
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return copy


func _plan(data: HoleData) -> void:
	var root := Node3D.new()
	root.name = "HolePlan"
	add_child(root)
	var bounds := HoleMap.local_bounds(data)
	var area := Vector2(BOARD.x - INSET * 2.0 - 0.12, BOARD.y - INSET * 2.0 - HEADER - 0.12)
	if bounds.size.x < 0.01 or bounds.size.y < 0.01:
		return
	var scale := minf(area.x / bounds.size.x, area.y / bounds.size.y)
	var drawn := bounds.size * scale
	var map_bottom := BOARD_Y - BOARD.y * 0.5 + INSET + 0.06
	var origin := Vector2(-drawn.x * 0.5, map_bottom + (area.y - drawn.y) * 0.5)
	root.add_child(_poly(PackedVector2Array([
		origin,
		origin + Vector2(drawn.x, 0.0),
		origin + drawn,
		origin + Vector2(0.0, drawn.y),
	]), _fill(Surface.Type.ROUGH), FACE_Z - 0.012))
	var patches := data.patches.duplicate()
	patches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Surface.PRIORITY[a["type"]] < Surface.PRIORITY[b["type"]]
	)
	for patch in patches:
		_patch(root, data, patch, bounds, scale, origin, Surface.DRAW_HEIGHT[patch["type"]] * 0.04)
	for prop in data.props:
		_prop(root, data, prop, bounds, scale, origin)
	_path(root, data, bounds, scale, origin)
	_dot(root, "Tee", _on_face(data, data.tee, bounds, scale, origin), 0.055, Palette.CYAN)
	_dot(root, "Cup", _on_face(data, data.cup, bounds, scale, origin), 0.05, Palette.FLAG)


func _patch(
	root: Node3D, data: HoleData, patch: Dictionary, bounds: Rect2, scale: float, origin: Vector2, z_off: float
) -> void:
	var color := _fill(patch["type"], bool(patch.get("practice", false)))
	if patch["round"]:
		var center := _on_face(data, patch["position"], bounds, scale, origin)
		center.z += z_off
		var size: Vector2 = patch["size"]
		var edge := _on_face(
			data, patch["position"] + Vector3(size.x * 0.5, 0.0, 0.0), bounds, scale, origin
		)
		_disk(root, "", center, maxf(0.03, center.distance_to(edge)), color)
		return
	var points := PackedVector2Array()
	var size: Vector2 = patch["size"]
	var position: Vector3 = patch["position"]
	var yaw := deg_to_rad(float(patch["yaw"]))
	for local in [
		Vector3(-size.x * 0.5, 0.0, -size.y * 0.5),
		Vector3(size.x * 0.5, 0.0, -size.y * 0.5),
		Vector3(size.x * 0.5, 0.0, size.y * 0.5),
		Vector3(-size.x * 0.5, 0.0, size.y * 0.5),
	]:
		var at := _on_face(data, local.rotated(Vector3.UP, yaw) + position, bounds, scale, origin)
		points.append(Vector2(at.x, at.y))
	root.add_child(_poly(points, color, FACE_Z + z_off))


func _prop(
	root: Node3D, data: HoleData, prop: Dictionary, bounds: Rect2, scale: float, origin: Vector2
) -> void:
	var at := _on_face(data, prop["position"], bounds, scale, origin)
	at.z += 0.01
	var size: Vector3 = prop["size"]
	var radius := maxf(0.025, size.x * scale * 0.35)
	match String(prop["kind"]):
		"tree":
			_disk(root, "", at, radius, Palette.TREE_CANOPY)
		"rock":
			_disk(root, "", at, radius, Palette.ROCK_TRIM)
		"tower":
			_disk(root, "", at, radius * 1.35, Palette.TOWER_TRIM)
		"culvert":
			_culvert_mark(root, data, prop, bounds, scale, origin)
		"mill_control":
			_disk(root, "", at, radius, Palette.CYAN)
		_:
			_disk(root, "", at, radius, Palette.WALL_TRIM)


func _culvert_mark(
	root: Node3D, data: HoleData, prop: Dictionary, bounds: Rect2, scale: float, origin: Vector2
) -> void:
	var size: Vector3 = prop["size"]
	var position: Vector3 = prop["position"]
	var yaw := deg_to_rad(float(prop.get("yaw", 0.0)))
	var points := PackedVector2Array()
	for local in [
		Vector3(-size.x * 0.5, 0.0, -size.z * 0.5),
		Vector3(size.x * 0.5, 0.0, -size.z * 0.5),
		Vector3(size.x * 0.5, 0.0, size.z * 0.5),
		Vector3(-size.x * 0.5, 0.0, size.z * 0.5),
	]:
		var at := _on_face(data, local.rotated(Vector3.UP, yaw) + position, bounds, scale, origin)
		points.append(Vector2(at.x, at.y))
	root.add_child(_poly(points, Palette.AMBER, FACE_Z + 0.012))


func _path(
	root: Node3D, data: HoleData, bounds: Rect2, scale: float, origin: Vector2
) -> void:
	for i in range(1, data.centerline.size()):
		var a := _on_face(data, data.centerline[i - 1], bounds, scale, origin)
		var b := _on_face(data, data.centerline[i], bounds, scale, origin)
		var span := Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y))
		if span < 0.02:
			continue
		var bar := MeshFactory.box(Vector3(0.03, span, 0.012), Palette.CYAN, Palette.GLOW_SOFT)
		bar.position = a.lerp(b, 0.5)
		bar.position.z = FACE_Z + 0.006
		bar.rotation.z = atan2(a.x - b.x, b.y - a.y)
		_unshaded(bar)
		root.add_child(bar)


func _dot(root: Node3D, node_name: String, at: Vector3, radius: float, color: Color) -> void:
	at.z += 0.014
	_disk(root, node_name, at, radius, color)


func _disk(root: Node3D, node_name: String, at: Vector3, radius: float, color: Color) -> void:
	var disk := MeshFactory.cylinder(radius, 0.016, color, Palette.GLOW_SOFT)
	if not node_name.is_empty():
		disk.name = node_name
	disk.rotation.x = TAU * 0.25
	disk.position = at
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_unshaded(disk)
	root.add_child(disk)


func _poly(points: PackedVector2Array, color: Color, z: float) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, points.size() - 1):
		for p in [points[0], points[i], points[i + 1]]:
			st.set_normal(Vector3.BACK)
			st.add_vertex(Vector3(p.x, p.y, z))
	st.generate_normals()
	st.commit(mesh)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = MeshFactory.material(color, true, Palette.GLOW_FAINT)
	var mat := node.material_override as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _on_face(
	data: HoleData, point: Vector3, bounds: Rect2, scale: float, origin: Vector2
) -> Vector3:
	var local := HoleMap.to_local(data, point)
	return Vector3(
		origin.x + (local.x - bounds.position.x) * scale,
		origin.y + (local.y - bounds.position.y) * scale,
		FACE_Z
	)


func _fill(type: Surface.Type, practice := false) -> Color:
	var look: Dictionary = Surface.look_of(type, practice)
	return Color(look["base"]).lerp(look["line"], 0.45)


func _lamp() -> void:
	var lamp := OmniLight3D.new()
	lamp.light_color = Palette.CYAN
	lamp.light_energy = 1.05
	lamp.omni_range = 6.5
	lamp.position = Vector3(0.0, BOARD_Y, 0.5)
	add_child(lamp)


func _unshaded(mesh: MeshInstance3D) -> void:
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
