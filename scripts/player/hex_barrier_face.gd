class_name HexBarrierFace
extends StaticBody3D
## One wall of a hex fort. Neon frame like the planted shield; the middle stays
## empty until a hit lights a grid so the partner can see which side to shoot.

const FRAME := 0.08
const FLASH_TIME := 0.32
const GRID_CELLS := 5.0
const PANEL_SHADER := preload("res://assets/shaders/neon_panel.gdshader")

var hits_left := 3

var _pane: MeshInstance3D
var _lamp: OmniLight3D
var _flash: Tween


func is_open() -> bool:
	return hits_left <= 0


func build(width: float, height: float, thickness: float, ghost: bool) -> void:
	add_child(_shape(width, height, thickness))
	add_child(_outline(width, height, thickness, ghost))
	if ghost:
		return
	_pane = _make_pane(width, height)
	_pane.visible = false
	add_child(_pane)


func take_hit(at := Vector3.ZERO) -> bool:
	if hits_left <= 0:
		return false
	hits_left -= 1
	if hits_left <= 0:
		Sfx.play("barrier_break", self)
		_open(at)
		return true
	Sfx.play("barrier_hit", self)
	_flash_grid()
	return false


func pane_lit() -> bool:
	return _pane != null and _pane.visible


func _open(at: Vector3) -> void:
	if _flash != null:
		_flash.kill()
		_flash = null
	for child in get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			shape.disabled = true
	visible = false
	var barrier := get_parent()
	if barrier == null or not barrier.has_method("_burst"):
		return
	var point := at if at != Vector3.ZERO else global_position
	barrier._burst(point)


func _flash_grid() -> void:
	if _pane == null:
		return
	_pane.visible = true
	var mat := _pane.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("alpha", 0.8)
		mat.set_shader_parameter("energy", 3.2)
	if _lamp != null:
		_lamp.light_energy = 4.5
	if _flash != null:
		_flash.kill()
	_flash = create_tween()
	_flash.tween_method(_fade_flash, 1.0, 0.0, FLASH_TIME)
	_flash.tween_callback(_end_flash)


func _fade_flash(amount: float) -> void:
	if _pane == null:
		return
	var mat := _pane.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("alpha", 0.8 * amount)
		mat.set_shader_parameter("energy", 3.2 * amount)
	if _lamp != null:
		_lamp.light_energy = lerpf(2.2, 4.5, amount)


func _end_flash() -> void:
	_flash = null
	if _pane != null:
		_pane.visible = false
	if _lamp != null:
		_lamp.light_energy = 2.2


func _shape(width: float, height: float, thickness: float) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, thickness)
	node.shape = box
	return node


func _outline(width: float, height: float, thickness: float, ghost: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Outline"
	var span := height - FRAME * 2.0
	var glow := Palette.GLOW_MEDIUM if ghost else Palette.GLOW_STRONG
	root.add_child(_bar(Vector3(width, FRAME, thickness), Vector3(0.0, (height - FRAME) * 0.5, 0.0), glow, ghost))
	root.add_child(_bar(Vector3(width, FRAME, thickness), Vector3(0.0, (FRAME - height) * 0.5, 0.0), glow, ghost))
	root.add_child(_bar(Vector3(FRAME, span, thickness), Vector3((FRAME - width) * 0.5, 0.0, 0.0), glow, ghost))
	root.add_child(_bar(Vector3(FRAME, span, thickness), Vector3((width - FRAME) * 0.5, 0.0, 0.0), glow, ghost))
	_lamp = OmniLight3D.new()
	_lamp.light_color = Palette.CYAN
	_lamp.light_energy = 1.1 if ghost else 2.2
	_lamp.omni_range = 4.2
	root.add_child(_lamp)
	return root


func _bar(size: Vector3, at: Vector3, glow: float, ghost: bool) -> MeshInstance3D:
	var node := MeshFactory.box(size, Palette.CYAN, glow)
	node.position = at
	if ghost:
		var mat := node.material_override as StandardMaterial3D
		if mat != null:
			var faded: StandardMaterial3D = mat.duplicate()
			faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			faded.albedo_color.a = 0.45
			node.material_override = faded
	return node


func _make_pane(width: float, height: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "Pane"
	var quad := QuadMesh.new()
	quad.size = Vector2(maxf(0.2, width - FRAME * 2.0), maxf(0.2, height - FRAME * 2.0))
	node.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = PANEL_SHADER
	mat.set_shader_parameter("line_color", Palette.CYAN)
	mat.set_shader_parameter("cells", GRID_CELLS)
	mat.set_shader_parameter("energy", 0.0)
	mat.set_shader_parameter("alpha", 0.0)
	node.material_override = mat
	return node
