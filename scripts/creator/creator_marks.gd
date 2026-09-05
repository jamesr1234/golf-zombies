class_name CreatorMarks
extends MeshInstance3D
## Neon guides drawn over the hole while it is being built: where the next
## fairway piece would run, the ring the group tool is gathering from, and a box
## around anything already picked up. None of it exists once the hole is played.

const LIFT := 0.35
const RING_STEPS := 40
const MARK := GridSnap.CELL * 0.9
## How tall a weapon line stands, so it reads as a wall to walk through rather
## than a stripe painted on the grass.
const POST := 3.2

var _lines := ImmediateMesh.new()
var _drawn := 0


static func create() -> CreatorMarks:
	var marks := CreatorMarks.new()
	marks.name = "CreatorMarks"
	marks.mesh = marks._lines
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.emission_enabled = true
	material.emission_energy_multiplier = Palette.GLOW_SOFT
	marks.material_override = material
	return marks


func clear() -> void:
	_lines.clear_surfaces()


func begin() -> void:
	clear()
	_drawn = 0


func finish() -> void:
	if _drawn == 0:
		return
	_lines.surface_end()


## The corner a fairway piece would add, so the shape is read before it lands.
func ghost_segment(from: Vector3, to: Vector3, width: float, ok: bool) -> void:
	var color := Palette.LIME if ok else Palette.HOT_PINK
	var along := to - from
	along.y = 0.0
	if along.length_squared() < 0.01:
		return
	var side := along.normalized().cross(Vector3.UP) * width * 0.5
	_segment(from + side, to + side, color)
	_segment(from - side, to - side, color)
	_segment(from + side, from - side, color)
	_segment(to + side, to - side, color)


## Where a dropped gun stops working, drawn across the fairway. This is the only
## place it is ever shown: the played hole has nothing there.
func gate_line(data: HoleData, t: float, width: float, color: Color) -> void:
	if data == null or t < 0.0:
		return
	var at := HoleGenerator.point_along(data, t)
	var along := HoleGenerator.point_along(data, minf(1.0, t + 0.01)) - at
	along.y = 0.0
	if along.length_squared() < 0.0001:
		along = data.along_cup()
	var side := along.normalized().cross(Vector3.UP) * width * 0.5
	var lift := Vector3.UP * POST
	_segment(at + side, at - side, color)
	_segment(at + side, at + side + lift, color)
	_segment(at - side, at - side + lift, color)
	_segment(at + side + lift, at - side + lift, color)


func ring(center: Vector3, radius: float, color: Color) -> void:
	var previous := center + Vector3(radius, 0.0, 0.0)
	for i in range(1, RING_STEPS + 1):
		var angle := TAU * float(i) / float(RING_STEPS)
		var point := center + Vector3(cos(angle), 0.0, sin(angle)) * radius
		_segment(previous, point, color)
		previous = point


func line(from: Vector3, to: Vector3, color: Color) -> void:
	_segment(from, to, color)


func marker(at: Vector3, color: Color) -> void:
	_segment(at + Vector3(-MARK, 0.0, 0.0), at + Vector3(MARK, 0.0, 0.0), color)
	_segment(at + Vector3(0.0, 0.0, -MARK), at + Vector3(0.0, 0.0, MARK), color)
	_segment(at, at + Vector3(0.0, MARK * 2.0, 0.0), color)


func _segment(from: Vector3, to: Vector3, color: Color) -> void:
	if _drawn == 0:
		_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(from + Vector3.UP * LIFT)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(to + Vector3.UP * LIFT)
	_drawn += 2
