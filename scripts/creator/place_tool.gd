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
## True after Circle locks the lava tiles and the crosshair is picking a stand-back.
var lava_respawning := false
## First corner of a lava fill, or INF while the next R2 still picks a start.
var lava_from := Vector3.INF
## Which sandtrap is having its circle drawn, or -1 for none.
var sanding := -1
## True while the bowl depth is being drawn after the circle is set.
var digging := false
var sand_radius := SandTrap.DEFAULT_RADIUS
var sand_depth := SandTrap.DEFAULT_DEPTH
## True after a sandtrap lands or leaves, so the creator rebuilds the ground.
var wants_rebuild := false
## Where down the hole the crosshair currently is, filled in by the creator
## because it is the only side that holds the built HoleData.
var aim_gate := 0.0
## Lens position while aiming, so a tunnel carve can face the next bank cell
## instead of the far point hanging at camera reach.
var look_from := Vector3.INF
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
var pond: PlaceWater
var tunnel: DigTunnel

var _ghost: Node3D
var _ghost_path := ""
var _at := Vector3.ZERO


func _init(for_hole: CustomHole) -> void:
	hole = for_hole
	pond = PlaceWater.new(self)
	tunnel = DigTunnel.new(self)


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
	var listed := PackedStringArray(PieceCatalog.entries(shelf()))
	if shelf() == PieceCatalog.PROPS:
		listed.append(CustomHole.SANDTRAP)
	return listed


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
	if CustomHole.is_sandtrap(path):
		return "SANDTRAP"
	return HoleStore.structure_title(path) if HoleStore.is_structure(path) else PieceCatalog.label_for(path)


## Same shelf the player is standing on, listed the way Fairway lists shapes.
func labels() -> PackedStringArray:
	var out: PackedStringArray = []
	for path in pieces():
		if CustomHole.is_spawn(path):
			out.append("ZOMBIE SPAWN")
		elif CustomHole.is_sandtrap(path):
			out.append("SANDTRAP")
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
	if is_zipping() or is_roaming() or is_lava_respawning() or is_lava_filling() or is_sanding() or pond.is_busy() or tunnel.is_dragging():
		return
	category = posmod(category + delta, shelves().size())
	picked = 0
	_clear_ghost()


func step_piece(delta: int) -> void:
	if is_zipping() or is_roaming() or is_lava_respawning() or is_lava_filling() or is_sanding() or pond.is_busy() or tunnel.is_dragging():
		return
	var listed := pieces()
	if listed.is_empty():
		return
	picked = posmod(picked + delta, listed.size())
	_clear_ghost()


func turn(steps: int) -> void:
	# Yaw means nothing to a corridor, so while digging the same buttons size it.
	if tunnel.grow(float(steps)):
		return
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
func aim(holder: Node3D, neighbors: Node, at: Vector3, from := Vector3.INF) -> void:
	look_from = from if from.is_finite() else at
	if is_zipping():
		_aim_zip_end(holder, neighbors, at)
		return
	if is_hunting():
		_aim_aggro(at)
		return
	if is_roaming():
		_aim_roam(at)
		return
	if is_lava_respawning():
		if not _holding:
			_at = _stand_at(at)
		_clear_ghost()
		return
	if is_lava_filling():
		if not _holding:
			_at = _stand_at(at)
		_clear_ghost()
		return
	if tunnel.is_dragging():
		_at = at
		_clear_ghost()
		return
	if pond.is_depthing() or pond.is_filling():
		if not _holding:
			_at = _water_aim(at)
		_clear_ghost()
		return
	if is_digging():
		_aim_sand_depth(at)
		return
	if is_sanding():
		_aim_sand_radius(at)
		return
	var path := picked_path()
	if is_gating() or path.is_empty():
		_clear_ghost()
		return
	if CustomHole.is_spawn(path):
		if not _holding:
			_clear_ghost()
			_at = _stand_at(at)
		return
	if CustomHole.is_sandtrap(path):
		if not _holding:
			_clear_ghost()
			_at = _free_ground(at)
		return
	if CustomHole.is_water(path):
		if tunnel.can_dig():
			_at = at
			_clear_ghost()
			return
		if not _holding:
			_at = _water_aim(at)
		if path != _ghost_path:
			_build_ghost(holder, path)
		if _ghost == null:
			return
		_ghost.rotation.y = deg_to_rad(yaw)
		_ghost.position = GridSnap.anchored_at(_ghost, _stand_at(_at), yaw)
		_ghost.visible = hole.covers(_at)
		return
	if CustomHole.is_lava(path):
		if not _holding:
			_at = _stand_at(at)
		if path != _ghost_path:
			_build_ghost(holder, path)
		if _ghost == null:
			return
		_ghost.rotation.y = deg_to_rad(yaw)
		_ghost.position = GridSnap.anchored_at(_ghost, _at, yaw)
		_ghost.visible = hole.covers(_at)
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
	_ghost.position = (
		GunPickup.sit_at(_ghost, _at, yaw)
		if CustomHole.is_weapon(path)
		else GridSnap.anchored_at(_ghost, _at, yaw)
	)
	_ghost.visible = hole.covers(_at)
	# #region agent log
	_dbg_place_ghost(path)
	# #endregion


func place() -> bool:
	if is_zipping():
		return _set_zip_end()
	if is_lava_respawning():
		return set_lava_respawn()
	if is_lava_filling():
		return _fill_lava()
	if pond.is_depthing():
		if pond.lock_depth():
			changed.emit()
			return true
		return false
	if pond.is_filling():
		if pond.fill():
			changed.emit()
			return true
		return false
	if tunnel.can_dig():
		if tunnel.dig():
			changed.emit()
			return true
		return false
	if is_digging():
		return set_sand_depth()
	if is_sanding():
		return set_sand_radius()
	if is_roaming():
		return false
	var path := picked_path()
	if path.is_empty():
		return false
	if not hole.covers(_at):
		refused.emit("OFF THE FAIRWAY. NOTHING OUT THERE IS REACHABLE.")
		return false
	if CustomHole.is_lava(path):
		if Lava.would_cover_respawn(hole.placements, _at):
			refused.emit("NOT ON A RESPAWN. THAT WOULD LOOP.")
			return false
		lava_from = _at
		_holding = false
		_clear_ghost()
		return true
	if CustomHole.is_water(path):
		return pond.begin_fill()
	if CustomHole.is_sandtrap(path):
		hole.add_placement(path, GridSnap.stored_offset(_at, height), yaw)
		_begin_sand(hole.placements.size() - 1)
		changed.emit()
		return true
	if CustomHole.is_zipline(path):
		zip_from = _at
		_holding = false
		return true
	hole.add_placement(path, GridSnap.stored_offset(_at, height), yaw)
	# #region agent log
	_dbg_drop(path)
	# #endregion
	# A gun asks for its line straight away. Walking away leaves it live for the
	# whole hole, which is the sane default.
	_holding = false
	if CustomHole.is_weapon(path):
		gating = hole.placements.size() - 1
	elif CustomHole.is_spawn(path):
		_begin_roam(hole.placements.size() - 1)
	elif CustomHole.is_windmill(path):
		hole.placements[hole.placements.size() - 1][CustomHole.SPIN] = CartPathWindmill.SPIN_DEFAULT
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
	if (
		_holding or is_gating() or is_zipping() or is_roaming()
		or is_lava_respawning() or is_lava_filling() or is_lava_pending()
		or is_sanding() or pond.is_busy() or pond.is_pending() or tunnel.is_dragging()
	):
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


func is_sanding() -> bool:
	return sanding >= 0 and sanding < hole.placements.size()


func is_digging() -> bool:
	return digging and is_sanding()


func is_lava_pending() -> bool:
	return CustomHole.is_lava(picked_path()) and not lava_respawning and not open_lava().is_empty()


func is_lava_respawning() -> bool:
	return lava_respawning


func is_lava_filling() -> bool:
	return lava_from.is_finite()


func lava_cells() -> Array[Vector3]:
	if not is_lava_filling():
		return []
	return Lava.cells_between(lava_from, _at)


func lava_stand_ok() -> bool:
	return hole.covers(_at) and not _lava_covers_stand(_at)


func lava_fill_ok() -> bool:
	if not is_lava_filling():
		return false
	var any := false
	for cell in lava_cells():
		var at := _stand_at(cell)
		if Lava.would_cover_respawn(hole.placements, at):
			return false
		if hole.covers(at) and not Lava.covers_any(hole.placements, at):
			any = true
	return any


func clear_lava_fill() -> bool:
	if not is_lava_filling():
		return false
	lava_from = Vector3.INF
	return true


func open_lava() -> Array[int]:
	var out: Array[int] = []
	for i in hole.placements.size():
		if not CustomHole.is_lava(String(hole.placements[i][CustomHole.PATH])):
			continue
		if not CustomHole.has_respawn(hole.placements[i]):
			out.append(i)
	return out


## Circle after the tiles are down: the crosshair is now picking the stand-back.
func confirm_lava() -> bool:
	if is_lava_filling() or not is_lava_pending():
		return false
	lava_respawning = true
	_holding = false
	_clear_ghost()
	return true


func set_lava_respawn() -> bool:
	if not is_lava_respawning():
		return false
	if not hole.covers(_at):
		refused.emit("OFF THE FAIRWAY. NOTHING OUT THERE IS REACHABLE.")
		return false
	if _lava_covers_stand(_at):
		refused.emit("NOT ON THE LAVA. THAT WOULD LOOP.")
		return false
	var stored := GridSnap.stored_offset(_at, height)
	for i in open_lava():
		hole.placements[i][CustomHole.RESPAWN] = stored
	lava_respawning = false
	changed.emit()
	return true


func clear_lava_aim() -> bool:
	if not is_lava_respawning():
		return false
	lava_respawning = false
	return true


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


func finish_spin(deg: float) -> bool:
	var index := hole.placements.size() - 1
	if index < 0:
		return false
	if not CustomHole.is_windmill(String(hole.placements[index][CustomHole.PATH])):
		return false
	hole.placements[index][CustomHole.SPIN] = CartPathWindmill.clamp_spin(deg)
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


func set_sand_radius() -> bool:
	if not is_sanding() or is_digging():
		return false
	hole.placements[sanding][CustomHole.RADIUS] = sand_radius
	digging = true
	sand_depth = SandTrap.DEFAULT_DEPTH
	hole.placements[sanding][CustomHole.DEPTH] = sand_depth
	return true


func set_sand_depth() -> bool:
	if not is_digging():
		return false
	hole.placements[sanding][CustomHole.RADIUS] = sand_radius
	hole.placements[sanding][CustomHole.DEPTH] = sand_depth
	sanding = -1
	digging = false
	wants_rebuild = true
	changed.emit()
	return true


func abort_sand() -> bool:
	if not is_sanding():
		return false
	var index := sanding
	sanding = -1
	digging = false
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
		# XZ only: the camera hangs in the air and a snapped gun sits on the
		# grass, so a 3D compare misses the thing you are looking straight at.
		var pos := _world_pos(hole.placements[i][CustomHole.POSITION])
		var distance := Vector2(pos.x - at.x, pos.z - at.z).length()
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
	if CustomHole.is_lava(String(hole.placements[index][CustomHole.PATH])):
		_erase_lava_pool(index)
	elif (
		CustomHole.is_water(String(hole.placements[index][CustomHole.PATH]))
		or CustomHole.is_tunnel(String(hole.placements[index][CustomHole.PATH]))
	):
		pond.erase_pool(index)
	else:
		if CustomHole.is_sandtrap(String(hole.placements[index][CustomHole.PATH])):
			wants_rebuild = true
		hole.remove_placement(index)
	changed.emit()
	return true


## The tiles confirmed with one stand-back come off together, so a pool is one
## take-back instead of a hunt through every cell.
func _erase_lava_pool(index: int) -> void:
	var pool := CustomHole.lava_pool(hole.placements, index)
	pool.reverse()
	for i in pool:
		hole.remove_placement(i)
	if open_lava().is_empty():
		lava_respawning = false


func lava_pool_at(at: Vector3) -> Array[int]:
	var index := nearest(at)
	if index < 0:
		return []
	return CustomHole.lava_pool(hole.placements, index)


func nearest(at: Vector3, within := 6.0) -> int:
	var best := -1
	var closest := within
	for i in hole.placements.size():
		var entry: Dictionary = hole.placements[i]
		var distance := _world_pos(entry[CustomHole.POSITION]).distance_to(at)
		if CustomHole.has_end(entry):
			distance = minf(distance, _world_pos(entry[CustomHole.END]).distance_to(at))
		if CustomHole.is_sandtrap(String(entry.get(CustomHole.PATH, ""))):
			var span := Vector2(
				entry[CustomHole.POSITION].x - at.x, entry[CustomHole.POSITION].z - at.z
			).length()
			if span <= SandTrap.radius_of(entry):
				distance = 0.0
		# A tunnel is a line, so it answers from anywhere along the run.
		if CustomHole.is_tunnel(String(entry.get(CustomHole.PATH, ""))):
			var near := WaterTunnel.closest_on(entry, at)
			if not near.is_empty():
				distance = minf(distance, float(near["distance"]))
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
	if is_sanding():
		abort_sand()
	gating = -1
	zip_from = Vector3.INF
	lava_from = Vector3.INF
	lava_respawning = false
	sanding = -1
	digging = false
	pond.drop()
	tunnel.drop()
	_holding = false
	_clear_ghost()


func summary() -> String:
	if is_gating():
		return "DRAW THE LINE   R2 TO SET   L2 FOR NO LINE"
	if is_zipping():
		return "PLACE THE LOWER END   R2 TO SET   L2 TO CANCEL"
	if is_hunting():
		return "SET THE CHASE   %d M   R2 TO SET   L2 TO CANCEL" % roundi(aggro_radius)
	if is_roaming():
		return "SET THE YARD   %d M   R2 TO SET   L2 TO CANCEL" % roundi(roam_radius)
	if is_lava_respawning():
		return "SET THE RESPAWN   R2 TO SET   NOT ON THE LAVA   L2 TO ADD TILES"
	if is_lava_filling():
		return "FILL LAVA   %d TILES   R2 TO SET   L2 TO CANCEL" % lava_cells().size()
	if is_lava_pending():
		return "PLACE LAVA   CIRCLE WHEN DONE   %d TILES" % open_lava().size()
	if pond.is_depthing():
		return "SET DEPTH   %.1f M   FLY DOWN   R2 TO LOCK THE FLOOR" % pond.preview_depth()
	if pond.is_filling():
		return "FILL WATER   %d TILES   R2 TO SET   L2 TO CANCEL" % pond.cells().size()
	if pond.is_pending():
		return "PLACE WATER   CIRCLE TO SET THE DEPTH   %d TILES" % pond.open().size()
	if tunnel.is_dragging():
		return "DIGGING   %.1f M BORE   R2 TURNS   L2 BACKS UP   REACH WATER TO FINISH" % tunnel.bore
	if tunnel.can_dig():
		return "DIG TUNNEL   %.1f M BORE   R2 STARTS   D-PAD SIZES IT" % tunnel.bore
	if CustomHole.is_water(picked_path()):
		return "R2 ON LAND STARTS ANOTHER POND   SWIM UNDER A POND TO DIG"
	if is_digging():
		return "SET DEPTH   %.1f M   R2 TO SET   L2 TO CANCEL" % sand_depth
	if is_sanding():
		return "SET THE CIRCLE   %d M   R2 TO SET   L2 TO CANCEL" % roundi(sand_radius)
	if is_holding():
		return "HOLDING   R2 TO SET   L2 TO MOVE AGAIN"
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


func _begin_sand(index: int) -> void:
	sanding = index
	digging = false
	sand_radius = SandTrap.DEFAULT_RADIUS
	sand_depth = SandTrap.DEFAULT_DEPTH
	var entry: Dictionary = hole.placements[index]
	entry[CustomHole.RADIUS] = sand_radius
	entry[CustomHole.DEPTH] = sand_depth


func _free_ground(at: Vector3) -> Vector3:
	var point := Vector3(at.x, 0.0, at.z)
	point.y = height.height_at(point.x, point.z) if height != null else 0.0
	return point


func _aim_sand_radius(at: Vector3) -> void:
	sand_radius = SandTrap.clamp_radius(_sand_span(at))


func _aim_sand_depth(at: Vector3) -> void:
	sand_depth = SandTrap.clamp_depth(_sand_span(at))


func _sand_span(at: Vector3) -> float:
	_clear_ghost()
	_at = _free_ground(at)
	if not is_sanding():
		return 0.0
	var origin: Vector3 = hole.placements[sanding][CustomHole.POSITION]
	return Vector2(_at.x - origin.x, _at.z - origin.z).length()


func _grounded(at: Vector3) -> Vector3:
	var snapped := GridSnap.to_grid(at)
	snapped.y = height.height_at(snapped.x, snapped.z) if height != null else 0.0
	return snapped


## Grass or the top of whatever is already standing in that column.
func _stand_at(at: Vector3) -> Vector3:
	var snapped := GridSnap.to_grid(at)
	snapped.y = GridSnap.column_top(at, space, height)
	return snapped


func _water_aim(at: Vector3) -> Vector3:
	var snapped := GridSnap.to_grid(at)
	var top := GridSnap.column_top(at, space, height)
	if at.y < top - 0.35:
		return Vector3(snapped.x, at.y, snapped.z)
	return Vector3(snapped.x, top, snapped.z)


func is_water_filling() -> bool:
	return pond.is_filling()


func is_water_pending() -> bool:
	return pond.is_pending()


func is_water_depthing() -> bool:
	return pond.is_depthing()


func water_cells() -> Array[Vector3]:
	return pond.cells()


func water_fill_ok() -> bool:
	return pond.fill_ok()


func confirm_water() -> bool:
	return pond.confirm()


func set_water_depth() -> bool:
	if not pond.lock_depth():
		return false
	changed.emit()
	return true


func clear_water_fill() -> bool:
	return pond.clear_fill()


func clear_water_depth() -> bool:
	return pond.clear_depth()


func undo_dig() -> bool:
	if not tunnel.undo():
		return false
	changed.emit()
	return true


func is_digging_tunnel() -> bool:
	return tunnel.is_dragging()


## True while the pond flow owns R2, so a dig cannot start over the top of one.
## Asked through here rather than off PlaceWater, which keeps the two helpers
## from having to resolve each other.
func water_pending() -> bool:
	return pond.is_busy() or not pond.open().is_empty()


## What the last R2 dropped, so the creator can say what just happened.
func last_path() -> String:
	if hole.placements.is_empty():
		return ""
	return String(hole.placements[hole.placements.size() - 1][CustomHole.PATH])


func water_pool_at(at: Vector3) -> Array[int]:
	var index := nearest(at)
	if index < 0:
		return []
	return CustomHole.water_pool(hole.placements, index)


func _lava_covers_stand(at: Vector3) -> bool:
	for entry in hole.placements:
		if not CustomHole.is_lava(String(entry.get(CustomHole.PATH, ""))):
			continue
		if Lava.covers_stand(_world_pos(entry[CustomHole.POSITION]), at):
			return true
	return false


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


func _fill_lava() -> bool:
	if not is_lava_filling():
		return false
	var path := picked_path()
	if not CustomHole.is_lava(path):
		return false
	var added := 0
	for cell in lava_cells():
		var at := _stand_at(cell)
		if Lava.would_cover_respawn(hole.placements, at):
			refused.emit("NOT ON A RESPAWN. THAT WOULD LOOP.")
			return false
		if not hole.covers(at) or Lava.covers_any(hole.placements, at):
			continue
		hole.add_placement(path, GridSnap.stored_offset(at, height), yaw)
		added += 1
	if added <= 0:
		refused.emit("THAT TILE IS ALREADY LAVA.")
		return false
	lava_from = Vector3.INF
	_holding = false
	changed.emit()
	return true


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
	# Guns are not cell-tall pieces. Snapping Y onto the 1.35 m grid buries
	# them whenever the fairway is not sitting on a cell, and the mesh is
	# centered so the origin-on-grass pose already puts half of it in the dirt.
	if CustomHole.is_weapon(picked_path()):
		return Vector3(snappedf(at.x, GridSnap.CELL), top, snappedf(at.z, GridSnap.CELL))
	if _ghost == null:
		return GridSnap.to_grid(Vector3(at.x, top, at.z))
	var turned := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at) * _hull()
	if turned.size == Vector3.ZERO:
		return GridSnap.to_grid(Vector3(at.x, top, at.z))
	var others := GridSnap.neighbor_boxes(neighbors, _ghost)
	var result := GridSnap.rest_on(at, top, turned, others)
	# #region agent log
	_dbg_snap("D", "surface", at, result, turned, others, top)
	# #endregion
	return result


func _snapped(neighbors: Node, at: Vector3) -> Vector3:
	if _ghost == null:
		return GridSnap.to_grid(at)
	# Turned first, or a piece rotated off-axis would be measured across
	# the wrong side and stop short of its neighbour.
	var turned := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at) * _hull()
	if turned.size == Vector3.ZERO:
		return GridSnap.to_grid(at)
	var others := GridSnap.neighbor_boxes(neighbors, _ghost)
	var result := GridSnap.place(at, turned, others)
	# #region agent log
	_dbg_snap("A", "grid", at, result, turned, others, -1.0)
	# #endregion
	return result


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
	for group in ["golf_carts", "transit_boost", "ziplines", "lava", "water"]:
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
var _dbg_snap_key := ""
var _dbg_snap_n := 0


func _dbg_snap(
	hid: String, mode: String, at: Vector3, result: Vector3, turned: AABB, others: Array, top: float
) -> void:
	var hull := _hull()
	var key := "%s|%s|%s|%d" % [mode, _dbg_v3(result), snappedf(yaw, 1.0), others.size()]
	if key == _dbg_snap_key:
		return
	_dbg_snap_key = key
	_dbg_snap_n += 1
	if _dbg_snap_n > 160:
		return
	_dbg_file(hid, "place_tool.gd:_snapped", "aim snap", {
		"mode": mode,
		"path": picked_path().get_file(),
		"surface": surface_snap,
		"yaw": snappedf(yaw, 0.1),
		"aim": _dbg_v3(at),
		"result": _dbg_v3(result),
		"top": snappedf(top, 0.01),
		"others": others.size(),
		"hull": _dbg_v3(hull.size),
		"turned": _dbg_v3(turned.size),
		"inflated": turned.size.length() - hull.size.length() > 0.05,
		"ghost": _ghost_path.get_file(),
		"holding": _holding,
	})


func _dbg_drop(path: String) -> void:
	_dbg_file("F", "place_tool.gd:place", "dropped", {
		"path": path.get_file(),
		"at": _dbg_v3(_at),
		"yaw": snappedf(yaw, 0.1),
		"surface": surface_snap,
		"covers": hole.covers(_at),
	})


func _dbg_v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


func _dbg_file(hid: String, loc: String, msg: String, data: Dictionary) -> void:
	var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-ed7827.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-ed7827.log", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"sessionId": "ed7827",
		"hypothesisId": hid,
		"location": loc,
		"message": msg,
		"data": data,
		"timestamp": Time.get_ticks_msec(),
	}))
	f.close()


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
