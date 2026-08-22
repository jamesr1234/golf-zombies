class_name SwingMeterUi
extends Control
## Vertical swing bar. Shows fill, the locked-in power mark and the contact
## window, but never a distance number: judging the distance is the game.

const TRACK_COLOR := Color(0.04, 0.02, 0.09, 0.78)
const FILL_COLOR := Palette.CYAN
const PUTT_FILL := Palette.LIME
const POWER_COLOR := Palette.AMBER
const WINDOW_COLOR := Color(Palette.LIME, 0.45)
const OUTLINE_COLOR := Color(Palette.MAGENTA, 0.85)

var meter: SwingMeter
var putting := false


func _draw() -> void:
	var track := Rect2(Vector2.ZERO, size)
	draw_rect(track, TRACK_COLOR)
	if meter != null:
		var window := SwingMeter.CONTACT_WINDOW * meter.kit.contact_scale
		var window_top := _to_y(window)
		var window_bottom := _to_y(-window)
		draw_rect(Rect2(0.0, window_top, size.x, window_bottom - window_top), WINDOW_COLOR)
		var fill_top := _to_y(meter.value)
		var base := _to_y(0.0)
		draw_rect(Rect2(0.0, fill_top, size.x, base - fill_top), PUTT_FILL if putting else FILL_COLOR)
		if meter.power > 0.0:
			var mark := _to_y(meter.power)
			draw_line(Vector2(0.0, mark), Vector2(size.x, mark), POWER_COLOR, 2.0)
	else:
		var window_top := _to_y(SwingMeter.CONTACT_WINDOW)
		var window_bottom := _to_y(-SwingMeter.CONTACT_WINDOW)
		draw_rect(Rect2(0.0, window_top, size.x, window_bottom - window_top), WINDOW_COLOR)
	draw_rect(track, OUTLINE_COLOR, false, 1.5)


## Maps a meter value onto the bar, leaving room below zero for the late-click
## window so a missed swing is visible rather than invisible.
func _to_y(value: float) -> float:
	var span := 1.0 + SwingMeter.CONTACT_WINDOW * 2.0
	var normalized := (value + SwingMeter.CONTACT_WINDOW * 2.0) / span
	return size.y * (1.0 - clampf(normalized, 0.0, 1.0))
