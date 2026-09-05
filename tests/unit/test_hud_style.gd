extends GutTest
## Neon scoreboard type: tracked Oxanium, palette colours, and a matching glow.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")


func test_chrome_uppercases_scoreboard_copy() -> void:
	assert_eq(HudStyle.chrome("Hole 1   Par 4"), "HOLE 1   PAR 4")
	assert_eq(HudStyle.chrome(""), "")


func test_readout_glows_in_the_palette_colour() -> void:
	var settings := HudStyle.readout(Palette.CYAN)
	assert_eq(settings.font_color, Palette.CYAN)
	assert_eq(settings.outline_color, Palette.NIGHT)
	assert_eq(settings.shadow_offset, Vector2.ZERO)
	assert_eq(settings.shadow_color, Color(Palette.CYAN, HudStyle.GLOW_ALPHA))
	assert_eq(settings.font_size, HudStyle.READOUT_SIZE)
	assert_gt(settings.outline_size, 0)
	assert_gt(settings.shadow_size, 0)


func test_banner_is_heavier_and_more_tracked_than_a_readout() -> void:
	var readout := HudStyle.readout(Palette.MAGENTA)
	var banner := HudStyle.banner(Palette.MAGENTA)
	assert_gt(banner.font_size, readout.font_size)
	assert_gt(banner.shadow_size, readout.shadow_size)
	assert_gt(
		(banner.font as FontVariation).get_spacing(TextServer.SPACING_GLYPH),
		(readout.font as FontVariation).get_spacing(TextServer.SPACING_GLYPH)
	)


func test_hud_applies_the_scoreboard_style_on_ready() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	add_child_autofree(hud)
	assert_eq(hud.score_label.label_settings.font_color, Palette.CYAN)
	assert_eq(hud.timer_label.label_settings.font_color, Palette.ICE)
	assert_eq(hud.money_label.label_settings.font_color, Palette.LIME)
	assert_eq(hud.ammo_label.label_settings.font_color, Palette.AMBER)
	assert_eq(hud.prompt_label.label_settings.font_color, Palette.LIME)
	assert_eq(hud.message_title.label_settings.font_color, Palette.MAGENTA)
	assert_eq(hud.message_body.label_settings.font_color, Palette.ICE)
	assert_eq(hud.shop_title.label_settings.font_color, Palette.AMBER)
	assert_not_null(hud.score_label.label_settings.font)


func test_the_shop_menu_sits_on_the_left() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	add_child_autofree(hud)
	var panel := hud.shop_panel.get_node("Panel") as Control
	assert_not_null(panel)
	assert_lt(panel.anchor_right, 0.2, "pinned to the left edge")
	assert_lt(panel.offset_right, 420.0, "narrow enough that the item stays in view")
	assert_eq(hud.shop_title.horizontal_alignment, HORIZONTAL_ALIGNMENT_LEFT)
	assert_eq(hud.shop_body.horizontal_alignment, HORIZONTAL_ALIGNMENT_LEFT)


func test_a_hit_flash_is_a_red_slap_not_the_low_health_haze() -> void:
	assert_gt(Hud.HIT_FLASH.r, 0.8)
	assert_lt(Hud.HIT_FLASH.g, 0.2)
	assert_gt(Hud.HIT_FLASH.a, Hud.HURT_TINT.a)


func test_a_sweet_callout_uses_scoreboard_chrome() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	add_child_autofree(hud)
	hud.flash_callout(Hud.SWEET_CALLOUT)
	assert_eq(hud.message_title.text, "NICE SHOT!")
	assert_true(hud.message.visible)


func test_the_ammo_readout_says_putter_on_the_green() -> void:
	assert_eq(Hud.golf_club_text(true), "Putter")
	assert_eq(HudStyle.chrome(Hud.golf_club_text(true)), "PUTTER")
	assert_eq(Hud.golf_club_text(false), "")
