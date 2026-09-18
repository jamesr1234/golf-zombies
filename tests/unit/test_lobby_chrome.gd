extends GutTest
## Compact lobby widgets have to stay smaller than the default chrome so the
## Online VS screen can hold voice plus host/join without clipping.


func test_compact_buttons_are_shorter() -> void:
	var full: Button = autofree(LobbyChrome.button("Host"))
	var compact: Button = autofree(LobbyChrome.button("Host", true))
	assert_lt(compact.custom_minimum_size.y, full.custom_minimum_size.y)
	assert_lt(compact.custom_minimum_size.x, full.custom_minimum_size.x)


func test_compact_fields_and_menus_match() -> void:
	var field: LineEdit = autofree(LobbyChrome.field("Host IP", "127.0.0.1", true))
	var menu: OptionButton = autofree(LobbyChrome.menu(true))
	var full: LineEdit = autofree(LobbyChrome.field("Host IP"))
	assert_eq(field.custom_minimum_size, menu.custom_minimum_size)
	assert_lt(field.custom_minimum_size.y, full.custom_minimum_size.y)


func test_voice_slider_covers_gain() -> void:
	var bar: HSlider = autofree(LobbyChrome.slider(0.0, VoiceCodec.MAX_GAIN, VoiceCodec.DEFAULT_GAIN))
	assert_eq(bar.min_value, 0.0)
	assert_eq(bar.max_value, VoiceCodec.MAX_GAIN)
	assert_eq(bar.value, VoiceCodec.DEFAULT_GAIN)
