class_name NetInterp
extends RefCounted
## Draws a puppet a step behind the newest snapshot, interpolating between the
## two that bracket that moment.
##
## Holding the stream back is what absorbs jitter. Measured wifi jitter runs to
## a hundred milliseconds, wider than the gap between sends, so packets arrive in
## clumps rather than evenly. A puppet that chases the newest one runs out of
## road during a clump, parks on its last pose, and jumps when the next arrives.
## With a queue in hand it always has somewhere to go, and the delay a viewer
## sees stops varying, which is the part the eye reads as a hitch.
##
## The queue sits as deep as the link has lately required and no deeper, so a
## clean connection is drawn close to live and only a bad one pays for it.
##
## The delay is only ever as long as its owner asks for. Things you watch are
## worth a real buffer; things you shoot are not, because the host scores shots
## against live positions and drawing them late only makes you miss.

## Past this the snapshot is a spawn or a seat change rather than a move, and
## sliding across it would draw the puppet through the world.
const SNAP_METERS := 4.0
## A puppet that moved less than this between snapshots was standing still, so
## the gap that preceded it says nothing about the connection.
const STALL_METERS := 0.05
## How long the worst gap stands before recent play can replace it. Without this
## a single hiccup while the match was still settling reads as the state of the
## connection for the rest of the round.
const WORST_HOLD := 6.0

## How far past the requested delay the queue may grow. Proportional rather than
## absolute, because the request is the owner's statement of how much lateness it
## can live with: a watched pawn asking for a tenth of a second will tolerate
## three, while a zombie asking for one send interval is something you aim at and
## must not wander that far behind where the host says it is.
const DEPTH_CEILING := 3.0
## How much deeper than the worst recent gap to sit, so a gap slightly worse than
## the last one still lands in time.
const DEPTH_MARGIN := 1.25
## Seconds of depth handed back per second of clean play, so a link that settles
## earns its responsiveness back instead of paying for one bad patch all match.
const DEPTH_DECAY := 0.02
## How much faster than real time the draw runs to make up ground lost to a dry
## queue, and how much slower to give ground back. Both are far too small to see.
const CATCHUP := 1.08
const EASE_OFF := 0.92
## Slack either side before the draw changes pace, so ordinary jitter does not
## keep nudging it.
const PACE_SLACK := 0.02

var nominal := 0.05
## What the owner asks to sit behind by.
var delay := 0.05
## What it actually sits behind by, which is deeper whenever the link has been
## producing gaps the requested delay could not cover.
var depth := 0.05
## Set on a puppet the local player is riding or steering, which is drawn as
## close to live as the snapshots allow. Buffering buys smoothness with delay,
## and that is the right trade for something you watch and the wrong one for
## something you are inside: the delay lands between the wheel and the view, so
## a fifth of a second of it reads as broken steering rather than a smooth ride.
var responsive := false

## Read by the debug overlay. The draw never reads these back.
var last_gap := 0.0
var worst_gap := 0.0
var arrivals := 0
## Snapshots that landed after the buffer had already run dry, which is the
## park-then-jump the eye reads as a dropped frame.
var stalls := 0
var snaps := 0

var _times: Array[float] = []
var _poses: Array[Transform3D] = []
var _clock := 0.0
## The moment being drawn. It runs on its own pace so a dry queue costs a pause
## rather than a jump, and it never runs backwards.
var _draw := 0.0
var _need := 0.0
var _last_arrival := 0.0
var _starved := false
var _worst_left := 0.0
var _live := false


## A fresh snapshot joins the back of the queue. Distance is measured against the
## newest snapshot rather than the drawn pose, because the drawn pose is
## deliberately behind and a fast cart would otherwise read as a teleport.
func arrive(target: Transform3D) -> void:
	if not _live or _newest().origin.distance_to(target.origin) > SNAP_METERS:
		if _live:
			snaps += 1
		_restart_at(target)
		return
	_record(_newest().origin.distance_to(target.origin))
	_times.append(_clock)
	_poses.append(target)
	_last_arrival = _clock


func _record(moved: float) -> void:
	var was_starved := _starved
	_starved = false
	if moved <= STALL_METERS:
		return
	arrivals += 1
	last_gap = _clock - _last_arrival
	# A queue shallower than the gaps the link actually produces runs dry, so
	# take the worst one seen rather than the average. It is the outliers that
	# park the puppet; the average never did.
	_need = maxf(_need, last_gap)
	if last_gap > worst_gap or _worst_left <= 0.0:
		worst_gap = last_gap
		_worst_left = WORST_HOLD
	if was_starved:
		stalls += 1


## A spawn or a seat change has no history worth keeping. Backdating the one
## snapshot by the delay puts the puppet on it now instead of easing toward it.
func _restart_at(pose: Transform3D) -> void:
	_times = [_clock - depth]
	_poses = [pose]
	_draw = _clock - depth
	_last_arrival = _clock
	_starved = false
	_live = true


func _newest() -> Transform3D:
	return _poses[_poses.size() - 1] if not _poses.is_empty() else Transform3D.IDENTITY


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
	_worst_left = 0.0


func sample(delta: float) -> Transform3D:
	_clock += delta
	_worst_left = maxf(0.0, _worst_left - delta)
	_need = maxf(0.0, _need - DEPTH_DECAY * delta)
	depth = clampf(_need * DEPTH_MARGIN, delay, delay if responsive else delay * DEPTH_CEILING)
	if _poses.is_empty():
		return Transform3D.IDENTITY
	_advance(delta)
	_drop_spent(_draw)
	var newest := _poses.size() - 1
	if _draw >= _times[newest]:
		# One snapshot is the seeded state, not a queue that ran dry. There has
		# to have been a pair to work through before running out means anything.
		_starved = newest > 0
		return _poses[newest]
	if _draw <= _times[0]:
		return _poses[0]
	var span := _times[1] - _times[0]
	var reached := 1.0 if span <= 0.0 else (_draw - _times[0]) / span
	return _poses[0].interpolate_with(_poses[1], clampf(reached, 0.0, 1.0))


## Walk the drawn moment forward, never past the newest snapshot. Stopping there
## is what turns a dry queue into a pause instead of a jump: the draw picks up
## where the data ran out rather than leaping to where the clock says it should
## be. The ground that costs is made back a little at a time afterwards.
func _advance(delta: float) -> void:
	var behind := (_clock - depth) - _draw
	var pace := 1.0
	if behind > PACE_SLACK:
		pace = CATCHUP
	elif behind < -PACE_SLACK:
		pace = EASE_OFF
	_draw = minf(_draw + delta * pace, _times[_poses.size() - 1])


## Everything older than the moment being drawn is spent, bar the one on its near
## side, which is still half of the pair being interpolated.
func _drop_spent(at: float) -> void:
	while _poses.size() > 2 and _times[1] <= at:
		_times.remove_at(0)
		_poses.remove_at(0)


## Entities call this every rendered frame. The target check is a fallback for a
## snapshot that arrived without the property setter firing.
func follow(
	node: Node3D, target: Transform3D, delta: float, p_interval: float, p_delay := 0.0
) -> void:
	nominal = p_interval
	# There is nothing to draw from between two snapshots that have not both
	# arrived, so the queue is never shorter than the gap between sends.
	delay = maxf(p_delay, p_interval)
	depth = maxf(depth, delay)
	if not _live or not target.is_equal_approx(_newest()):
		arrive(target)
	node.global_transform = sample(delta)
