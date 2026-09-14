class_name CreatorLesson
extends RefCounted
## Action-by-action walkthrough of the hole creator. Only the current step's
## command is accepted; doing it earns a compliment and the next prompt.

signal prompted(text: String)
signal praised(text: String)
signal finished

enum Act {
	STEP_PIECE, CONFIRM, CANCEL, UNDO, REDO, SWITCH_TOOL, STEP_SHELF,
	SIDE, TURN, CONTEXT, SNAP_SURFACE, YAW_SNAP, HELP, MENU, SAVE, LINE,
}

## CreatorMode.Tool values, kept as ints so this script does not import CreatorMode.
const TOOL_PLACE := 1
const TOOL_GROUP := 2

const NEXT := KEY_ENTER
const NEXT_HINT := "Enter or Cross to continue."
const FLY_SECONDS := 2.4
const LOOK_SECONDS := 2.0
const LIFT_SECONDS := 1.1
const NEED_CYCLE := 3
const NEED_NUDGE := 3
const NEED_FAIRWAY := 3
const NEED_AGAIN := 2
const NEED_RAMPS := 2
const NEED_PROPS := 2
const ROCKET := "res://resources/weapons/rocket.tres"
const CART := "res://scenes/vehicles/golf_cart.tscn"
const PRAISE: PackedStringArray = [
	"NICE!", "THAT'S IT!", "CLEAN!", "GOT IT!", "SHARP!", "PERFECT!",
	"YES!", "ON THE MONEY!", "SWEET!", "NAILED IT!", "THERE IT IS!",
	"GOOD ONE!", "EXACTLY!", "BOOM!", "SMOOTH!",
]
const TIPS := {
	"fly": "Hold Shift to cover a long hole faster.",
	"look": "The piece hangs under the crosshair, so look where you want it to sit.",
	"climb": "Triangle or Space lifts you over a tall piece you just dropped.",
	"drop": "Cross or Z drops you back onto the grass when you have climbed too high.",
	"cycle_fairway": "Watch the ghost on the grass. A sharp dogleg needs room before you commit.",
	"place_fairway": "Mix the shapes. A hole is more interesting when it is not one long straight.",
	"take_back": "L2 only peels the last fairway piece. Undo walks further back.",
	"place_again": "Two pieces is already playable. Longer holes just keep stacking.",
	"undo": "If you make a few mistakes, hold L1 and Circle to undo back to where you want.",
	"redo": "Hold L1+Triangle to step forward through everything you just undid.",
	"switch_place": "L1 and R1 walk the three tools. 1, 2 and 3 jump straight to one.",
	"cycle_place": "The list on the left is the same pieces the D-pad is walking.",
	"turn": "R snaps in 45s. Turn rotation snap off if you need a finer angle.",
	"surface_snap": "Leave this on. A piece that is not snapped sits in the air or buries in the dirt, and nobody can play it.",
	"yaw_snap": "Spin while it is off so the piece sits how you want, then lock the 45s again.",
	"hold": "Park the ghost, then fly around it so you can see how it sits on the grass.",
	"place_held": "R2 still drops the parked piece, not wherever the camera is pointing now.",
	"shelf_vehicles": "The cart has to sit on the grass. Surface snap keeps the wheels on the playable ground.",
	"place_cart": "Snap it to the ground or it floats and you cannot drive it. You will need it to climb the ramps.",
	"place_obstacles": "Park the cart at the bottom. Drive off a ramp and land the jump to keep building.",
	"shelf_props": "Square walks obstacles, props, vehicles, weapons, then spawns.",
	"place_prop": "Props have to sit on the fairway. Aim at the grass, not the dirt beside it.",
	"shelf_weapons": "A gun with no line stays live for the whole hole.",
	"place_weapon": "The rocket is on this shelf. Cycle to it if another gun is up.",
	"set_line": "The line is only a creator guide. Players never see it on the hole.",
	"shelf_spawns": "A spawn is a pack. You pick who walks it after the rings.",
	"place_spawn": "Plant them further up the hole so you have room to shoot from the tee.",
	"set_yard": "The yard is where they roam until someone gets close.",
	"set_chase": "Keep the chase ring outside the yard or they start hunting immediately.",
	"set_counts": "Wipe out the pack in playtest to keep building.",
	"switch_group": "Group turns loose pieces into one structure you can drop again.",
	"grow": "Grow the ring until both pieces sit inside it. Wheel or D-pad does the same job.",
	"select": "Click again to drop a selection. Guns and spawns cannot go in a structure.",
	"merge": "The loose pieces leave and the structure stands where they were.",
	"help": "L1+R1 opens this list any time, so you do not have to remember every button.",
	"help_close": "The list hides while a menu is up so you can still read the pause rows.",
	"menu": "Save, playtest and erase live here. A pad has no spare button once you are building.",
	"menu_close": "Esc or Options toggles it. You can keep building the moment it closes.",
	"save": "A hole named Hole 1 through Hole 12 replaces that slot on the regular course.",
}

const STEPS: Array[Dictionary] = [
	{"id": "fly", "prompt": "Fly around for a few seconds. WASD or the left stick.", "allow": []},
	{"id": "look", "prompt": "Look around for a few seconds. Mouse or the right stick.", "allow": []},
	{"id": "climb", "prompt": "Climb. Space or Triangle.", "allow": []},
	{"id": "drop", "prompt": "Drop. Z or Cross.", "allow": []},
	{"id": "cycle_fairway", "prompt": "Cycle through a few fairway shapes. Q / E or D-pad Up / Down.", "allow": [Act.STEP_PIECE]},
	{"id": "place_fairway", "prompt": "Lay three different fairway pieces. Click or R2.", "allow": [Act.CONFIRM, Act.STEP_PIECE]},
	{"id": "take_back", "prompt": "Take that piece back. Right click, Backspace or L2.", "allow": [Act.CANCEL]},
	{"id": "place_again", "prompt": "Lay two more pieces. Click or R2.", "allow": [Act.CONFIRM, Act.STEP_PIECE]},
	{"id": "undo", "prompt": "Undo. Ctrl+Z or L1+Circle.", "allow": [Act.UNDO]},
	{"id": "redo", "prompt": "Redo. Ctrl+Y or L1+Triangle.", "allow": [Act.REDO]},
	{"id": "switch_place", "prompt": "Switch to the Place tool. 2 or R1.", "allow": [Act.SWITCH_TOOL]},
	{"id": "cycle_place", "prompt": "Cycle through a few obstacles. Q / E or D-pad Up / Down.", "allow": [Act.STEP_PIECE]},
	{"id": "surface_snap", "prompt": "Turn surface snap on so pieces sit on the playable grass. T or L3.", "allow": [Act.SNAP_SURFACE]},
	{"id": "yaw_snap", "prompt": "Turn rotation snap off, spin the piece, then snap back on. Y or R3.", "allow": [Act.YAW_SNAP, Act.TURN]},
	{"id": "turn", "prompt": "Turn the piece a few ways. R or D-pad Left / Right.", "allow": [Act.TURN]},
	{"id": "hold", "prompt": "Park the ghost with Circle, then fly around it.", "allow": [Act.CONTEXT]},
	{"id": "place_held", "prompt": "Drop the parked piece. Click or R2.", "allow": [Act.CONFIRM, Act.CANCEL]},
	{"id": "shelf_vehicles", "prompt": "Walk the shelves to Vehicles. Tab or Square.", "allow": [Act.STEP_SHELF]},
	{"id": "place_cart", "prompt": "Drop the cart on the grass with surface snap on. Click or R2.", "allow": [Act.CONFIRM, Act.STEP_PIECE, Act.STEP_SHELF, Act.SNAP_SURFACE, Act.TURN]},
	{"id": "place_obstacles", "prompt": "Walk back to Obstacles, then drop a few ramps. Cycle, then click or R2.", "allow": [Act.CONFIRM, Act.STEP_PIECE, Act.STEP_SHELF, Act.TURN]},
	{"id": "shelf_props", "prompt": "Walk the shelves to Props. Tab or Square.", "allow": [Act.STEP_SHELF]},
	{"id": "place_prop", "prompt": "Drop two different props. Cycle, then click or R2.", "allow": [Act.CONFIRM, Act.STEP_PIECE, Act.STEP_SHELF]},
	{"id": "shelf_weapons", "prompt": "Walk the shelves to Weapons. Tab or Square.", "allow": [Act.STEP_SHELF]},
	{"id": "place_weapon", "prompt": "Drop a rocket on the fairway. Click or R2.", "allow": [Act.CONFIRM, Act.STEP_PIECE, Act.STEP_SHELF]},
	{"id": "set_line", "prompt": "Set how far down the hole the gun stays live. Click or R2.", "allow": [Act.CONFIRM, Act.LINE]},
	{"id": "shelf_spawns", "prompt": "Walk the shelves to Spawns. Tab or Square.", "allow": [Act.STEP_SHELF]},
	{"id": "place_spawn", "prompt": "Drop a zombie spawn further up the hole. Click or R2.", "allow": [Act.CONFIRM, Act.STEP_SHELF]},
	{"id": "set_yard", "prompt": "Set the yard they walk. Click or R2.", "allow": [Act.CONFIRM, Act.CANCEL]},
	{"id": "set_chase", "prompt": "Set the chase range. Click or R2.", "allow": [Act.CONFIRM, Act.CANCEL]},
	{"id": "set_counts", "prompt": "Pick who walks the yard, then confirm.", "allow": [Act.CONFIRM, Act.CANCEL]},
	{"id": "switch_group", "prompt": "Switch to the Group tool. 3 or R1.", "allow": [Act.SWITCH_TOOL]},
	{"id": "grow", "prompt": "Grow and shrink the ring a few times. Left / Right, wheel or D-pad.", "allow": [Act.SIDE]},
	{"id": "select", "prompt": "Aim the ring over two blocks and select them. Click or R2.", "allow": [Act.CONFIRM, Act.SIDE]},
	{"id": "merge", "prompt": "Merge them into a structure. F or Circle, then name it.", "allow": [Act.CONTEXT, Act.CONFIRM, Act.SIDE, Act.CANCEL]},
	{"id": "help", "prompt": "Open the pad list. H or L1+R1.", "allow": [Act.HELP]},
	{"id": "help_close", "prompt": "Close the pad list. H or L1+R1.", "allow": [Act.HELP]},
	{"id": "menu", "prompt": "Open the menu. Esc or Options.", "allow": [Act.MENU]},
	{"id": "menu_close", "prompt": "Close the menu. Esc or Options.", "allow": [Act.MENU]},
	{"id": "save", "prompt": "Name and save this hole. Ctrl+S.", "allow": [Act.SAVE]},
	{"id": "done", "prompt": "That's the course creator. Keep building, or quit from the menu.", "allow": []},
]

const ICONS := {
	"fly": {"icons": ["l_stick"], "keys": "WASD"},
	"look": {"icons": ["r_stick"], "keys": "MOUSE"},
	"climb": {"icons": ["triangle"], "keys": "SPACE"},
	"drop": {"icons": ["cross"], "keys": "Z"},
	"cycle_fairway": {"icons": ["dpad_up", "dpad_down"], "join": "/", "keys": "Q / E"},
	"place_fairway": {"icons": ["r2"], "keys": "CLICK"},
	"take_back": {"icons": ["l2"], "keys": "RIGHT CLICK"},
	"place_again": {"icons": ["r2"], "keys": "CLICK"},
	"undo": {"icons": ["l1", "circle"], "join": "+", "keys": "CTRL+Z"},
	"redo": {"icons": ["l1", "triangle"], "join": "+", "keys": "CTRL+Y"},
	"switch_place": {"icons": ["r1"], "keys": "2"},
	"cycle_place": {"icons": ["dpad_up", "dpad_down"], "join": "/", "keys": "Q / E"},
	"surface_snap": {"icons": ["l3"], "keys": "T"},
	"yaw_snap": {"icons": ["r3"], "keys": "Y"},
	"turn": {"icons": ["dpad_left", "dpad_right"], "join": "/", "keys": "R"},
	"hold": {"icons": ["circle"], "keys": "F"},
	"place_held": {"icons": ["r2"], "keys": "CLICK"},
	"shelf_vehicles": {"icons": ["square"], "keys": "TAB"},
	"place_cart": {"icons": ["r2"], "keys": "CLICK"},
	"place_obstacles": {"icons": ["r2"], "keys": "CLICK"},
	"shelf_props": {"icons": ["square"], "keys": "TAB"},
	"place_prop": {"icons": ["r2"], "keys": "CLICK"},
	"shelf_weapons": {"icons": ["square"], "keys": "TAB"},
	"place_weapon": {"icons": ["r2"], "keys": "CLICK"},
	"set_line": {"icons": ["r2"], "keys": "CLICK"},
	"shelf_spawns": {"icons": ["square"], "keys": "TAB"},
	"place_spawn": {"icons": ["r2"], "keys": "CLICK"},
	"set_yard": {"icons": ["r2"], "keys": "CLICK"},
	"set_chase": {"icons": ["r2"], "keys": "CLICK"},
	"set_counts": {"icons": ["circle"], "keys": "E"},
	"switch_group": {"icons": ["r1"], "keys": "3"},
	"grow": {"icons": ["dpad_left", "dpad_right"], "join": "/", "keys": "WHEEL"},
	"select": {"icons": ["r2"], "keys": "CLICK"},
	"merge": {"icons": ["circle"], "keys": "F"},
	"help": {"icons": ["l1", "r1"], "join": "+", "keys": "H"},
	"help_close": {"icons": ["l1", "r1"], "join": "+", "keys": "H"},
	"menu": {"icons": ["options"], "keys": "ESC"},
	"menu_close": {"icons": ["options"], "keys": "ESC"},
	"save": {"icons": ["options"], "keys": "CTRL+S"},
}

var _index := 0
var _live := false
var _waiting := false
var _saved := false
var _last_praise := ""
var _snap := {}
var _practice := 0.0
var _left := 0
var _seen: Array[int] = []
var _last_pos := Vector3.ZERO
var _last_y := 0.0
var _last_yaw := 0.0
var _last_pitch := 0.0
var _last_reach := 0.0
var _last_piece_yaw := 0.0
var _last_radius := 0.0
var _last_yaw_snap := true
var _spun_free := false


static func ids() -> PackedStringArray:
	var found := PackedStringArray()
	for step in STEPS:
		found.append(String(step["id"]))
	return found


func start(mode: Node3D) -> void:
	_index = 0
	_live = true
	_waiting = false
	_saved = false
	_last_praise = ""
	_snap = _capture(mode)
	_reset_track(mode)
	prompted.emit(prompt())


func tick(mode: Node3D, delta: float) -> void:
	if not _live:
		return
	if _snap.is_empty():
		_snap = _capture(mode)
		_reset_track(mode)
	if _waiting:
		return
	_track(mode, delta)
	_refresh_left(mode)
	if _met(mode):
		_praise()


func continue_tip(mode: Node3D) -> void:
	if not _waiting:
		return
	_advance(mode)


func launches_playtest() -> bool:
	return _waiting and playtest_goal() != GameSettings.TutorialGoal.NONE


func playtest_goal() -> GameSettings.TutorialGoal:
	match id():
		"place_obstacles":
			return GameSettings.TutorialGoal.DRIVE_RAMP
		"set_counts":
			return GameSettings.TutorialGoal.CLEAR_PACK
		_:
			return GameSettings.TutorialGoal.NONE


func resume_at(mode: Node3D, at: int) -> void:
	_index = clampi(at, 0, STEPS.size() - 1)
	_waiting = false
	_live = id() != "done"
	if not _live:
		finished.emit()
	_snap = _capture(mode)
	_reset_track(mode)
	prompted.emit(prompt())


func allows(act: Act) -> bool:
	if not _live:
		return true
	if act == Act.MENU:
		return true
	if _waiting:
		return false
	if act == Act.SNAP_SURFACE and _index > _step_index("surface_snap"):
		return true
	if act == Act.YAW_SNAP and _index > _step_index("yaw_snap"):
		return true
	if act == Act.TURN and _index > _step_index("turn"):
		return true
	return _allows().has(act)


func is_live() -> bool:
	return _live


func praising() -> bool:
	return _waiting


func id() -> String:
	return String(STEPS[_index]["id"])


func prompt() -> String:
	var text := String(STEPS[_index]["prompt"])
	if _left > 0:
		text += "   %d left." % _left
	return text


func tip() -> String:
	return String(TIPS.get(id(), ""))


func icons() -> PackedStringArray:
	var row: Dictionary = ICONS.get(id(), {})
	var found := PackedStringArray()
	for name in row.get("icons", []):
		found.append(String(name))
	return found


func icon_join() -> String:
	return String(ICONS.get(id(), {}).get("join", ""))


func keys() -> String:
	return String(ICONS.get(id(), {}).get("keys", ""))


func index() -> int:
	return _index


func count() -> int:
	return STEPS.size()


func note_saved() -> void:
	_saved = true


func after_cancel(mode: Node3D) -> void:
	match id():
		"place_held":
			if not mode._place.is_holding():
				_rewind("hold", mode)
		"set_yard", "set_chase", "set_counts":
			if not mode._place.is_roaming() and not _finished_spawn(mode):
				_rewind("place_spawn", mode)


func compliment() -> String:
	var pick := PRAISE[randi() % PRAISE.size()]
	if PRAISE.size() > 1:
		while pick == _last_praise:
			pick = PRAISE[randi() % PRAISE.size()]
	_last_praise = pick
	return pick


func _praise() -> void:
	_waiting = true
	# #region agent log
	var f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-e87fdb.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-e87fdb.log", FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(JSON.stringify({
			"sessionId": "e87fdb",
			"runId": "pre-fix",
			"hypothesisId": "E",
			"location": "creator_lesson.gd:_praise",
			"message": "step complete",
			"timestamp": Time.get_ticks_msec(),
			"data": {"id": id()},
		}))
		f.close()
	# #endregion
	praised.emit(compliment())


func _advance(mode: Node3D) -> void:
	_index = mini(_index + 1, STEPS.size() - 1)
	_waiting = false
	_snap = _capture(mode)
	_reset_track(mode)
	_skip_done_steps(mode)
	if id() == "done":
		_live = false
		finished.emit()
		prompted.emit(prompt())
		return
	if _met(mode):
		_praise()
		return
	prompted.emit(prompt())


func _skip_done_steps(mode: Node3D) -> void:
	while id() != "done" and playtest_goal() == GameSettings.TutorialGoal.NONE and _met(mode):
		_index = mini(_index + 1, STEPS.size() - 1)
		_snap = _capture(mode)
		_reset_track(mode)


func _rewind(to: String, mode: Node3D) -> void:
	for i in STEPS.size():
		if String(STEPS[i]["id"]) == to:
			_index = i
			_waiting = false
			_snap = _capture(mode)
			_reset_track(mode)
			prompted.emit(prompt())
			return


func _allows() -> Array:
	return STEPS[_index].get("allow", []) as Array


func _met(mode: Node3D) -> bool:
	if mode == null or mode.hole == null:
		return false
	match id():
		"fly":
			return _practice >= FLY_SECONDS
		"look":
			return _practice >= LOOK_SECONDS
		"climb", "drop":
			return _practice >= LIFT_SECONDS
		"turn", "grow":
			return _practice >= float(NEED_NUDGE)
		"cycle_fairway", "cycle_place":
			return _seen.size() >= NEED_CYCLE
		"place_fairway":
			return _gained_pieces(mode) >= NEED_FAIRWAY
		"place_again":
			return _gained_pieces(mode) >= NEED_AGAIN
		"take_back", "undo":
			return mode.hole.pieces.size() < int(_snap.get("pieces", 0))
		"redo":
			return mode.hole.pieces.size() > int(_snap.get("pieces", 0))
		"switch_place":
			return int(mode.tool) == TOOL_PLACE
		"surface_snap":
			return mode._place.surface_snap
		"yaw_snap":
			return _spun_free and mode._place.yaw_snap
		"place_obstacles":
			return _ramp_count(mode) >= NEED_RAMPS
		"hold":
			return mode._place.is_holding() and _practice >= FLY_SECONDS
		"place_held":
			return mode.hole.placements.size() > int(_snap.get("placed", 0))
		"shelf_vehicles":
			return mode._place.shelf() == PieceCatalog.VEHICLES
		"place_cart":
			return mode._place.surface_snap and _placed_kind(mode, _is_cart)
		"shelf_props":
			return mode._place.shelf() == PieceCatalog.PROPS
		"place_prop":
			return _new_kinds(mode, PieceCatalog.PROP_DIR).size() >= NEED_PROPS
		"shelf_weapons":
			return mode._place.shelf() == PieceCatalog.WEAPONS
		"place_weapon":
			return _placed_kind(mode, _is_rocket)
		"set_line":
			return not mode._place.is_gating() and _gated_weapon(mode)
		"shelf_spawns":
			return mode._place.shelf() == PlaceTool.SPAWNS
		"place_spawn":
			return mode._place.is_roaming() or _finished_spawn(mode)
		"set_yard":
			return mode._place.is_hunting() or _finished_spawn(mode)
		"set_chase":
			return mode._ui.picking_spawn() or _finished_spawn(mode)
		"set_counts":
			return not mode._place.is_roaming() and _finished_spawn(mode)
		"switch_group":
			return int(mode.tool) == TOOL_GROUP
		"select":
			return mode._group.selected.size() >= GroupTool.MIN_PARTS
		"merge":
			return HoleStore.list_structures().size() > int(_snap.get("structures", 0))
		"help":
			return mode.help_is_open()
		"help_close":
			return not mode.help_is_open()
		"menu":
			return mode.menu_is_open()
		"menu_close":
			return not mode.menu_is_open()
		"save":
			return _saved
		_:
			return false


func _reset_track(mode: Node3D) -> void:
	_practice = 0.0
	_left = 0
	_seen.clear()
	_spun_free = false
	if mode == null or mode._camera == null:
		return
	_last_pos = mode._camera.global_position
	_last_y = mode._camera.global_position.y
	_last_yaw = mode._camera.yaw
	_last_pitch = mode._camera.pitch
	_last_reach = mode._camera.reach
	_last_piece_yaw = mode._place.yaw
	_last_radius = mode._group.radius
	_last_yaw_snap = mode._place.yaw_snap


func _track(mode: Node3D, delta: float) -> void:
	if mode == null or mode._camera == null:
		return
	match id():
		"fly", "hold":
			if id() == "hold" and not mode._place.is_holding():
				_practice = 0.0
			elif _flat(mode._camera.global_position).distance_to(_flat(_last_pos)) > 0.08:
				_practice += delta
			_last_pos = mode._camera.global_position
		"yaw_snap":
			if not mode._place.yaw_snap and absf(mode._place.yaw - _last_piece_yaw) > 0.5:
				_spun_free = true
			_last_piece_yaw = mode._place.yaw
			_last_yaw_snap = mode._place.yaw_snap
		"look":
			if (
				absf(mode._camera.yaw - _last_yaw) > 0.35
				or absf(mode._camera.pitch - _last_pitch) > 0.35
			):
				_practice += delta
			_last_yaw = mode._camera.yaw
			_last_pitch = mode._camera.pitch
		"climb":
			if mode._camera.global_position.y > _last_y + 0.02:
				_practice += delta
			_last_y = mode._camera.global_position.y
		"drop":
			if mode._camera.global_position.y < _last_y - 0.02:
				_practice += delta
			_last_y = mode._camera.global_position.y
		"turn":
			if absf(mode._place.yaw - _last_piece_yaw) > 0.5:
				_practice += 1.0
			_last_piece_yaw = mode._place.yaw
		"grow":
			if not is_equal_approx(mode._group.radius, _last_radius):
				_practice += 1.0
			_last_radius = mode._group.radius
		"cycle_fairway":
			_note_seen(mode._fairway.picked)
		"cycle_place":
			_note_seen(mode._place.picked)
		_:
			pass


func _note_seen(value: int) -> void:
	if _seen.has(value):
		return
	_seen.append(value)


func _refresh_left(mode: Node3D) -> void:
	var next := _count_left(mode)
	if next == _left:
		return
	_left = next
	prompted.emit(prompt())


func _count_left(mode: Node3D) -> int:
	if mode == null or mode.hole == null:
		return 0
	match id():
		"place_fairway":
			return maxi(0, NEED_FAIRWAY - _gained_pieces(mode))
		"place_again":
			return maxi(0, NEED_AGAIN - _gained_pieces(mode))
		"place_obstacles":
			return maxi(0, NEED_RAMPS - _ramp_count(mode))
		"place_prop":
			return maxi(0, NEED_PROPS - _new_kinds(mode, PieceCatalog.PROP_DIR).size())
		"cycle_fairway", "cycle_place":
			return maxi(0, NEED_CYCLE - _seen.size())
		"turn", "grow":
			return maxi(0, NEED_NUDGE - int(_practice))
		_:
			return 0


func _gained_pieces(mode: Node3D) -> int:
	return mode.hole.pieces.size() - int(_snap.get("pieces", 0))


func _ramp_count(mode: Node3D) -> int:
	var n := 0
	var start := int(_snap.get("placed", 0))
	for i in range(start, mode.hole.placements.size()):
		if _is_ramp(String(mode.hole.placements[i][CustomHole.PATH])):
			n += 1
	return n


func _is_ramp(path: String) -> bool:
	return path.get_file().begins_with("ramp_")


func _is_rocket(path: String) -> bool:
	return path == ROCKET


func _is_cart(path: String) -> bool:
	return path == CART


func _step_index(step_id: String) -> int:
	for i in STEPS.size():
		if String(STEPS[i]["id"]) == step_id:
			return i
	return STEPS.size()


func _new_kinds(mode: Node3D, prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	var start := int(_snap.get("placed", 0))
	for i in range(start, mode.hole.placements.size()):
		var path := String(mode.hole.placements[i][CustomHole.PATH])
		if not path.begins_with(prefix) or out.has(path):
			continue
		out.append(path)
	return out


func _placed_kind(mode: Node3D, ok: Callable) -> bool:
	if mode.hole.placements.size() <= int(_snap.get("placed", 0)):
		return false
	return bool(ok.call(_last_path(mode)))


func _last_path(mode: Node3D) -> String:
	if mode.hole.placements.is_empty():
		return ""
	return String(mode.hole.placements[mode.hole.placements.size() - 1][CustomHole.PATH])


func _gated_weapon(mode: Node3D) -> bool:
	for entry in mode.hole.placements:
		if CustomHole.is_weapon(String(entry[CustomHole.PATH])):
			if float(entry.get(CustomHole.GATE, CustomHole.NO_GATE)) != CustomHole.NO_GATE:
				return true
	return false


func _finished_spawn(mode: Node3D) -> bool:
	for entry in mode.hole.placements:
		if not CustomHole.is_spawn(String(entry[CustomHole.PATH])):
			continue
		if SpawnPack.total(entry.get(CustomHole.COUNTS, {})) > 0:
			return true
	return false


func _capture(mode: Node3D) -> Dictionary:
	if mode == null or mode._camera == null:
		return {}
	return {
		"pos": mode._camera.global_position,
		"y": mode._camera.global_position.y,
		"yaw": mode._camera.yaw,
		"pitch": mode._camera.pitch,
		"reach": mode._camera.reach,
		"pieces": mode.hole.pieces.size(),
		"placed": mode.hole.placements.size(),
		"fairway": mode._fairway.picked,
		"place": mode._place.picked,
		"piece_yaw": mode._place.yaw,
		"shelf": mode._place.shelf(),
		"surface": mode._place.surface_snap,
		"yaw_snap": mode._place.yaw_snap,
		"radius": mode._group.radius,
		"structures": HoleStore.list_structures().size(),
	}


func _flat(at: Vector3) -> Vector3:
	at.y = 0.0
	return at
