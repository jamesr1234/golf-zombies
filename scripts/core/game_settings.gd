class_name GameSettings
extends Object
## Session picks from the title menu, plus the four difficulty tables.
## Static so the last mode and difficulty survive a scene reload.

enum Mode { SOLO, COOP, ONLINE_VS }
enum Kind { EASY, MEDIUM, HARD, IMPOSSIBLE }

const LABELS: PackedStringArray = ["Easy", "Medium", "Hard", "Impossible"]

static var mode := Mode.SOLO
static var difficulty := Kind.MEDIUM


static func is_solo() -> bool:
	return mode == Mode.SOLO


static func is_online() -> bool:
	return mode == Mode.ONLINE_VS


static func hole_seconds() -> float:
	return seconds_for(difficulty)


static func difficulty_label() -> String:
	return label_for(difficulty)


static func spawn_interval_scale() -> float:
	return interval_scale_for(difficulty)


static func spawn_cap_scale() -> float:
	return cap_scale_for(difficulty)


static func zombie_hp_scale() -> float:
	return hp_scale_for(difficulty)


static func zombie_speed_scale() -> float:
	return speed_scale_for(difficulty)


static func gunner_unlock(base_unlock: int) -> int:
	return gunner_unlock_for(difficulty, base_unlock)


static func reset() -> void:
	mode = Mode.SOLO
	difficulty = Kind.MEDIUM


static func label_for(kind: Kind) -> String:
	return LABELS[clampi(kind, 0, LABELS.size() - 1)]


static func seconds_for(kind: Kind) -> float:
	match kind:
		Kind.EASY:
			return 180.0
		Kind.HARD:
			return 90.0
		Kind.IMPOSSIBLE:
			return 60.0
		_:
			return GameState.HOLE_SECONDS


static func interval_scale_for(kind: Kind) -> float:
	match kind:
		Kind.EASY:
			return 1.5
		Kind.HARD:
			return 0.7
		Kind.IMPOSSIBLE:
			return 0.45
		_:
			return 1.0


static func cap_scale_for(kind: Kind) -> float:
	match kind:
		Kind.EASY:
			return 0.7
		Kind.HARD:
			return 1.3
		Kind.IMPOSSIBLE:
			return 1.7
		_:
			return 1.0


static func hp_scale_for(kind: Kind) -> float:
	match kind:
		Kind.EASY:
			return 0.85
		Kind.HARD:
			return 1.2
		Kind.IMPOSSIBLE:
			return 1.5
		_:
			return 1.0


static func speed_scale_for(kind: Kind) -> float:
	match kind:
		Kind.EASY:
			return 0.9
		Kind.HARD:
			return 1.1
		Kind.IMPOSSIBLE:
			return 1.25
		_:
			return 1.0


static func gunner_unlock_for(kind: Kind, base_unlock: int) -> int:
	match kind:
		Kind.EASY:
			return maxi(base_unlock, 2)
		Kind.HARD, Kind.IMPOSSIBLE:
			return 0
		_:
			return base_unlock
