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
	_marks.finish()


func refresh() -> void:
	var current := tool_handler()
	_ui.show_hole(_mode.hole, current.label(), current.summary(), picked_label())
	match _mode.tool:
		CreatorMode.Tool.FAIRWAY:
			_ui.show_palette(fairway_labels(), _fairway.picked, _fairway.allowed())
		CreatorMode.Tool.PLACE:
			if _place.is_gating() or _place.is_zipping() or _place.is_roaming():
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
