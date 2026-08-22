class_name Music
extends Object
## Three beds: lounge on the title screen, Gravity once a hole is on, and
## elevator music in the clubhouse. Lives on the tree root so a scene change
## does not restart it. Entering the clubhouse crossfades off the hole bed;
## walking away turns the elevator down; teeing off cuts it dead.

enum Track { NONE, LOUNGE, LEVEL, CLUBHOUSE }

const LEVEL_PATH := "res://assets/music/gravity.ogg"
const LOUNGE_PATH := "res://assets/music/lounge.wav"
const CLUBHOUSE_PATH := "res://assets/music/elevator.mp3"
const PLAYER_NAME := "MusicPlayer"
const FADER_NAME := "MusicFader"
const VOLUME_DB := {
	Track.LOUNGE: -11.0,
	Track.LEVEL: -10.0,
	Track.CLUBHOUSE: -10.0,
}
const CROSSFADE_SEC := 2.2
const SILENCE_DB := -80.0
## Full elevator volume inside the hall and just outside the doors.
const CLUBHOUSE_NEAR := 22.0
## Fallback quiet end when no tee is known. Match flow replaces this with the
## walk from the clubhouse to the next tee box.
const CLUBHOUSE_FAR := 48.0

static var current: int = Track.NONE
static var following_clubhouse := false
static var _fade_far := CLUBHOUSE_FAR

static var _fade: Tween


static func play_lounge() -> AudioStreamPlayer:
	return play(Track.LOUNGE)


static func play_level() -> AudioStreamPlayer:
	return play(Track.LEVEL)


static func play_clubhouse() -> AudioStreamPlayer:
	return play(Track.CLUBHOUSE)


static func enter_clubhouse() -> AudioStreamPlayer:
	return play(Track.CLUBHOUSE, CROSSFADE_SEC)


static func play(track: int, fade_sec: float = 0.0) -> AudioStreamPlayer:
	if track != Track.LOUNGE and track != Track.LEVEL and track != Track.CLUBHOUSE:
		return player()
	following_clubhouse = false
	_fade_far = CLUBHOUSE_FAR
	if current == track:
		var existing := player()
		if existing != null:
			if not existing.playing:
				existing.play()
			if fade_sec <= 0.0:
				_kill_fader()
				existing.volume_db = float(VOLUME_DB[track])
			return existing
	var stream := _load_track(track)
	if stream == null:
		return null
	var node := player()
	if node == null:
		node = _make_player(PLAYER_NAME)
		if node == null:
			return null
	if fade_sec > 0.0 and current != Track.NONE and node.playing:
		_crossfade_to(node, stream, track, fade_sec)
	else:
		_cut_to(node, stream, track)
	return node


static func follow_clubhouse(far_meters: float = -1.0) -> void:
	if current != Track.CLUBHOUSE:
		return
	following_clubhouse = true
	_fade_far = far_meters if far_meters > CLUBHOUSE_NEAR else CLUBHOUSE_FAR
	_stop_fade()
	_kill_fader()


static func set_listener_distance(meters: float) -> void:
	if not following_clubhouse or current != Track.CLUBHOUSE:
		return
	var node := player()
	if node == null:
		return
	node.volume_db = volume_at_distance(meters)


static func volume_at_distance(meters: float) -> float:
	var full := float(VOLUME_DB[Track.CLUBHOUSE])
	var span := _fade_far - CLUBHOUSE_NEAR
	var t := 0.0 if span <= 0.0 else clampf((meters - CLUBHOUSE_NEAR) / span, 0.0, 1.0)
	var linear := (1.0 - t) * db_to_linear(full)
	if linear <= 0.0001:
		return SILENCE_DB
	return linear_to_db(linear)


static func player() -> AudioStreamPlayer:
	return _named_player(PLAYER_NAME)


static func fader() -> AudioStreamPlayer:
	return _named_player(FADER_NAME)


static func is_playing() -> bool:
	var node := player()
	return node != null and node.playing


static func stop() -> void:
	current = Track.NONE
	following_clubhouse = false
	_fade_far = CLUBHOUSE_FAR
	_stop_fade()
	_free_named(FADER_NAME)
	_free_named(PLAYER_NAME)


static func _cut_to(node: AudioStreamPlayer, stream: AudioStream, track: int) -> void:
	_stop_fade()
	_kill_fader()
	node.stream = stream
	node.volume_db = float(VOLUME_DB[track])
	current = track
	node.play()


static func _crossfade_to(
	node: AudioStreamPlayer, stream: AudioStream, track: int, fade_sec: float
) -> void:
	_stop_fade()
	var outgoing := _make_player(FADER_NAME)
	if outgoing == null:
		_cut_to(node, stream, track)
		return
	outgoing.stream = node.stream
	outgoing.volume_linear = node.volume_linear
	outgoing.play(node.get_playback_position())
	node.stream = stream
	node.volume_linear = 0.0
	current = track
	node.play()
	var tween := node.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_parallel(true)
	tween.tween_property(node, "volume_linear", db_to_linear(float(VOLUME_DB[track])), fade_sec)
	tween.tween_property(outgoing, "volume_linear", 0.0, fade_sec)
	tween.set_parallel(false)
	tween.tween_callback(Callable(Music, "_kill_fader"))
	_fade = tween


static func _load_track(track: int) -> AudioStream:
	var path := LOUNGE_PATH
	if track == Track.LEVEL:
		path = LEVEL_PATH
	elif track == Track.CLUBHOUSE:
		path = CLUBHOUSE_PATH
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	_enable_loop(stream)
	return stream


static func _named_player(player_name: String) -> AudioStreamPlayer:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var node := tree.root.get_node_or_null(player_name) as AudioStreamPlayer
	if node == null or node.is_queued_for_deletion():
		return null
	return node


static func _make_player(player_name: String) -> AudioStreamPlayer:
	var existing := _named_player(player_name)
	if existing != null:
		return existing
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var node := AudioStreamPlayer.new()
	node.name = player_name
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(node)
	return node


static func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


static func _stop_fade() -> void:
	if _fade != null:
		_fade.kill()
		_fade = null


static func _kill_fader() -> void:
	_free_named(FADER_NAME)


static func _free_named(player_name: String) -> void:
	var node := _named_player(player_name)
	if node == null:
		return
	node.stop()
	node.free()
