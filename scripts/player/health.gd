class_name Health
extends Node
## Player vitality: damage, regeneration, the downed state with its bleed-out
## timer, and partner revives. All timing goes through tick() so the rules can
## be tested without a running scene.

signal damaged(amount: float)
signal downed()
signal revived()
signal died()

enum State { ALIVE, DOWNED, DEAD }

@export var max_hp := 100.0
@export var bleed_out_time := 45.0
@export var revive_time := 3.0
@export var revive_hp_fraction := 0.5
## Medkits heal immediately; regen still covers a break in contact.
@export var regen_delay := 6.0
@export var regen_rate := 7.0

var hp := 100.0
var state: State = State.ALIVE
var bleed_remaining := 0.0
var revive_progress := 0.0
## Next down auto-gets up at half HP instead of waiting for a partner.
var auto_revives := 0

var _time_since_damage := 999.0


func _ready() -> void:
	hp = max_hp
	bleed_remaining = bleed_out_time


func _process(delta: float) -> void:
	if NetSession.defers_world():
		return
	tick(delta)


func is_alive() -> bool:
	return state == State.ALIVE


func is_downed() -> bool:
	return state == State.DOWNED


func fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


func bleed_fraction() -> float:
	return clampf(bleed_remaining / bleed_out_time, 0.0, 1.0)


func revive_fraction() -> float:
	return clampf(revive_progress / revive_time, 0.0, 1.0)


func take_damage(amount: float) -> void:
	if state != State.ALIVE or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	_time_since_damage = 0.0
	damaged.emit(amount)
	if hp <= 0.0:
		if auto_revives > 0:
			auto_revives -= 1
			hp = max_hp * revive_hp_fraction
			_time_since_damage = 0.0
			Sfx.play("revived", self)
			revived.emit()
			return
		state = State.DOWNED
		bleed_remaining = bleed_out_time
		revive_progress = 0.0
		Sfx.play("downed", self)
		downed.emit()
		return
	Sfx.play("damage", self)


func add_revive_progress(delta: float) -> void:
	if state != State.DOWNED:
		return
	revive_progress += delta
	if revive_progress >= revive_time:
		state = State.ALIVE
		hp = max_hp * revive_hp_fraction
		revive_progress = 0.0
		_time_since_damage = 0.0
		Sfx.play("revived", self)
		revived.emit()


func reset_revive_progress() -> void:
	revive_progress = 0.0


func heal(amount := -1.0) -> void:
	if state != State.ALIVE:
		return
	if amount < 0.0:
		hp = max_hp
	else:
		hp = minf(max_hp, hp + amount)


func add_auto_revive(amount := 1) -> void:
	if amount > 0:
		auto_revives += amount


func revive_now() -> void:
	if state != State.DOWNED:
		return
	state = State.ALIVE
	hp = max_hp * revive_hp_fraction
	revive_progress = 0.0
	_time_since_damage = 0.0
	Sfx.play("revived", self)
	revived.emit()


## Clubhouse and a fresh hole: stand back up at full health, even from dead.
func restore() -> void:
	state = State.ALIVE
	hp = max_hp
	revive_progress = 0.0
	bleed_remaining = bleed_out_time
	_time_since_damage = 999.0


func tick(delta: float) -> void:
	match state:
		State.ALIVE:
			_time_since_damage += delta
			if _time_since_damage >= regen_delay and hp < max_hp:
				hp = minf(max_hp, hp + regen_rate * delta)
		State.DOWNED:
			bleed_remaining = maxf(0.0, bleed_remaining - delta)
			if bleed_remaining <= 0.0:
				state = State.DEAD
				Sfx.play("died", self)
				died.emit()
