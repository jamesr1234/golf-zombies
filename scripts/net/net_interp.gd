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
## Measured LAN gaps reach roughly seven times the send interval on a bad packet,
## and a window shorter than that parks the puppet until the next one lands. The
## ceiling only costs lag when the gaps are really that wide, because the window
## eases toward what it measures rather than sitting at the limit.
const WINDOW_MAX_SCALE := 7.0
## A puppet that moved less than this between snapshots was standing still, so
## the gap that preceded it says nothing about the connection.
const STALL_METERS := 0.05

var nominal := 0.05
var window := 0.05
var from := Transform3D.IDENTITY
var to := Transform3D.IDENTITY
var age := 0.0
var _live := false

## Read by the debug overlay. The glide never reads these back.
var last_gap := 0.0
var worst_gap := 0.0
var arrivals := 0
## Moving snapshots that landed after the glide had already finished, which is
## the park-then-jump the eye reads as a dropped frame.
var stalls := 0
var snaps := 0


## A fresh snapshot. `age` still holds the real gap since the last one, which is
## what the next glide runs over. It is clamped because a puppet that holds
## still stops reporting, and that silence must not slow its next move.
func arrive(target: Transform3D, current: Transform3D) -> void:
	if not _live or current.origin.distance_to(target.origin) > SNAP_METERS:
		if _live:
			snaps += 1
		from = target
		to = target
		window = nominal
		age = window
		_live = true
		return
	_record(current.origin.distance_to(target.origin))
	var measured := clampf(age, nominal * WINDOW_MIN_SCALE, nominal * WINDOW_MAX_SCALE)
	window = lerpf(window, measured, WINDOW_EASE)
	from = current
	to = target
	age = 0.0


## Called before the window and age are rolled forward, so `age` is still the gap
## this snapshot arrived on and `window` is still the glide it had to beat.
func _record(moved: float) -> void:
	if moved <= STALL_METERS:
		return
	arrivals += 1
	last_gap = age
	worst_gap = maxf(worst_gap, age)
	if age > window * STRETCH:
		stalls += 1


func stall_percent() -> float:
	if arrivals == 0:
		return 0.0
	return float(stalls) / float(arrivals) * 100.0


func reset_stats() -> void:
	last_gap = 0.0
	worst_gap = 0.0
	arrivals = 0
	stalls = 0
	snaps = 0


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
