class_name NetDebug
extends Label
## Temporary readout for the online frame-drop hunt. It tells a real render hitch,
## where frame time spikes, apart from an interpolation stall, where frames stay on
## time but snapshots land late so a puppet parks and then jumps. Toggle with F3.
## The same lines go to the Output log every two seconds, on a hitch, and once
## more when you hide the overlay, so you can copy them after the match.
##
## Reading it: if WORST climbs well past 16 ms when you see the hitch, the client
## is dropping frames. If frame time holds and a puppet's STALL climbs instead,
## the frames are fine and the snapshots are late.
##
## When frames are slow, GPU is what separates a fill-rate problem from a code
## one. It is the card's own time on this viewport, so it climbs with resolution
## and shader cost rather than with how much script is running. RENDER is the cpu
## side of handing that work over, and PHYSICS is the simulation step. Godot
## folds drawing and the vsync wait into its process timer, so that number only
## ever repeats the frame time and is not worth showing.
##
## A hitch on a steady beat is something on a timer, so HITCH reports the gap
## between the last two and how far the node count moved across the bad frame.
## Nodes arriving on the beat means the cost is building whatever spawned.

## A frame this long is a visible hitch at 60 Hz.
const SPIKE_MS := 30.0
## How long the worst frame stands before it decays, so the number reflects recent
## play rather than the whole match.
const WORST_HOLD := 6.0
## How often the same lines go to the Output log while the overlay is up.
const LOG_EVERY := 2.0
## A floor on logging, even while spiking. On a machine slow enough that every
## frame counts as a spike, a print per frame is its own performance problem and
## would poison the very reading we are taking.
const LOG_MIN_GAP := 0.5

var world: Node3D

var _worst_ms := 0.0
var _worst_left := 0.0
var _spikes := 0
var _since_log := 0.0
var _last_delta := 1.0 / 60.0
var _nodes_seen := 0
var _since_spike := 0.0
var _spike_period := 0.0
var _spike_grew := 0


func _ready() -> void:
	label_settings = HudStyle.readout(Palette.LIME, 13)
	position = Vector2(24.0, 24.0)
	visible = false
	_nodes_seen = node_count()


func _process(delta: float) -> void:
	_last_delta = delta
	var spiked := _track_frame(delta)
	if not visible:
		return
	text = HudStyle.chrome(report(delta))
	_since_log += delta
	if due_to_log(spiked, _since_log):
		dump(delta)
		_since_log = 0.0


static func due_to_log(spiked: bool, since_log: float) -> bool:
	if since_log >= LOG_EVERY:
		return true
	return spiked and since_log >= LOG_MIN_GAP


## Toggling on clears the counters, so a second press is how you start a fresh
## reading before trying to trigger the hitch again. Toggling off dumps one last
## reading to the Output log so you can copy it after the hitch.
func toggle() -> String:
	if visible:
		var body := dump(_last_delta)
		visible = false
		_measure(false)
		return body
	visible = true
	_measure(true)
	reset()
	return ""


## Timing the card costs a little of what it measures, so only ask for it while
## the overlay is up.
func _measure(on: bool) -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), on)


func reset() -> void:
	_worst_ms = 0.0
	_worst_left = 0.0
	_spikes = 0
	_since_log = 0.0
	_since_spike = 0.0
	_spike_period = 0.0
	_spike_grew = 0
	_nodes_seen = node_count()
	for interp in puppets().values():
		interp.reset_stats()


static func node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func dump(delta: float) -> String:
	var body := report(delta)
	print("[net-debug]\n%s" % body)
	return body


func _track_frame(delta: float) -> bool:
	var ms := delta * 1000.0
	var spiked := ms >= SPIKE_MS
	var nodes := node_count()
	var grew := nodes - _nodes_seen
	_nodes_seen = nodes
	_since_spike += delta
	if spiked:
		_spikes += 1
		_spike_period = _since_spike
		_spike_grew = grew
		_since_spike = 0.0
	_worst_left = maxf(0.0, _worst_left - delta)
	if ms > _worst_ms or _worst_left <= 0.0:
		_worst_ms = ms
		_worst_left = WORST_HOLD
	return spiked


func report(delta: float) -> String:
	var rid := get_viewport().get_viewport_rid()
	var view := get_viewport().get_visible_rect().size
	var lines: PackedStringArray = [
		"fps %d   frame %.1f ms   worst %.1f ms   spikes %d" % [
			Engine.get_frames_per_second(), delta * 1000.0, _worst_ms, _spikes
		],
		"gpu %.1f ms   render %.1f ms   physics %.1f ms" % [
			RenderingServer.viewport_get_measured_render_time_gpu(rid),
			RenderingServer.viewport_get_measured_render_time_cpu(rid),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		],
		"draw %d   objects %d   view %dx%d" % [
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			int(view.x), int(view.y),
		],
		"nodes %d   bodies %d   pairs %d" % [
			_nodes_seen,
			int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
			int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		],
		"hitch every %.2f s   %+d nodes on it" % [_spike_period, _spike_grew],
	]
	lines.append(link_line(multiplayer.multiplayer_peer as ENetMultiplayerPeer, multiplayer.get_peers()))
	var remote := puppets()
	if remote.is_empty():
		lines.append("no remote puppets")
	for label in remote:
		lines.append(line_for(label, remote[label]))
	return "\n".join(lines)


## What the transport thinks of the link. JITTER is the one that matters here: a
## puppet can only arrive as steadily as the wire delivers, so a jittery link
## shows up as a stall no matter how good the frame rate is at either end.
static func link_line(enet: ENetMultiplayerPeer, ids: PackedInt32Array) -> String:
	if enet == null or ids.is_empty():
		return "link idle"
	var peer := enet.get_peer(ids[0])
	if peer == null:
		return "link idle"
	return "ping %d ms   jitter %d ms   loss %.1f%%" % [
		int(peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)),
		int(peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)),
		peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / 65536.0 * 100.0,
	]


## DEPTH is how far behind live this puppet is being drawn. It grows itself to
## cover the gaps the link is making, so watching it climb is watching the wire
## get worse.
static func line_for(label: String, interp: NetInterp) -> String:
	return "%s   gap %d ms   worst %d ms   stall %d%%   depth %d ms   snap %d" % [
		label,
		roundi(interp.last_gap * 1000.0),
		roundi(interp.worst_gap * 1000.0),
		roundi(interp.stall_percent()),
		roundi(interp.depth * 1000.0),
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
