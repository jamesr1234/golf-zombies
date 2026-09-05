@tool
class_name Culvert
extends StaticBody3D
## Concrete underpass through a ridge. The heightmap is the driving floor;
## this body is only the walls and ceiling so the cart cannot climb out sideways.

const WIDTH := CulvertHole.WIDTH
const HEIGHT := CulvertHole.HEIGHT
const LENGTH := CulvertHole.PIPE
const WALL := 0.7
const ROOF := 0.45
## Short enough to hop (player jump is ~1.2 m) and long enough to stand on.
const STEP_RISE := 0.7
const STEP_RUN := 1.0
const STEP_WIDTH := 1.8


var _width := WIDTH
var _height := HEIGHT
var _length := LENGTH


static func create(prop: Dictionary) -> Culvert:
	var pipe := Culvert.new()
	pipe.name = "Culvert"
	pipe.collision_layer = Layers.WORLD
	pipe.collision_mask = 0
	var size: Vector3 = prop.get("size", Vector3(WIDTH, HEIGHT, LENGTH))
	pipe._width = size.x
	pipe._height = size.y
	pipe._length = size.z
	pipe.position = prop["position"]
	pipe.rotation.y = deg_to_rad(float(prop.get("yaw", 0.0)))
	pipe._build(pipe._width, pipe._height, pipe._length)
	return pipe


func to_prop() -> Dictionary:
	return {
		"kind": "culvert",
		"position": Vector3(position.x, 0.0, position.z),
		"size": Vector3(_width, _height, _length),
		"yaw": rad_to_deg(rotation.y),
	}


func _ready() -> void:
	add_to_group("culverts")
	if get_child_count() == 0:
		collision_layer = Layers.WORLD
		collision_mask = 0
		_build(_width, _height, _length)


func _build(width: float, height: float, length: float) -> void:
	var side := width * 0.5 + WALL * 0.5
	_slab(Vector3(WALL, height, length), Vector3(-side, height * 0.5, 0.0), Palette.WALL)
	_slab(Vector3(WALL, height, length), Vector3(side, height * 0.5, 0.0), Palette.WALL)
	_roof(width, height, length)
	_stairs(width, height, length)
	_portal(width, height, -length * 0.5)
	_portal(width, height, length * 0.5)
	for i in 3:
		var lamp := OmniLight3D.new()
		lamp.light_color = Palette.AMBER
		lamp.light_energy = 2.4
		lamp.omni_range = 14.0
		lamp.position = Vector3(
			0.0, height * 0.72, lerpf(-length * 0.32, length * 0.32, float(i) / 2.0)
		)
		add_child(lamp)


func _roof(width: float, height: float, length: float) -> void:
	var span := _stair_span()
	var top := Vector3(0.0, height + ROOF * 0.5, 0.0)
	_slab(Vector3(width + WALL * 2.0, ROOF, length - span * 2.0), top, Palette.WALL)
	var cap := Vector3(width + WALL - STEP_WIDTH, ROOF, span)
	var cap_x := (-WALL - STEP_WIDTH) * 0.5
	for along_sign: float in [-1.0, 1.0]:
		_slab(cap, Vector3(cap_x, top.y, along_sign * (length - span) * 0.5), Palette.WALL)


func _stairs(width: float, height: float, length: float) -> void:
	var count := step_count()
	var rise := (height + ROOF) / float(count)
	var x := width * 0.5 - STEP_WIDTH * 0.5
	for along_sign: float in [-1.0, 1.0]:
		var mouth := along_sign * length * 0.5
		for i in count:
			var along := mouth - along_sign * (float(i) + 0.5) * STEP_RUN
			_step(Vector3(x, rise * (float(i) + 0.5), along), rise)


func _step(at: Vector3, rise: float) -> void:
	_slab(Vector3(STEP_WIDTH, rise, STEP_RUN * 0.92), at, Palette.WALL)
	var trim_h := rise * 0.12
	var strip := MeshFactory.box(
		Vector3(STEP_WIDTH * 1.04, trim_h, STEP_RUN * 0.96),
		Palette.WALL_TRIM,
		Palette.GLOW_MEDIUM
	)
	strip.position = at + Vector3(0.0, rise * 0.5 - trim_h * 0.5, 0.0)
	add_child(strip)


func step_count() -> int:
	return maxi(2, ceili((_height + ROOF) / STEP_RISE))


func _stair_span() -> float:
	return float(step_count() - 1) * STEP_RUN + STEP_RUN * 0.35


func _slab(size: Vector3, at: Vector3, color: Color) -> void:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	node.shape = box
	node.position = at
	add_child(node)
	var mesh := MeshFactory.box(size, color, Palette.GLOW_FAINT)
	MeshFactory.apply_grid(mesh, Surface.LOOK[Surface.Type.ROUGH])
	mesh.position = at
	add_child(mesh)


func _portal(width: float, height: float, along: float) -> void:
	var frame := MeshFactory.box(
		Vector3(width + WALL * 2.2, 0.22, 0.28), Palette.CYAN, Palette.GLOW_STRONG
	)
	frame.position = Vector3(0.0, height + 0.08, along)
	add_child(frame)
	var ring := MeshFactory.torus(width * 0.22, width * 0.38, Palette.AMBER, Palette.GLOW_MEDIUM)
	ring.rotation.x = TAU * 0.25
	ring.position = Vector3(0.0, height * 0.45, along)
	add_child(ring)
