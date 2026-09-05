class_name FairwayTool
extends RefCounted
## Lays the shape of the hole. A piece snaps onto the end of the last one, so
## the ribbon is always one connected fairway; undo pops the last piece back
## off. Nothing here touches the world, which is rebuilt by the creator once a
## change lands.

signal changed
signal refused(reason: String)

const NAME := "FAIRWAY"

var hole: CustomHole
var picked := 0


func _init(for_hole: CustomHole) -> void:
	hole = for_hole


func label() -> String:
	return NAME


func pick(index: int) -> void:
	picked = posmod(index, FairwayPiece.count())


func step_pick(delta: int) -> void:
	pick(picked + delta)


func picked_label() -> String:
	return FairwayPiece.label_of(picked)


## The ghost corner a piece would add, so the player sees where the fairway is
## about to run before committing to it.
func preview() -> Array[Vector3]:
	var next := hole.pieces.duplicate()
	next.append(picked)
	var line := FairwayPiece.points(next)
	return [line[line.size() - 2], line[line.size() - 1]]


func place() -> bool:
	if hole.pieces.size() >= FairwayPiece.MAX_PIECES:
		refused.emit("THIS HOLE IS AS LONG AS IT GETS")
		return false
	if not hole.append_piece(picked):
		refused.emit("THAT TURN WOULD RUN BACK OVER THE FAIRWAY")
		return false
	changed.emit()
	return true


func undo() -> bool:
	if not hole.pop_piece():
		refused.emit("NOTHING LEFT TO TAKE BACK")
		return false
	changed.emit()
	return true


## The palette greys out anything that would fold the ribbon, so a player never
## picks a shape that is then turned away.
func allowed() -> Array[bool]:
	return hole.allowed_pieces()


func summary() -> String:
	return "PAR %d   %d M   %d PIECES" % [
		hole.par(), roundi(hole.length()), hole.pieces.size()
	]
