extends StaticBody3D
## Forcefield on both lips of the landing strip. The tall pane only lights
## when something strikes it.

const _SCRIPT := preload("res://scripts/course/fairway_field.gd")
const GROUP := "fairway_field"
const STEP := 2.0
const OVERLAP := 2.5
## Taller than a stuffed flop off the mesa. The ball cannot clear the lip.
const HEIGHT := 240.0
const THICK := 0.25
## A boosted cart covers 1.4 m in a physics frame. Anything thinner than that is
## crossed whole and leaves the cart fenced out in the rough, so the collider is
## deep enough for several frames of it. It grows outward only: the inner face
## stays on the visible pane, so the strip is exactly as wide as it looks.
const HIT_THICK := 4.0
const FLASH := 0.3
const HIT_ENERGY := 4.0
const HIT_RADIUS := 12.0
const _SHADER := preload("res://assets/shaders/fairway_field.gdshader")
const _Trees := preload("res://scripts/course/course_trees.gd")


var _mat: ShaderMaterial
var _flash: Tween


static func create(data: HoleData) -> StaticBody3D:
	var field = _SCRIPT.new()
	field.name = "FairwayField"
	field._build(data)
	return field


func hit_energy() -> float:
	if _mat == null:
		return 0.0
	return float(_mat.get_shader_parameter("hit_energy"))


func pulse(at: Vector3) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("hit_pos", at)
	_mat.set_shader_parameter("hit_energy", HIT_ENERGY)
	if _flash != null:
		_flash.kill()
	_flash = create_tween()
	_flash.tween_method(_fade, HIT_ENERGY, 0.0, FLASH)


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = Layers.FORCEFIELD
	collision_mask = 0


func _build(data: HoleData) -> void:
	collision_layer = Layers.FORCEFIELD
	collision_mask = 0
	add_to_group(GROUP)
	_mat = ShaderMaterial.new()
	_mat.shader = _SHADER
	_mat.set_shader_parameter("line_color", Palette.CYAN)
	_mat.set_shader_parameter("hit_radius", HIT_RADIUS)
	_mat.set_shader_parameter("hit_energy", 0.0)
	var points := _ribbon(data)
	var next := 0.0
	var travelled := 0.0
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var along := b - a
		along.y = 0.0
		var span := along.length()
		if span < 0.4:
			continue
		var dir := along / span
		var right := dir.cross(Vector3.UP).normalized()
		travelled += span
		while next <= travelled + 0.01:
			var t := 1.0 - (travelled - next) / span
			var at := a.lerp(b, clampf(t, 0.0, 1.0))
			_try_panel(data, at, dir, right)
			next += STEP
	_cap_start(data, points)


func _ribbon(data: HoleData) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if data.practice_tee.distance_squared_to(data.tee) > 0.25:
		points.append(data.practice_tee)
	points.append_array(data.centerline)
	return points


func _try_panel(data: HoleData, at: Vector3, dir: Vector3, right: Vector3) -> void:
	var half := _half_at(data, at)
	for s in 2:
		var side := -1.0 if s == 0 else 1.0
		var spot := at + right * side * half
		if _skip(data, spot):
			continue
		_panel(spot, dir, right * side)


func _half_at(data: HoleData, at: Vector3) -> float:
	var fairway := data.fairway_width() * 0.5
	var green := data.green_radius + HoleGenerator.FRINGE_WIDTH
	var blend := 1.0 - clampf((at.distance_to(data.cup) - green) / 12.0, 0.0, 1.0)
	return lerpf(fairway, green, blend)


func _skip(data: HoleData, spot: Vector3) -> bool:
	return _Trees.in_exit_corridor(data, spot)


func _cap_start(data: HoleData, points: Array[Vector3]) -> void:
	if points.size() < 2:
		return
	var dir: Vector3 = points[1] - points[0]
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var half := _half_at(data, points[0])
	var door := ClubhouseBuild.HALL * 0.5 + 0.6
	if door >= half - 0.5:
		return
	var span := half - door
	for s in 2:
		var side := -1.0 if s == 0 else 1.0
		var mid := points[0] + right * side * (door + span * 0.5)
		_panel(mid, right, -dir, span)


func _panel(at: Vector3, dir: Vector3, outward: Vector3, length := STEP + OVERLAP) -> void:
	var basis := Basis(outward, Vector3.UP, dir).orthonormalized()
	var xform := Transform3D(basis, at + Vector3.UP * (HEIGHT * 0.5))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HIT_THICK, HEIGHT, length)
	shape.shape = box
	# Local +X is outward, so the extra depth is pushed into the rough.
	shape.transform = xform.translated_local(Vector3((HIT_THICK - THICK) * 0.5, 0.0, 0.0))
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var quad := BoxMesh.new()
	quad.size = Vector3(THICK, HEIGHT, length)
	mesh.mesh = quad
	mesh.material_override = _mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.transform = xform
	add_child(mesh)


func _fade(energy: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("hit_energy", energy)
