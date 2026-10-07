class_name LeaderboardApi
extends Node
## Talks to the bottle leaderboard server. Every call resolves to
## {ok, status, data, error} so screens never have to think about HTTP.
##
## The web build asks the site it was served from. Anywhere else (the editor,
## a test run) uses LEADERBOARD_URL, or the server running on this machine.

const DEV_URL := "http://127.0.0.1:8787"
const TIMEOUT := 10.0


static func base_url() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.origin", true))
	var from_env := OS.get_environment("LEADERBOARD_URL")
	return from_env if not from_env.is_empty() else DEV_URL


func code_status(code: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/api/code/%s" % code)


func set_nickname(code: String, nickname: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/api/code/%s/nickname" % code, {"nickname": nickname})


func start_run(code: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/api/run/start", {"code": code})


func finish_run(ticket: String, holed: bool, strokes: int) -> Dictionary:
	return await _call(
		HTTPClient.METHOD_POST, "/api/run/finish", {"ticket": ticket, "holed": holed, "strokes": strokes}
	)


func top(limit: int) -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/api/leaderboard?limit=%d" % limit)


func _call(method: int, path: String, body := {}) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var payload := JSON.stringify(body) if method == HTTPClient.METHOD_POST else ""
	var sent := http.request(
		base_url() + path, PackedStringArray(["Content-Type: application/json"]), method, payload
	)
	if sent != OK:
		http.queue_free()
		return reply(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	var done: Array = await http.request_completed
	http.queue_free()
	return reply(done[0], done[1], (done[3] as PackedByteArray).get_string_from_utf8())


## Pure, so the copy for each failure can be tested without a server.
static func reply(result: int, status: int, text: String) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "data": {}, "error": "Can't reach the leaderboard right now."}
	# An error page from the proxy isn't JSON; parse quietly instead of logging.
	var json := JSON.new()
	var data: Dictionary = json.data if json.parse(text) == OK and json.data is Dictionary else {}
	var ok := status >= 200 and status < 300
	return {"ok": ok, "status": status, "data": data, "error": "" if ok else str(data.get("error", "Something went wrong."))}
