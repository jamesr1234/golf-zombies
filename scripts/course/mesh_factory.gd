class_name MeshFactory
extends Object
## Placeholder-art helpers. Every visual in the game is built from these so the
## neon look stays consistent and no scene needs bespoke material setup.

const GRID_SHADER := preload("res://assets/shaders/neon_grid.gdshader")
## Only the pond surface is see-through, so it gets its own shader rather than an
## alpha switch on the one every opaque lie shares.
const WATER_SHADER := preload("res://assets/shaders/neon_water.gdshader")


static func material(color: Color, unshaded := false, emission := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	mat.metallic = 0.25
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Builds the neon grid material described by a Surface.LOOK entry. An entry with
## an opacity is water and gets the transparent shader.
static func grid_material(look: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER if look.has("opacity") else GRID_SHADER
	mat.set_shader_parameter("base_color", look["base"])
	mat.set_shader_parameter("line_color", look["line"])
	mat.set_shader_parameter("cell_size", look["cell"])
	mat.set_shader_parameter("line_energy", look["energy"])
	mat.set_shader_parameter("scroll_speed", look["scroll"])
	if look.has("fill"):
		mat.set_shader_parameter("fill_energy", look["fill"])
	if look.has("fade_start"):
		mat.set_shader_parameter("fade_start", look["fade_start"])
	if look.has("fade_end"):
		mat.set_shader_parameter("fade_end", look["fade_end"])
	if look.has("opacity"):
		mat.set_shader_parameter("opacity", look["opacity"])
	return mat


## Swaps every mesh in a branch over to a grid material, so the same call works
## for a bare MeshInstance3D or for a body with a mesh child.
static func apply_grid(node: Node, look: Dictionary) -> void:
	var mesh_node := node as MeshInstance3D
	if mesh_node != null:
		mesh_node.material_override = grid_material(look)
	for child in node.get_children():
		apply_grid(child, look)


static func flat_quad(size: Vector2, color: Color, emission := 0.0) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	return _instance(mesh, color, emission)


static func disk(radius: float, color: Color, emission := 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.04
	mesh.radial_segments = 24
	return _instance(mesh, color, emission)


static func torus(inner: float, outer: float, color: Color, emission := 0.0) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 28
	mesh.ring_segments = 12
	return _instance(mesh, color, emission)


static func box(size: Vector3, color: Color, emission := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(mesh, color, emission)


static func cylinder(radius: float, height: float, color: Color, emission := 0.0) -> MeshInstance3D:
	return taper(radius, radius, height, color, emission)


static func taper(
	bottom: float, top: float, height: float, color: Color, emission := 0.0
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 10
	return _instance(mesh, color, emission)


static func sphere(radius: float, color: Color, emission := 0.0) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	return _instance(mesh, color, emission)


## Static body with a box collider, used for ground, barriers and props.
static func box_body(
	size: Vector3, color: Color, layer: int, visible_mesh := true, emission := 0.0
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	if visible_mesh:
		body.add_child(box(size, color, emission))
	return body


static func cylinder_body(
	radius: float, height: float, color: Color, layer: int, emission := 0.0
) -> StaticBody3D:
	return taper_body(radius, radius, height, color, layer, emission)


static func taper_body(
	bottom: float, top: float, height: float, color: Color, layer: int, emission := 0.0
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = maxf(bottom, top)
	cylinder_shape.height = height
	shape.shape = cylinder_shape
	body.add_child(shape)
	body.add_child(taper(bottom, top, height, color, emission))
	return body


static func _instance(mesh: Mesh, color: Color, emission: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color, false, emission)
	return node
