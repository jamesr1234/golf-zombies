class_name GameSettings
extends Object
## Session picks from the title menu, plus the four difficulty tables.
## Static so the last mode and difficulty survive a scene reload.

enum Mode { SOLO, COOP, ONLINE_VS, ONLINE_COOP_VS }
enum Kind { EASY, MEDIUM, HARD, IMPOSSIBLE }
enum TutorialGoal { NONE, DRIVE_RAMP, CLEAR_PACK }

const LABELS: PackedStringArray = ["Easy", "Medium", "Hard", "Impossible"]

static var mode := Mode.SOLO
static var difficulty := Kind.MEDIUM
## Set when a player-made hole is on. The match plays this one hole instead of
## the twelve-hole course, and the creator hands its work-in-progress over the
## same way when a hole is taken out for a playtest.
static var custom_hole: CustomHole
## The hole the creator should open with. Empty means start something new.
static var creator_hole: CustomHole
## True when the creator should run the action-by-action lesson.
static var creator_tutorial := false
## Lesson step to resume after a tutorial playtest. 0 means start from the top.
static var creator_lesson_at := 0
## Tool in hand when that playtest launched, so the workbench opens on Place.
static var creator_lesson_tool := 0
## Pause / finish of a tutorial playtest should land back in the creator.
static var return_to_creator := false
## What the current lesson playtest has to finish before the workbench opens.
static var tutorial_goal := TutorialGoal.NONE


static func is_solo() -> bool:
	return mode == Mode.SOLO


static func is_online() -> bool:
	return mode == Mode.ONLINE_VS or mode == Mode.ONLINE_COOP_VS


static func is_coop_vs() -> bool:
	return mode == Mode.ONLINE_COOP_VS


static func online_max_players() -> int:
	return CoopVs.FIELD_SIZE if is_coop_vs() else 8


static func max_over_par() -> int:
	return CoopVs.MAX_OVER_PAR if is_coop_vs() else GameState.MAX_OVER_PAR


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
	custom_hole = null
	creator_hole = null
	creator_tutorial = false
	_clear_lesson()


static func mute_master(muted: bool) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, muted)


static func is_custom() -> bool:
	return custom_hole != null


## A hole goes out to be played on its own copy, so a shot taken on it can never
## write back into what is still open in the creator.
static func play_custom(hole: CustomHole) -> void:
	mode = Mode.SOLO
	custom_hole = hole.copy()
	creator_hole = hole


## Same as play_custom, but the pause menu and a finished hole send the player
## back to the workbench on the next lesson step.
static func play_tutorial_hole(
	hole: CustomHole, lesson_at: int, tool := 0, goal := TutorialGoal.NONE
) -> void:
	play_custom(hole)
	creator_tutorial = true
	creator_lesson_at = maxi(lesson_at, 0)
	creator_lesson_tool = tool
	return_to_creator = true
	tutorial_goal = goal


static func edit_custom(hole: CustomHole) -> void:
	creator_hole = hole
	custom_hole = null
	creator_tutorial = false
	_clear_lesson()


static func start_tutorial() -> void:
	var hole := CustomHole.create("Tutorial")
	hole.needs_width = true
	edit_custom(hole)
	creator_tutorial = true


static func take_creator_hole() -> CustomHole:
	var hole := creator_hole if creator_hole != null else CustomHole.create()
	creator_hole = null
	custom_hole = null
	return hole


static func take_creator_tutorial() -> bool:
	var on := creator_tutorial
	creator_tutorial = false
	return on


static func take_creator_lesson_at() -> int:
	var at := creator_lesson_at
	creator_lesson_at = 0
	return at


static func take_creator_lesson_tool() -> int:
	var next := creator_lesson_tool
	creator_lesson_tool = 0
	return next


static func take_return_to_creator() -> bool:
	var on := return_to_creator
	return_to_creator = false
	tutorial_goal = TutorialGoal.NONE
	return on


static func _clear_lesson() -> void:
	creator_lesson_at = 0
	creator_lesson_tool = 0
	return_to_creator = false
	tutorial_goal = TutorialGoal.NONE


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
