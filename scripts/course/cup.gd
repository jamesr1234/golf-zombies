class_name Cup
extends Area3D
## The hole itself. Polls instead of reacting to body_entered so a ball that
## rattles in and settles still drops. The well is a real cavity: walls and a
## floor on the cup layer, so the ball can fall in once the green lets it go.

const RADIUS := 0.9
const DEPTH := 0.7
const FLOOR_THICK := 0.1
const WALLS := 16
const WALL_THICK := 0.14


static func create(position: Vector3) -> Cup:
	var node := Cup.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = RADIUS
	cylinder.height = 1.0
	shape.shape = cylinder
	shape.position.y = 0.5
	node.add_child(shape)
	var ring := MeshFactory.torus(
		RADIUS * 0.78, RADIUS * 1.35, Palette.CUP_RING, Palette.GLOW_STRONG
	)
	ring.position.y = 0.03
	node.add_child(ring)
	node.add_child(_liner())
	var bed := MeshFactory.disk(RADIUS * 0.98, Palette.CUP_MOUTH)
	bed.position.y = -DEPTH + 0.02
	node.add_child(bed)
	node.add_child(_well())
	node.position = position + Vector3.UP * Surface.DRAW_HEIGHT[Surface.Type.GREEN]
	return node


func _ready() -> void:
	collision_layer = Layers.SURFACE
	collision_mask = Layers.BALL
	monitoring = true


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		var ball := body as GolfBall
		if ball != null:
			ball.try_hole_out(self)


func rest_y() -> float:
	return global_position.y + floor_top() + GolfBall.RADIUS


static func floor_top() -> float:
	return -DEPTH + FLOOR_THICK


static func _liner() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	for i in segs:
		var a := TAU * float(i) / float(segs)
		var b := TAU * float(i + 1) / float(segs)
		var t0 := Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS)
		var t1 := Vector3(cos(b) * RADIUS, 0.0, sin(b) * RADIUS)
		var b0 := t0 + Vector3.DOWN * DEPTH
		var b1 := t1 + Vector3.DOWN * DEPTH
		st.add_vertex(t0)
		st.add_vertex(b0)
		st.add_vertex(t1)
		st.add_vertex(t1)
		st.add_vertex(b0)
		st.add_vertex(b1)
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = MeshFactory.material(Palette.CUP_MOUTH, false, Palette.GLOW_FAINT)
	return mesh


static func _well() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Well"
	body.collision_layer = Layers.CUP
	body.collision_mask = 0
	var pad := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = RADIUS
	cylinder.height = FLOOR_THICK
	pad.shape = cylinder
	pad.position.y = -DEPTH + FLOOR_THICK * 0.5
	body.add_child(pad)
	var chord := TAU * RADIUS / float(WALLS) * 1.15
	for i in WALLS:
		var angle := TAU * float(i) / float(WALLS)
		var wall := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WALL_THICK, DEPTH, chord)
		wall.shape = box
		var along := Vector3(cos(angle), 0.0, sin(angle))
		wall.position = along * (RADIUS + WALL_THICK * 0.5) + Vector3.DOWN * (DEPTH * 0.5)
		wall.rotation.y = -angle
		body.add_child(wall)
	return body
