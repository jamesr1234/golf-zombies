class_name PlaceTool
extends RefCounted
## Drops obstacles, structures and saved groups onto the hole. The ghost under
## the crosshair snaps to the same 1.35 m grid the editor plugin uses, so a
## piece placed in game meets its neighbours as flush as one placed by hand.

signal changed
signal refused(reason: String)

const NAME := "PLACE"
const SPAWNS := "spawns"
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
## Which spawn is having its yard drawn, or -1 for none.
var roaming := -1
var roam_radius := SpawnPack.DEFAULT_RADIUS
## True while the chase ring is being drawn after the yard is set.
var hunting := false
var aggro_radius := SpawnPack.DEFAULT_AGGRO
## Where down the hole the crosshair currently is, filled in by the creator
## because it is the only side that holds the built HoleData.
var aim_gate := 0.0
## When set, the ghost sits on the fairway or on top of whatever is already
## standing in that column, instead of hanging at the camera's reach.
var surface_snap := false
## Right-stick click turns this off so a piece can be nudged off the 45s, then
## back on to drop it onto the same angles again.
var yaw_snap := true
## Circle parks the ghost so the camera can walk around it. R2 still drops it.
var _holding := false
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
	out.append(SPAWNS)
	out.append("groups")
	return out


func shelf() -> String:
	return shelves()[posmod(category, shelves().size())]


func pieces() -> PackedStringArray:
	if shelf() == "groups":
		return HoleStore.list_structures()
	if shelf() == SPAWNS:
		return PackedStringArray([CustomHole.SPAWN])
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
	if CustomHole.is_spawn(path):
		return "ZOMBIE SPAWN"
	return HoleStore.structure_title(path) if HoleStore.is_structure(path) else PieceCatalog.label_for(path)


## Same shelf the player is standing on, listed the way Fairway lists shapes.
func labels() -> PackedStringArray:
	var out: PackedStringArray = []
	for path in pieces():
		if CustomHole.is_spawn(path):
			out.append("ZOMBIE SPAWN")
		elif HoleStore.is_structure(path):
			out.append(HoleStore.structure_title(path))
		else:
			out.append(PieceCatalog.label_for(path))
	return out


func picked_index() -> int:
	var listed := pieces()
	if listed.is_empty():
		return -1
	return posmod(picked, listed.size())


func step_shelf(delta: int) -> void:
	if is_zipping() or is_roaming():
		return
	category = posmod(category + delta, shelves().size())
	picked = 0
	_clear_ghost()


func step_piece(delta: int) -> void:
	if is_zipping() or is_roaming():
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
	if is_hunting():
		_aim_aggro(at)
		return
	if is_roaming():
		_aim_roam(at)
		return
	var path := picked_path()
	if is_gating() or path.is_empty():
		_clear_ghost()
		return
	if CustomHole.is_spawn(path):
		if not _holding:
			_clear_ghost()
			_at = _grounded(at)
		return
	if path != _ghost_path:
		_build_ghost(holder, path)
	if _ghost == null:
		return
	if CustomHole.is_zipline(path):
		var zip := _ghost as Zipline
		if zip != null:
			zip.collapse_end()
	if not _holding:
		_at = _surface_snapped(neighbors, at) if surface_snap else _snapped(neighbors, at)
	_ghost.rotation.y = deg_to_rad(yaw)
	_ghost.position = GridSnap.anchored_at(_ghost, _at, yaw)
	_ghost.visible = hole.covers(_at)
	# #region agent log
	_dbg_place_ghost(path)
	# #endregion


func place() -> bool:
	if is_zipping():
		return _set_zip_end()
	if is_roaming():
		return false
	var path := picked_path()
	if path.is_empty():
		return false
	if not hole.covers(_at):
		refused.emit("OFF THE FAIRWAY. NOTHING OUT THERE IS REACHABLE.")
		return false
	if CustomHole.is_zipline(path):
		zip_from = _at
		_holding = false
		return true
	hole.add_placement(path, GridSnap.stored_offset(_at, height), yaw)
	# A gun asks for its line straight away. Walking away leaves it live for the
	# whole hole, which is the sane default.
	_holding = false
	if CustomHole.is_weapon(path):
		gating = hole.placements.size() - 1
	elif CustomHole.is_spawn(path):
		_begin_roam(hole.placements.size() - 1)
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


func is_holding() -> bool:
	return _holding


## Park the ghost where it is. The camera can walk around it; R2 still places.
func hold() -> bool:
	if _holding or is_gating() or is_zipping() or is_roaming():
		return false
	if picked_path().is_empty():
		refused.emit("NOTHING TO PLACE")
		return false
	if not hole.covers(_at):
		refused.emit("OFF THE FAIRWAY. NOTHING OUT THERE IS REACHABLE.")
		return false
	_holding = true
	return true


func release_hold() -> bool:
	if not _holding:
		return false
	_holding = false
	return true


func is_gating() -> bool:
	return gating >= 0 and gating < hole.placements.size()


func is_roaming() -> bool:
	return roaming >= 0 and roaming < hole.placements.size()


func is_hunting() -> bool:
	return hunting and is_roaming()


func set_roam() -> bool:
	if not is_roaming() or is_hunting():
		return false
	hole.placements[roaming][CustomHole.RADIUS] = roam_radius
	hunting = true
	aggro_radius = SpawnPack.DEFAULT_AGGRO
	hole.placements[roaming][CustomHole.AGGRO] = aggro_radius
	return true


func set_aggro() -> bool:
	if not is_hunting():
		return false
	hole.placements[roaming][CustomHole.AGGRO] = aggro_radius
	return true


func finish_spawn(counts: Dictionary) -> bool:
	if not is_roaming():
		return false
	var clamped := SpawnPack.clamp_counts(counts)
	if SpawnPack.total(clamped) <= 0:
		return false
	hole.placements[roaming][CustomHole.COUNTS] = clamped
	hole.placements[roaming][CustomHole.AGGRO] = aggro_radius
	roaming = -1
	hunting = false
	changed.emit()
	return true


func abort_spawn() -> bool:
	if not is_roaming():
		return false
	var index := roaming
	roaming = -1
	hunting = false
	if index >= 0 and index < hole.placements.size():
		hole.remove_placement(index)
	changed.emit()
	return true


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
	# #region agent log
	var _cands: Array = []
	for i in hole.placements.size():
		var _p: Vector3 = hole.placements[i][CustomHole.POSITION]
		var _lifted := _p
		if height != null:
			_lifted = Vector3(_p.x, height.height_at(_p.x, _p.z) + _p.y, _p.z)
		_cands.append({
			"i": i,
			"path": String(hole.placements[i][CustomHole.PATH]).get_file(),
			"stored": [snappedf(_p.x, 0.01), snappedf(_p.y, 0.01), snappedf(_p.z, 0.01)],
			"lifted": [snappedf(_lifted.x, 0.01), snappedf(_lifted.y, 0.01), snappedf(_lifted.z, 0.01)],
			"d_stored": snappedf(_p.distance_to(at), 0.01),
			"d_lifted": snappedf(_lifted.distance_to(at), 0.01),
			"dxz": snappedf(Vector2(_p.x - at.x, _p.z - at.z).length(), 0.01),
		})
		_cands.sort_custom(func(a, b): return float(a["d_lifted"]) < float(b["d_lifted"]))
	if _cands.size() > 8:
		_cands.resize(8)
	var _f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-2b6f56.log", FileAccess.READ_WRITE)
	if _f == null:
		_f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-2b6f56.log", FileAccess.WRITE)
	if _f != null:
		_f.seek_end()
		_f.store_line(JSON.stringify({
			"sessionId": "2b6f56", "runId": "post-fix", "hypothesisId": "B",
			"location": "place_tool.gd:erase",
			"message": "erase nearest scan", "timestamp": Time.get_ticks_msec(),
			"data": {
				"aim": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)],
				"ghost_at": [snappedf(_at.x, 0.01), snappedf(_at.y, 0.01), snappedf(_at.z, 0.01)],
				"picked": index,
				"count": hole.placements.size(),
				"within": 6.0,
				"closest": _cands,
			},
		}))
		_f.close()
	# #endregion
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
		var distance := _world_pos(entry[CustomHole.POSITION]).distance_to(at)
		if CustomHole.has_end(entry):
			distance = minf(distance, _world_pos(entry[CustomHole.END]).distance_to(at))
		if distance < closest:
			closest = distance
			best = i
	return best


func _world_pos(stored: Vector3) -> Vector3:
	if height == null:
		return stored
	return Vector3(stored.x, height.height_at(stored.x, stored.z) + stored.y, stored.z)


## Leaving the tool abandons a half-drawn line without changing what is stored.
func release() -> void:
	if is_roaming():
		abort_spawn()
	gating = -1
	zip_from = Vector3.INF
	_holding = false
	_clear_ghost()


func summary() -> String:
	if is_gating():
		return "DRAW THE LINE   CLICK TO SET   RIGHT CLICK FOR NO LINE"
	if is_zipping():
		return "PLACE THE LOWER END   CLICK TO SET   RIGHT CLICK TO CANCEL"
	if is_hunting():
		return "SET THE CHASE   %d M   CLICK TO SET   RIGHT CLICK TO CANCEL" % roundi(aggro_radius)
	if is_roaming():
		return "SET THE YARD   %d M   CLICK TO SET   RIGHT CLICK TO CANCEL" % roundi(roam_radius)
	if is_holding():
		return "HOLDING   CLICK TO SET   RIGHT CLICK TO MOVE AGAIN"
	var lock := ""
	if surface_snap:
		lock += "   SURFACE SNAP"
	lock += "   YAW SNAP" if yaw_snap else "   FREE YAW"
	return "%s   %d PLACED   YAW %d%s" % [
		shelf().to_upper(), hole.placements.size(), roundi(yaw), lock
	]


func _begin_roam(index: int) -> void:
	roaming = index
	hunting = false
	roam_radius = SpawnPack.DEFAULT_RADIUS
	aggro_radius = SpawnPack.DEFAULT_AGGRO
	var entry: Dictionary = hole.placements[index]
	entry[CustomHole.RADIUS] = roam_radius
	entry[CustomHole.AGGRO] = aggro_radius
	entry[CustomHole.COUNTS] = SpawnPack.empty_counts()


func _grounded(at: Vector3) -> Vector3:
	var snapped := GridSnap.to_grid(at)
	snapped.y = height.height_at(snapped.x, snapped.z) if height != null else 0.0
	return snapped


func _aim_span(at: Vector3) -> float:
	_clear_ghost()
	_at = _grounded(at)
	if not is_roaming():
		return 0.0
	var origin: Vector3 = hole.placements[roaming][CustomHole.POSITION]
	return Vector2(_at.x - origin.x, _at.z - origin.z).length()


func _aim_roam(at: Vector3) -> void:
	roam_radius = SpawnPack.clamp_radius(_aim_span(at))


func _aim_aggro(at: Vector3) -> void:
	aggro_radius = SpawnPack.clamp_aggro(_aim_span(at))


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
		ghost.cull_mode = BaseMaterial3D.CULL_DISABLED
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


# #region agent log
var _dbg_n := 0


func _dbg_place_ghost(path: String) -> void:
	_dbg_n += 1
	if _dbg_n > 200 or (_dbg_n > 1 and _dbg_n % 20 != 0):
		return
	var cull := -1
	var meshes := 0
	var leds := 0
	if _ghost != null:
		for node in _ghost.find_children("*", "MeshInstance3D", true, false):
			meshes += 1
			if String(node.name) == "Leds":
				leds += 1
			var mat := (node as MeshInstance3D).material_override as StandardMaterial3D
			if mat != null:
				cull = mat.cull_mode
	var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-f6d8e1.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-f6d8e1.log", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"sessionId": "f6d8e1", "runId": "post-fix", "hypothesisId": "J",
		"location": "place_tool.gd:aim",
		"message": "place ghost cull and meshes",
		"timestamp": Time.get_ticks_msec(),
		"data": {
			"path": path.get_file(),
			"yaw": snappedf(yaw, 0.1),
			"visible": _ghost.visible if _ghost != null else false,
			"cull_mode": cull,
			"meshes": meshes,
			"leds": leds,
		},
	}))
	f.close()
# #endregion
