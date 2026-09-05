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
		CreatorMode.Tool.GROUP:
			_marks.ring(_group.center(), _group.radius, Palette.AMBER)
			for i in hole.placements.size():
				if _group.is_selected(i):
					_marks.marker(hole.placements[i][CustomHole.POSITION], Palette.LIME)
		CreatorMode.Tool.PLACE:
			_draw_gates(data, hole)
			_draw_zip()
	_marks.finish()


func refresh() -> void:
	var current := tool_handler()
	_ui.show_hole(_mode.hole, current.label(), current.summary(), picked_label())
	match _mode.tool:
		CreatorMode.Tool.FAIRWAY:
			_ui.show_palette(fairway_labels(), _fairway.picked, _fairway.allowed())
		CreatorMode.Tool.PLACE:
			if _place.is_gating() or _place.is_zipping():
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
