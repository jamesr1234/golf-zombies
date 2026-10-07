class_name DemoRun
extends RefCounted
## Which kind of demo round this is, carried from the menu to the end screen.
## Practice is free and never saved. Ranked spends one of the bottle code's
## tries the moment it starts and holds the server's ticket until the end.

## Same alphabet and length the server hands out, so a typo is caught here.
const _CODE := "^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{10}$"

static var ranked := false
static var code := ""
static var ticket := ""


## The bottle code from ?c= on the page address. DEMO_CODE stands in off the web.
static func page_code() -> String:
	var raw := ""
	if OS.has_feature("web"):
		raw = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('c')||''", true))
	else:
		raw = OS.get_environment("DEMO_CODE")
	return raw.strip_edges().to_upper()


static func valid_code(raw: String) -> bool:
	var pattern := RegEx.create_from_string(_CODE)
	return pattern.search(raw) != null


static func begin(p_ranked: bool, p_ticket := "") -> void:
	ranked = p_ranked
	ticket = p_ticket


## Hands the ticket over exactly once, so a score can never be sent twice.
static func take_ticket() -> String:
	var held := ticket
	ticket = ""
	return held


static func tries_copy(status: Dictionary) -> String:
	var left := int(status.get("tries_left", 0))
	var total := int(status.get("tries", 3))
	if left <= 0:
		return "No ranked tries left on this bottle. Practice is still free."
	return "%d of %d ranked tries left" % [left, total]


static func best_copy(status: Dictionary) -> String:
	var best: Variant = status.get("best")
	if not best is Dictionary:
		return ""
	return "Your best: %d strokes in %.1fs" % [int(best["strokes"]), float(best["seconds"])]
