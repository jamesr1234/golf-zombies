class_name DemoEnd
extends Control
## After the demo hole: how it went, the ranked result and top scores when it
## counted, back to the menu, and the call to action.

const TOP := 5

## Set on the scene once the store page or brand link exists. Empty hides it.
@export var cta_url := ""
@export var cta_label := "GET THE FULL GAME"

static var won := false
static var strokes := -1
static var par := 0
static var played := false

var _api: LeaderboardApi
var _ranked_info: Label
var _board: Label


static func record(p_won: bool, p_strokes: int, p_par: int) -> void:
	won = p_won
	strokes = p_strokes
	par = p_par
	played = true


static func holed() -> bool:
	return played and won and strokes > 0


static func headline() -> String:
	if not played:
		return "THANKS FOR PLAYING"
	if holed():
		return "HOLED IN %d" % strokes
	return "THE ZOMBIES GOT YOU"


static func detail() -> String:
	if not holed():
		return "Give it another swing."
	var diff := strokes - par
	if diff == 0:
		return "Par %d. Right on the number." % par
	return "Par %d. %s%d." % [par, "+" if diff > 0 else "", diff]


static func rank_copy(result: Dictionary) -> String:
	var rank: Variant = result.get("rank")
	if rank == null:
		return "Ranked try used. No score this time."
	return "Leaderboard rank #%d (%.1fs)" % [int(rank), float(result.get("seconds", 0.0))]


static func board_copy(scores: Array) -> String:
	var lines := PackedStringArray(["TOP SCORES"])
	for i in scores.size():
		var row: Dictionary = scores[i]
		lines.append("%d. %s  %d strokes  %.1fs" % [i + 1, row.nickname, int(row.strokes), float(row.seconds)])
	if scores.is_empty():
		lines.append("No scores yet. Be the first.")
	return "\n".join(lines)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_api = LeaderboardApi.new()
	add_child(_api)
	var column := DemoUi.column(self)
	column.add_child(DemoUi.label(headline(), HudStyle.banner(Palette.ORANGE, 48)))
	column.add_child(DemoUi.label(detail(), HudStyle.readout(Palette.ICE)))
	_ranked_info = DemoUi.label("", HudStyle.readout(Palette.CYAN))
	column.add_child(_ranked_info)
	_board = DemoUi.label("", HudStyle.readout(Palette.ICE, HudStyle.BODY_SIZE))
	column.add_child(_board)
	column.add_child(DemoUi.button("PLAY AGAIN", _play_again))
	if not cta_url.is_empty():
		column.add_child(DemoUi.button(cta_label, _open_cta))
	if DemoRun.ranked:
		_report()


## A ranked round always ends here, even if it was quit from the pause menu,
## so the spent try is closed out as unholed rather than left hanging.
func _report() -> void:
	var ticket := DemoRun.take_ticket()
	if ticket.is_empty():
		return
	_ranked_info.text = "Saving your score..."
	var reply := await _api.finish_run(ticket, holed(), maxi(strokes, 0))
	var lines := PackedStringArray([rank_copy(reply.data) if reply.ok else reply.error])
	var status := await _api.code_status(DemoRun.code)
	if status.ok:
		lines.append(DemoRun.tries_copy(status.data))
	_ranked_info.text = "\n".join(lines)
	var top := await _api.top(TOP)
	if top.ok:
		_board.text = board_copy(top.data.get("scores", []))


func _play_again() -> void:
	get_tree().change_scene_to_file(DemoBoot.MENU)


func _open_cta() -> void:
	OS.shell_open(cta_url)
