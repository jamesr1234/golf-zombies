class_name TeamScore
extends GameState
## One team's stroke card for Coop Multiplayer VS. Money stays on PlayerScore.

var team := 0
var done_this_hole := false
## 0 = slot A tees first on hole 1; flips after the ball comes to rest.
var striker_slot := 0


func _init(p_pars: PackedInt32Array = PackedInt32Array()) -> void:
	if p_pars.is_empty():
		p_pars = HoleGenerator.pars()
	super._init(p_pars)
	max_over = CoopVs.MAX_OVER_PAR


func color() -> Color:
	return Palette.seat_color(team)


func striker_seat() -> int:
	return CoopVs.seat_for_team(team, striker_slot)


func advance_turn() -> int:
	striker_slot = 1 - striker_slot
	return striker_seat()


func reset_turn() -> void:
	striker_slot = 0


func finish_hole() -> void:
	if hole_index < 0 or hole_index >= results.size():
		return
	results[hole_index] = strokes
	done_this_hole = true
	hole_completed.emit(hole_index, strokes)


## Timeout and the stroke cap both lock the hole at par + 4.
func settle_pickup() -> void:
	var limit := max_strokes()
	if strokes != limit:
		strokes = limit
		strokes_changed.emit(strokes)
	finish_hole()


func advance_to(index: int) -> void:
	hole_index = clampi(index, 0, maxi(0, pars.size() - 1))
	strokes = 0
	done_this_hole = false
	reset_turn()
	strokes_changed.emit(strokes)


static func everyone_done(cards: Array) -> bool:
	if cards.is_empty():
		return false
	for card in cards:
		if card == null or not (card as TeamScore).done_this_hole:
			return false
	return true
