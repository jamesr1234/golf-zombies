class_name GrappleLine
extends Node3D
## Neon rope from the muzzle to the claw. The cable stays taut while you ride.

const COLOR := Palette.HOT_PINK
const CORE := Palette.ICE
const WIDTH := 0.055
const GLOW_WIDTH := 0.11


var _cable: MeshInstance3D
var _glow: MeshInstance3D
var _claw: Node3D
var _lamp: OmniLight3D
var _ribbon: MeshInstance3D
var _pulse := 0.0


func _ready() -> void:
	top_level = true
	global_position = Vector3.ZERO
	global_rotation = Vector3.ZERO
	_cable = MeshFactory.box(Vector3(0.035, 0.035, 1.0), CORE, Palette.GLOW_STRONG)
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cable)
	_glow = MeshFactory.box(Vector3(0.07, 0.07, 1.0), Color(COLOR, 0.55), Palette.GLOW_MEDIUM)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = ImmediateMesh.new()
	_ribbon.material_override = _ribbon_material()
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ribbon)
	_claw = GrappleHook.build_claw(COLOR)
	add_child(_claw)
	_lamp = OmniLight3D.new()
	_lamp.light_color = COLOR
	_lamp.light_energy = 6.0
	_lamp.omni_range = 8.0
	add_child(_lamp)
	hide_line()


func draw(from: Vector3, to: Vector3, latched: bool) -> void:
	if from.distance_squared_to(to) < 0.004:
		hide_line()
		return
	global_position = Vector3.ZERO
	global_rotation = Vector3.ZERO
	visible = true
	_pulse = wrapf(_pulse + 0.12, 0.0, TAU)
	var length := from.distance_to(to)
	_place_span(_cable, from, to, length, 0.035)
	_place_span(_glow, from, to, length, 0.07 + sin(_pulse) * 0.012)
	_glow.scale.x = 1.0 + sin(_pulse * 2.0) * 0.18
	_glow.scale.y = _glow.scale.x
	_claw.visible = true
	_claw.global_position = to
	var face := to + (to - from)
	var up := Vector3.UP
	if absf(to.direction_to(face).dot(up)) > 0.95:
		up = Vector3.RIGHT
	_claw.look_at(face, up)
	_lamp.visible = true
	_lamp.global_position = to
	_lamp.light_energy = (5.4 if latched else 3.6) + sin(_pulse * 3.0) * 1.6
	_draw_ribbon(from, to)


func hide_line() -> void:
	visible = false
	if _claw != null:
		_claw.visible = false
	if _lamp != null:
		_lamp.visible = false
	if _ribbon != null:
		var mesh := _ribbon.mesh as ImmediateMesh
		if mesh != null:
			mesh.clear_surfaces()


func _place_span(mesh: MeshInstance3D, from: Vector3, to: Vector3, length: float, thick: float) -> void:
	mesh.visible = length > 0.08
	if not mesh.visible:
		return
	mesh.global_position = from.lerp(to, 0.5)
	mesh.scale = Vector3(thick / 0.035, thick / 0.035, maxf(0.08, length))
	var up := Vector3.UP
	if absf(from.direction_to(to).dot(up)) > 0.95:
		up = Vector3.RIGHT
	mesh.look_at(to, up)


func _draw_ribbon(from: Vector3, to: Vector3) -> void:
	var mesh := _ribbon.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var along := to - from
	if along.length_squared() < 0.002:
		return
	var dir := along.normalized()
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var alpha := 0.55 + sin(_pulse * 2.4) * 0.2
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in 2:
		var at := from if i == 0 else to
		var color := Color(COLOR, alpha)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(at + side * GLOW_WIDTH)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(at - side * GLOW_WIDTH)
	mesh.surface_end()
	var lift := side.cross(dir).normalized()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in 2:
		var at := from if i == 0 else to
		var color := Color(CORE, alpha * 0.8)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(at + lift * WIDTH)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(at - lift * WIDTH)
	mesh.surface_end()


func _ribbon_material() -> StandardMaterial3D:
	var mat := MeshFactory.material(COLOR, true)
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
