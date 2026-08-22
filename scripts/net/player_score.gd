class_name PlayerScore
extends GameState
## One player's stroke card and wallet. Hole index is advanced by the VS round,
## not by this object, so eight cards can finish the same hole independently.

var peer_id := 1
var seat := 0
var done_this_hole := false


func _init(p_pars: PackedInt32Array = PackedInt32Array()) -> void:
	if p_pars.is_empty():
		p_pars = HoleGenerator.pars()
	super._init(p_pars)


func color() -> Color:
	return Palette.seat_color(seat)


## Record this hole without moving the rest of the field on.
func finish_hole() -> void:
	if hole_index < 0 or hole_index >= results.size():
		return
	results[hole_index] = strokes
	done_this_hole = true
	hole_completed.emit(hole_index, strokes)


func settle_pickup() -> void:
	cap_at_limit()
	if strokes < max_strokes():
		strokes = max_strokes()
		strokes_changed.emit(strokes)
	finish_hole()


func advance_to(index: int) -> void:
	hole_index = clampi(index, 0, maxi(0, pars.size() - 1))
	strokes = 0
	done_this_hole = false
	strokes_changed.emit(strokes)


func is_leading(others: Array) -> bool:
	var mine := relative_to_par()
	for other in others:
		var card := other as PlayerScore
		if card == null or card == self:
			continue
		if card.relative_to_par() < mine:
			return false
	return true


static func everyone_done(cards: Array) -> bool:
	if cards.is_empty():
		return false
	for card in cards:
		if card == null or not (card as PlayerScore).done_this_hole:
			return false
	return true
