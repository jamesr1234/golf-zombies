class_name PlaceTool
extends RefCounted
## Drops obstacles, structures and saved groups onto the hole. The ghost under
## the crosshair snaps to the same 1.35 m grid the editor plugin uses, so a
## piece placed in game meets its neighbours as flush as one placed by hand.

signal changed
signal refused(reason: String)

const NAME := "PLACE"
const TURN := 45.0
const TURN_FREE := 5.0
const TURN_SPEED := 270.0
const GHOST_ALPHA := 0.42

var hole: CustomHole
var category := 0
var picked := 0
var yaw := 0.0
## Which placement is having its line drawn, or -1 for none. Only a weapon ever
## gets one, and only one at a time.
var gating := -1
## World pose of a zipline start waiting for its lower end, or INF for none.
var zip_from := Vector3.INF
## Where down the hole the crosshair currently is, filled in by the creator
## because it is the only side that holds the built HoleData.
var aim_gate := 0.0
## When set, the ghost sits on the fairway or on top of whatever is already
## standing in that column, instead of hanging at the camera's reach.
var surface_snap := false
## Right-stick click turns this off so a piece can be nudged off the 45s, then
## back on to drop it onto the same angles again.
var yaw_snap := true
var height: HeightField
var space: PhysicsDirectSpaceState3D

var _ghost: Node3D
var _ghost_path := ""
var _at := Vector3.ZERO


func _init(for_hole: CustomHole) -> void:
	hole = for_hole


func label() -> String:
	return NAME


## Catalog pieces first, then anything the player grouped themselves.
func shelves() -> PackedStringArray:
	var out := PieceCatalog.categories()
	out.append("groups")
	return out


func shelf() -> String:
	return shelves()[posmod(category, shelves().size())]


func pieces() -> PackedStringArray:
	if shelf() == "groups":
		return HoleStore.list_structures()
	return PieceCatalog.entries(shelf())


func picked_path() -> String:
	var listed := pieces()
	if listed.is_empty():
		return ""
	return listed[posmod(picked, listed.size())]


func picked_label() -> String:
	var path := picked_path()
	if path.is_empty():
		return "NOTHING TO PLACE"
	return HoleStore.structure_title(path) if HoleStore.is_structure(path) else PieceCatalog.label_for(path)


## Same shelf the player is standing on, listed the way Fairway lists shapes.
func labels() -> PackedStringArray:
	var out: PackedStringArray = []
	for path in pieces():
		out.append(
			HoleStore.structure_title(path) if HoleStore.is_structure(path)
			else PieceCatalog.label_for(path)
		)
	return out


func picked_index() -> int:
	var listed := pieces()
	if listed.is_empty():
		return -1
	return posmod(picked, listed.size())


func step_shelf(delta: int) -> void:
	if is_zipping():
		return
	category = posmod(category + delta, shelves().size())
	picked = 0
	_clear_ghost()


func step_piece(delta: int) -> void:
	if is_zipping():
		return
	var listed := pieces()
	if listed.is_empty():
		return
	picked = posmod(picked + delta, listed.size())
	_clear_ghost()


func turn(steps: int) -> void:
	# Positive steps are the right button. Clockwise from above is negative yaw.
	var step := TURN if yaw_snap else TURN_FREE
	if yaw_snap:
		yaw = snapped_yaw(yaw)
	yaw = fmod(yaw - step * float(steps) + 360.0, 360.0)


## Held left/right while snap is off. Snap mode stays one click per 45.
func spin(dir: float, delta: float) -> void:
	if yaw_snap or dir == 0.0:
		return
	yaw = fmod(yaw - TURN_SPEED * dir * delta + 360.0, 360.0)


func toggle_surface_snap() -> void:
	surface_snap = not surface_snap


func toggle_yaw_snap() -> void:
	yaw_snap = not yaw_snap
	if yaw_snap:
		yaw = snapped_yaw(yaw)


static func snapped_yaw(value: float) -> float:
	return fmod(snappedf(value, TURN) + 360.0, 360.0)


## Held out at the camera's reach, then dropped onto the grid and pushed off
## anything already standing there.
func aim(holder: Node3D, neighbors: Node, at: Vector3) -> void:
	if is_zipping():
		_aim_zip_end(holder, neighbors, at)
		return
	var path := picked_path()
	if is_gating() or path.is_empty():
		_clear_ghost()
		return
	if path != _ghost_path:
		_build_ghost(holder, path)
	if _ghost == null:
		return
	if CustomHole.is_zipline(path):
		var zip := _ghost as Zipline
		if zip != null:
			zip.collapse_end()
	_at = _surface_snapped(neighbors, at) if surface_snap else _snapped(neighbors, at)
	_ghost.rotation.y = deg_to_rad(yaw)
	_ghost.position = GridSnap.anchored_at(_ghost, _at, yaw)
	_ghost.visible = hole.covers(_at)


func place() -> bool:
	if is_zipping():
		return _set_zip_end()
	var path := picked_path()
	if path.is_empty():
		return false
	if not hole.covers(_at):
		refused.emit("OFF THE FAIRWAY. NOTHING OUT THERE IS REACHABLE.")
		return false
	if CustomHole.is_zipline(path):
		zip_from = _at
		return true
	hole.add_placement(path, GridSnap.stored_offset(_at, height), yaw)
	# A gun asks for its line straight away. Walking away leaves it live for the
	# whole hole, which is the sane default.
	if CustomHole.is_weapon(path):
		gating = hole.placements.size() - 1
	changed.emit()
	return true


func is_zipping() -> bool:
	return zip_from.is_finite()


func clear_zip() -> bool:
	if not is_zipping():
		return false
	zip_from = Vector3.INF
	return true


func aim_at() -> Vector3:
	return _at


func is_gating() -> bool:
	return gating >= 0 and gating < hole.placements.size()


## Aim at a gun already on the hole to redraw its line.
func start_gate(at: Vector3) -> bool:
	var index := nearest_weapon(at)
	if index < 0:
		refused.emit("NO WEAPON CLOSE ENOUGH TO DRAW A LINE FOR")
		return false
	gating = index
	_clear_ghost()
	return true


## Confirm while gating: the gun stops working wherever the crosshair is.
func set_gate() -> bool:
	if not is_gating():
		return false
	hole.placements[gating][CustomHole.GATE] = clampf(aim_gate, 0.0, 1.0)
	gating = -1
	changed.emit()
	return true


## Cancel while gating: no line at all, so the gun lasts the whole hole.
func clear_gate() -> bool:
	if not is_gating():
		return false
	hole.placements[gating][CustomHole.GATE] = CustomHole.NO_GATE
	gating = -1
	changed.emit()
	return true


func nearest_weapon(at: Vector3, within := 8.0) -> int:
	var best := -1
	var closest := within
	for i in hole.placements.size():
		if not CustomHole.is_weapon(String(hole.placements[i][CustomHole.PATH])):
			continue
		var distance: float = (hole.placements[i][CustomHole.POSITION] as Vector3).distance_to(at)
		if distance < closest:
			closest = distance
			best = i
	return best


## Whatever is nearest the crosshair comes out, so a mistake is one click to
## undo without hunting for a handle.
func erase(at: Vector3) -> bool:
	var index := nearest(at)
	if index < 0:
		refused.emit("NOTHING CLOSE ENOUGH TO REMOVE")
		return false
	hole.remove_placement(index)
	changed.emit()
	return true


func nearest(at: Vector3, within := 6.0) -> int:
	var best := -1
	var closest := within
	for i in hole.placements.size():
		var entry: Dictionary = hole.placements[i]
		var distance: float = (entry[CustomHole.POSITION] as Vector3).distance_to(at)
		if CustomHole.has_end(entry):
			distance = minf(distance, (entry[CustomHole.END] as Vector3).distance_to(at))
		if distance < closest:
			closest = distance
			best = i
	return best


## Leaving the tool abandons a half-drawn line without changing what is stored.
func release() -> void:
	gating = -1
	zip_from = Vector3.INF
	_clear_ghost()


func summary() -> String:
	if is_gating():
		return "DRAW THE LINE   CLICK TO SET   RIGHT CLICK FOR NO LINE"
	if is_zipping():
		return "PLACE THE LOWER END   CLICK TO SET   RIGHT CLICK TO CANCEL"
	var lock := ""
	if surface_snap:
		lock += "   SURFACE SNAP"
	lock += "   YAW SNAP" if yaw_snap else "   FREE YAW"
	return "%s   %d PLACED   YAW %d%s" % [
		shelf().to_upper(), hole.placements.size(), roundi(yaw), lock
	]


func _set_zip_end() -> bool:
	if not is_zipping():
		return false
	if not hole.covers(_at):
		refused.emit("OFF THE FAIRWAY. NOTHING OUT THERE IS REACHABLE.")
		return false
	if _at.y >= zip_from.y - Zipline.LEVEL_EPS:
		refused.emit("THE END HAS TO SIT LOWER THAN THE START.")
		return false
	hole.add_placement(
		CustomHole.ZIPLINE,
		GridSnap.stored_offset(zip_from, height),
		yaw,
		CustomHole.NO_GATE,
		GridSnap.stored_offset(_at, height)
	)
	zip_from = Vector3.INF
	changed.emit()
	return true


func _aim_zip_end(holder: Node3D, neighbors: Node, at: Vector3) -> void:
	if _ghost_path != CustomHole.ZIPLINE or _ghost == null:
		_build_ghost(holder, CustomHole.ZIPLINE)
	if _ghost == null:
		return
	_at = _zip_point(neighbors, at)
	var zip := _ghost as Zipline
	if zip == null:
		return
	_ghost.rotation.y = deg_to_rad(yaw)
	zip.span(zip_from, _at)
	var cable := zip.get_node_or_null("Cable")
	if cable != null:
		_fade(cable)
	_ghost.visible = hole.covers(_at)


func _zip_point(neighbors: Node, at: Vector3) -> Vector3:
	var half := Zipline.CELL * Zipline.DECK_CELLS * 0.5
	var deck := AABB(Vector3(-half, 0.0, -half), Vector3(half * 2.0, Zipline.DECK, half * 2.0))
	var others := GridSnap.neighbor_boxes(neighbors, _ghost)
	if surface_snap:
		return GridSnap.rest_on(at, GridSnap.column_top(at, space, height), deck, others)
	return GridSnap.place(at, deck, others)


func _surface_snapped(neighbors: Node, at: Vector3) -> Vector3:
	var top := GridSnap.column_top(at, space, height)
	if _ghost == null:
		return GridSnap.to_grid(Vector3(at.x, top, at.z))
	var turned := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at) * _hull()
	if turned.size == Vector3.ZERO:
		return GridSnap.to_grid(Vector3(at.x, top, at.z))
	return GridSnap.rest_on(at, top, turned, GridSnap.neighbor_boxes(neighbors, _ghost))


func _snapped(neighbors: Node, at: Vector3) -> Vector3:
	if _ghost == null:
		return GridSnap.to_grid(at)
	# Turned first, or a piece rotated off-axis would be measured across
	# the wrong side and stop short of its neighbour.
	var turned := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at) * _hull()
	if turned.size == Vector3.ZERO:
		return GridSnap.to_grid(at)
	return GridSnap.place(at, turned, GridSnap.neighbor_boxes(neighbors, _ghost))


func _hull() -> AABB:
	if _ghost == null:
		return AABB()
	return GridSnap.footprint_centered(GridSnap.local_aabb(_ghost))


func _build_ghost(holder: Node3D, path: String) -> void:
	_clear_ghost()
	_ghost = _preview_node(path)
	if _ghost == null:
		return
	_ghost_path = path
	_ghost.name = "Ghost"
	# Faded after it is in the tree: a gun pickup builds its mesh in _ready, so
	# fading any earlier would leave it solid.
	holder.add_child(_ghost)
	_ghost.process_mode = Node.PROCESS_MODE_DISABLED
	for group in ["golf_carts", "transit_boost", "ziplines"]:
		if _ghost.is_in_group(group):
			_ghost.remove_from_group(group)
	_fade(_ghost)


## A group has no scene of its own, so its first piece stands in for it.
func _preview_node(path: String) -> Node3D:
	if not HoleStore.is_structure(path):
		return CustomOverlay.instantiate(path)
	var parts := HoleStore.structure_parts(path)
	if parts.is_empty():
		return null
	return CustomOverlay.instantiate(String(parts[0][CustomHole.PATH]))


func _fade(node: Node) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		var ghost := StandardMaterial3D.new()
		ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ghost.albedo_color = Color(Palette.CYAN, GHOST_ALPHA)
		mesh.material_override = ghost
	var body := node as CollisionObject3D
	if body != null:
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_fade(child)


func _clear_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_path = ""
