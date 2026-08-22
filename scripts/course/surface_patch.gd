class_name SurfacePatch
extends Area3D
## A patch of fairway, green, sand or water. Tall enough to catch a ball sitting
## on a slope, but the ball only takes the lie (and water) while it is grounded,
## so a shot flying overhead keeps its air physics.

const DETECT_SPAN := 16.0
## Neon lip around a putting surface. Fat enough to read from the tee, short
## enough that a putt never feels like it is rolling through a wall.
const RIM_THICK := 0.7
const RIM_HEIGHT := 0.42
const RIM_LIFT := 0.12

var type: Surface.Type = Surface.Type.FAIRWAY


static func create(patch: Dictionary, height: HeightField = null) -> SurfacePatch:
	var node := SurfacePatch.new()
	node.type = patch["type"]
	var look: Dictionary = Surface.look_for(patch)
	var shape := CollisionShape3D.new()
	_fit_detector(shape, patch, height)
	node.add_child(_draped_mesh(patch, look, height))
	if node.type == Surface.Type.GREEN:
		node.add_child(_putting_marker(patch))
	node.add_child(shape)
	var position: Vector3 = patch["position"]
	node.position = Vector3(position.x, 0.0, position.z)
	node.rotation.y = deg_to_rad(patch["yaw"])
	return node


## Water is the column between its surface and its floor. Stopping at the surface
## is what keeps a ball resting on the dry bank inside the rectangle from reading
## as a splash.
static func _fit_detector(shape: CollisionShape3D, patch: Dictionary, _height: HeightField) -> void:
	var size: Vector2 = patch["size"]
	var span := DETECT_SPAN
	var mid := DETECT_SPAN * 0.25
	if patch["type"] == Surface.Type.WATER:
		var top := water_level(patch) + 0.3
		var bottom := top - HeightField.WATER_DEPTH - 1.5
		span = top - bottom
		mid = (top + bottom) * 0.5
	shape.position.y = mid
	if patch["round"]:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = size.x * 0.5
		cylinder.height = span
		shape.shape = cylinder
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, span, size.y)
		shape.shape = box


func _ready() -> void:
	collision_layer = Layers.SURFACE
	collision_mask = Layers.BALL
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	var ball := body as GolfBall
	if ball != null:
		ball.enter_surface(type)


func _on_body_exited(body: Node3D) -> void:
	var ball := body as GolfBall
	if ball != null:
		ball.exit_surface(type)


## The height a pond's surface is drawn and read at. The generator levels the
## bank to this, so the water meets the land instead of stepping up or down to it.
static func water_level(patch: Dictionary) -> float:
	var position: Vector3 = patch["position"]
	return float(patch.get("water_y", position.y))


## The painted lie follows the heightmap so a downhill fairway does not float
## above the ground or clip through a rise. Water is the exception: a pond surface
## is flat, and the ground was levelled to its edge to meet it.
static func _draped_mesh(
	patch: Dictionary, look: Dictionary, height: HeightField
) -> MeshInstance3D:
	var size: Vector2 = patch["size"]
	var draw: float = Surface.DRAW_HEIGHT[patch["type"]]
	var mesh_node := MeshInstance3D.new()
	if patch["type"] == Surface.Type.WATER:
		if patch["round"]:
			mesh_node.mesh = MeshFactory.disk(size.x * 0.5, look["line"]).mesh
		else:
			mesh_node.mesh = MeshFactory.flat_quad(size, look["line"]).mesh
		mesh_node.position.y = water_level(patch) + draw
		MeshFactory.apply_grid(mesh_node, look)
		return mesh_node
	if height == null:
		if patch["round"]:
			mesh_node.mesh = MeshFactory.disk(size.x * 0.5, look["line"]).mesh
		else:
			mesh_node.mesh = MeshFactory.flat_quad(size, look["line"]).mesh
		mesh_node.position.y = draw
		MeshFactory.apply_grid(mesh_node, look)
		return mesh_node
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if patch["round"]:
		_drape_disk(st, size.x * 0.5, patch, height, draw)
	else:
		_drape_quad(st, size, patch, height, draw)
	st.generate_normals()
	mesh_node.mesh = st.commit()
	MeshFactory.apply_grid(mesh_node, look)
	return mesh_node


static func _drape_quad(
	st: SurfaceTool, size: Vector2, patch: Dictionary, height: HeightField, draw: float
) -> void:
	var steps_x := maxi(1, int(size.x / HeightField.CELL))
	var steps_z := maxi(1, int(size.y / HeightField.CELL))
	for z in steps_z:
		for x in steps_x:
			var a := _local_on_ground(size, x, z, steps_x, steps_z, patch, height, draw)
			var b := _local_on_ground(size, x + 1, z, steps_x, steps_z, patch, height, draw)
			var c := _local_on_ground(size, x, z + 1, steps_x, steps_z, patch, height, draw)
			var d := _local_on_ground(size, x + 1, z + 1, steps_x, steps_z, patch, height, draw)
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(d)
			st.add_vertex(c)


static func _local_on_ground(
	size: Vector2, x: int, z: int, steps_x: int, steps_z: int,
	patch: Dictionary, height: HeightField, draw: float
) -> Vector3:
	var local := Vector3(
		(float(x) / float(steps_x) - 0.5) * size.x,
		0.0,
		(float(z) / float(steps_z) - 0.5) * size.y
	)
	return _lift_local(local, patch, height, draw)


static func _drape_disk(
	st: SurfaceTool, radius: float, patch: Dictionary, height: HeightField, draw: float
) -> void:
	var rings := 8
	var segs := 24
	var hole := _cut_radius(patch)
	var center := _lift_local(Vector3.ZERO, patch, height, draw)
	for ring in rings:
		var inner := hole + (radius - hole) * float(ring) / float(rings)
		var outer := hole + (radius - hole) * float(ring + 1) / float(rings)
		for i in segs:
			var a := TAU * float(i) / float(segs)
			var b := TAU * float(i + 1) / float(segs)
			var i0 := (
				_lift_local(Vector3(cos(a), 0.0, sin(a)) * inner, patch, height, draw)
				if inner > 0.0001 else center
			)
			var i1 := (
				_lift_local(Vector3(cos(b), 0.0, sin(b)) * inner, patch, height, draw)
				if inner > 0.0001 else center
			)
			var o0 := _lift_local(Vector3(cos(a), 0.0, sin(a)) * outer, patch, height, draw)
			var o1 := _lift_local(Vector3(cos(b), 0.0, sin(b)) * outer, patch, height, draw)
			st.add_vertex(i0)
			st.add_vertex(o1)
			st.add_vertex(o0)
			st.add_vertex(i0)
			st.add_vertex(i1)
			st.add_vertex(o1)


static func _lift_local(
	local: Vector3, patch: Dictionary, height: HeightField, draw: float
) -> Vector3:
	var position: Vector3 = patch["position"]
	var world := local.rotated(Vector3.UP, deg_to_rad(patch["yaw"])) + Vector3(position.x, 0.0, position.z)
	local.y = height.height_at(world.x, world.z) + draw
	return local


static func _cut_radius(patch: Dictionary) -> float:
	if not patch["round"]:
		return 0.0
	if patch["type"] == Surface.Type.GREEN or patch["type"] == Surface.Type.FRINGE:
		return Cup.RADIUS
	return 0.0


## Fog-proof lime hoop around the putting surface, plus a lamp so the disk glows
## even when the grid has faded out. Collision stays off: this is only a look.
static func _putting_marker(patch: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "GreenRim"
	root.add_to_group("green_rims")
	var size: Vector2 = patch["size"]
	var position: Vector3 = patch["position"]
	root.position.y = position.y + Surface.DRAW_HEIGHT[Surface.Type.GREEN] + RIM_LIFT
	var practice := bool(patch.get("practice", false))
	if patch["round"]:
		root.add_child(_round_rim(size.x * 0.5, practice))
	else:
		root.add_child(_rect_rim(size, practice))
	if not practice:
		root.add_child(_green_lamp(size))
	return root


static func _round_rim(radius: float, practice := false) -> MeshInstance3D:
	var glow := Palette.GLOW_SOFT if practice else Palette.GLOW_STRONG
	var ring := MeshFactory.torus(
		maxf(0.2, radius - RIM_THICK * 0.4), radius + RIM_THICK * 0.6,
		Palette.LIME, glow
	)
	_beacon(ring, 0.55 if practice else 0.95)
	return ring


static func _rect_rim(size: Vector2, practice := false) -> Node3D:
	var frame := Node3D.new()
	var t := RIM_THICK
	var h := RIM_HEIGHT
	var glow := Palette.GLOW_SOFT if practice else Palette.GLOW_STRONG
	var bars := [
		[Vector3(0.0, 0.0, size.y * 0.5), Vector3(size.x + t, h, t)],
		[Vector3(0.0, 0.0, -size.y * 0.5), Vector3(size.x + t, h, t)],
		[Vector3(size.x * 0.5, 0.0, 0.0), Vector3(t, h, size.y)],
		[Vector3(-size.x * 0.5, 0.0, 0.0), Vector3(t, h, size.y)],
	]
	for bar in bars:
		var mesh := MeshFactory.box(bar[1], Palette.LIME, glow)
		mesh.position = bar[0]
		_beacon(mesh, 0.55 if practice else 0.95)
		frame.add_child(mesh)
	return frame


static func _green_lamp(size: Vector2) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.name = "GreenLamp"
	lamp.light_color = Palette.LIME
	lamp.light_energy = 3.4
	lamp.omni_range = maxf(size.x, size.y) * 0.75 + 8.0
	lamp.position = Vector3(0.0, 4.5, 0.0)
	return lamp


static func _beacon(mesh: MeshInstance3D, alpha: float) -> void:
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = alpha
