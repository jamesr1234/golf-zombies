extends Object
## Shared lava visuals: stacked glowing terraces, skip shapes on the pool body,
## and a handful of rising bubbles. One pool node owns one of each.

const SHADER := preload("res://assets/shaders/neon_lava.gdshader")
const SLAB := 0.38
const LAYERS := 3
const INSET := 0.09
const BUBBLES := 18


static func rim() -> float:
	return Surface.DRAW_HEIGHT[Surface.Type.FAIRWAY]


static func material(heat := 1.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("crust_color", Color(0.18, 0.03, 0.01).lerp(Color(0.07, 0.01, 0.0), 1.0 - heat))
	mat.set_shader_parameter("glow_color", Color(1.0, 0.16, 0.04).lerp(Color(1.0, 0.42, 0.06), 1.0 - heat))
	mat.set_shader_parameter("bubble_color", Color(1.0, 0.72, 0.18))
	mat.set_shader_parameter("cell_size", GridSnap.CELL)
	mat.set_shader_parameter("energy", lerpf(5.4, 3.2, heat))
	return mat


static func layer_mesh(index: int) -> BoxMesh:
	var inset := float(index) * INSET * 2.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(
		maxf(GridSnap.CELL - inset, 0.45),
		SLAB / float(LAYERS),
		maxf(GridSnap.CELL - inset, 0.45)
	)
	return mesh


static func layer_y(index: int) -> float:
	var thick := SLAB / float(LAYERS)
	return rim() - SLAB + (float(index) + 0.5) * thick


static func slab_at(offset: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Surface"
	for i in LAYERS:
		var node := MeshInstance3D.new()
		node.mesh = layer_mesh(i)
		node.position = Vector3(offset.x, layer_y(i), offset.z)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.material_override = material(float(i) / float(LAYERS - 1))
		root.add_child(node)
	return root


static func pool_surface(cells: Array[Vector3], origin: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Surface"
	for layer in LAYERS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = layer_mesh(layer)
		mm.instance_count = cells.size()
		for i in cells.size():
			var offset := cells[i] - origin
			mm.set_instance_transform(
				i, Transform3D(Basis.IDENTITY, Vector3(offset.x, layer_y(layer), offset.z))
			)
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.material_override = material(float(layer) / float(LAYERS - 1))
		root.add_child(node)
	return root


static func skip_shape(offset: Vector3) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GridSnap.CELL, SLAB, GridSnap.CELL)
	node.shape = box
	node.position = Vector3(offset.x, rim() - SLAB * 0.5, offset.z)
	return node


static func bubbles(cells: Array[Vector3], origin: Vector3) -> GPUParticles3D:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for cell in cells:
		var offset := cell - origin
		lo = lo.min(offset)
		hi = hi.max(offset)
	var mid := (lo + hi) * 0.5
	var node := GPUParticles3D.new()
	node.name = "Bubbles"
	node.amount = maxi(BUBBLES, cells.size() * 3)
	node.lifetime = 1.35
	node.preprocess = 0.7
	node.position = Vector3(mid.x, rim(), mid.z)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(
		maxf((hi.x - lo.x) * 0.5 + GridSnap.CELL * 0.35, 0.4),
		0.06,
		maxf((hi.z - lo.z) * 0.5 + GridSnap.CELL * 0.35, 0.4)
	)
	process.direction = Vector3.UP
	process.spread = 28.0
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 1.4
	process.gravity = Vector3(0.0, 0.55, 0.0)
	process.scale_min = 0.05
	process.scale_max = 0.14
	process.color = Color(1.0, 0.55, 0.1)
	node.process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	mesh.radial_segments = 8
	mesh.rings = 4
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_color = Color(1.0, 0.62, 0.12)
	look.emission_enabled = true
	look.emission = Color(1.0, 0.45, 0.06)
	look.emission_energy_multiplier = 3.2
	mesh.material = look
	node.draw_pass_1 = mesh
	return node
