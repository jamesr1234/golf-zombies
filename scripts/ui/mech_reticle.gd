class_name MechReticle
extends Control
## Fighter-style brackets for mech L2. Hidden unless the pilot is ADS.

const RING := 46.0
const GAP := 11.0
const ARM := 18.0
const TICK := 7.0


func _draw() -> void:
	var c := size * 0.5
	var beat := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
	_ring(c, RING + 10.0, 1.4, Color(Palette.MECH, 0.18 + beat * 0.1))
	_ring(c, RING, 2.2, Palette.NIGHT)
	_ring(c, RING, 1.15, Color(Palette.MECH, 0.95))
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_bracket(c, dir)
	draw_circle(c, 3.4, Palette.NIGHT)
	draw_circle(c, 2.1, Palette.LED_RED)
	draw_circle(c, 0.8, Palette.ICE)


func _bracket(c: Vector2, dir: Vector2) -> void:
	var tip := c + dir * (RING + GAP)
	var side := Vector2(-dir.y, dir.x)
	var a := tip + dir * ARM
	var b := tip + side * ARM * 0.55
	draw_line(tip, a, Palette.NIGHT, 5.0)
	draw_line(tip, b, Palette.NIGHT, 5.0)
	draw_line(tip, a, Palette.AMBER, 2.0)
	draw_line(tip, b, Palette.AMBER, 2.0)
	var tick := c + dir * (RING - TICK * 1.6)
	draw_line(tick, tick + dir * TICK, Palette.ICE, 1.4)


func _ring(c: Vector2, radius: float, width: float, tint: Color) -> void:
	draw_arc(c, radius, 0.0, TAU, 48, tint, width, true)
