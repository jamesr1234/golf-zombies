extends Node
## Session-wide voice for online lobby and match. Captures the chosen headset
## mic, sends 20 ms PCM to every human peer, and plays theirs on a Voice bus.
## Steam Voice stays unused so LAN works and this file never touches Steam.

signal speaking_changed()
signal prefs_changed()

const SPEAK_HOLD := 0.35

var config_path := VoiceCodec.LIVE_PATH
var muted := false
var open_mic := false
var talking := false
var last_packet := PackedByteArray()
var send_count := 0
var speaking: Dictionary = {}
var _mic_name := ""
var _speaker_name := ""
var _rack := VoiceRack.new()
var _mic: AudioStreamPlayer
var _pending := PackedVector2Array()
var _capturing := false
var _vad_hang := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_args():
		if String(arg).contains("gut"):
			config_path = VoiceCodec.TEST_PATH
			break
	_load_prefs()


func _process(delta: float) -> void:
	_decay_speaking(delta)
	if not NetSession.is_active():
		_stop_capture()
		return
	if muted:
		talking = false
		_vad_hang = 0
		return
	if open_mic or _ptt_held():
		_ensure_capture()
		_capture_and_send()
	else:
		talking = false
		_vad_hang = 0


func can_open_mic() -> bool:
	return DisplayServer.get_name() != "headless"


func is_capturing() -> bool:
	return _capturing and _mic != null and _mic.playing


func is_speaking(peer_id: int) -> bool:
	return float(speaking.get(peer_id, 0.0)) > 0.0


func input_device() -> String:
	return _mic_name


func output_device() -> String:
	return _speaker_name


func input_devices() -> PackedStringArray:
	return VoiceCodec.device_choices(AudioServer.get_input_device_list(), _mic_name)


func output_devices() -> PackedStringArray:
	return VoiceCodec.device_choices(AudioServer.get_output_device_list(), _speaker_name)


func set_muted(on: bool) -> void:
	muted = on
	if muted:
		talking = false
		_vad_hang = 0
	_save_prefs()
	prefs_changed.emit()


func set_open_mic(on: bool) -> void:
	open_mic = on
	_save_prefs()
	prefs_changed.emit()


func set_input_device(name: String) -> void:
	_mic_name = "" if name == "Default" else name
	_apply_devices()
	_save_prefs()
	prefs_changed.emit()


func set_output_device(name: String) -> void:
	_speaker_name = "" if name == "Default" else name
	_apply_devices()
	_save_prefs()
	prefs_changed.emit()


func lobby_hint() -> String:
	if muted:
		return "Mic muted"
	if open_mic:
		return "Open mic on. Talking goes to everyone."
	return "Hold T or Select to talk"


func pause_hint() -> String:
	return lobby_hint()


func hud_line() -> String:
	if muted:
		return "Mic muted"
	if talking:
		return "Talk"
	var names: PackedStringArray = []
	for peer_id in speaking.keys():
		if int(peer_id) == multiplayer.get_unique_id():
			continue
		if is_speaking(int(peer_id)):
			var seat := NetSession.seat_for(int(peer_id))
			names.append(CoopVs.seat_name(seat) if seat >= 0 else "peer %d" % int(peer_id))
	if names.is_empty():
		return lobby_hint()
	return " ".join(names)


func try_send(frames: PackedVector2Array, ptt: bool) -> bool:
	var speech := VoiceCodec.is_speech(frames)
	var hanging := _vad_hang > 0
	if not VoiceCodec.should_transmit(muted, open_mic, ptt, speech, hanging):
		talking = false
		return false
	if not NetSession.is_active():
		talking = false
		return false
	_vad_hang = VoiceCodec.next_hang(speech, _vad_hang)
	talking = true
	_mark_speaking(multiplayer.get_unique_id())
	_transmit(VoiceCodec.pack(frames))
	return true


func accepts_sender(peer_id: int) -> bool:
	return VoiceCodec.accepts_peer(peer_id)


func _ptt_held() -> bool:
	return InputMap.has_action("p1_talk") and Input.is_action_pressed("p1_talk")


func reset_for_test() -> void:
	muted = false
	open_mic = false
	talking = false
	last_packet = PackedByteArray()
	send_count = 0
	speaking.clear()
	_pending = PackedVector2Array()
	_vad_hang = 0
	_stop_capture()


func _capture_and_send() -> void:
	if _rack.capture == null or not is_capturing():
		return
	var avail := _rack.capture.get_frames_available()
	if avail <= 0:
		return
	var raw := _rack.capture.get_buffer(avail)
	var frames := VoiceCodec.downsample(raw, int(AudioServer.get_mix_rate()), VoiceCodec.RATE)
	_pending.append_array(frames)
	var ptt := _ptt_held()
	while _pending.size() >= VoiceCodec.PACKET_FRAMES:
		var chunk := _pending.slice(0, VoiceCodec.PACKET_FRAMES)
		_pending = _pending.slice(VoiceCodec.PACKET_FRAMES)
		try_send(chunk, ptt)


func _transmit(packet: PackedByteArray) -> void:
	last_packet = packet
	send_count += 1
	if not NetSession.is_active():
		return
	_hear.rpc(packet)


@rpc("any_peer", "call_remote", "unreliable")
func _hear(packet: PackedByteArray) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not accepts_sender(from):
		return
	_mark_speaking(from)
	if can_open_mic():
		_rack.play(self, from, VoiceCodec.unpack(packet))


func _mark_speaking(peer_id: int) -> void:
	speaking[peer_id] = SPEAK_HOLD
	speaking_changed.emit()


func _decay_speaking(delta: float) -> void:
	var gone: Array = []
	for peer_id in speaking.keys():
		speaking[peer_id] = float(speaking[peer_id]) - delta
		if float(speaking[peer_id]) <= 0.0:
			gone.append(peer_id)
	for peer_id in gone:
		speaking.erase(peer_id)
		if int(peer_id) == multiplayer.get_unique_id():
			talking = false
	if not gone.is_empty():
		speaking_changed.emit()


func _ensure_capture() -> void:
	if _capturing or not can_open_mic():
		return
	InputActions.register_for_mode(GameSettings.mode)
	_rack.ensure_buses()
	_apply_devices()
	if _mic == null:
		_mic = AudioStreamPlayer.new()
		_mic.stream = AudioStreamMicrophone.new()
		_mic.bus = VoiceRack.RECORD_BUS
		add_child(_mic)
	_mic.play()
	_capturing = true


func _stop_capture() -> void:
	if _mic != null:
		_mic.stop()
	_capturing = false
	_pending = PackedVector2Array()
	_vad_hang = 0
	talking = false
	_rack.clear()


func _apply_devices() -> void:
	if not can_open_mic():
		return
	AudioServer.input_device = _mic_name if _mic_name != "" else "Default"
	AudioServer.output_device = _speaker_name if _speaker_name != "" else "Default"


func _load_prefs() -> void:
	var prefs := VoiceCodec.read_prefs(config_path)
	muted = bool(prefs.muted)
	open_mic = bool(prefs.open_mic)
	_mic_name = str(prefs.mic)
	_speaker_name = str(prefs.speakers)
	_apply_devices()


func _save_prefs() -> void:
	VoiceCodec.write_prefs(config_path, muted, open_mic, _mic_name, _speaker_name)
