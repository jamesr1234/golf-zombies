class_name NetPredict
extends RefCounted
## Keeps a body honest while it is driven from replicated input rather than from
## replicated poses.
##
## A pose is a sample; a stick is a cause. A peer handed the samples has to
## rebuild the motion out of them, so every uneven delivery is on screen and no
## amount of buffering changes that, only how far behind you watch it happen. A
## peer handed the cause generates the motion itself, continuously, at the
## physics rate, and an uneven delivery costs a sliver of input lag instead.
##
## What that gives up is certainty, and this is what buys it back. The host's
## account is the real one, but it is also late, and lateness is not error: a
## body running the same input is simply further along the same line. So the
## disagreement worth correcting is between the host's pose and the nearest place
## the body actually was, not where it happens to be now. Measured that way the
## round trip cancels out on its own and only genuine divergence is left to close.

## Past this the two are telling different stories rather than the same one late,
## which means something the input never accounted for: a shove, a windmill, a
## hijack. The host's version wins outright.
const SNAP := 3.0
## Disagreement below this is left alone, so the correction never picks a fight
## with input that was already right.
const SLACK := 0.05
## Share of the remaining disagreement closed per second. Slow enough to read as
## the body settling rather than as something pulling it.
const PULL := 3.0
## How much of the recent path to keep. It has to outlast the round trip, since
## that is how old the host's account of it is.
const SECONDS := 0.6

var _track: PackedVector3Array = []


func clear() -> void:
	_track.clear()


func remember(at: Vector3) -> void:
	_track.append(at)
	var keep := int(SECONDS * Engine.physics_ticks_per_second)
	while _track.size() > keep:
		_track.remove_at(0)


## True when the body had to be handed back to the host wholesale.
func correct(node: Node3D, host: Transform3D, delta: float) -> bool:
	if _track.is_empty():
		return false
	var drift := host.origin - nearest(_track, host.origin)
	var apart := drift.length()
	if apart > SNAP:
		node.global_transform = host
		_track.clear()
		return true
	if apart > SLACK:
		node.global_position += drift * clampf(PULL * delta, 0.0, 1.0)
	return false


static func nearest(track: PackedVector3Array, to: Vector3) -> Vector3:
	var best := track[0]
	var best_sq := best.distance_squared_to(to)
	for point in track:
		var away := point.distance_squared_to(to)
		if away < best_sq:
			best_sq = away
			best = point
	return best
