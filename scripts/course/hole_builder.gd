class_name HoleBuilder
extends Object
## Turns a HoleData description into scene nodes: ground, surface patches, the
## cup, props, out-of-bounds barriers, and a navigation region for the zombies.

const TeeMarker := preload("res://scripts/course/tee_sign.gd")
const _SniperTower := preload("res://scripts/course/sniper_tower.gd")
const _Tree := preload("res://scripts/course/tree_prop.gd")

const BARRIER_HEIGHT := 9.0
const BARRIER_THICKNESS := 1.5
## Taller than a real flagstick on purpose, so the pin still reads from the
## tee after the yardage sign has dropped behind you.
const FLAG_HEIGHT := 5.0
## Off the hitting area, close enough to read as you walk onto the tee.
const SIGN_SIDE := 5.6
const SIGN_BACK := 2.0
## Straight up from the pin into the sky, so the hole stays readable from the
## tee, the cart, or the bottom of a valley.
const BEAM_HEIGHT := 140.0


static func build(data: HoleData) -> Node3D:
	var root := Node3D.new()
	root.name = "Hole"
	var region := _navigation_region(data)
	root.add_child(region)
	region.add_child(_ground(data))
	for prop in data.props:
		region.add_child(create_prop(prop))
	for jump in data.jumps:
		region.add_child(JumpRamp.create(jump))
	for patch in data.patches:
		root.add_child(SurfacePatch.create(patch, data.height))
	root.add_child(Cup.create(data.cup))
	root.add_child(_flag(data.cup))
	root.add_child(_tee_sign(data))
	root.add_child(PracticeGreen.create(data))
	for barrier in _barriers(data):
		root.add_child(barrier)
	return root


## Baking needs the geometry to be inside the tree, so it happens after the hole
## has been added to the world. Threaded, so loading a hole never hitches.
##
## Only the peer that paths zombies should bake. Computer 2 does not, and a
## course-sized threaded bake is what froze it mid-hole: the work finishes
## whenever it finishes, then the main thread stops to apply the mesh.
static func should_bake(defers_world: bool) -> bool:
	return not defers_world


static func bake_navigation(root: Node3D) -> void:
	if root == null or not should_bake(NetSession.defers_world()):
		return
	for child in root.get_children():
		var region := child as NavigationRegion3D
		if region != null:
			region.bake_navigation_mesh()
			return


static func _navigation_region(data: HoleData) -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.cell_size = 1.0
	mesh.cell_height = 0.5
	# Kept to a whole number of cells so the baker does not round it silently.
	mesh.agent_radius = 1.0
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 1.5
	mesh.agent_max_slope = 60.0
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = Layers.WORLD | Layers.PROP
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	var floor_y := data.height.min_height - HeightField.SKIRT - 1.0
	var span_y := data.height.max_height - floor_y + 12.0
	mesh.filter_baking_aabb = AABB(
		Vector3(data.bounds.position.x, floor_y, data.bounds.position.y),
		Vector3(data.bounds.size.x, span_y, data.bounds.size.y)
	)
	region.navigation_mesh = mesh
	return region


static func _ground(data: HoleData) -> StaticBody3D:
	return data.height.make_body()


static func create_prop(prop: Dictionary) -> Node3D:
	var kind: String = prop["kind"]
	var size: Vector3 = prop["size"]
	var position: Vector3 = prop["position"]
	var body: StaticBody3D
	match kind:
		"tree":
			return _Tree.create(prop)
		"rock":
			body = MeshFactory.box_body(size, Palette.ROCK, Layers.PROP)
			body.add_child(_trim(Vector3(size.x, size.y * 0.12, size.z), Palette.ROCK_TRIM, size.y))
			body.position = position + Vector3.UP * size.y * 0.5
		"tower":
			return _SniperTower.create(prop)
		_:
			body = MeshFactory.box_body(size, Palette.WALL, Layers.PROP)
			body.add_child(_trim(Vector3(size.x, size.y * 0.1, size.z), Palette.WALL_TRIM, size.y))
			body.position = position + Vector3.UP * size.y * 0.5
	body.rotation.y = deg_to_rad(prop["yaw"])
	return body


## A glowing strip along the top edge of a prop, so obstacles read as shapes in
## the dark instead of black blobs.
static func _trim(size: Vector3, color: Color, host_height: float) -> MeshInstance3D:
	var strip := MeshFactory.box(
		Vector3(size.x * 1.04, size.y, size.z * 1.04), color, Palette.GLOW_MEDIUM
	)
	strip.position.y = host_height * 0.5 - size.y * 0.5
	return strip


static func _tee_sign(data: HoleData) -> Node3D:
	var along := _tee_along(data)
	var right := along.cross(Vector3.UP).normalized()
	var at := data.tee + right * SIGN_SIDE - along * SIGN_BACK
	at.y = data.tee.y
	# Face the tee so the copy reads from the hitting area, not the rough.
	return TeeMarker.create(data, at, -right)


static func _tee_along(data: HoleData) -> Vector3:
	var along := data.cup - data.tee
	if data.centerline.size() > 1:
		along = data.centerline[1] - data.tee
	along.y = 0.0
	if along.length_squared() < 0.01:
		return Vector3.FORWARD
	return along.normalized()


static func _flag(cup: Vector3) -> Node3D:
	var root := Node3D.new()
	var pole := MeshFactory.cylinder(0.09, FLAG_HEIGHT, Palette.FLAGPOLE, Palette.GLOW_MEDIUM)
	pole.position.y = FLAG_HEIGHT * 0.5
	root.add_child(pole)
	var flag := MeshFactory.box(Vector3(1.5, 0.95, 0.04), Palette.FLAG, Palette.GLOW_STRONG)
	flag.position = Vector3(0.75, FLAG_HEIGHT - 0.6, 0.0)
	root.add_child(flag)
	root.add_child(pin_beam())
	root.position = cup
	return root


## A thin unshaded column from the cup to the sky. No collision, so it never
## knocks a shot down, and fog does not eat it or the pin vanishes on long holes.
static func pin_beam() -> Node3D:
	var beam := Node3D.new()
	beam.name = "PinBeam"
	beam.add_child(_beam_shaft(0.11, 0.7, Palette.GLOW_STRONG))
	beam.add_child(_beam_shaft(0.38, 0.22, Palette.GLOW_MEDIUM))
	return beam


static func _beam_shaft(radius: float, alpha: float, energy: float) -> MeshInstance3D:
	var shaft := MeshFactory.cylinder(radius, BEAM_HEIGHT, Palette.FLAG, energy)
	shaft.position.y = BEAM_HEIGHT * 0.5
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := shaft.material_override as StandardMaterial3D
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = alpha
	mat.disable_fog = true
	return shaft


static func _barriers(data: HoleData) -> Array[StaticBody3D]:
	var center := data.bounds.get_center()
	var half := data.bounds.size * 0.5
	var low := data.height.min_height - 1.0
	var high := data.height.max_height + BARRIER_HEIGHT
	var mid := (low + high) * 0.5
	var tall := high - low
	var sides: Array[StaticBody3D] = []
	var spans := [
		[Vector3(center.x, mid, center.y - half.y), Vector3(data.bounds.size.x, tall, BARRIER_THICKNESS)],
		[Vector3(center.x, mid, center.y + half.y), Vector3(data.bounds.size.x, tall, BARRIER_THICKNESS)],
		[Vector3(center.x - half.x, mid, center.y), Vector3(BARRIER_THICKNESS, tall, data.bounds.size.y)],
		[Vector3(center.x + half.x, mid, center.y), Vector3(BARRIER_THICKNESS, tall, data.bounds.size.y)],
	]
	for span in spans:
		var body := MeshFactory.box_body(span[1], Color.WHITE, Layers.BARRIER, false)
		body.position = span[0]
		sides.append(body)
	return sides
