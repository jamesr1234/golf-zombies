class_name VoicePad
extends VBoxContainer
## Mic, speakers, mute, and open-mic for the lobby. VoiceChat owns the state.

var _mic: OptionButton
var _speakers: OptionButton
var _mute: Button
var _open: Button
var _hint: Label


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 8)
	add_child(LobbyChrome.heading("Voice"))
	_mic = _device_menu()
	_mic.item_selected.connect(_on_mic)
	add_child(_mic)
	_speakers = _device_menu()
	_speakers.item_selected.connect(_on_speakers)
	add_child(_speakers)
	_mute = LobbyChrome.button("Mute mic")
	_mute.pressed.connect(_on_mute)
	_open = LobbyChrome.button("Open mic")
	_open.pressed.connect(_on_open)
	add_child(LobbyChrome.row([_mute, _open]))
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.label_settings = HudStyle.readout(Palette.ICE, 14)
	add_child(_hint)
	VoiceChat.speaking_changed.connect(refresh)
	VoiceChat.prefs_changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if VoiceChat.speaking_changed.is_connected(refresh):
		VoiceChat.speaking_changed.disconnect(refresh)
	if VoiceChat.prefs_changed.is_connected(refresh):
		VoiceChat.prefs_changed.disconnect(refresh)


func refresh() -> void:
	_fill(_mic, VoiceChat.input_devices(), VoiceChat.input_device())
	_fill(_speakers, VoiceChat.output_devices(), VoiceChat.output_device())
	_mute.text = HudStyle.chrome("Unmute mic" if VoiceChat.muted else "Mute mic")
	_open.text = HudStyle.chrome("Push to talk" if VoiceChat.open_mic else "Open mic")
	_hint.text = HudStyle.chrome(VoiceChat.lobby_hint())


func _device_menu() -> OptionButton:
	var menu := OptionButton.new()
	menu.custom_minimum_size = Vector2(360.0, 36.0)
	menu.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return menu


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
