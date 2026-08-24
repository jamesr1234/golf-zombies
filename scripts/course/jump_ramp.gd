@tool
class_name JumpRamp
extends StaticBody3D
## A takeoff the cart can launch from. The heightmap is the driving surface
## because the cart floor-snaps to it; the collider fills the pond under the lip
## so Jolt cannot follow the bowl through the mesh.

const WIDTH := 10.0
const LENGTH := 13.0
const ANGLE_DEG := 20.0
## Deep enough to reach a pond floor, so the cart cannot drive the bowl under the
## slope. Boxes, not convex hulls: Jolt's character body ignores those.
const FILL := 8.0

var width := WIDTH
var length := LENGTH
var angle_deg := ANGLE_DEG
var role := "takeoff"


static func lip_height(length := LENGTH, angle_deg := ANGLE_DEG) -> float:
	return length * sin(deg_to_rad(angle_deg))


static func ground_run(length := LENGTH, angle_deg := ANGLE_DEG) -> float:
	return length * cos(deg_to_rad(angle_deg))


static func rear_of(jump: Dictionary) -> Vector3:
	var origin: Vector3 = jump["position"]
	var run := ground_run(jump.get("length", LENGTH), jump.get("angle_deg", ANGLE_DEG))
	return origin + Vector3.BACK.rotated(Vector3.UP, deg_to_rad(jump["yaw"])) * (run * 0.5)


static func contains(jump: Dictionary, point: Vector3) -> bool:
	var origin: Vector3 = jump["position"]
	var local := (point - origin).rotated(Vector3.UP, -deg_to_rad(jump["yaw"]))
	var hw: float = float(jump.get("width", WIDTH)) * 0.5 + 1.0
	var hz := ground_run(jump.get("length", LENGTH), jump.get("angle_deg", ANGLE_DEG)) * 0.5 + 1.0
	return absf(local.x) <= hw and absf(local.z) <= hz


## Sculpt the hole's ground into the slope. Floor-snap follows the heightmap, so
## a separate mesh on top of a pond bowl is something the cart drives under.
static func raise_ground(field, jump: Dictionary) -> void:
	var origin: Vector3 = jump["position"]
	var yaw := deg_to_rad(jump["yaw"])
	var width: float = jump.get("width", WIDTH)
	var length: float = jump.get("length", LENGTH)
	var angle_deg: float = jump.get("angle_deg", ANGLE_DEG)
	var run := ground_run(length, angle_deg)
	var rise := lip_height(length, angle_deg)
	var rear := rear_of(jump)
	var base: float = field.height_at(rear.x, rear.z)
	var hw := width * 0.5
	var hz := run * 0.5
	var cell: float = field.cell
	var pad: float = maxf(hw, hz) + cell
	var origin_x: float = field.origin.x
	var origin_z: float = field.origin.y
	var map_w: int = field.width
	var map_d: int = field.depth
	var x0 := maxi(0, int(floor((origin.x - pad - origin_x) / cell)))
	var z0 := maxi(0, int(floor((origin.z - pad - origin_z) / cell)))
	var x1 := mini(map_w - 1, int(ceil((origin.x + pad - origin_x) / cell)))
	var z1 := mini(map_d - 1, int(ceil((origin.z + pad - origin_z) / cell)))
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := origin_x + float(x) * cell
			var wz := origin_z + float(z) * cell
			var local := (Vector3(wx, 0.0, wz) - Vector3(origin.x, 0.0, origin.z)).rotated(
				Vector3.UP, -yaw
			)
			if absf(local.x) > hw:
				continue
			var t := inverse_lerp(hz, -hz, local.z)
			# Hold the lip for one cell so bilinear samples at the edge are not
			# mixed with the pond bowl.
			if t < 0.0 or t > 1.0 + cell / run:
				continue
			var at: int = z * map_w + x
			field.samples[at] = maxf(field.samples[at], base + clampf(t, 0.0, 1.0) * rise)


## How far a launch from this lip travels before it hits the far bank, counting
## the extra hang time from leaving the ground high.
static func flight_distance(
	speed: float, angle_deg := ANGLE_DEG, height := 0.0, gravity := GolfCart.AIR_GRAVITY
) -> float:
	if gravity <= 0.0 or speed <= 0.0:
		return 0.0
	var angle := deg_to_rad(angle_deg)
	var vx := speed * cos(angle)
	var vy := speed * sin(angle)
	var disc := vy * vy + 2.0 * gravity * height
	if disc < 0.0:
		return 0.0
	return vx * (vy + sqrt(disc)) / gravity


static func create(jump: Dictionary) -> JumpRamp:
	var ramp := JumpRamp.new()
	ramp.name = "JumpRamp"
	ramp.width = float(jump.get("width", WIDTH))
	ramp.length = float(jump.get("length", LENGTH))
	ramp.angle_deg = float(jump.get("angle_deg", ANGLE_DEG))
	ramp.role = String(jump.get("role", "takeoff"))
	ramp.rotation.y = deg_to_rad(jump["yaw"])
	ramp.position = jump["position"]
	ramp._assemble()
	return ramp


func to_jump() -> Dictionary:
	return {
		"position": Vector3(position.x, 0.0, position.z),
		"yaw": rad_to_deg(rotation.y),
		"width": width,
		"length": length,
		"angle_deg": angle_deg,
		"role": role,
	}


func _ready() -> void:
	if get_child_count() == 0:
		_assemble()


func _assemble() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	add_child(_shape(width, length, angle_deg))
	var deck := _wedge(width, length, angle_deg)
	MeshFactory.apply_grid(deck, Surface.LOOK[Surface.Type.FAIRWAY])
	add_child(deck)
	add_child(_lip(width, length, angle_deg))
	if role == "takeoff":
		for mark in _chevrons(length, angle_deg):
			add_child(mark)


static func _thickness(length: float, angle_deg: float) -> float:
	return lip_height(length, angle_deg) / cos(deg_to_rad(angle_deg)) + FILL


static func _shape(width: float, length: float, angle_deg: float) -> CollisionShape3D:
	var angle := deg_to_rad(angle_deg)
	var thick := _thickness(length, angle_deg)
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, thick, length)
	node.shape = box
	node.rotation.x = angle
	# Top-rear of the box sits on the ground; the lip is LENGTH * sin(angle) up.
	node.position = Vector3(
		0.0,
		length * 0.5 * sin(angle) - thick * 0.5 * cos(angle),
		-thick * 0.5 * sin(angle)
	)
	return node


static func _corners(width: float, length: float, angle_deg: float) -> Dictionary:
	var hw := width * 0.5
	var hz := ground_run(length, angle_deg) * 0.5
	var rise := lip_height(length, angle_deg)
	return {
		"rl": Vector3(-hw, 0.0, hz),
		"rr": Vector3(hw, 0.0, hz),
		"fl": Vector3(-hw, 0.0, -hz),
		"fr": Vector3(hw, 0.0, -hz),
		"tl": Vector3(-hw, rise, -hz),
		"tr": Vector3(hw, rise, -hz),
	}


static func _wedge(width: float, length: float, angle_deg: float) -> MeshInstance3D:
	var c := _corners(width, length, angle_deg)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, c.rl, c.rr, c.tr, c.tl)
	_quad(st, c.fl, c.tl, c.tr, c.fr)
	_tri(st, c.rl, c.tl, c.fl)
	_tri(st, c.rr, c.fr, c.tr)
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = MeshFactory.material(Palette.AMBER, false, Palette.GLOW_SOFT)
	return node


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _lip(width: float, length: float, angle_deg: float) -> MeshInstance3D:
	var strip := MeshFactory.box(
		Vector3(width * 1.04, 0.12, 0.38), Palette.AMBER, Palette.GLOW_STRONG
	)
	var hz := ground_run(length, angle_deg) * 0.5
	strip.position = Vector3(0.0, lip_height(length, angle_deg) + 0.08, -hz)
	strip.rotation.x = deg_to_rad(angle_deg)
	return strip


static func _chevrons(length: float, angle_deg: float) -> Array[MeshInstance3D]:
	var marks: Array[MeshInstance3D] = []
	var hz := ground_run(length, angle_deg) * 0.5
	var rise := lip_height(length, angle_deg)
	for i in 3:
		var mark := MeshFactory.box(Vector3(0.9, 0.05, 0.9), Palette.CYAN, Palette.GLOW_STRONG)
		var t := lerpf(0.28, 0.82, float(i) / 2.0)
		mark.position = Vector3(0.0, t * rise + 0.05, lerpf(hz, -hz, t))
		mark.rotation.x = deg_to_rad(angle_deg)
		mark.rotate_object_local(Vector3.UP, deg_to_rad(45.0))
		marks.append(mark)
	return marks
