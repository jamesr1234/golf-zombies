class_name VoicePad
extends VBoxContainer
## Mic, speakers, gain, and a live talk meter for the lobby.

var _mic: OptionButton
var _speakers: OptionButton
var _mute: Button
var _open: Button
var _gain: HSlider
var _gain_label: Label
var _meter_fill: ColorRect
var _hint: Label


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 4)
	add_child(LobbyChrome.heading("Voice", true))
	_mic = LobbyChrome.menu(true)
	_mic.item_selected.connect(_on_mic)
	add_child(_mic)
	_speakers = LobbyChrome.menu(true)
	_speakers.item_selected.connect(_on_speakers)
	add_child(_speakers)
	_mute = LobbyChrome.button("Mute mic", true)
	_mute.pressed.connect(_on_mute)
	_open = LobbyChrome.button("Open mic", true)
	_open.pressed.connect(_on_open)
	add_child(LobbyChrome.row([_mute, _open], true))
	add_child(_gain_row())
	add_child(_meter())
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.label_settings = HudStyle.readout(Palette.ICE, 12)
	add_child(_hint)
	VoiceChat.speaking_changed.connect(refresh)
	VoiceChat.prefs_changed.connect(refresh)
	VoiceChat.set_preview(true)
	refresh()


func _exit_tree() -> void:
	VoiceChat.set_preview(false)
	if VoiceChat.speaking_changed.is_connected(refresh):
		VoiceChat.speaking_changed.disconnect(refresh)
	if VoiceChat.prefs_changed.is_connected(refresh):
		VoiceChat.prefs_changed.disconnect(refresh)


func _process(_delta: float) -> void:
	if _meter_fill == null:
		return
	var level := clampf(VoiceChat.input_level, 0.0, 1.0)
	_meter_fill.anchor_right = level
	if level > 0.85:
		_meter_fill.color = Palette.ORANGE
	elif level > 0.12:
		_meter_fill.color = Palette.LIME
	else:
		_meter_fill.color = Palette.ICE


func refresh() -> void:
	_fill(_mic, VoiceChat.input_devices(), VoiceChat.input_device())
	_fill(_speakers, VoiceChat.output_devices(), VoiceChat.output_device())
	_mute.text = HudStyle.chrome("Unmute mic" if VoiceChat.muted else "Mute mic")
	_open.text = HudStyle.chrome("Push to talk" if VoiceChat.open_mic else "Open mic")
	_hint.text = HudStyle.chrome(VoiceChat.lobby_hint())
	if _gain != null and not is_equal_approx(_gain.value, VoiceChat.mic_gain):
		_gain.set_value_no_signal(VoiceChat.mic_gain)
	_refresh_gain_label()


func _gain_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_gain_label = Label.new()
	_gain_label.custom_minimum_size = Vector2(92.0, 18.0)
	_gain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gain_label.label_settings = HudStyle.readout(Palette.AZURE, 12)
	row.add_child(_gain_label)
	_gain = LobbyChrome.slider(0.0, VoiceCodec.MAX_GAIN, VoiceChat.mic_gain)
	_gain.value_changed.connect(_on_gain)
	row.add_child(_gain)
	return row


func _meter() -> ColorRect:
	var track := ColorRect.new()
	track.custom_minimum_size = Vector2(280.0, 10.0)
	track.color = Color(Palette.ICE, 0.16)
	track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	track.clip_contents = true
	_meter_fill = ColorRect.new()
	_meter_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_meter_fill.anchor_right = 0.0
	_meter_fill.offset_left = 0.0
	_meter_fill.offset_right = 0.0
	_meter_fill.offset_top = 1.0
	_meter_fill.offset_bottom = -1.0
	_meter_fill.color = Palette.ICE
	_meter_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_meter_fill)
	return track


func _fill(menu: OptionButton, names: PackedStringArray, current: String) -> void:
	var selected := current if current != "" else "Default"
	var same := menu.item_count == names.size()
	if same:
		for i in names.size():
			if menu.get_item_text(i) != names[i]:
				same = false
				break
	if not same:
		menu.clear()
		for name in names:
			menu.add_item(name)
	for i in names.size():
		if names[i] == selected:
			menu.select(i)
			return
	if menu.item_count > 0:
		menu.select(0)


func _refresh_gain_label() -> void:
	if _gain_label == null:
		return
	_gain_label.text = HudStyle.chrome("Mic %s" % VoiceCodec.gain_label(VoiceChat.mic_gain))


func _on_mic(index: int) -> void:
	VoiceChat.set_input_device(_mic.get_item_text(index))


func _on_speakers(index: int) -> void:
	VoiceChat.set_output_device(_speakers.get_item_text(index))


func _on_mute() -> void:
	Sfx.play("ui_confirm", self)
	VoiceChat.set_muted(not VoiceChat.muted)


func _on_open() -> void:
	Sfx.play("ui_confirm", self)
	VoiceChat.set_open_mic(not VoiceChat.open_mic)


func _on_gain(value: float) -> void:
	VoiceChat.set_mic_gain(value)
	_refresh_gain_label()
