class_name VoiceRack
extends RefCounted
## Record and Voice buses plus one generator player per talking peer.

const RECORD_BUS := "Record"
const VOICE_BUS := "Voice"

var capture: AudioEffectCapture
var _players: Dictionary = {}


func ensure_buses() -> void:
	if AudioServer.get_bus_index(RECORD_BUS) < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, RECORD_BUS)
		AudioServer.set_bus_mute(idx, true)
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
	if AudioServer.get_bus_index(VOICE_BUS) < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, VOICE_BUS)
		AudioServer.set_bus_send(idx, "Master")
	var record := AudioServer.get_bus_index(RECORD_BUS)
	for i in AudioServer.get_bus_effect_count(record):
		var effect := AudioServer.get_bus_effect(record, i)
		if effect is AudioEffectCapture:
			capture = effect
			return


func play(parent: Node, peer_id: int, frames: PackedVector2Array) -> void:
	if frames.is_empty() or parent == null:
		return
	ensure_buses()
	var playback := _playback_for(parent, peer_id)
	if playback == null:
		return
	var avail := playback.get_frames_available()
	if avail <= 0:
		return
	if frames.size() > avail:
		frames = frames.slice(0, avail)
	playback.push_buffer(frames)


func clear() -> void:
	for slot in _players.values():
		var player := slot.get("player") as AudioStreamPlayer
		if player != null:
			player.queue_free()
	_players.clear()


func _playback_for(parent: Node, peer_id: int) -> AudioStreamGeneratorPlayback:
	if _players.has(peer_id):
		return _players[peer_id].get("playback") as AudioStreamGeneratorPlayback
	var player := AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = VoiceCodec.RATE
	stream.buffer_length = 0.2
	player.stream = stream
	player.bus = VOICE_BUS
	parent.add_child(player)
	player.play()
	var slot := {"player": player, "playback": player.get_stream_playback()}
	_players[peer_id] = slot
	return slot.playback as AudioStreamGeneratorPlayback
