extends GutTest
## Voice stays a Godot capture plus RPC. These cases never open a mic.

const FREE_PORT := 47781


func before_each() -> void:
	VoiceChat.reset_for_test()


func after_each() -> void:
	NetSession.close()
	VoiceChat.reset_for_test()
	GameSettings.reset()
	_wipe_prefs()
	InputActions.register_for_mode(GameSettings.Mode.SOLO)


func test_a_tone_survives_a_round_trip() -> void:
	var wave := VoiceCodec.tone(VoiceCodec.PACKET_FRAMES)
	var back := VoiceCodec.unpack(VoiceCodec.pack(wave))
	assert_eq(back.size(), VoiceCodec.PACKET_FRAMES)
	assert_almost_eq(VoiceCodec.rms(back), VoiceCodec.rms(wave), 0.02)


func test_silence_is_not_speech() -> void:
	assert_false(VoiceCodec.is_speech(VoiceCodec.silence(VoiceCodec.PACKET_FRAMES)))
	assert_true(VoiceCodec.is_speech(VoiceCodec.tone(VoiceCodec.PACKET_FRAMES)))


func test_mute_and_ptt_gate_a_send() -> void:
	assert_false(VoiceCodec.should_transmit(true, false, true, true), "mute wins")
	assert_false(VoiceCodec.should_transmit(false, false, false, true), "PTT is off")
	assert_true(VoiceCodec.should_transmit(false, false, true, false), "PTT sends even if quiet")
	assert_true(VoiceCodec.should_transmit(false, true, false, true), "open mic needs speech")
	assert_false(VoiceCodec.should_transmit(false, true, true, false), "open mic ignores PTT on hush")


func test_cpu_peers_are_skipped() -> void:
	assert_false(VoiceChat.accepts_sender(CoopVs.cpu_peer_id(0)))
	assert_false(VoiceCodec.accepts_peer(-2))
	assert_true(VoiceChat.accepts_sender(1))
	assert_true(VoiceChat.accepts_sender(2))


func test_stays_idle_without_a_session() -> void:
	assert_false(NetSession.is_active())
	assert_false(VoiceChat.try_send(VoiceCodec.tone(VoiceCodec.PACKET_FRAMES), true))
	assert_eq(VoiceChat.send_count, 0)
	assert_false(VoiceChat.is_capturing())


func test_headless_does_not_open_the_mic() -> void:
	if DisplayServer.get_name() != "headless":
		pass_test("this GUT run has a window")
		return
	assert_false(VoiceChat.can_open_mic())


func test_a_session_does_not_open_the_mic_until_someone_talks() -> void:
	assert_eq(NetSession.host(FREE_PORT), OK)
	assert_false(VoiceChat.is_capturing(), "PTT default does not open the mic")
	assert_true(VoiceChat.try_send(VoiceCodec.tone(VoiceCodec.PACKET_FRAMES), true))
	assert_eq(VoiceChat.send_count, 1)
	assert_true(VoiceChat.talking)
	assert_true(VoiceChat.is_speaking(multiplayer.get_unique_id()))


func test_mute_blocks_a_live_send() -> void:
	assert_eq(NetSession.host(FREE_PORT), OK)
	VoiceChat.set_muted(true)
	assert_false(VoiceChat.try_send(VoiceCodec.tone(VoiceCodec.PACKET_FRAMES), true))
	assert_eq(VoiceChat.send_count, 0)


func test_open_mic_needs_speech() -> void:
	assert_eq(NetSession.host(FREE_PORT), OK)
	VoiceChat.set_open_mic(true)
	assert_false(VoiceChat.try_send(VoiceCodec.silence(VoiceCodec.PACKET_FRAMES), true))
	assert_true(VoiceChat.try_send(VoiceCodec.tone(VoiceCodec.PACKET_FRAMES), false))


func test_prefs_remember_the_headset() -> void:
	VoiceChat.set_muted(true)
	VoiceChat.set_open_mic(true)
	VoiceChat.set_input_device("AirPods")
	VoiceChat.set_output_device("AirPods")
	var prefs := VoiceCodec.read_prefs(VoiceChat.config_path)
	assert_true(bool(prefs.muted))
	assert_true(bool(prefs.open_mic))
	assert_eq(str(prefs.mic), "AirPods")
	assert_eq(str(prefs.speakers), "AirPods")


func test_device_choices_keep_default_first() -> void:
	var names := VoiceCodec.device_choices(PackedStringArray(["Built-in", "Headset"]), "Headset")
	assert_eq(names[0], "Default")
	assert_true(names.has("Headset"))
	assert_true(names.has("Built-in"))


func test_online_talk_is_on_t_and_select() -> void:
	InputActions.register_for_mode(GameSettings.Mode.ONLINE_VS)
	assert_true(_has_key("p1_talk", KEY_T))
	assert_true(_has_joy("p1_talk", JOY_BUTTON_BACK))


func test_downsample_keeps_a_tone() -> void:
	var high := VoiceCodec.tone(480)
	var low := VoiceCodec.downsample(high, 48000, 16000)
	assert_eq(low.size(), 160)
	assert_gt(VoiceCodec.rms(low), 0.1)


func _has_key(action: String, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
			return true
	return false


func _has_joy(action: String, button: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return true
	return false


func _wipe_prefs() -> void:
	var abs := ProjectSettings.globalize_path(VoiceChat.config_path)
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)
