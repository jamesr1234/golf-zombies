class_name SwingMeterUi
extends Control
## Vertical swing bar. Sweet spots mark max power at the top and perfect
## contact at the bottom. No distance number: judging that is the game.

const TRACK_COLOR := Color(0.04, 0.02, 0.09, 0.78)
const FILL_COLOR := Palette.CYAN
const PUTT_FILL := Palette.LIME
const POWER_COLOR := Palette.AMBER
const WINDOW_COLOR := Color(Palette.LIME, 0.32)
const POWER_SWEET := Color(Palette.AMBER, 0.46)
const CONTACT_SWEET := Color(Palette.LIME, 0.55)
const OUTLINE_COLOR := Color(Palette.MAGENTA, 0.85)
const MISS_COLOR := Color(Palette.MAGENTA, 0.16)
## Empty track above full power so the top sweet spot sits inside the bar.
const HEADROOM := 0.1
const PAD := 3.0
const PIP_COUNT := 14

var meter: SwingMeter
var putting := false
var _last_value := 0.0


func _ready() -> void:
	set_process(visible)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(visible)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var track := Rect2(Vector2.ZERO, size)
	draw_rect(track, TRACK_COLOR)
	_draw_miss_zone()
	_draw_ticks()
	if meter != null:
		_draw_power_ghost()
		_draw_fill()
		_draw_trail()
		if meter.power > 0.0:
			_draw_mark(meter.power, Color(POWER_COLOR, 0.9), 2.4)
	_draw_band(1.0 - SwingMeter.POWER_SWEET, 1.0 + HEADROOM * 0.2, _live_band(POWER_SWEET, 1.0, 0.16))
	_draw_band(-_contact_window(), _contact_window(), _live_band(WINDOW_COLOR, 0.0, _contact_window()))
	_draw_band(-_contact_sweet(), _contact_sweet(), _live_band(CONTACT_SWEET, 0.0, _contact_sweet() * 2.0))
	_draw_pips()
	_draw_sweet(1.0, POWER_COLOR)
	_draw_sweet(0.0, Palette.LIME)
	if meter != null and meter.is_swinging():
		_draw_needle()
	_draw_frame()
	if meter != null:
		_last_value = meter.value


func power_sweet_y() -> float:
	return _to_y(1.0)


func contact_sweet_y() -> float:
	return _to_y(0.0)


## 1 at the target, 0 outside the radius. Idle address stays still.
func heat_at(target: float, radius: float) -> float:
	if meter == null or not meter.is_swinging():
		return 0.0
	return clampf(1.0 - absf(meter.value - target) / maxf(radius, 0.001), 0.0, 1.0)


func pulse(rate := 1.0) -> float:
	return 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * rate)


func fill_tint() -> Color:
	if putting:
		return PUTT_FILL
	if meter == null:
		return FILL_COLOR
	match meter.state:
		SwingMeter.State.BACKSWING:
			return FILL_COLOR.lerp(POWER_COLOR, clampf(meter.value, 0.0, 1.0))
		SwingMeter.State.DOWNSWING:
			return POWER_COLOR.lerp(PUTT_FILL, 1.0 - clampf(meter.value, 0.0, 1.0))
		_:
			return FILL_COLOR


func _contact_window() -> float:
	if meter == null:
		return SwingMeter.CONTACT_WINDOW
	return SwingMeter.CONTACT_WINDOW * meter.kit.contact_scale


func _contact_sweet() -> float:
	if meter == null:
		return SwingMeter.CONTACT_SWEET
	return SwingMeter.CONTACT_SWEET * meter.kit.contact_scale


func _live_band(base: Color, target: float, radius: float) -> Color:
	var heat := heat_at(target, radius)
	var beat := pulse(3.2 if meter != null and meter.state == SwingMeter.State.DOWNSWING else 1.4)
	return Color(base, clampf(base.a + heat * (0.28 + 0.4 * beat), 0.0, 0.95))


func _draw_fill() -> void:
	var top := _to_y(meter.value)
	var base := _to_y(0.0)
	if absf(base - top) <= 0.5:
		return
	var x0 := PAD
	var x1 := size.x - PAD
	var y0 := minf(top, base)
	var y1 := maxf(top, base)
	var tint := fill_tint()
	var tip := Color(tint, 0.92)
	var root := Color(tint, 0.18)
	var colors := PackedColorArray([tip, tip, root, root] if top <= base else [root, root, tip, tip])
	draw_polygon(PackedVector2Array([
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)
	]), colors)
	draw_line(Vector2(x0, top), Vector2(x1, top), Color(tint, 0.8), 2.0)


func _draw_power_ghost() -> void:
	if meter.power <= 0.0 or meter.state != SwingMeter.State.DOWNSWING:
		return
	var top := _to_y(meter.power)
	var base := _to_y(0.0)
	var height := absf(base - top)
	if height <= 0.5:
		return
	draw_rect(Rect2(PAD, minf(top, base), size.x - PAD * 2.0, height), Color(POWER_COLOR, 0.16))


func _draw_miss_zone() -> void:
	_draw_band(-SwingMeter.CONTACT_WINDOW * 2.0, -_contact_window(), MISS_COLOR)


func _draw_ticks() -> void:
	for i in 11:
		var value := float(i) * 0.1
		var y := _to_y(value)
		var major := i % 5 == 0
		var lit := meter != null and meter.is_swinging() and meter.value >= value
		draw_line(
			Vector2(PAD, y), Vector2(PAD + (7.0 if major else 3.5), y),
			Color(Palette.ICE, 0.55 if lit else 0.16), 1.2 if major else 1.0
		)


func _draw_pips() -> void:
	if meter == null:
		return
	var x := size.x - 5.0
	var tint := fill_tint()
	for i in PIP_COUNT:
		var value := float(i) / float(PIP_COUNT - 1)
		var y := _to_y(value)
		var lit := meter.value >= value and meter.is_swinging()
		var near := absf(meter.value - value) < 0.08 and meter.is_swinging()
		var color := Color(tint if lit else Palette.ICE, 0.95 if near else (0.7 if lit else 0.14))
		draw_rect(Rect2(x, y - 1.4, 3.2, 2.8), color)


func _draw_trail() -> void:
	if not meter.is_swinging():
		return
	var delta := meter.value - _last_value
	if absf(delta) < 0.002 or absf(delta) > 0.28:
		return
	var color := fill_tint()
	for i in 3:
		var ghost := meter.value - delta * (0.45 + float(i) * 0.4)
		draw_line(
			Vector2(PAD, _to_y(ghost)), Vector2(size.x - PAD, _to_y(ghost)),
			Color(color, 0.16 / float(i + 1)), 3.5 - float(i)
		)


func _draw_needle() -> void:
	var y := _to_y(meter.value)
	var color := _needle_tint()
	var heat := maxf(heat_at(1.0, 0.14), heat_at(0.0, _contact_window()))
	var glow := 6.0 + heat * 5.0 * pulse(4.0)
	draw_line(Vector2(1.0, y), Vector2(size.x - 1.0, y), Color(color, 0.28), glow)
	draw_line(Vector2(PAD * 0.5, y), Vector2(size.x - PAD * 0.5, y), color, 2.4)
	draw_line(Vector2(PAD, y), Vector2(size.x - PAD, y), Palette.ICE, 1.1)
	var reach := 5.0 + heat * 2.5
	_draw_chevron(Vector2(PAD + 1.0, y), reach, 1.0, color)
	_draw_chevron(Vector2(size.x - PAD - 1.0, y), reach, -1.0, color)


func _needle_tint() -> Color:
	if heat_at(1.0, SwingMeter.POWER_SWEET * 1.6) > 0.5:
		return POWER_COLOR.lerp(Palette.ICE, 0.4)
	if heat_at(0.0, _contact_sweet() * 2.2) > 0.5:
		return Palette.LIME.lerp(Palette.ICE, 0.45)
	return fill_tint()


func _draw_band(lo: float, hi: float, color: Color) -> void:
	var top := _to_y(hi)
	draw_rect(Rect2(0.0, top, size.x, maxf(2.0, _to_y(lo) - top)), color)


func _draw_mark(value: float, color: Color, width: float) -> void:
	var y := _to_y(value)
	draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(color, 0.28), width + 5.0)
	draw_line(Vector2(0.0, y), Vector2(size.x, y), color, width)


func _draw_sweet(value: float, color: Color) -> void:
	var y := _to_y(value)
	var heat := heat_at(value, 0.12)
	draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(color, 0.2 + heat * 0.4), 7.0)
	draw_line(Vector2(0.0, y), Vector2(size.x, y), color, 3.0 + heat * 1.6)
	draw_line(Vector2(1.0, y - 5.0), Vector2(1.0, y + 5.0), color, 2.0)
	draw_line(Vector2(size.x - 1.0, y - 5.0), Vector2(size.x - 1.0, y + 5.0), color, 2.0)


func _draw_chevron(at: Vector2, reach: float, inward: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(reach * inward, 0.0),
		at + Vector2(0.0, -4.0),
		at + Vector2(0.0, 4.0),
	]), color)


func _draw_frame() -> void:
	var color := OUTLINE_COLOR
	if meter != null and meter.state == SwingMeter.State.DOWNSWING:
		color = Color(Palette.LIME, 0.55 + 0.35 * pulse(3.4))
	elif heat_at(1.0, 0.16) > 0.45:
		color = Color(POWER_COLOR, 0.6 + 0.3 * pulse(2.6))
	draw_rect(Rect2(Vector2.ZERO, size), Color(color, 0.5), false, 1.0)
	var arm := 9.0
	for corner in [
		Vector2(1.0, 1.0), Vector2(size.x - 1.0, 1.0),
		Vector2(1.0, size.y - 1.0), Vector2(size.x - 1.0, size.y - 1.0),
	]:
		var sx := 1.0 if corner.x < size.x * 0.5 else -1.0
		var sy := 1.0 if corner.y < size.y * 0.5 else -1.0
		draw_line(corner, corner + Vector2(arm * sx, 0.0), color, 2.0)
		draw_line(corner, corner + Vector2(0.0, arm * sy), color, 2.0)


## Maps a meter value onto the bar. Room above 1.0 frames the power sweet
## spot; room below zero shows a late click.
func _to_y(value: float) -> float:
	var low := -SwingMeter.CONTACT_WINDOW * 2.0
	var high := 1.0 + HEADROOM
	var normalized := (value - low) / (high - low)
	return size.y * (1.0 - clampf(normalized, 0.0, 1.0))
