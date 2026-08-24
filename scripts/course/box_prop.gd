@tool
class_name BoxProp
extends StaticBody3D
## Rock or wall you can drop on a hole overlay. Trees stay generated in code.

const _SCRIPT := preload("res://scripts/course/box_prop.gd")

@export var kind := "rock"
@export var size := Vector3(2.0, 1.2, 2.0)


static func create(prop: Dictionary) -> BoxProp:
	var body = _SCRIPT.new()
	body.name = "Rock" if String(prop.get("kind", "rock")) == "rock" else "Wall"
	body.kind = String(prop.get("kind", "rock"))
	body.size = prop["size"]
	body.position = prop["position"]
	body.rotation.y = deg_to_rad(float(prop["yaw"]))
	body._build()
	return body


func to_prop() -> Dictionary:
	return {
		"kind": kind,
		"position": Vector3(position.x, 0.0, position.z),
		"size": size,
		"yaw": rad_to_deg(rotation.y),
	}


func _ready() -> void:
	if get_child_count() == 0:
		_build()


func _build() -> void:
	collision_layer = Layers.PROP
	collision_mask = 0
	var rock := kind == "rock"
	var color := Palette.ROCK if rock else Palette.WALL
	var trim := Palette.ROCK_TRIM if rock else Palette.WALL_TRIM
	var trim_h := size.y * (0.12 if rock else 0.1)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	add_child(shape)
	var mesh := MeshFactory.box(size, color)
	mesh.position.y = size.y * 0.5
	add_child(mesh)
	var strip := MeshFactory.box(
		Vector3(size.x * 1.04, trim_h, size.z * 1.04), trim, Palette.GLOW_MEDIUM
	)
	strip.position.y = size.y - trim_h * 0.5
	add_child(strip)
