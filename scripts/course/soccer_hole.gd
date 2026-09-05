class_name SoccerHole
extends Object
## Hole 12: a long, wide landing strip aimed at a soccer goal. First ball
## through the net wins. The target is big; the carry is the hard part.

const INDEX := 11
const YARDS := 500
const METRE := 0.9144
const LENGTH := YARDS * METRE
const GREEN_RADIUS := 18.0
const PAR := 5


static func applies(data: HoleData) -> bool:
	return data != null and data.custom == null and data.index == INDEX


static func applies_index(index: int) -> bool:
	return index == INDEX


static func layout(data: HoleData, _headings: Array[float], _width: float) -> void:
	data.soccer_goal = true
