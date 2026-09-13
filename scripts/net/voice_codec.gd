class_name VoiceCodec
extends Object
## 16 kHz mono PCM plus a cheap energy gate. A short hangover keeps a quiet
## word from dropping the line. VoiceChat owns devices and RPCs; this file
## stays headless so GUT can pack a tone without opening a mic.

const RATE := 16000
const PACKET_MS := 20
const PACKET_FRAMES := RATE * PACKET_MS / 1000
const VAD_THRESHOLD := 0.005
const VAD_HANG_PACKETS := 18
const LIVE_PATH := "user://voice.cfg"
const TEST_PATH := "user://voice_test.cfg"


static func pack(frames: PackedVector2Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(frames.size() * 2)
	for i in frames.size():
		var sample := clampf((frames[i].x + frames[i].y) * 0.5, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))
	return bytes


static func unpack(bytes: PackedByteArray) -> PackedVector2Array:
	var count := bytes.size() / 2
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in count:
		var sample := float(bytes.decode_s16(i * 2)) / 32768.0
		frames[i] = Vector2(sample, sample)
	return frames


static func rms(frames: PackedVector2Array) -> float:
	if frames.is_empty():
		return 0.0
	var acc := 0.0
	for frame in frames:
		var sample := (frame.x + frame.y) * 0.5
		acc += sample * sample
	return sqrt(acc / float(frames.size()))


static func is_speech(frames: PackedVector2Array, threshold := VAD_THRESHOLD) -> bool:
	return rms(frames) >= threshold


static func should_transmit(
	muted: bool, open_mic: bool, ptt: bool, speech: bool, hanging := false
) -> bool:
	if muted:
		return false
	if not open_mic:
		return ptt
	return speech or hanging


static func next_hang(speech: bool, hang: int, packets := VAD_HANG_PACKETS) -> int:
	return packets if speech else maxi(hang - 1, 0)


static func accepts_peer(peer_id: int) -> bool:
	return peer_id > 0 and not CoopVs.is_cpu_peer(peer_id)


static func downsample(frames: PackedVector2Array, from_rate: int, to_rate: int) -> PackedVector2Array:
	if frames.is_empty() or from_rate <= 0 or to_rate <= 0:
		return PackedVector2Array()
	if from_rate == to_rate:
		return frames
	var ratio := float(from_rate) / float(to_rate)
	var count := int(floor(float(frames.size()) / ratio))
	var out := PackedVector2Array()
	out.resize(count)
	for i in count:
		out[i] = frames[int(i * ratio)]
	return out


static func tone(frames: int, amplitude := 0.4) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(maxi(0, frames))
	for i in out.size():
		var sample := amplitude * sin(float(i) * 0.4)
		out[i] = Vector2(sample, sample)
	return out


static func silence(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(maxi(0, frames))
	return out


static func device_choices(listed: PackedStringArray, current := "") -> PackedStringArray:
	var out := PackedStringArray(["Default"])
	for name in listed:
		if name != "" and name != "Default" and not out.has(name):
			out.append(name)
	if current != "" and current != "Default" and not out.has(current):
		out.append(current)
	return out


static func write_prefs(path: String, muted: bool, open_mic: bool, mic: String, speakers: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("voice", "muted", muted)
	cfg.set_value("voice", "open_mic", open_mic)
	cfg.set_value("voice", "mic", mic)
	cfg.set_value("voice", "speakers", speakers)
	cfg.save(path)


static func read_prefs(path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	var out := {"muted": false, "open_mic": false, "mic": "", "speakers": ""}
	if cfg.load(path) != OK:
		return out
	out.muted = bool(cfg.get_value("voice", "muted", false))
	out.open_mic = bool(cfg.get_value("voice", "open_mic", false))
	out.mic = str(cfg.get_value("voice", "mic", ""))
	out.speakers = str(cfg.get_value("voice", "speakers", ""))
	return out
