class_name GameState
extends RefCounted
## The shared team scorecard, the double-bogey pickup, and the wallet.
##
## Strokes are shared: there is one ball, so there is one score. A hole allows
## par + 2 strokes. Reach that without holing out and you pick up for a double
## bogey: money comes out of the pot, and the run goes on. Par and under pay
## into the same pot; leftover seconds only pay when the score is that good.
## Kills stack on top either way.

signal strokes_changed(strokes: int)
signal hole_completed(index: int, strokes: int)
signal course_completed()
signal money_changed(money: int)

const HOLE_COUNT := 9
const MAX_OVER_PAR := 2
const HOLE_SECONDS := 120.0
## Finishing with the full two minutes left pays this; each leftover second is
## worth the same, so a slow hole still pays a little and a timed-out hole pays
## nothing extra. Only awarded on par or better.
const DOLLARS_PER_SECOND := 5
## Par pays this; each stroke under par adds the under bonus on top.
const PAY_PAR := 50
const PAY_UNDER := 30
## Taken from the wallet when the hole is finished at double bogey.
const PAY_DOUBLE_BOGEY := -40

var pars: PackedInt32Array
## Strokes actually taken per hole, -1 until the hole is holed out.
var results: PackedInt32Array
var hole_index := 0
var strokes := 0
var money := 0
## Shared deployable stock. Survives hole changes; placed forts do not.
var barrier_charges := 0
## One mech per round. The placed suit lasts only the hole it was bought on.
var mech_bought := false
var club_id := ClubKit.STARTER_ID
## Added onto the next hole's clock, then cleared.
var bonus_seconds := 0
## First seconds of the next hole do not tick, then cleared.
var freeze_seconds := 0.0


func _init(p_pars: PackedInt32Array) -> void:
	pars = p_pars.duplicate()
	results = PackedInt32Array()
	results.resize(pars.size())
	results.fill(-1)


func par() -> int:
	return pars[hole_index]


func max_strokes() -> int:
	return par() + MAX_OVER_PAR


func strokes_remaining() -> int:
	return max_strokes() - strokes


func add_stroke(count := 1) -> void:
	strokes += count
	strokes_changed.emit(strokes)


## True once this hole is a double bogey even if the next swing drops.
func at_stroke_limit() -> bool:
	return strokes >= max_strokes()


func cap_at_limit() -> void:
	var limit := max_strokes()
	if strokes > limit:
		strokes = limit
		strokes_changed.emit(strokes)


func hole_out() -> void:
	results[hole_index] = strokes
	hole_completed.emit(hole_index, strokes)
	if hole_index >= pars.size() - 1:
		course_completed.emit()
		return
	hole_index += 1
	strokes = 0
	strokes_changed.emit(strokes)


func is_course_complete() -> bool:
	return results[results.size() - 1] != -1


func total_strokes() -> int:
	var sum := 0
	for value in results:
		if value > 0:
			sum += value
	return sum


func played_par() -> int:
	var sum := 0
	for i in results.size():
		if results[i] > 0:
			sum += pars[i]
	return sum


func relative_to_par() -> int:
	return total_strokes() - played_par()


func credit(amount: int) -> void:
	if amount <= 0:
		return
	money += amount
	money_changed.emit(money)


## Positive amounts credit; negative amounts take what the wallet can spare.
func apply_payout(amount: int) -> int:
	if amount > 0:
		credit(amount)
		return amount
	if amount == 0 or money <= 0:
		return 0
	var taken := mini(-amount, money)
	money -= taken
	money_changed.emit(money)
	return -taken


func try_spend(amount: int) -> bool:
	if amount < 0 or amount > money:
		return false
	if amount == 0:
		return true
	money -= amount
	money_changed.emit(money)
	return true


func add_barrier_charges(amount: int) -> void:
	if amount <= 0:
		return
	barrier_charges += amount


func try_place_barrier() -> bool:
	if barrier_charges <= 0:
		return false
	barrier_charges -= 1
	return true


func club_kit() -> ClubKit:
	return ClubKit.by_id(club_id)


func equip_club(kit_id: String) -> void:
	var kit := ClubKit.by_id(kit_id)
	if kit.tier() > club_kit().tier():
		club_id = kit.id


func add_bonus_seconds(amount: int) -> void:
	if amount > 0:
		bonus_seconds += amount


func take_bonus_seconds() -> float:
	var extra := float(bonus_seconds)
	bonus_seconds = 0
	return extra


func add_freeze_seconds(amount: float) -> void:
	if amount > 0.0:
		freeze_seconds += amount


func take_freeze_seconds() -> float:
	var extra := freeze_seconds
	freeze_seconds = 0.0
	return extra


static func time_bonus(seconds_left: float) -> int:
	return int(floorf(maxf(0.0, seconds_left) * DOLLARS_PER_SECOND))


## Score money for a hole. Par and under pay; bogey is a wash; double bogey costs.
static func score_payout(relative: int) -> int:
	if relative >= MAX_OVER_PAR:
		return PAY_DOUBLE_BOGEY
	if relative > 0:
		return 0
	return PAY_PAR + (-relative) * PAY_UNDER


## Wallet change for finishing a hole, before the empty-wallet clamp.
static func hole_payout(relative: int, seconds_left: float) -> int:
	var pay := score_payout(relative)
	if relative <= 0:
		pay += time_bonus(seconds_left)
	return pay


static func format_clock(seconds: float) -> String:
	var whole := maxi(0, ceili(seconds))
	if seconds <= 0.0:
		whole = 0
	return "%d:%02d" % [whole / 60, whole % 60]


static func format_money(amount: int) -> String:
	if amount < 0:
		return "-$%d" % -amount
	return "$%d" % amount


static func format_relative(value: int) -> String:
	if value == 0:
		return "E"
	return "+%d" % value if value > 0 else str(value)
