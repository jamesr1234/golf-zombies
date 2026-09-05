class_name HitFx
extends Object
## Short-lived hitscan feedback. Everything is spawned under the shared world
## root so it stays put instead of riding along with the shooter.

const YARD := 0.9144
const SNIPER_FADE_YARDS := 75.0
const SNIPER_FADE_SPAN_YARDS := 50.0
const SNIPER_LED_WIDTH := 0.07
const SNIPER_LED_SLICE := 5.0
const SNIPER_HOLD := 0.28
const SNIPER_FADE := 0.42


static func spawn(root: Node, from: Vector3, to: Vector3, color: Color) -> void:
	if root == null:
		return
	_tracer(root, from, to, color)
	spark(root, to, color)


## Expanding flash for a rocket (or anything else that hits a volume).
static func blast(root: Node, at: Vector3, radius: float, color: Color) -> void:
	if root == null:
		return
	var size := maxf(0.4, radius)
	var node := MeshFactory.sphere(0.35, color, Palette.GLOW_STRONG)
	root.add_child(node)
	node.global_position = at
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE * (size / 0.35), 0.16)
	tween.tween_callback(node.queue_free)
	var lamp := OmniLight3D.new()
	lamp.light_color = color
	lamp.light_energy = 8.0
	lamp.omni_range = size * 1.6
	root.add_child(lamp)
	lamp.global_position = at
	var fade := lamp.create_tween()
	fade.tween_property(lamp, "light_energy", 0.0, 0.22)
	fade.tween_callback(lamp.queue_free)


static func spark(root: Node, at: Vector3, color: Color) -> void:
	if root == null:
		return
	var node := MeshFactory.sphere(0.17, color, Palette.GLOW_STRONG)
	root.add_child(node)
	node.global_position = at
	_fade(node, 0.18)


## Flecks flying off a flushed golf shot. Sized to read from the swing camera.
static func burst(root: Node, at: Vector3, color: Color, count := 18) -> void:
	if root == null:
		return
	blast(root, at, 1.6, color)
	for i in count:
		var fly := Vector3(
			randf_range(-1.0, 1.0), randf_range(0.45, 1.25), randf_range(-1.0, 1.0)
		).normalized() * randf_range(2.4, 5.2)
		var tint := color if i % 2 == 0 else Palette.AMBER
		var fleck := MeshFactory.box(Vector3(0.18, 0.18, 0.7), tint, Palette.GLOW_STRONG)
		root.add_child(fleck)
		fleck.global_position = at
		if fly.length_squared() > 0.0001:
			fleck.look_at(at + fly, Vector3.UP)
		var tween := fleck.create_tween()
		tween.set_parallel()
		tween.tween_property(fleck, "global_position", at + fly, 0.45)
		tween.tween_property(fleck, "scale", Vector3(0.08, 0.08, 1.0), 0.45)
		tween.chain().tween_callback(fleck.queue_free)


static func sniper_fade_after() -> float:
	return SNIPER_FADE_YARDS * YARD


static func sniper_alpha(along_m: float) -> float:
	var start := sniper_fade_after()
	if along_m <= start:
		return 1.0
	var span := SNIPER_FADE_SPAN_YARDS * YARD
	return clampf(1.0 - (along_m - start) / span, 0.12, 1.0)


static func sniper_tint(from_player: bool) -> Color:
	return Palette.LED_WHITE if from_player else Palette.LED_RED


static func sniper_beam(root: Node, from: Vector3, to: Vector3, color: Color, grow := false) -> Node3D:
	if root == null:
		return null
	var length := from.distance_to(to)
	if length < 0.4:
		return null
	var beam := Node3D.new()
	beam.add_to_group("sniper_beams")
	root.add_child(beam)
	beam.global_position = from
	var up := Vector3.UP
	if absf(from.direction_to(to).dot(up)) > 0.95:
		up = Vector3.RIGHT
	beam.look_at(to, up)
	var along := 0.0
	while along < length:
		var span := minf(SNIPER_LED_SLICE, length - along)
		var mid := along + span * 0.5
		var alpha := sniper_alpha(mid)
		var led := MeshFactory.box(
			Vector3(SNIPER_LED_WIDTH, SNIPER_LED_WIDTH, maxf(0.08, span * 0.94)),
			Color(color, alpha),
			Palette.GLOW_STRONG * alpha
		)
		_lit(led, color, alpha)
		led.position.z = -mid
		led.set_meta("along", mid)
		led.visible = not grow
		beam.add_child(led)
		along += span
	var lamp := OmniLight3D.new()
	lamp.light_color = color
	lamp.light_energy = 6.5
	lamp.omni_range = 14.0
	beam.add_child(lamp)
	if not grow:
		sniper_finish(beam)
	return beam


static func sniper_draw_to(beam: Node3D, along_m: float) -> void:
	if beam == null or not is_instance_valid(beam):
		return
	for child in beam.get_children():
		var led := child as MeshInstance3D
		if led == null:
			continue
		led.visible = float(led.get_meta("along", 0.0)) <= along_m


static func sniper_drawn_count(beam: Node3D) -> int:
	if beam == null or not is_instance_valid(beam):
		return 0
	var n := 0
	for child in beam.get_children():
		if child is MeshInstance3D and child.visible:
			n += 1
	return n


static func sniper_finish(beam: Node3D) -> void:
	if beam == null or not is_instance_valid(beam) or beam.has_meta("fading"):
		return
	beam.set_meta("fading", true)
	var tween := beam.create_tween()
	tween.tween_interval(SNIPER_HOLD)
	tween.tween_property(beam, "scale", Vector3(0.04, 0.04, 1.0), SNIPER_FADE)
	tween.tween_callback(beam.queue_free)


static func _tracer(root: Node, from: Vector3, to: Vector3, color: Color) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var node := MeshFactory.box(Vector3(0.045, 0.045, length), color, Palette.GLOW_STRONG)
	root.add_child(node)
	node.global_position = from.lerp(to, 0.5)
	node.look_at(to, Vector3.UP)
	_fade(node, 0.06)


static func _fade(node: Node3D, duration: float) -> void:
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3(0.05, 0.05, 1.0), duration)
	tween.tween_callback(node.queue_free)


static func _lit(node: MeshInstance3D, color: Color, alpha: float) -> void:
	var mat := node.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, alpha)
	mat.emission = color
	mat.emission_energy_multiplier = Palette.GLOW_STRONG * alpha
