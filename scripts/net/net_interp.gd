class_name NetInterp
extends RefCounted
## Glides a puppet toward replicated snapshots. The glide runs over the measured
## gap between arrivals rather than the nominal send rate, so a packet that
## lands late stretches the run instead of parking the puppet on its last pose.

const SNAP_METERS := 4.0
## Run a little past the measured gap so the next snapshot lands mid-glide
## instead of after a stall. The cost is a few ms of extra visual lag.
const STRETCH := 1.15
## How much of a fresh measurement to fold in, so one jittery packet cannot
## swing the window.
const WINDOW_EASE := 0.25
const WINDOW_MIN_SCALE := 0.5
const WINDOW_MAX_SCALE := 3.0

var nominal := 0.05
var window := 0.05
var from := Transform3D.IDENTITY
var to := Transform3D.IDENTITY
var age := 0.0
var _live := false


## A fresh snapshot. `age` still holds the real gap since the last one, which is
## what the next glide runs over. It is clamped because a puppet that holds
## still stops reporting, and that silence must not slow its next move.
func arrive(target: Transform3D, current: Transform3D) -> void:
	if not _live or current.origin.distance_to(target.origin) > SNAP_METERS:
		from = target
		to = target
		window = nominal
		age = window
		_live = true
		return
	var measured := clampf(age, nominal * WINDOW_MIN_SCALE, nominal * WINDOW_MAX_SCALE)
	window = lerpf(window, measured, WINDOW_EASE)
	from = current
	to = target
	age = 0.0


func sample(delta: float) -> Transform3D:
	age += delta
	var span := window * STRETCH
	if span <= 0.0:
		return to
	return from.interpolate_with(to, clampf(age / span, 0.0, 1.0))


## Entities call this every rendered frame. The target check is a fallback for
## a snapshot that arrived without the property setter firing.
func follow(node: Node3D, target: Transform3D, delta: float, p_interval: float) -> void:
	nominal = p_interval
	if not _live or not target.is_equal_approx(to):
		arrive(target, node.global_transform)
	node.global_transform = sample(delta)
