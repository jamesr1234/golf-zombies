class_name HudStyle
extends Object
## Neon scoreboard type for every HUD label. Oxanium, wide tracking, a dark
## knockout outline and a coloured glow, all drawn from Palette.

const READOUT_FONT := preload("res://assets/fonts/Oxanium-Bold.ttf")
const BANNER_FONT := preload("res://assets/fonts/Oxanium-ExtraBold.ttf")
const READOUT_SIZE := 18
const PROMPT_SIZE := 16
const BODY_SIZE := 16
const BANNER_SIZE := 32
const READOUT_TRACKING := 2
const BANNER_TRACKING := 6
const GLOW_ALPHA := 0.5


static func apply(hud: Hud) -> void:
	hud.score_label.label_settings = readout(Palette.CYAN)
	hud.timer_label.label_settings = readout(Palette.ICE)
	hud.money_label.label_settings = readout(Palette.LIME)
	hud.ammo_label.label_settings = readout(Palette.AMBER)
	hud.prompt_label.label_settings = readout(Palette.LIME, PROMPT_SIZE)
	hud.message_title.label_settings = banner(Palette.MAGENTA)
	hud.message_body.label_settings = readout(Palette.ICE, BODY_SIZE)
	hud.shop_title.label_settings = banner(Palette.AMBER)
	hud.shop_body.label_settings = readout(Palette.ICE, BODY_SIZE)


static func chrome(text: String) -> String:
	return text.to_upper()


static func readout(color: Color, size := READOUT_SIZE) -> LabelSettings:
	return _settings(_face(READOUT_FONT, READOUT_TRACKING), size, color, 8, 10)


static func banner(color: Color, size := BANNER_SIZE) -> LabelSettings:
	return _settings(_face(BANNER_FONT, BANNER_TRACKING), size, color, 12, 18)


static func _face(font: Font, tracking: int) -> FontVariation:
	var face := FontVariation.new()
	face.base_font = font
	face.set_spacing(TextServer.SPACING_GLYPH, tracking)
	face.set_spacing(TextServer.SPACING_SPACE, tracking)
	return face


static func _settings(
	font: Font, size: int, color: Color, outline: int, glow: int
) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font = font
	settings.font_size = size
	settings.font_color = color
	settings.outline_size = outline
	settings.outline_color = Palette.NIGHT
	settings.shadow_size = glow
	settings.shadow_color = Color(color, GLOW_ALPHA)
	settings.shadow_offset = Vector2.ZERO
	return settings
