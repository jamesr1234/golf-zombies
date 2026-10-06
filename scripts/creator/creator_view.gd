class_name CreatorView
extends RefCounted
## What the creator shows for the tool in hand: the neon guides over the hole
## and the readouts down the side. Split off creator_mode.gd so that file stays
## about what the builder is doing rather than how it is drawn.

var _mode: CreatorMode
var _marks: CreatorMarks
var _ui: CreatorUi
var _fairway: FairwayTool
var _place: PlaceTool
var _group: GroupTool


func _init(
	mode: CreatorMode, marks: CreatorMarks, ui: CreatorUi,
	fairway: FairwayTool, place: PlaceTool, group: GroupTool
) -> void:
	_mode = mode
	_marks = marks
	_ui = ui
	_fairway = fairway
	_place = place
	_group = group


func draw(data: HoleData) -> void:
	var hole := _mode.hole
	_marks.begin()
	match _mode.tool:
		CreatorMode.Tool.FAIRWAY:
			var ends := _fairway.preview()
			_marks.ghost_segment(
				ends[0], ends[1], hole.width(),
				hole.can_append(_fairway.picked)
			)
			# #region agent log
			_dbg_fairway(data, hole, ends)
			# #endregion
		CreatorMode.Tool.GROUP:
			_marks.view_ring(
				_group.center(), _group.radius, Palette.AMBER, _view_camera()
			)
			for i in hole.placements.size():
				if _group.is_selected(i):
					_marks.marker(hole.placements[i][CustomHole.POSITION], Palette.LIME)
		CreatorMode.Tool.PLACE:
			_draw_gates(data, hole)
			_draw_zip()
			_draw_spawns(hole)
			_draw_lava(hole)
			_draw_water(hole)
			_draw_sand(hole)
	_marks.finish()


func refresh() -> void:
	var current := tool_handler()
	_ui.show_hole(_mode.hole, current.label(), current.summary(), picked_label())
	match _mode.tool:
		CreatorMode.Tool.FAIRWAY:
			_ui.show_palette(fairway_labels(), _fairway.picked, _fairway.allowed())
		CreatorMode.Tool.PLACE:
			if (
				_place.is_gating() or _place.is_zipping() or _place.is_roaming()
				or _place.is_lava_respawning() or _place.is_lava_filling()
				or _place.is_sanding() or _place.is_water_filling()
				or _place.is_water_depthing() or _place.is_digging_tunnel()
			):
				_ui.show_palette(PackedStringArray(), -1, [])
			else:
				_ui.show_palette(
					_place.labels(), _place.picked_index(), [], _place.shelf().to_upper()
				)
		_:
			_ui.show_palette(PackedStringArray(), -1, [])


func tool_handler() -> RefCounted:
	match _mode.tool:
		CreatorMode.Tool.PLACE:
			return _place
		CreatorMode.Tool.GROUP:
			return _group
		_:
			return _fairway


func picked_label() -> String:
	match _mode.tool:
		CreatorMode.Tool.PLACE:
			if _place.is_gating():
				return "WEAPON LINE"
			if _place.is_zipping():
				return "ZIPLINE END"
			if _place.is_hunting():
				return "CHASE RANGE"
			if _place.is_roaming():
				return "SPAWN YARD"
			if _place.is_lava_respawning():
				return "LAVA RESPAWN"
			if _place.is_lava_filling():
				return "LAVA FILL"
			if _place.is_lava_pending():
				return "CONFIRM LAVA"
			if _place.is_water_depthing():
				return "WATER DEPTH"
			if _place.is_water_filling():
				return "WATER FILL"
			if _place.is_water_pending():
				return "CONFIRM WATER"
			if _place.is_digging_tunnel():
				return "DIGGING"
			if _place.tunnel.can_dig():
				return "DIG TUNNEL"
			if _place.is_digging():
				return "SAND DEPTH"
			if _place.is_sanding():
				return "SAND CIRCLE"
			if _place.is_holding():
				return "HOLDING"
			return _place.picked_label()
		CreatorMode.Tool.GROUP:
			return "READY TO MERGE" if _group.can_save() else "RING TWO OR MORE PIECES"
		_:
			return _fairway.picked_label()


func fairway_labels() -> PackedStringArray:
	var out: PackedStringArray = []
	for i in FairwayPiece.count():
		out.append(FairwayPiece.label_of(i))
	return out


func _view_camera() -> Camera3D:
	if not _marks.is_inside_tree():
		return null
	return _marks.get_viewport().get_camera_3d()


## Every weapon line already drawn, plus the one being dragged out right now.
func _draw_gates(data: HoleData, hole: CustomHole) -> void:
	for i in hole.placements.size():
		if i == _place.gating:
			continue
		_marks.gate_line(
			data, float(hole.placements[i].get(CustomHole.GATE, CustomHole.NO_GATE)),
			hole.width(), Palette.AMBER
		)
	if not _place.is_gating():
		return
	_marks.marker(hole.placements[_place.gating][CustomHole.POSITION], Palette.LIME)
	_marks.gate_line(data, _place.aim_gate, hole.width(), Palette.LIME)


func _draw_zip() -> void:
	if not _place.is_zipping():
		return
	_marks.marker(_place.zip_from, Palette.LIME)
	_marks.marker(_place.aim_at(), Palette.CYAN)
	_marks.line(_place.zip_from, _place.aim_at(), Palette.LIME)


func _draw_spawns(hole: CustomHole) -> void:
	for i in hole.placements.size():
		if not CustomHole.is_spawn(String(hole.placements[i][CustomHole.PATH])):
			continue
		var at: Vector3 = hole.placements[i][CustomHole.POSITION]
		var editing := i == _place.roaming
		var yard := _place.roam_radius if editing and not _place.is_hunting() else SpawnPack.clamp_radius(
			float(hole.placements[i].get(CustomHole.RADIUS, SpawnPack.DEFAULT_RADIUS))
		)
		var chase := _place.aggro_radius if editing and _place.is_hunting() else SpawnPack.clamp_aggro(
			float(hole.placements[i].get(CustomHole.AGGRO, SpawnPack.DEFAULT_AGGRO))
		)
		var yard_color := Palette.LIME if editing and not _place.is_hunting() else Palette.SUN
		var chase_color := Palette.LIME if editing and _place.is_hunting() else Palette.CYAN
		_marks.marker(at, yard_color if editing else Palette.SUN)
		_marks.ring(at, yard, yard_color)
		_marks.ring(at, chase, chase_color)
	if CustomHole.is_spawn(_place.picked_path()) and not _place.is_roaming():
		_marks.marker(_place.aim_at(), Palette.CYAN)


func _draw_lava(hole: CustomHole) -> void:
	var hover := _place.lava_pool_at(_place.aim_at())
	var hovering := {}
	for i in hover:
		hovering[i] = true
	var drawn := {}
	var seen: Array[Vector3] = []
	for i in hole.placements.size():
		var entry: Dictionary = hole.placements[i]
		if not CustomHole.is_lava(String(entry[CustomHole.PATH])):
			continue
		var tile: Vector3 = entry[CustomHole.POSITION]
		_marks.marker(tile, Palette.ORANGE if not CustomHole.has_respawn(entry) else Palette.LAVA)
		if CustomHole.has_respawn(entry):
			var point := CustomHole.respawn_of(entry)
			var already := false
			for other in seen:
				if other.distance_to(point) < 0.05:
					already = true
					break
			if not already:
				seen.append(point)
				_marks.marker(point, Palette.SUN)
		if drawn.has(i):
			continue
		var pool := CustomHole.lava_pool(hole.placements, i)
		var cells: Array[Vector3] = []
		var pending := false
		for j in pool:
			drawn[j] = true
			cells.append(hole.placements[j][CustomHole.POSITION])
			if not CustomHole.has_respawn(hole.placements[j]):
				pending = true
		var color := Palette.LIME if hovering.has(i) else (Palette.ORANGE if pending else Palette.LAVA)
		_marks.footprint(cells, color)
	if _place.is_lava_filling():
		var color := Palette.LIME if _place.lava_fill_ok() else Palette.SUN
		_marks.area(_place.lava_from, _place.aim_at(), color)
		return
	if not _place.is_lava_respawning():
		return
	var at := _place.aim_at()
	_marks.marker(at, Palette.SUN if not _place.lava_stand_ok() else Palette.LIME)


func _draw_water(hole: CustomHole) -> void:
	var hover := _place.water_pool_at(_place.aim_at())
	var hovering := {}
	for i in hover:
		hovering[i] = true
	var drawn := {}
	for i in hole.placements.size():
		var entry: Dictionary = hole.placements[i]
		if not CustomHole.is_water(String(entry[CustomHole.PATH])):
			continue
		var tile: Vector3 = entry[CustomHole.POSITION]
		var pending := not WaterTile.has_depth(entry)
		var color := Palette.ORANGE if pending else Palette.AZURE
		_marks.marker(tile, color)
		if drawn.has(i):
			continue
		var pool := CustomHole.water_pool(hole.placements, i)
		var cells: Array[Vector3] = []
		for j in pool:
			drawn[j] = true
			cells.append(hole.placements[j][CustomHole.POSITION])
		var rim := Palette.LIME if hovering.has(i) else color
		_marks.footprint(cells, rim)
	if _place.is_water_filling():
		var color := Palette.LIME if _place.water_fill_ok() else Palette.SUN
		_marks.area(_place.pond.from, _place.aim_at(), color)
		return
	_draw_tunnels(hole)
	if not _place.is_water_depthing():
		return
	var listed := _place.pond.open()
	if listed.is_empty():
		return
	var origin: Vector3 = hole.placements[listed[0]][CustomHole.POSITION]
	_marks.column(origin, _place.pond.preview_depth(), Palette.CYAN)


## Dug runs stay outlined while the creator is open, since the finished tunnel
## itself is buried and there is nothing on the surface to point at it.
func _draw_tunnels(hole: CustomHole) -> void:
	for entry in hole.placements:
		if not CustomHole.is_tunnel(String(entry[CustomHole.PATH])):
			continue
		var color := Palette.CYAN if WaterTunnel.is_done(entry) else Palette.ORANGE
		_marks.tube(WaterTunnel.nodes_of(entry), WaterTunnel.bore_of(entry), color)
	if not _place.tunnel.can_dig():
		return
	var next := _place.tunnel.dig_preview()
	if next.size() < 2:
		return
	var lands := not _place.tunnel.dig_lands_in().is_empty()
	_marks.tube(next, _place.tunnel.bore, Palette.LIME if lands else Palette.SUN)


func _draw_sand(hole: CustomHole) -> void:
	for i in hole.placements.size():
		if not CustomHole.is_sandtrap(String(hole.placements[i][CustomHole.PATH])):
			continue
		var at: Vector3 = hole.placements[i][CustomHole.POSITION]
		var editing := i == _place.sanding
		var radius := _place.sand_radius if editing else SandTrap.radius_of(hole.placements[i])
		var depth := _place.sand_depth if editing and _place.is_digging() else SandTrap.depth_of(
			hole.placements[i]
		)
		var color := Palette.LIME if editing else Palette.AMBER
		_marks.marker(at, color)
		if editing and _place.is_digging():
			_marks.bowl(at, radius, depth, color)
		elif editing:
			_marks.disk(at, radius, color)
		else:
			_marks.ring(at, radius, color)
	if CustomHole.is_sandtrap(_place.picked_path()) and not _place.is_sanding():
		_marks.marker(_place.aim_at(), Palette.CYAN)


# #region agent log
var _dbg_n := 0


func _dbg_fairway(data: HoleData, hole: CustomHole, ends: Array[Vector3]) -> void:
	_dbg_n += 1
	if _dbg_n > 80 or (_dbg_n > 1 and _dbg_n % 20 != 0):
		return
	var h0 := 0.0
	var h1 := 0.0
	if data != null and data.height != null:
		h0 = data.height.height_at(ends[0].x, ends[0].z)
		h1 = data.height.height_at(ends[1].x, ends[1].z)
	var piece := FairwayPiece.at(_fairway.picked)
	var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-f6d8e1.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-f6d8e1.log", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"sessionId": "f6d8e1", "runId": "pre-fix", "hypothesisId": "BE",
		"location": "creator_view.gd:draw",
		"message": "fairway ghost piece vs ground",
		"timestamp": Time.get_ticks_msec(),
		"data": {
			"piece": String(piece.get("id", "")),
			"turn": piece.get("turn", 0.0),
			"width": snappedf(hole.width(), 0.01),
			"draw_y": CreatorMarks.LIFT,
			"h_from": snappedf(h0, 0.01),
			"h_to": snappedf(h1, 0.01),
			"y_gap_from": snappedf(CreatorMarks.LIFT - h0, 0.01),
			"y_gap_to": snappedf(CreatorMarks.LIFT - h1, 0.01),
			"chord": snappedf(ends[0].distance_to(ends[1]), 0.01),
		},
	}))
	f.close()
# #endregion
