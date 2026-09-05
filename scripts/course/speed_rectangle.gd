@tool
class_name SpeedRectangle
extends CartPathBoost
## A placeable speed pad. Same glow and shove as the race-hole rectangles.

const SPAN := 16.0
const PAD_WIDTH := 14.0
const PAD_FILL := 0.88
## Thick enough to read on the turf. Floor snap parks the origin on the grass,
## so a paper-thin stripe would sit inside the fairway mesh.
const THICKNESS := 0.36
const LIFT := 0.14


func _ready() -> void:
	_face()
	if get_child_count() == 0:
		dress_pad(SPAN, PAD_WIDTH, PAD_FILL, THICKNESS, LIFT)
	super._ready()


func _on_body_entered(body: Node3D) -> void:
	_face()
	super._on_body_entered(body)


func _face() -> void:
	along = Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
