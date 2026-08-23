class_name NetInterp
extends RefCounted
## Lerps a puppet toward replicated snapshots. Large jumps snap so a spawn or
## seat change does not slide across the hole.

const SNAP_METERS := 4.0

var interval := 0.05
var from := Transform3D.IDENTITY
var to := Transform3D.IDENTITY
var age := 0.0
var _live := false


func push(target: Transform3D, current: Transform3D) -> void:
	if not _live or current.origin.distance_to(target.origin) > SNAP_METERS:
		from = target
		to = target
		age = interval
		_live = true
		return
	from = current
	to = target
	age = 0.0


func sample(delta: float) -> Transform3D:
	age += delta
	if interval <= 0.0:
		return to
	return from.interpolate_with(to, clampf(age / interval, 0.0, 1.0))


func follow(node: Node3D, target: Transform3D, delta: float, p_interval: float) -> void:
	interval = p_interval
	if not _live or not target.is_equal_approx(to):
		push(target, node.global_transform)
	node.global_transform = sample(delta)
