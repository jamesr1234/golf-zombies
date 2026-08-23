class_name NetDebug
extends Label
## Temporary readout for the online frame-drop hunt. It tells a real render hitch,
## where frame time spikes, apart from an interpolation stall, where frames stay on
## time but snapshots land late so a puppet parks and then jumps. Toggle with F3.
##
## Reading it: if WORST climbs well past 16 ms when you see the hitch, the client
## is dropping frames. If frame time holds and a puppet's STALL climbs instead,
## the frames are fine and the snapshots are late.

## A frame this long is a visible hitch at 60 Hz.
const SPIKE_MS := 30.0
## How long the worst frame stands before it decays, so the number reflects recent
## play rather than the whole match.
const WORST_HOLD := 6.0

var world: Node3D

var _worst_ms := 0.0
var _worst_left := 0.0
var _spikes := 0


func _ready() -> void:
	label_settings = HudStyle.readout(Palette.LIME, 13)
	position = Vector2(24.0, 24.0)
	visible = false


func _process(delta: float) -> void:
	_track_frame(delta)
	if visible:
		text = HudStyle.chrome(report(delta))


## Toggling on clears the counters, so a second press is how you start a fresh
## reading before trying to trigger the hitch again.
func toggle() -> void:
	visible = not visible
	if visible:
		reset()


func reset() -> void:
	_worst_ms = 0.0
	_worst_left = 0.0
	_spikes = 0
	for interp in puppets().values():
		interp.reset_stats()


func _track_frame(delta: float) -> void:
	var ms := delta * 1000.0
	if ms >= SPIKE_MS:
		_spikes += 1
	_worst_left = maxf(0.0, _worst_left - delta)
	if ms > _worst_ms or _worst_left <= 0.0:
		_worst_ms = ms
		_worst_left = WORST_HOLD


func report(delta: float) -> String:
	var lines: PackedStringArray = [
		"fps %d   frame %.1f ms   worst %.1f ms   spikes %d" % [
			Engine.get_frames_per_second(), delta * 1000.0, _worst_ms, _spikes
		],
		"draw %d   objects %d" % [
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		],
	]
	var remote := puppets()
	if remote.is_empty():
		lines.append("no remote puppets")
	for label in remote:
		lines.append(line_for(label, remote[label]))
	return "\n".join(lines)


static func line_for(label: String, interp: NetInterp) -> String:
	return "%s   gap %d ms   worst %d ms   stall %d%%   snap %d" % [
		label,
		roundi(interp.last_gap * 1000.0),
		roundi(interp.worst_gap * 1000.0),
		roundi(interp.stall_percent()),
		interp.snaps,
	]


## Every replicated body this peer only watches, keyed by the name to show.
func puppets() -> Dictionary:
	var found := {}
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player != null and not NetSession.should_simulate(player):
			found["p%d" % player.peer_id] = player.net_interp()
	var carts: Node = world.get_node_or_null("Carts") if world != null else null
	if carts == null:
		return found
	for node in carts.get_children():
		var cart := node as GolfCart
		if cart != null and not NetSession.should_simulate(cart):
			found[String(cart.name).to_lower()] = cart.net_interp()
	return found
